from __future__ import annotations
from typing import Literal, TypedDict, Callable, cast, get_args
from pathlib import Path
import json

import numpy as np
import numpy.typing as npt
import pytest

from cyndilib.audio_reference import AudioReference, AudioReferenceConverter
from cyndilib import AudioFrameSync, AudioRecvFrame, AudioSendFrame
from cyndilib.sender import Sender
from conftest import AudioInitParams, AudioParams
import _test_audio_frame  # type: ignore[missing-import]


ReferenceAmplitude = Literal['0.063', '0.1', '0.63', '1.0', '5.01', '10.0']
ReferenceAmplitudes: list[ReferenceAmplitude] = list(get_args(ReferenceAmplitude))

AmplitudeMap = dict[ReferenceAmplitude, float]


HERE = Path(__file__).parent.resolve()
REF_DATA_DIR = HERE / 'data' / 'audio_references'



class AudioReferenceExtraMetaTD(TypedDict):
    dBu: str
    dBVU: str


class AudioReferenceExtraMeta(TypedDict):
    dBu: float
    dBVU: float


class AudioReferenceDataTD(TypedDict):
    audio_file: str
    sample_rate: int
    no_channels: int
    extra_metadata: AudioReferenceExtraMetaTD

class AudioReferenceData(TypedDict):
    audio_file: Path
    npz_file: Path
    sample_rate: int
    no_channels: int
    extra_metadata: AudioReferenceExtraMeta


def load_audio_reference_index() -> list[AudioReferenceData]:
    index_file = REF_DATA_DIR / 'index.json'
    data = index_file.read_text()
    index: list[AudioReferenceDataTD] = json.loads(data)
    r: list[AudioReferenceData] = []
    for item in index:
        audio_file = REF_DATA_DIR / item['audio_file']
        extra_metadata: AudioReferenceExtraMeta = {
            'dBu': float(item['extra_metadata']['dBu']),
            'dBVU': float(item['extra_metadata']['dBVU']),
        }
        npz_file = audio_file.with_suffix('.npz')
        assert npz_file.exists(), f'Expected {npz_file} to exist'
        r.append(AudioReferenceData(
            audio_file=audio_file,
            npz_file=npz_file,
            sample_rate=item['sample_rate'],
            no_channels=item['no_channels'],
            extra_metadata=extra_metadata,
        ))
    return r

AUDIO_REFERENCE_FILE_DATA: list[AudioReferenceData] = load_audio_reference_index()


@pytest.fixture(params=AUDIO_REFERENCE_FILE_DATA)
def audio_reference_data(request) -> AudioReferenceData:
    return request.param



AMPLITUDE_MAPS: dict[AudioReference, AmplitudeMap] = {
    AudioReference.dBu: {
        '0.063': -20,
        '0.1': -16,
        '0.63': 0,
        '1.0': 4,
        '10.0': 24,
    },
    AudioReference.dBVU: {
        '0.063': -24,
        '0.1': -20,
        '0.63': -4,
        '1.0': 0,
        '10.0': 20,
    },
    AudioReference.dBFS_smpte: {
        '0.063': -44,
        '0.1': -40,
        '0.63': -24,
        '1.0': -20,
        '10.0': 0,
    },
    AudioReference.dBFS_ebu: {
        '0.063': -38,
        '0.1': -34,
        '0.63': -18,
        '1.0': -14,
        '5.01': 0,
    },
}


@pytest.fixture(params=list(AudioReference))
def audio_reference(request) -> AudioReference:
    return request.param


@pytest.fixture
def audio_reference_with_amplitude(audio_reference: AudioReference) -> tuple[AudioReference, AmplitudeMap]:
    return audio_reference, AMPLITUDE_MAPS[audio_reference]


def build_sine_wave(
    fc: float = 1000.0,
    fs: float = 48000.0,
    duration: float = 1.0,
    amplitude: float = 1.0,
) -> npt.NDArray[np.float32]:
    """Build a sine wave signal."""
    t = np.arange(0, duration, 1 / fs)
    sig = amplitude * np.sin(2 * np.pi * fc * t)
    sig = np.reshape(sig, (1, sig.size))
    return np.asarray(sig, dtype=np.float32)


def test_dbfs_smpte():
    reference = AudioReference.dBFS_smpte
    converter = AudioReferenceConverter(reference)
    assert converter.reference == reference
    assert converter.value == reference.value

    # dBFS_smpte    NDI amplitude   smpte amplitude
    #    0 dB(FS)       10.0                1.0
    #  -20 dB(FS)        1.0                0.1
    #  -40 dB(FS)        0.1                0.01
    assert converter.calc_amplitude(0) == pytest.approx(10.0, rel=1e-6)

    for db, amp in [(0, 10.), (-20, 1.0), (-40, 0.1)]:
        assert converter.calc_amplitude(db) == pytest.approx(amp, rel=1e-6)
        assert converter.calc_dB(amp) == pytest.approx(db, rel=1e-6)
        dbfs_amp = 10 ** (db / 20.0)
        sig = build_sine_wave(amplitude=dbfs_amp)
        ndi_sig = np.empty_like(sig)
        converter.to_ndi_array(sig, ndi_sig)
        assert np.max(np.abs(ndi_sig)) == pytest.approx(amp, rel=1e-6)

        ndi_sig = build_sine_wave(amplitude=amp)
        sig = np.empty_like(ndi_sig)
        converter.from_ndi_array(ndi_sig, sig)
        assert np.max(np.abs(sig)) == pytest.approx(dbfs_amp, rel=1e-6)


def test_dbfs_ebu():
    reference = AudioReference.dBFS_ebu
    converter = AudioReferenceConverter(reference)
    assert converter.reference == reference
    assert converter.value == reference.value

    # dBFS_ebu amplitude is 6 dB higher than dBFS_smpte
    # at   0 dB(FS) is  ~5.01
    # at -14 dB(FS) is    1.0
    # at -34 dB(FS) is    0.1
    zero_dBFS_ebu_amplitude = 10 ** (14 / 20.0)
    assert round(zero_dBFS_ebu_amplitude, 2) == 5.01
    for db, amp in [(0, zero_dBFS_ebu_amplitude), (-14, 1.0), (-34, 0.1)]:
        assert converter.calc_amplitude(db) == pytest.approx(amp, rel=1e-6)
        assert converter.calc_dB(amp) == pytest.approx(db, rel=1e-6)

        dbfs_amp = 10 ** (db / 20.0)
        sig = build_sine_wave(amplitude=dbfs_amp)
        ndi_sig = np.empty_like(sig)
        converter.to_ndi_array(sig, ndi_sig)
        assert np.max(np.abs(ndi_sig)) == pytest.approx(amp, rel=1e-6)

        ndi_sig = build_sine_wave(amplitude=amp)
        sig = np.empty_like(ndi_sig)
        converter.from_ndi_array(ndi_sig, sig)
        assert np.max(np.abs(sig)) == pytest.approx(dbfs_amp, rel=1e-6)


def test_calc_amplitude(audio_reference_with_amplitude: tuple[AudioReference, AmplitudeMap]) -> None:
    # print(audio_reference)
    # round_decimals = 3
    reference, amplitude_map = audio_reference_with_amplitude
    converter = AudioReferenceConverter(reference)
    assert converter.reference == reference
    assert converter.value == reference.value
    print(f'{reference=}')
    for amp_str, db_val in amplitude_map.items():
        round_decimals = len(amp_str.split('.')[1]) if '.' in amp_str else 0
        expected_amplitude = float(amp_str)
        # expected_amplitude = round(expected_amplitude, round_decimals)
        amplitude = converter.calc_amplitude(db_val)
        print(f'{db_val=}, {expected_amplitude=}, {amplitude=}')
        assert round(amplitude, round_decimals) == expected_amplitude


def test_calc_dB(audio_reference_with_amplitude: tuple[AudioReference, AmplitudeMap]) -> None:
    reference, amplitude_map = audio_reference_with_amplitude
    converter = AudioReferenceConverter(reference)
    print(f'{reference=}')
    for amp_str, db_val in amplitude_map.items():
        round_decimals = 1#len(amp_str.split('.')[1]) if '.' in amp_str else 0
        expected_dB = float(db_val)
        # expected_dB = round(expected_dB, round_decimals)
        amplitude = float(amp_str)
        dB = converter.calc_dB(amplitude)
        print(f'{amp_str=}, {expected_dB=}, {dB=}')
        assert round(dB, round_decimals) == expected_dB


def test_to_other(audio_reference_with_amplitude: tuple[AudioReference, AmplitudeMap]) -> None:
    reference, amplitude_map = audio_reference_with_amplitude
    converter = AudioReferenceConverter(reference)
    print(f'{reference=}, {amplitude_map=}')
    other_converter = AudioReferenceConverter()
    sig = build_sine_wave(amplitude=1.0)
    for other_reference in AudioReference:
        # other_converter = AudioReferenceConverter(other_reference)
        other_converter.reference = other_reference
        amp_str = '1.0'
        ref_dB = amplitude_map[amp_str]
        ref_amp = 10 ** (ref_dB / 20.0)
        converted_amp = converter.to_other(other_reference, 1.0, force=True)
        print(f'{other_reference=}, {ref_dB=}, {ref_amp=}, {converted_amp=}')
        assert converted_amp == pytest.approx(other_converter.calc_amplitude(ref_dB), rel=1e-6)

        converted_sig = np.empty_like(sig)
        converter.to_other_array(other_reference, sig, converted_sig)
        # converted_sig = converter.to_other_array(other_reference, sig, force=True)
        converted_amp_expected = other_converter.calc_amplitude(ref_dB)
        print(f'{converted_sig=}, {converted_amp_expected=}')
        assert np.max(np.abs(converted_sig)) == pytest.approx(converted_amp_expected, rel=1e-6)
        # assert np.allclose(sig, converted_sig)


def test_wave(
    audio_reference: AudioReference,
    audio_reference_data: AudioReferenceData
) -> None:
    reference = audio_reference
    converter = AudioReferenceConverter(reference)
    dbu_converter = AudioReferenceConverter(AudioReference.dBu)
    dbvu_converter = AudioReferenceConverter(AudioReference.dBVU)
    npz_filename = audio_reference_data['npz_file']
    with np.load(npz_filename) as npz_file:
        wave_data = npz_file['audio_data']
        assert isinstance(wave_data, np.ndarray)
        assert wave_data.dtype == np.float32
        assert wave_data.shape[1] == audio_reference_data['no_channels']
        nframes = wave_data.shape[0]
        wave_data = np.transpose(wave_data)
        assert wave_data.shape[0] == audio_reference_data['no_channels']
        assert wave_data.shape[1] == nframes
        wave_data = cast(np.ndarray[tuple[int, int], np.dtype[np.float32]], wave_data)

    wave_dBu = audio_reference_data['extra_metadata']['dBu']
    wave_dBVU = audio_reference_data['extra_metadata']['dBVU']
    wave_max = np.max(np.abs(wave_data))
    print(f'dBu={wave_dBu:5.0f}, dBVU={wave_dBVU:5.0f}, amp_max={wave_max}')

    src_amp_expected = dbu_converter.calc_amplitude(wave_dBu)
    assert np.allclose(wave_max, src_amp_expected)

    src_amp_expected = dbvu_converter.calc_amplitude(wave_dBVU)
    assert np.allclose(wave_max, src_amp_expected)

    wave_data_local = np.empty_like(wave_data)
    converter.from_ndi_array(wave_data, wave_data_local)
    local_dB_offset = wave_dBVU + reference.value
    local_amp_expected = 10 ** (local_dB_offset / 20.0)
    print(f'{reference=}, {local_dB_offset=}, {local_amp_expected=}')
    assert np.allclose(np.max(np.abs(wave_data_local)), local_amp_expected)
    if converter.is_ndi_native:
        # If the reference is NDI native, the data should be the same
        assert np.allclose(wave_data, wave_data_local)

    wave_data_ndi = np.empty_like(wave_data_local)
    converter.to_ndi_array(wave_data_local, wave_data_ndi)
    assert np.allclose(wave_data, wave_data_ndi)
    if converter.is_ndi_native:
        # If the reference is NDI native, the data should be the same
        assert np.allclose(wave_data, wave_data_ndi)



@pytest.fixture
def fake_audio_data(
    fake_audio_builder: Callable[[AudioInitParams], AudioParams],
) -> AudioParams:
    # Disable the noise generator and set the signal amplitude to 1.0
    params = AudioInitParams(
        nse_amplitude=0.0,
        sig_amplitude=1.0,
        sig_fc=1000.0,
    )
    return fake_audio_builder(params)


def test_audio_send_frame(
    request,
    audio_reference: AudioReference,
    fake_audio_data: AudioParams,
):
    sender_name = request.node.nodeid.split('::')[-1]
    sender = Sender(sender_name)

    af = AudioSendFrame()
    af.sample_rate = fake_audio_data.sample_rate
    af.num_channels = fake_audio_data.num_channels
    af.set_max_num_samples(fake_audio_data.s_perseg)
    af.reference_level = audio_reference
    sender.set_audio_frame(af)

    # The sine amplitude is 1.0 which equals 0 dBVU (the native NDI level).
    # The AudioSendFrame should convert this to 1 / reference_amplitude before
    # sending.
    expected_amplitude = 1 / (10 ** (audio_reference.value / 20.0))

    with sender:
        assert af.shape == (fake_audio_data.num_channels, fake_audio_data.s_perseg)
        src_samples = fake_audio_data.samples_3d[0]
        assert src_samples.shape == (fake_audio_data.num_channels, fake_audio_data.s_perseg)
        af.write_data(src_samples)
        samples_written = _test_audio_frame.get_audio_send_frame_current_data(af)
        assert samples_written.shape == src_samples.shape
        samples_expected = src_samples * expected_amplitude
        assert np.allclose(samples_written, samples_expected)
        if audio_reference == AudioReference.dBVU:
            assert np.array_equal(samples_written, src_samples)


def test_audio_frame_sync(
    audio_reference: AudioReference,
    fake_audio_data: AudioParams,
):
    fs = fake_audio_data.sample_rate

    af = AudioFrameSync()
    af.sample_rate = fake_audio_data.sample_rate
    af.num_channels = fake_audio_data.num_channels
    af.reference_level = audio_reference

    # The sine amplitude is 1.0 which equals 0 dBVU (the native NDI level).
    # The AudioFrameSync should convert this to the reference_amplitude before
    # we read from it.
    expected_amplitude = 10 ** (audio_reference.value / 20.0)

    src_samples = fake_audio_data.samples_3d[0]
    _test_audio_frame.fill_audio_frame_sync(
        audio_frame=af,
        samples=src_samples,
        sample_rate=int(fs),
        timestamp=0,
        do_process=True,
    )
    samples_received = af.get_array()
    assert samples_received.shape == src_samples.shape
    samples_expected = src_samples * expected_amplitude
    assert np.allclose(samples_received, samples_expected)
    if audio_reference == AudioReference.dBVU:
        assert np.array_equal(samples_received, src_samples)
