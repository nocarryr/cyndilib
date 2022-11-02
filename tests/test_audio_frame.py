import time
from pprint import pprint
from functools import partial
from collections import namedtuple
import threading
import traceback
import pytest

import numpy as np

from cyndilib.audio_frame import AudioRecvFrame, AudioFrameSync

from _test_audio_frame import fill_audio_frame, fill_audio_frame_sync, audio_frame_process_events



AudioParams = namedtuple('AudioParams', [
    'sample_rate', 'num_channels', 'num_samples', 'num_segments', 's_perseg',
    'samples_3d', 'samples_2d'],
    defaults=[
        48000, 2, 48000*2, 48000*2//6000, 6000, None, None,
    ]
)

# DEFAULT_AUDIO_PARAMS = AudioParams(
#     sample_rate=48000,
#     num_channels=2,
#     num_samples=48000 * 2,
#     s_perseg=6000,
#     num_segments = 48000 * 2 // 6000,
#     samples_3d=None,
#     samples_2d=None,
# )

@pytest.fixture
def fake_audio_builder():
    def build_fake_data(
        params: AudioParams
        # sample_rate: int,
        # num_channels: int,
        # num_samples: int,
        # num_segments: int,
        # s_perseg: int,
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
        # result = AudioParams(
        #     sample_rate, num_channels, num_samples, num_segments, s_perseg, b, a,
        # )
        # return result
    return build_fake_data

@pytest.fixture(params=[2, 8, 16, 32])
def num_seconds(request):
    return request.param

@pytest.fixture
def fake_audio_data(num_seconds, fake_audio_builder):
    params = AudioParams()
    num_samples = params.sample_rate * num_seconds
    num_segments = num_samples // params.s_perseg
    params = params._replace(num_samples=num_samples, num_segments=num_segments)
    return fake_audio_builder(params)

@pytest.fixture
def fake_audio_data_longer(num_seconds, fake_audio_builder):
    params = AudioParams()
    num_samples = params.sample_rate * num_seconds * 2
    num_segments = num_samples // params.s_perseg
    params = params._replace(num_samples=num_samples, num_segments=num_segments)
    return fake_audio_builder(params)

def test_buffer_read_all(fake_audio_data):
    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    max_buffers = fake_audio_data.num_segments
    num_segments = fake_audio_data.num_segments
    s_perseg = fake_audio_data.s_perseg
    audio_frame = AudioRecvFrame(max_buffers=max_buffers)
    assert audio_frame.max_buffers == max_buffers

    max_bfr_samples = max_buffers * s_perseg
    assert max_bfr_samples == N

    print(f'{max_buffers=}, {max_bfr_samples=}')

    assert num_segments * s_perseg == N


    samples = fake_audio_data.samples_3d
    samples_flat = fake_audio_data.samples_2d
    timestamps = np.arange(num_segments) / fs * s_perseg
    ndi_timestamps = np.zeros(num_segments, dtype=np.int32)
    results = np.zeros((num_segments, num_channels, s_perseg), dtype=np.float32)
    # read_timestamps = np.zeros_like(ndi_timestamps)

    for i in range(max_buffers):
        ndi_ts, read_indices = fill_audio_frame(audio_frame, samples[i], fs, timestamps[i])
        ndi_timestamps[i] = ndi_ts
        bfr_depth = audio_frame.get_buffer_depth()
        # print(f'{read_indices=}')
        print(f'{i=} {bfr_depth=}')
        assert bfr_depth == i + 1
    # print('buffering complete')
    # time.sleep(.2)

    num_read_samples = audio_frame.get_read_length()
    assert num_read_samples == max_bfr_samples
    # print('get_all_read_data()')
    # time.sleep(.1)
    read_data, read_timestamps = audio_frame.get_all_read_data()
    # time.sleep(.1)
    assert audio_frame.get_read_length() == 0
    print(f'{read_data.shape=}')

    assert read_data.shape[1] == num_read_samples
    num_read_segments = num_read_samples // s_perseg
    print(f'{num_segments=}, {num_read_segments=}, {num_read_samples=}')
    assert np.array_equal(samples_flat, read_data)
    assert np.array_equal(ndi_timestamps, read_timestamps)
    col_idx = 0
    for i in range(num_read_segments):
        print(f'{i=}, {col_idx=}')
        results[i,...] = read_data[:, col_idx:col_idx+s_perseg]
        col_idx += s_perseg
    assert np.array_equal(samples[:max_buffers,...], results[:max_buffers,...])
    # print('exit')
    # time.sleep(.5)


def test_buffer_read_single(fake_audio_data_longer):
    fake_audio_data = fake_audio_data_longer
    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    max_buffers = fake_audio_data.num_segments // 2
    num_segments = fake_audio_data.num_segments
    s_perseg = fake_audio_data.s_perseg
    audio_frame = AudioRecvFrame(max_buffers=max_buffers)

    assert max_buffers * s_perseg == N // 2

    samples = fake_audio_data.samples_3d
    samples_flat = fake_audio_data.samples_2d
    timestamps = np.arange(num_segments) / fs * s_perseg
    ndi_timestamps = np.zeros(num_segments, dtype=np.int32)
    results = np.zeros((num_segments, num_channels, s_perseg), dtype=np.float32)


    for i in range(num_segments):
        # print(f'{i=}, {audio_frame.view_count=}')
        ndi_ts, read_indices = fill_audio_frame(audio_frame, samples[i], fs, timestamps[i])
        ndi_timestamps[i] = ndi_ts
        print(f'{read_indices=}')
        assert audio_frame.get_buffer_depth() == 1
        read_data, read_timestamp = audio_frame.get_read_data()
        assert read_data.shape == (num_channels, s_perseg)
        results[i,...] = read_data
        assert read_timestamp == ndi_timestamps[i]
        assert audio_frame.get_buffer_depth() == 0
    assert np.array_equal(samples, results)

def test_buffer_fill_read_data(fake_audio_data):
    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    max_buffers = fake_audio_data.num_segments
    num_segments = fake_audio_data.num_segments
    s_perseg = fake_audio_data.s_perseg
    audio_frame = AudioRecvFrame(max_buffers=max_buffers)

    samples = fake_audio_data.samples_3d
    samples_flat = fake_audio_data.samples_2d
    timestamps = np.arange(num_segments) / fs * s_perseg
    ndi_timestamps = np.zeros(num_segments, dtype=np.int32)
    results = np.zeros((num_segments, num_channels, s_perseg), dtype=np.float32)
    read_data = np.zeros((num_channels, s_perseg), dtype=np.float32)

    for i in range(num_segments):
        ndi_ts, read_indices = fill_audio_frame(audio_frame, samples[i], fs, timestamps[i])
        ndi_timestamps[i] = ndi_ts
        read_timestamp = audio_frame.fill_read_data(read_data)
        assert read_timestamp == ndi_ts
        assert np.array_equal(read_data, samples[i])
        results[i,...] = read_data[...]

    assert np.array_equal(samples, results)

def test_buffer_fill_read_data_threaded(fake_audio_data, listener_pair):
    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    max_buffers = fake_audio_data.num_segments
    num_segments = fake_audio_data.num_segments
    s_perseg = fake_audio_data.s_perseg
    audio_frame = AudioRecvFrame(max_buffers=max_buffers)

    samples = fake_audio_data.samples_3d
    samples_flat = fake_audio_data.samples_2d
    timestamps = np.arange(num_segments) / fs * s_perseg
    ndi_timestamps = np.zeros(num_segments, dtype=np.int32)
    results = np.zeros((num_segments, num_channels, s_perseg), dtype=np.float32)
    result_timestamps = np.zeros(num_segments, dtype=np.int64)
    read_data = np.zeros((num_channels, s_perseg), dtype=np.float32)
    read_timestamps = np.zeros(num_segments, dtype=np.int64)


    sender_thread, listener_thread = listener_pair
    sender_thread.audio_frame = audio_frame
    # sender_thread.callback = process_callback
    sender_thread.run_forever = True

    i = 0
    read_idx, write_idx = 0, 0
    num_written, num_read = 0, 0
    num_remain = num_segments
    while write_idx < num_segments:
        print(f'{i=}, {num_written=}, {num_read=}, {num_remain=}')
        print(f'{read_idx=}, {write_idx=}')
        ndi_ts, read_indices = fill_audio_frame(
            audio_frame, samples[write_idx], fs, timestamps[write_idx], do_process=False
        )
        print(read_indices)
        ndi_timestamps[write_idx] = ndi_ts
        for state, data in listener_thread:
            print(f'{state=}, {data=}')
            if state == 'process_triggered':
                pass
            elif state == 'process_finished':
                num_written += 1
                num_remain -= 1
                proc_bfr_len, proc_ts = data
                assert proc_bfr_len == num_written - num_read == audio_frame.get_buffer_depth()
                assert proc_ts == ndi_timestamps[write_idx]

                write_idx += 1
                next_ndi_ts, read_indices = fill_audio_frame(
                    audio_frame, samples[write_idx], fs, timestamps[write_idx], do_process=True
                )
                print(read_indices)
                ndi_timestamps[write_idx] = next_ndi_ts
                assert audio_frame.get_buffer_depth() == proc_bfr_len + 1
                # assert next_ndi_ts ==
                num_written += 1
                num_remain -= 1
                assert audio_frame.get_buffer_depth() == num_written - num_read
                read_timestamp = audio_frame.fill_read_data(read_data)
                assert read_timestamp == ndi_timestamps[read_idx]
                assert np.array_equal(read_data, samples[read_idx])
                write_idx += 1
                read_idx += 1
                num_read += 1
                # num_remain -= 1
            elif state == 'callback_result':
                pass
        i += 2


def test_buffer_overwrite(fake_audio_data_longer):
    fake_audio_data = fake_audio_data_longer
    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    max_buffers = fake_audio_data.num_segments // 2
    num_segments = fake_audio_data.num_segments
    s_perseg = fake_audio_data.s_perseg
    audio_frame = AudioRecvFrame(max_buffers=max_buffers)

    assert max_buffers * s_perseg == N // 2

    samples = fake_audio_data.samples_3d
    samples_flat = fake_audio_data.samples_2d
    timestamps = np.arange(num_segments) / fs * s_perseg
    ndi_timestamps = np.zeros(num_segments, dtype=np.int32)
    results = np.zeros((num_segments, num_channels, s_perseg), dtype=np.float32)

    for i in range(num_segments):
        ndi_ts, read_indices = fill_audio_frame(audio_frame, samples[i], fs, timestamps[i])
        ndi_timestamps[i] = ndi_ts
        bfr_len = audio_frame.get_buffer_depth()
        print(f'{i=}, {bfr_len=}, {read_indices=}')
        cur_timestamp = audio_frame.get_timestamp()
        assert cur_timestamp == ndi_ts

        if i >= max_buffers:
            assert bfr_len == max_buffers
            segment_index = i - max_buffers + 1
            assert segment_index > 0
            print(f'{segment_index=}, {cur_timestamp=}')
            read_data, read_timestamp = audio_frame.get_read_data()
            assert np.array_equal(read_data, samples[segment_index,...])
            assert read_timestamp == ndi_timestamps[segment_index]



def test_frame_sync(fake_audio_data_longer):
    fake_audio_data = fake_audio_data_longer
    # fs = 48000
    # N = 60
    # num_channels = 2

    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    max_buffers = fake_audio_data.num_segments // 2
    num_segments = fake_audio_data.num_segments
    s_perseg = fake_audio_data.s_perseg
    audio_frame = AudioFrameSync()

    def iter_divisors():
        while True:
            yield from range(2, 32)
    divisor_iter = iter_divisors()

    def next_sample_length(num_samples_used):
        num_remain = N - num_samples_used
        if num_remain < 3:
            return num_remain
        i = 0
        while True:
            divisor = next(divisor_iter)
            if num_remain % divisor == 0:
                return num_remain // divisor
            i += 1
            if i > 32:
                return num_remain

    samples = fake_audio_data.samples_3d
    samples_flat = fake_audio_data.samples_2d
    ndi_timestamps = []
    results = []

    num_samples_used = 0
    s_idx = 0
    e_idx = 0
    last_ts = 0
    while num_samples_used < N:
        samp_len = next_sample_length(num_samples_used)
        # print(f'{samp_len=}, {num_samples_used=}')
        e_idx = s_idx + samp_len
        src_samples = samples_flat[:,s_idx:e_idx]
        fill_audio_frame_sync(audio_frame, src_samples, fs, last_ts)
        r = audio_frame.get_array()
        assert np.array_equal(src_samples, r)
        results.append(r)
        last_ts += samp_len / fs
        num_samples_used += samp_len
        s_idx = e_idx

    results = np.concatenate(results, axis=1)
    assert np.array_equal(samples_flat, results)
