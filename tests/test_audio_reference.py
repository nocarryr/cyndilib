from __future__ import annotations
from typing import Literal, get_args

import numpy as np
import numpy.typing as npt
import pytest

from cyndilib.audio_reference import AudioReference, AudioReferenceConverter


ReferenceAmplitude = Literal['0.063', '0.1', '0.63', '1.0', '5.01', '10.0']
ReferenceAmplitudes: list[ReferenceAmplitude] = list(get_args(ReferenceAmplitude))

AmplitudeMap = dict[ReferenceAmplitude, float]

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
