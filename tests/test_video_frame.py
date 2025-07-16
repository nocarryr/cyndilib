from __future__ import annotations
from typing import Callable
from fractions import Fraction
import time
import numpy as np
import pytest
from cyndilib.video_frame import VideoRecvFrame, VideoSendFrame
from cyndilib.wrapper import FourCC
from _test_video_frame import (             # type: ignore[missing-import]
    build_test_frame, build_test_frames,
    buffer_into_video_frame, video_frame_process_events,
)
from _test_send_frame_status import (       # type: ignore[missing-import]
    set_send_frame_sender_status, set_send_frame_send_complete,
    set_vid_send_frame_complete, get_video_frame_data,
    check_video_send_frame, get_null_idx, get_max_frame_buffers,
)
from conftest import VideoParams, VideoInitParams

MAX_FRAME_BUFFERS = get_max_frame_buffers()
NULL_INDEX = get_null_idx()


@pytest.fixture
def fake_video_frames_bench(fake_video_builder: Callable[[VideoInitParams], np.ndarray]) -> VideoParams:
    params = VideoInitParams(
        width=160,
        height=90,
        frame_rate=Fraction(30, 1),
        num_frames=30,
    )
    frames = fake_video_builder(params)
    return VideoParams.from_init(params, frames=frames)


def test():
    width, height = 1920, 1080

    vf = VideoRecvFrame()
    for i in range(30):
        expected_data = build_test_frame(width, height, False, True, False, i)
        buffer_into_video_frame(vf, width, height, expected_data)
        assert vf.get_buffer_depth() == 1
        assert vf.get_view_count() == 0
        assert vf.get_buffer_size() == width * height * 4
        result = np.frombuffer(vf, dtype=np.uint8)
        assert vf.get_view_count() == 1
        result = result.copy()
        assert vf.get_buffer_depth() == 0
        assert result.size == expected_data.size
        assert np.array_equal(result, expected_data)



def test_frame_builder():
    width, height = 640, 360
    num_frames = 160

    a = arr_uint32 = build_test_frame(width, height, True, False, False)
    b = arr_uint8_flat = build_test_frame(width, height, False, True, False)
    c = arr_struct = build_test_frame(width, height, False, False, True)
    d = arr_uint8_3d = build_test_frame(width, height, False, False, False)

    assert a.tobytes() == b.tobytes() == c.tobytes() == d.tobytes()

    a = arr_uint32 = build_test_frames(width, height, num_frames, True, False, False)
    b = arr_uint8_flat = build_test_frames(width, height, num_frames, False, True, False)
    c = arr_struct = build_test_frames(width, height, num_frames, False, False, True)
    d = arr_uint8_3d = build_test_frames(width, height, num_frames, False, False, False)

    x_inc = width // num_frames
    for i in range(num_frames):
        x_offset = i * x_inc
        f = build_test_frame(width, height, False, False, False, x_offset)
        assert a[i].tobytes() == f.tobytes()
        assert a[i].tobytes() == b[i].tobytes() == c[i].tobytes() == d[i].tobytes()


def test_video_send_frame(fake_video_frames: VideoParams):
    width, height, fr, num_frames, fake_frames = fake_video_frames

    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)

    expected_write_idx = 0
    expected_read_idx = NULL_INDEX

    assert vf.ndim == 1
    assert vf.shape == (0,)
    assert vf.write_index == expected_write_idx
    assert vf.read_index == expected_read_idx


    set_send_frame_sender_status(vf, True)
    assert vf.write_index == expected_write_idx
    assert vf.read_index == expected_read_idx
    check_video_send_frame(vf)

    for i in range(num_frames):
        print(f'{i=}')
        assert vf.write_index == expected_write_idx
        assert vf.read_index == expected_read_idx

        vf.write_data(fake_frames[i])

        expected_read_idx = expected_write_idx
        expected_write_idx = (expected_write_idx + 1) % MAX_FRAME_BUFFERS
        assert vf.write_index == expected_write_idx
        assert vf.read_index == expected_read_idx
        check_video_send_frame(vf)

        set_send_frame_send_complete(vf)

        expected_read_idx = NULL_INDEX
        assert vf.write_index == expected_write_idx
        assert vf.read_index == expected_read_idx
        check_video_send_frame(vf)

    set_send_frame_sender_status(vf, False)

    vf.destroy()
    assert vf.write_index == 0
    assert vf.read_index == NULL_INDEX


def test_video_benchmark(benchmark, fake_video_frames_bench: VideoParams):
    width, height, fr, num_frames, fake_frames = fake_video_frames_bench

    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)
    assert vf.get_line_stride() == width * 4
    items_per_frame = fake_frames.shape[-1]

    results = np.zeros((num_frames, items_per_frame), dtype=fake_frames.dtype)

    set_send_frame_sender_status(vf, True)

    assert vf.shape == results[0].shape

    def run_video_test():
        for i in range(num_frames):
            vf.write_data(fake_frames[i])
            get_video_frame_data(vf, results[i,...])
            set_vid_send_frame_complete(vf)

    benchmark(run_video_test)

    assert np.array_equal(fake_frames, results)

    set_send_frame_sender_status(vf, False)
    vf.destroy()
