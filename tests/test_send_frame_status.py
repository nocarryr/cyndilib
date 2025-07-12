from __future__ import annotations
from typing import Callable
import pytest
import numpy as np

from cyndilib.wrapper import *
from cyndilib.audio_frame import AudioSendFrame
from cyndilib.video_frame import VideoSendFrame

import _test_send_frame_status  # type: ignore[missing-import]
from conftest import AudioInitParams, AudioParams, VideoParams, IS_CI_BUILD

NULL_INDEX = _test_send_frame_status.get_null_idx()
MAX_FRAME_BUFFERS = _test_send_frame_status.get_max_frame_buffers()

@pytest.fixture
def fake_audio_data(fake_audio_builder: Callable[[AudioInitParams], AudioParams]) -> AudioParams:
    num_seconds = 8 if IS_CI_BUILD else 32
    params = AudioInitParams()
    num_samples = params.sample_rate * num_seconds
    num_segments = num_samples // params.s_perseg
    params = params._replace(num_samples=num_samples, num_segments=num_segments)
    return fake_audio_builder(params)

def test_indexing():
    _test_send_frame_status.test_indexing()

def test_video(fake_video_frames: VideoParams):
    width, height, fr, num_frames, fake_frames = fake_video_frames

    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)
    assert vf.get_line_stride() == width * 4

    results = np.zeros_like(fake_frames[0])

    write_index = 0
    read_index = NULL_INDEX

    _test_send_frame_status.set_send_frame_sender_status(vf, True)

    for i in range(num_frames):
        _test_send_frame_status.check_video_send_frame(vf, write_index, read_index)
        vf.write_data(fake_frames[i])
        read_index = write_index
        write_index = (write_index + 1) % MAX_FRAME_BUFFERS
        print(f'w={write_index}, r={read_index}')

        _test_send_frame_status.check_video_send_frame(vf, write_index, read_index)
        _test_send_frame_status.get_video_frame_data(vf, results)
        assert np.array_equal(fake_frames[i], results)

        _test_send_frame_status.set_send_frame_send_complete(vf)
        read_index = NULL_INDEX
        _test_send_frame_status.check_video_send_frame(vf, write_index, read_index)

    _test_send_frame_status.set_send_frame_sender_status(vf, False)
    vf.destroy()

def test_audio(fake_audio_data: AudioParams):
    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    num_segments = fake_audio_data.num_segments
    s_perseg = fake_audio_data.s_perseg

    samples = fake_audio_data.samples_3d
    samples_flat = fake_audio_data.samples_2d

    af = AudioSendFrame()
    af.sample_rate = fs
    af.num_channels = num_channels
    # af.num_samples = s_perseg
    af.set_max_num_samples(s_perseg)
    assert af.num_samples == s_perseg

    results = np.zeros_like(samples[0])

    write_index = 0
    read_index = NULL_INDEX

    _test_send_frame_status.set_send_frame_sender_status(af, True)

    assert af.shape == results.shape

    for i in range(num_segments):
        _test_send_frame_status.check_audio_send_frame(af, write_index, read_index)
        # af.write_data(samples[i])
        _test_send_frame_status.write_audio_frame_memview(af, samples[i])
        read_index = write_index
        write_index = (write_index + 1) % MAX_FRAME_BUFFERS
        print(f'{i=}, w={write_index}, r={read_index}')

        _test_send_frame_status.check_audio_send_frame(af, write_index, read_index)
        _test_send_frame_status.get_audio_frame_data(af, results)
        assert np.array_equal(samples[i], results)

        _test_send_frame_status.set_send_frame_send_complete(af)
        read_index = NULL_INDEX
        _test_send_frame_status.check_audio_send_frame(af, write_index, read_index)

    _test_send_frame_status.set_send_frame_sender_status(af, False)
    af.destroy()
