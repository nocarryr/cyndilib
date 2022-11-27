import time
import numpy as np
from cyndilib.video_frame import VideoRecvFrame
from _test_video_frame import (
    build_test_frame, build_test_frames,
    buffer_into_video_frame, video_frame_process_events,
)

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
