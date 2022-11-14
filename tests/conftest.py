import pytest
from collections import namedtuple
from fractions import Fraction
import numpy as np

from _test_video_frame import build_test_frames

AudioParams = namedtuple('AudioParams', [
    'sample_rate', 'num_channels', 'num_samples', 'num_segments', 's_perseg',
    'samples_3d', 'samples_2d'],
    defaults=[
        48000, 2, 48000*2, 48000*2//6000, 6000, None, None,
    ]
)

VideoParams = namedtuple('VideoParams', [
    'width', 'height', 'frame_rate', 'num_frames', 'frames',
])

@pytest.fixture
def fake_audio_builder():
    def build_fake_data(
        params: AudioParams
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

        return params._replace(samples_3d=b, samples_2d=a)

    return build_fake_data


@pytest.fixture
def fake_video_builder():
    def build_fake_data(width, height, num_frames, as_uint32=True, as_flat_uint8=False):
        return build_test_frames(width, height, num_frames, as_uint32, as_flat_uint8)

    return build_fake_data


@pytest.fixture(params=[(640,360), (1280,720), (1920,1080)])
def video_resolution(request):
    w, h = request.param
    return w, h


@pytest.fixture(params=[59.94, 29.97, 25])
def video_frame_rate(request):
    if request.param == int(request.param):
        return Fraction(request.param, 1)
    else:
        return Fraction(int(round(request.param)) * 1000, 1001)

@pytest.fixture
def fake_video_frames(video_resolution, video_frame_rate, fake_video_builder):
    w, h = video_resolution
    num_frames = 160
    frames = fake_video_builder(w, h, num_frames, False, True)
    return VideoParams(w, h, video_frame_rate, num_frames, frames)


@pytest.fixture
def fake_av_frames(fake_video_frames, fake_audio_builder):
    num_frames = fake_video_frames.num_frames
    fs = Fraction(48000, 1)
    s_perseg = fs / fake_video_frames.frame_rate
    if s_perseg.denominator == 1:
        s_perseg = s_perseg.numerator
    else:
        s_perseg = int(s_perseg) + 1

    params = AudioParams(
        sample_rate=int(fs), num_samples=s_perseg * num_frames,
        s_perseg=s_perseg, num_segments=num_frames,
    )
    # print(f'{params=}')
    audio_data = fake_audio_builder(params)
    return fake_video_frames, audio_data
