from __future__ import annotations
import time
from pprint import pprint
from functools import partial
import threading
import traceback
import pytest

import numpy as np

from conftest import AudioParams, IS_CI_BUILD

from cyndilib.locks import RLock, Condition
from cyndilib.audio_frame import AudioRecvFrame, AudioFrameSync, AudioSendFrame

from _test_audio_frame import (
    fill_audio_frame, fill_audio_frame_sync, audio_frame_process_events,
)
from _test_send_frame_status import (
    set_send_frame_sender_status, set_send_frame_send_complete,
    check_audio_send_frame, get_max_frame_buffers, get_null_idx,
)

NULL_INDEX = get_null_idx()
MAX_FRAME_BUFFERS = get_max_frame_buffers()

class State:
    def __init__(self, group: 'StateGroup', name: str, index_: int):
        self.__name = name
        self.__index = index_
        self._active = False
        self.group = group
        self.active_cond = Condition(group._lock)
        self.inactive_cond = Condition(group._lock)
        self._handler = None
    @property
    def name(self) -> str:
        return self.__name
    @property
    def index(self) -> int:
        return self.__index
    @property
    def active(self) -> bool:
        return self._active
    @active.setter
    def active(self, value: bool):
        self.set_active(value)

    def set_handler(self, cb):
        assert self._handler is None
        assert callable(cb)
        self._handler = cb

    def __call__(self) -> bool:
        if self._handler is not None:
            result = self._handler()
            return result
        return True

    def acquire(self, blocking=True, timeout=-1):
        self.group.acquire(blocking, timeout)
    def release(self):
        self.group.release()
    def __enter__(self):
        self.group.acquire()
        return self
    def __exit__(self, *args):
        self.group.release()

    def set_active(self, value: bool):
        with self.group:
            if not self.group.can_continue:
                return
            if value is self.active:
                return
            # self._active = value
            self._set_active(value)
            self.group._on_state_active(self, value)

    def _set_active(self, value: bool):
        self._active = value
        if value:
            self.inactive_cond.notify_all()
        else:
            self.active_cond.notify_all()

    def __repr__(self):
        return f'<{self.__class__.__name__}: {self}>'
    def __str__(self):
        if self.group.name is not None:
            name = f'{self.group.name}.{self.name}'
        else:
            name = self.name
        return f'"{name}" (active={self.active})'

class StateGroup:
    def __init__(
        self,
        state_names: list[str],
        lock: RLock|None = None,
        name: str|None = None,
        state_continue_timeout: float = .01,
    ):
        if len(state_names) != len(set(state_names)):
            raise ValueError('state_names must be unique')
        self.state_names = state_names
        self.name = name
        if lock is None:
            lock = RLock()
        self._lock = lock
        self._lock_count = 0
        states = [State(self, name, i) for i, name in enumerate(state_names)]
        self.states = {state.name:state for state in states}
        self.states_by_index = tuple(states)
        self.state_cond = Condition(lock)
        self.continue_wait_cond = Condition(lock)
        self.state_continue_timeout = state_continue_timeout
        self._can_continue = True
        self._current_state_name = None

    @property
    def current_state(self) -> State|None:
        if self._current_state_name is None:
            return None
        return self.states[self._current_state_name]
    @current_state.setter
    def current_state(self, value: State|str|None):
        self.set_current_state(value)

    @property
    def can_continue(self) -> bool:
        if self.current_state is None:
            self._can_continue = True
        return self._can_continue

    def set_current_state(self, state:State|str|None):
        with self:
            if state is None:
                assert self.current_state is not None
                self._can_continue = True
                self.current_state.set_active(False)
            else:
                if not isinstance(state, State):
                    state = self[state]
                if state is self.current_state:
                    return
                state.set_active(True)

    def activate_next_state(self):
        with self:
            if not self.can_continue:
                return self.current_state
            if self.current_state is None:
                state = self.states_by_index[0]
            else:
                idx = self.current_state.index + 1
                try:
                    state = self.states_by_index[idx]
                except IndexError:
                    state = None
            self.current_state = state
        return state

    def set_handler(self, state: State|str, cb):
        if not isinstance(state, State):
            state = self[state]
        state.set_handler(cb)

    def copy(self) -> StateGroup:
        state_names = [state.name for state in self.states_by_index]
        return StateGroup(state_names, state_continue_timeout=self.state_continue_timeout)

    def _on_state_active(self, state: State, value: bool):
        prev_state_name = self._current_state_name
        if value:
            for oth_state in self:
                if oth_state is state:
                    continue
                if oth_state.active:
                    oth_state._set_active(False)
            self._current_state_name = state.name
        else:
            if self.current_state is state:
                self._current_state_name = None

        if prev_state_name != self._current_state_name:
            self.state_cond.notify_all()

    def acquire(self, blocking=True, timeout=-1):
        self._lock.acquire(blocking, timeout)
    def release(self):
        self._lock.release()
    def __enter__(self):
        self.acquire()
        return self
    def __exit__(self, *args):
        self.release()

    def call_state_handler(self) -> bool:
        assert not self._lock.locked or self._lock._is_owned()
        state = self.current_state
        if state is None:
            self._can_continue = True
        else:
            self._can_continue = state()
        return self.can_continue

    def wait_if_no_continue(self):
        if self.can_continue:
            return
        with self:
            self.continue_wait_cond.wait(self.state_continue_timeout)

    def get(self, name: str) -> State|None:
        return self.states.get(name)
    def __getitem__(self, name: str) -> State:
        return self.states[name]

    def __iter__(self):
        yield from self.states.values()

    def __repr__(self):
        if self.name is not None:
            f'<{self.name}: "{self.states!r}">'
        return f'<{self.__class__.__name__}: "{self.states!r}">'
    def __str__(self):
        return str(self.states)


class StateThread(threading.Thread):
    def __init__(
        self,
        state_group: StateGroup,
        num_iterations: int = 1,
        iter_duration: float|None = None,
        exc_cond: Condition|None = None,
    ):
        super().__init__()
        self.state_group = state_group
        self.num_iterations = num_iterations
        self.iter_duration = iter_duration
        self._cur_iteration = 0
        self.finished = False
        self._running = False
        self.started = threading.Event()
        self.stopped = threading.Event()
        self.continue_evt = threading.Event()
        self.continue_cond = threading.Condition()
        if exc_cond is None:
            exc_cond = Condition()
        self.exc_cond = exc_cond
        self.exc = None
    @property
    def cur_iteration(self) -> int:
        return self._cur_iteration
    @cur_iteration.setter
    def cur_iteration(self, value: int):
        self._cur_iteration = value
        # print(f'{self.state_group.name}: cur_iteration={value}')
    def run(self):
        self._running = True
        iter_start_ts = None
        try:
            while self._running:
                self.started.set()
                self.continue_evt.wait()

                with self.state_group as g:
                    if not self._running:
                        g.state_cond.notify_all()
                        break
                    last_state = g.current_state
                    if last_state is None or iter_start_ts is None:
                        iter_start_ts = time.time()
                    if g.can_continue:
                        state = g.activate_next_state()
                        # print(f'StateThread {state=}')
                        if state is None:
                            iter_end_ts = time.time()
                            elapsed = iter_end_ts - iter_start_ts
                            iter_start_ts = None
                            self.cur_iteration += 1
                            if self.cur_iteration >= self.num_iterations:
                                self.finished = True
                                g.state_cond.notify_all()
                                break
                            self.wait_for_next_iteration(elapsed)
                            continue
                    else:
                        state = g.current_state
                        assert state is not None
                        g.wait_if_no_continue()
                try:
                    g.call_state_handler()
                except Exception as exc:
                    self.exc = exc
                    traceback.print_exc()
                    with self.exc_cond:
                        self.exc_cond.notify_all()
                    break
                self.handle_state(state)
        except Exception as exc:
            self.exc = exc
            traceback.print_exc()
            with self.exc_cond:
                self.exc_cond.notify_all()
        print(f'<{self.__class__.__name__} ({self.state_group}) thread exit>')
        with self.exc_cond:
            self.exc_cond.notify_all()
        self.stopped.set()

    def stop(self):
        self._running = False
        with self.state_group as g:
            g.state_cond.notify_all()
        self.stopped.wait()

    def wait_for_next_iteration(self, elapsed: float):
        target_dur = self.iter_duration
        if target_dur is None:
            return
        if elapsed >= target_dur:
            return
        sleep_time = target_dur - elapsed
        time.sleep(sleep_time)

    def handle_state(self, state: State):
        pass
        # print(f'<{self.__class__.__name__}.handle_state({state!r})>')


@pytest.fixture(params=[2, 8] if IS_CI_BUILD else [2, 8, 16, 32])
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

@pytest.mark.flaky(max_runs=3)
def test_buffer_fill_read_data_threaded(fake_audio_data):
    fs = fake_audio_data.sample_rate
    N = fake_audio_data.num_samples
    num_channels = fake_audio_data.num_channels
    max_buffers = fake_audio_data.num_segments // 2
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

    state_names = (
        'FILL_FRAME', 'READ_FRAME',
    )
    num_iterations = num_segments
    segment_time = s_perseg / fs
    exc_cond = Condition()
    send_states = StateGroup(state_names, name='send_states', state_continue_timeout=.001)
    send_thread = StateThread(
        send_states,
        num_iterations=num_iterations,
        exc_cond=exc_cond,
        iter_duration=segment_time / 2,
    )
    read_states = send_states.copy()
    read_states.name = 'read_states'
    read_thread = StateThread(
        read_states,
        exc_cond=exc_cond,
        num_iterations=num_iterations,
        iter_duration=segment_time / 3
    )

    def _fill_frame():
        i = send_thread.cur_iteration
        ndi_ts, indices = fill_audio_frame(
            audio_frame, samples[i], fs, timestamps[i], check_can_receive = True
        )
        if ndi_ts is None:
            return False
        print(f'{i=}, {ndi_ts=}, {indices=}')
        return True
    send_states.set_handler('FILL_FRAME', _fill_frame)

    def fill_read_data():
        i = read_thread.cur_iteration
        if audio_frame.get_buffer_depth() == 0:
            return False
        ts = audio_frame.fill_read_data(read_data)
        print(f'{i=}, {ts=}')
        results[i,...] = read_data[...]
        result_timestamps[i] = read_timestamps[0]
        return True
    read_states.set_handler('READ_FRAME', fill_read_data)

    send_thread.start()
    read_thread.start()
    send_thread.started.wait()
    read_thread.started.wait()
    send_thread.continue_evt.set()
    # read_thread.continue_evt.set()
    state = send_states['FILL_FRAME']
    try:
        while send_thread.cur_iteration < max_buffers:
            with send_states:
                send_states.state_cond.wait()

        with exc_cond:
            print('--------------starting-read-thread-----------------')
            read_thread.continue_evt.set()
            has_exc = exc_cond.wait()

        if has_exc:
            if send_thread.exc is not None:
                read_thread.stop()
            if read_thread.exc is not None:
                send_thread.stop()

        send_thread.join()
        read_thread.join()
    except:
        send_thread.stop()
        read_thread.stop()
        raise

    assert np.array_equal(samples[:num_iterations], results[:num_iterations])


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
        cur_timestamp = audio_frame.timestamp
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

def test_audio_send_frame(fake_audio_data):
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
    af.set_max_num_samples(s_perseg)

    expected_write_idx = 0
    expected_read_idx = NULL_INDEX


    assert af.write_index == expected_write_idx
    assert af.read_index == expected_read_idx


    set_send_frame_sender_status(af, True)
    assert af.ndim == 2
    assert af.shape == (num_channels, s_perseg)
    assert af.strides == (s_perseg*4, 4)
    assert af.write_index == expected_write_idx
    assert af.read_index == expected_read_idx
    check_audio_send_frame(af)

    for i in range(num_segments):
        print(f'{i=}')
        assert af.write_index == expected_write_idx
        assert af.read_index == expected_read_idx

        af.write_data(samples[i])

        expected_read_idx = expected_write_idx
        expected_write_idx = (expected_write_idx + 1) % MAX_FRAME_BUFFERS
        assert af.write_index == expected_write_idx
        assert af.read_index == expected_read_idx
        check_audio_send_frame(af)

        set_send_frame_send_complete(af)

        expected_read_idx = NULL_INDEX
        assert af.write_index == expected_write_idx
        assert af.read_index == expected_read_idx
        check_audio_send_frame(af)

    set_send_frame_sender_status(af, False)

    af.destroy()
    assert af.write_index == 0
    assert af.read_index == NULL_INDEX
