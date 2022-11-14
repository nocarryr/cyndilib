# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=NUMPY_INCLUDE
# distutils: define_macros=CYTHON_TRACE_NOGIL=1

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

cdef extern from * nogil:
    """
    #include <chrono>
    #include <thread>
    #include <stdint.h>
    using namespace std::chrono_literals;

    void sleep_for(double seconds){
        int64_t i = (int64_t)seconds * 1000000;
        int64_t j = (seconds - (int64_t)seconds) * 1000000;
        i += j;
        auto microseconds = std::chrono::microseconds(i);
        std::this_thread::sleep_for(microseconds);
    }

    double get_cpp_time(){
        using namespace std::chrono;
        auto tsNow = high_resolution_clock::now();
        auto msD = duration_cast<microseconds>(tsNow.time_since_epoch());
        double result = msD.count();
        result *= 0.000001;
        return result;
    }
    """
    cdef double get_cpp_time()
    cdef void sleep_for(double seconds)


@cython.boundscheck(False)
@cython.wraparound(False)
def test_send_video_and_audio(
    Sender sender,
    cnp.uint8_t[:,:] fake_frames,
    cnp.float32_t[:,:,:] audio_samples,
    object frame_rate,
    size_t num_frame_repeats = 10,
    size_t num_full_repeats = 1,
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
    cdef double start_ts, elapsed
    while cur_iteration < num_full_repeats:
        j = 0
        with sender:
            # sleep_for(.5)
            assert sender._running is True
            print('loop_start')
            # sleep_for(.5)
            # while True:
            for x in range(num_frame_repeats):
                for i in range(num_frames):
                    # print(f'send frame {i}')
                    start_ts = get_cpp_time()

                    sender._write_video_and_audio(fake_frames[i], audio_samples[i])
                    # sender._write_audio(audio_samples[i])
                    # # sender._write_video(fake_frames[i])
                    # sender._write_video_async(fake_frames[i])

                    elapsed = get_cpp_time() - start_ts
                    frame_time_view[cur_iteration, j] = elapsed
                    j += 1

        cur_iteration += 1

    return frame_times
