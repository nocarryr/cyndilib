# cython: language_level=3
# cython: linetrace=True
# cython: profile=False
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS

cimport cython
from libc.stdint cimport *
cimport numpy as cnp
import numpy as np

from fractions import Fraction
# import time

from cyndilib.wrapper cimport *
from cyndilib.audio_frame cimport AudioSendFrame
from cyndilib.video_frame cimport VideoSendFrame
from cyndilib.sender cimport Sender
from cyndilib.clock cimport time


@cython.boundscheck(False)
@cython.wraparound(False)
def test_send_video_and_audio(
    Sender sender,
    cnp.uint8_t[:,:] fake_frames,
    cnp.float32_t[:,:,:] audio_samples,
    object frame_rate,
    size_t num_frame_repeats = 10,
    size_t num_full_repeats = 1,
    bint send_audio = True
):
    cdef size_t num_frames = fake_frames.shape[0]

    # fr = Fraction(60000, 1001)
    cdef object one_frame = 1 / frame_rate

    cdef double wait_time = float(one_frame)

    cdef cnp.ndarray[cnp.float64_t, ndim=2] frame_times = np.zeros(
        (num_full_repeats, num_frame_repeats*num_frames),
        dtype=np.float64,
    )
    cdef cnp.float64_t[:,:] frame_time_view = frame_times

    cdef size_t i, j = 0, x, cur_iteration = 0
    cdef bint r
    cdef double start_ts, elapsed
    while cur_iteration < num_full_repeats:
        j = 0
        with sender:
            assert sender._running is True
            print('loop_start')
            for x in range(num_frame_repeats):
                for i in range(num_frames):
                    # print(f'send frame {i}')
                    start_ts = time()

                    if send_audio:
                        r = sender._write_video_and_audio(fake_frames[i], audio_samples[i])
                    else:
                        r = sender._write_video_async(fake_frames[i])
                    assert r is True
                    elapsed = time() - start_ts
                    frame_time_view[cur_iteration, j] = elapsed
                    j += 1

        cur_iteration += 1

    return frame_times
