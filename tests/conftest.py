from __future__ import annotations
import os
import pytest
from typing import NamedTuple, overload
from fractions import Fraction
import numpy as np
import numpy.typing as npt
import psutil

from _test_video_frame import build_test_frames # type: ignore[missing-imports]

IS_CI_BUILD = 'true' in [os.environ.get(key) for key in ['CI', 'CODESPACES']]

class BaseAudioParams(NamedTuple):
    sample_rate: int = 48000
    num_channels: int = 2
    num_samples: int = 48000*2
    num_segments: int = 48000*2//6000
    s_perseg: int = 6000
    samples_3d: npt.NDArray|None = None
    samples_2d: npt.NDArray|None = None

class AudioParams(BaseAudioParams):
    samples_3d: npt.NDArray
    samples_2d: npt.NDArray


class BaseVideoParams(NamedTuple):
    width: int
    height: int
    frame_rate: Fraction
    num_frames: int
    frames: npt.NDArray|None    # (frame_num, height, width, 4)
    as_uint32: bool = True
    as_flat_uint8: bool = False

class BaseVideoParamsUint8(BaseVideoParams):
    as_uint32: bool = False
    as_flat_uint8: bool = True

class VideoParams(BaseVideoParams):
    frames: npt.NDArray[np.uint32]         # (frame_num, height, width, 4)
    # as_uint32: bool = True
    # as_uint8: bool = False

class VideoParamsUint8(BaseVideoParamsUint8):
    frames: npt.NDArray[np.uint8]         # (frame_num, height, width, 4)
    # as_uint32: bool = False
    # as_uint8: bool = True



def build_fake_audio(
    params: BaseAudioParams|AudioParams
) -> AudioParams:
    print(f'N={params.num_samples}')
    fc = 2000
    sig_dbFS = -6
    sig_amp = 10 ** (sig_dbFS/20)
    nse_dbFS = -30
    nse_amp = 10 ** (nse_dbFS/20)
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
    params = params._replace(samples_3d=b, samples_2d=a)
    if not isinstance(params, AudioParams):
        params = AudioParams(**params._asdict())
    return params


@pytest.fixture
def fake_audio_builder():
    return build_fake_audio


@overload
def build_fake_video(params: BaseVideoParamsUint8) -> npt.NDArray[np.uint8]: ...
@overload
def build_fake_video(params: BaseVideoParams) -> npt.NDArray[np.uint32]: ...
def build_fake_video(
    params: BaseVideoParams|BaseVideoParamsUint8
) -> npt.NDArray:
    return build_test_frames(
        params.width, params.height, params.num_frames,
        params.as_uint32, params.as_flat_uint8
    )

@pytest.fixture
def fake_video_builder():
    return build_fake_video


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
    video_params: BaseVideoParams,
    audio_params: AudioParams|None = None,
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
    video_params: BaseVideoParams,
    audio_params: AudioParams|None = None,
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
) -> VideoParamsUint8:
    w, h = video_resolution
    num_frames = 40 if IS_CI_BUILD else 160
    video_params = BaseVideoParamsUint8(w, h, video_frame_rate, num_frames, None)
    mem_ok, mem_req, mem_avail = check_mem_available(video_params)
    while not mem_ok:
        num_frames //= 2
        if num_frames < 40:
            pytest.skip(f'not enough memory. requires {humanize_bytes(mem_req)}, only {humanize_bytes(mem_avail)} available')
        video_params = video_params._replace(num_frames=num_frames)
        mem_ok, mem_req, mem_avail = check_mem_available(video_params)
    try:
        frames = build_fake_video(video_params)
    except MemoryError:
        print(f'{psutil.virtual_memory()=}')
        raise
    return VideoParamsUint8(w, h, video_frame_rate, num_frames, frames)


@pytest.fixture
def fake_av_frames(
    fake_video_frames: VideoParamsUint8,
) -> tuple[VideoParamsUint8, AudioParams]:
    num_frames = fake_video_frames.num_frames
    fs = Fraction(48000, 1)
    s_perseg = fs / fake_video_frames.frame_rate
    if s_perseg.denominator == 1:
        s_perseg = s_perseg.numerator
    else:
        s_perseg = int(s_perseg) + 1

    params = BaseAudioParams(
        sample_rate=int(fs), num_samples=s_perseg * num_frames,
        s_perseg=s_perseg, num_segments=num_frames,
    )
    # print(f'{params=}')
    audio_data = build_fake_audio(params)
    return fake_video_frames, audio_data
