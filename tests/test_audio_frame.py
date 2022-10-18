import time
import pytest

import numpy as np

from cyndilib.audio_frame import AudioRecvFrame

from _test_audio_frame import run_test

def build_fake_data(sample_rate, num_channels, num_samples, num_segments, s_perseg):
    # a = np.array((num_samples), dtype=np.float32)
    # s_perseg = num_samples // num_segments
    print(f'N={num_samples}')
    fc = 2000
    amp = 2*np.sqrt(2)
    t = np.arange(num_samples) / sample_rate
    a = amp*np.sin(2*np.pi*fc*t)
    print(f'a.size={a.size}')
    a = np.resize(a, (num_segments, s_perseg))
    sp_list = [a.shape[0], a.shape[1]]
    print(f'a.shape={sp_list}')
    b = np.zeros((num_segments, num_channels, s_perseg), dtype=a.dtype)
    sp_list = [b.shape[0], b.shape[1], b.shape[2]]
    print(f'b.shape={sp_list}')
    assert b.size == num_samples * num_channels
    for i in range(num_channels):
        b[:,i,:] = a
    b = np.asarray(b, dtype=np.float32)
    return b


def test():
    num_seconds = 64
    num_repeats = 8
    fs = 48000
    N = fs * num_seconds
    s_perseg = 6000#fs // 4
    num_segments = N // s_perseg
    assert num_segments * s_perseg == N

    audio_frame = AudioRecvFrame()
    # cdef cnp.ndarray[cnp.float32_t, ndim=3] samples = build_fake_data(fs, 2, N, num_segments, s_perseg)
    # cdef cnp.ndarray[cnp.float32_t, ndim=3] results = np.zeros((num_segments, 2, s_perseg), dtype=np.float32)
    samples = build_fake_data(fs, 2, N, num_segments, s_perseg)
    results = np.zeros((num_segments, 2, s_perseg), dtype=np.float32)
    print('_test start')
    # with nogil:
    # cdef size_t i
    # times = []
    # cdef cnp.ndarray[cnp.float64_t, ndim=1] times = np.zeros(num_repeats, dtype=np.float64)
    times = np.zeros(num_repeats, dtype=np.float64)
    g_start = time.time()
    # cdef double start_ts, end_ts, duration
    for i in range(num_repeats):
        start_ts = time.time()
        run_test(audio_frame, samples, results)
        end_ts = time.time()
        duration = end_ts - start_ts
        times[i] = duration
        assert np.array_equal(samples, results)
    g_end = time.time()
    print('_test return')
    times /= 1000
    min_t = times.min()
    max_t = times.max()
    avg_t = times.mean()
    print(f'min: {min_t}ms, max: {max_t}, avg: {avg_t}')
    time.sleep(.1)
    # np.savez('audio_frame_test', samples=samples, results=results)
