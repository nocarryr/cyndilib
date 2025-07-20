from __future__ import annotations
from typing import NamedTuple, Callable
import os
import pytest
from fractions import Fraction
import numpy as np
import psutil

from _test_video_frame import build_test_frames # type: ignore[missing-import]

IS_CI_BUILD = 'true' in [os.environ.get(key) for key in ['CI', 'CODESPACES']]


class AudioInitParams(NamedTuple):
    """Parameters used to generate fake audio data.
    """
    sample_rate: int = 48000
    num_channels: int = 2
    num_samples: int = 48000 * 2
    num_segments: int = 48000 * 2 // 6000
    s_perseg: int = 6000
    sig_fc: float = 2000
    sig_amplitude: float = 10 ** (-6/20)
    nse_amplitude: float = 10 ** (-30/20)

class AudioParams(NamedTuple):
    """Generated fake audio data and parameters.
    """
    samples_3d: np.ndarray
    samples_2d: np.ndarray
    sample_rate: int = 48000
    num_channels: int = 2
    num_samples: int = 48000 * 2
    num_segments: int = 48000 * 2 // 6000
    s_perseg: int = 6000
    sig_fc: float = 2000
    sig_amplitude: float = 10 ** (-6/20)
    nse_amplitude: float = 10 ** (-30/20)

    @classmethod
    def from_init(
        cls,
        init: AudioInitParams,
        samples_3d: np.ndarray,
        samples_2d: np.ndarray
    ) -> AudioParams:
        """Create AudioParams from AudioInitParams and generated data.
        """
        return cls(
            samples_3d=samples_3d,
            samples_2d=samples_2d,
            sample_rate=init.sample_rate,
            num_channels=init.num_channels,
            num_samples=init.num_samples,
            num_segments=init.num_segments,
            s_perseg=init.s_perseg,
            sig_fc=init.sig_fc,
            sig_amplitude=init.sig_amplitude,
            nse_amplitude=init.nse_amplitude,
        )


class VideoInitParams(NamedTuple):
    """Parameters used to generate fake video data.
    """
    width: int
    height: int
    frame_rate: Fraction
    num_frames: int
    as_uint32: bool = False
    as_flat_uint8: bool = True

class VideoParams(NamedTuple):
    """Generated fake video data and parameters.
    """
    width: int
    height: int
    frame_rate: Fraction
    num_frames: int
    frames: np.ndarray
    @classmethod
    def from_init(cls, init: VideoInitParams, frames: np.ndarray) -> VideoParams:
        """Create VideoParams from VideoInitParams and generated data.
        """
        return cls(
            init.width, init.height, init.frame_rate,
            init.num_frames, frames
        )


@pytest.fixture
def fake_audio_builder() -> Callable[[AudioInitParams], AudioParams]:
    def build_fake_data(
        params: AudioInitParams
    ) -> AudioParams:
        print(f'N={params.num_samples}')
        fc = params.sig_fc
        sig_amp = params.sig_amplitude
        nse_amp = params.nse_amplitude
        t = np.arange(params.num_samples) / params.sample_rate
        a = sig_amp*np.sin(2*np.pi*fc*t)
        print(f'a.size={a.size}')
        a2 = np.zeros((params.num_channels, params.num_samples), dtype=a.dtype)
        for i in range(params.num_channels):
            a2[i,...] = a + nse_amp*np.random.uniform(-1, 1, a.size)
        a = np.asarray(a2, dtype=np.float32)
        b = np.zeros((params.num_segments, params.num_channels, params.s_perseg), dtype=a.dtype)
        s_perseg = params.s_perseg
        for i in range(params.num_segments):
            for j in range(params.num_channels):
                b[i,j,:] = a[j,i*s_perseg:i*s_perseg+s_perseg]

        return AudioParams.from_init(params, b, a)

    return build_fake_data


@pytest.fixture
def fake_video_builder() -> Callable[[VideoInitParams], np.ndarray]:
    def build_fake_data(video_params: VideoInitParams):
        return build_test_frames(
            video_params.width, video_params.height, video_params.num_frames,
            video_params.as_uint32, video_params.as_flat_uint8
        )

    return build_fake_data


@pytest.fixture(params=[(640,360), (1280,720), (1920,1080)])
def video_resolution(request) -> tuple[int, int]:
    w, h = request.param
    return w, h


@pytest.fixture(params=[59.94, 29.97, 25])
def video_frame_rate(request) -> Fraction:
    if request.param == int(request.param):
        return Fraction(request.param, 1)
    else:
        return Fraction(int(round(request.param)) * 1000, 1001)

def get_available_mem():
    return psutil.virtual_memory().available

ONE_KB = 2 ** (10)
ONE_MB = 2 ** (20)

def humanize_bytes(nbytes: int) -> str:
    if nbytes <= ONE_MB * 2:
        kb = nbytes / ONE_KB
        kb_i = int(kb)
        kb_f = int((kb % 1) * 100)
        return f'{kb_i:,}.{kb_f} KB'
    mb = nbytes / ONE_MB
    mb_i = int(mb)
    mb_f = int((mb % 1) * 100)
    return f'{mb_i:,}.{mb_f} MB'

def calc_mem_required(
    video_params: VideoInitParams,
    audio_params: AudioInitParams|None = None,
) -> int:

    vid_dt = np.dtype(np.uint8)
    aud_dt = np.dtype(np.float32)
    vid_mem = video_params.width * video_params.height * 4 * vid_dt.itemsize
    vid_mem *= video_params.num_frames
    aud_mem = 0
    if audio_params is not None:
        samples_per_frame = audio_params.sample_rate / video_params.frame_rate
        s_perseg = int(samples_per_frame)
        if samples_per_frame.denominator != 1:
            s_perseg += 1
        aud_mem = s_perseg * audio_params.num_channels * aud_dt.itemsize
        aud_mem *= video_params.num_frames
    return vid_mem + aud_mem

def check_mem_available(
    video_params: VideoInitParams,
    audio_params: AudioInitParams|None = None,
) -> tuple[bool, int, int]:

    mem_padding = 200 * ONE_MB
    mem_req = calc_mem_required(video_params, audio_params)
    mem_avail = get_available_mem()
    r = mem_avail >= (mem_req*2) + mem_padding
    return r, mem_req, mem_avail


@pytest.fixture
def fake_video_frames(
    video_resolution: tuple[int, int],
    video_frame_rate: Fraction,
    fake_video_builder: Callable[[VideoInitParams], np.ndarray]
) -> VideoParams:
    w, h = video_resolution
    num_frames = 40 if IS_CI_BUILD else 160
    video_params = VideoInitParams(w, h, video_frame_rate, num_frames)
    mem_ok, mem_req, mem_avail = check_mem_available(video_params)
    while not mem_ok:
        num_frames //= 2
        if num_frames < 40:
            pytest.skip(f'not enough memory. requires {humanize_bytes(mem_req)}, only {humanize_bytes(mem_avail)} available')
        video_params = video_params._replace(num_frames=num_frames)
        mem_ok, mem_req, mem_avail = check_mem_available(video_params)
    try:
        frames = fake_video_builder(video_params)
    except MemoryError:
        print(f'{psutil.virtual_memory()=}')
        raise
    return VideoParams(w, h, video_frame_rate, num_frames, frames)


@pytest.fixture
def fake_av_frames(
    fake_video_frames: VideoParams,
    fake_audio_builder: Callable[[AudioInitParams], AudioParams]
) -> tuple[VideoParams, AudioParams]:
    num_frames = fake_video_frames.num_frames
    fs = Fraction(48000, 1)
    s_perseg = fs / fake_video_frames.frame_rate
    if s_perseg.denominator == 1:
        s_perseg = s_perseg.numerator
    else:
        s_perseg = int(s_perseg) + 1

    params = AudioInitParams(
        sample_rate=int(fs), num_samples=s_perseg * num_frames,
        s_perseg=s_perseg, num_segments=num_frames,
    )
    # print(f'{params=}')
    audio_data = fake_audio_builder(params)
    return fake_video_frames, audio_data
