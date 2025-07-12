from __future__ import annotations
import pytest
import threading
import time
from fractions import Fraction
from functools import partial
import numpy as np

from cyndilib.wrapper.ndi_structs import FourCC
from cyndilib.sender import Sender
from cyndilib.video_frame import VideoSendFrame
from cyndilib.audio_frame import AudioSendFrame
from cyndilib.locks import RLock, Condition

from conftest import IS_CI_BUILD, AudioParams, VideoParams

import _test_sender             # type: ignore[missing-import]
import _test_audio_frame        # type: ignore[missing-import]
import _test_send_frame_status  # type: ignore[missing-import]

NULL_INDEX = _test_send_frame_status.get_null_idx()
MAX_FRAME_BUFFERS = _test_send_frame_status.get_max_frame_buffers()


def test_send_video(request, fake_video_frames: VideoParams):
    width, height, fr, num_frames, fake_frames = fake_video_frames
    name = request.node.nodeid.split('::')[-1]
    sender = Sender(name)
    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    assert vf.get_fourcc() == FourCC.RGBA
    print(f'{vf.get_fourcc()=}')

    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)
    vf.set_metadata(b'<some_xml_tag />')
    sender.set_video_frame(vf)

    one_frame = 1 / fr
    wait_time = float(one_frame)

    print('opening sender')
    with sender:
        pass
    time.sleep(.2)
    print('opening again')
    with sender:
        iter_start_ts = time.time()
        for i in range(num_frames):
            start_ts = time.time()
            print(f'send frame {i}')
            vf.set_metadata(b'<some_other_xml_tag />')
            r = sender.write_video_async(fake_frames[i])
            assert r is True
            elapsed = time.time() - start_ts
            if elapsed < wait_time:
                sleep_time = wait_time - elapsed - .0005
                if sleep_time < 0:
                    continue
                print(f'{sleep_time=}')
                time.sleep(sleep_time)
        iter_end_ts = time.time()

    iter_duration = iter_end_ts - iter_start_ts
    expected_dur = one_frame * num_frames
    print(f'{iter_duration=}, {float(expected_dur)=}')
    if not IS_CI_BUILD:
        dur_min = expected_dur - one_frame
        dur_max = expected_dur + one_frame
        assert dur_min <= expected_dur <= dur_max
    print('sender closed')


def setup_sender(
    request: pytest.FixtureRequest,
    video_data: VideoParams,
    audio_data: AudioParams,
) -> Sender:
    # name = 'test_send_video'
    name = request.node.nodeid.split('::')[-1]
    print(f'{name=}')
    sender = Sender(name, clock_video=True, clock_audio=True)
    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    assert vf.get_fourcc() == FourCC.RGBA
    print(f'{vf.get_fourcc()=}')

    vf.set_frame_rate(video_data.frame_rate)
    vf.set_resolution(video_data.width, video_data.height)
    assert vf.get_frame_rate() == video_data.frame_rate
    assert vf.xres == video_data.width
    assert vf.yres == video_data.height
    sender.set_video_frame(vf)

    af = AudioSendFrame()
    af.sample_rate = audio_data.sample_rate
    af.num_channels = audio_data.num_channels
    af.set_max_num_samples(audio_data.s_perseg)
    sender.set_audio_frame(af)

    return sender

def test_send_video_and_audio_cy(request, fake_av_frames: tuple[VideoParams, AudioParams]):
    video_data, audio_data = fake_av_frames

    sender = setup_sender(request, video_data, audio_data)

    num_frame_repeats = 2
    num_full_repeats = 1
    one_frame = 1 / video_data.frame_rate

    start_ts = time.time()
    frame_times = _test_sender.test_send_video_and_audio(
        sender, video_data.frames, audio_data.samples_3d, video_data.frame_rate,
        num_frame_repeats, num_full_repeats, send_audio=True,
    )
    end_ts = time.time()

    duration = end_ts - start_ts
    expected_dur = one_frame * video_data.num_frames * num_frame_repeats * num_full_repeats
    print(f'{duration=}, {float(expected_dur)=}')
    if not IS_CI_BUILD:
        dur_min = expected_dur - one_frame
        dur_max = expected_dur + one_frame
        assert dur_min <= expected_dur <= dur_max

    fps_arr = 1 / frame_times[:,1:]
    # print(f'{fps_arr=}')
    print(f'{fps_arr.mean()=}, {frame_times.mean()=}, {fps_arr.min()=}, {fps_arr.max()=}')

    print('sender closed')


def test_send_video_and_audio_py(request, fake_av_frames: tuple[VideoParams, AudioParams]):
    video_data, audio_data = fake_av_frames

    sender = setup_sender(request, video_data, audio_data)
    vf = sender.video_frame
    af = sender.audio_frame

    if vf:
        vf.set_metadata(b'<some_xml_tag />')

    num_frame_repeats = 2
    num_full_repeats = 1
    one_frame = 1 / video_data.frame_rate

    frame_times = np.zeros((num_full_repeats, num_frame_repeats*video_data.num_frames), dtype=np.float64)

    cur_iteration = 0
    while cur_iteration < num_full_repeats:
        j = 0
        vid_write_index, aud_write_index = 0, 0
        vid_read_index, aud_read_index = NULL_INDEX, NULL_INDEX

        with sender:
            # time.sleep(.5)
            assert sender._running is True
            assert sender.source is not None
            print(f'{sender.source.name=}')
            print('loop_start')
            # time.sleep(.5)
            iter_start_ts = time.time()
            for x in range(num_frame_repeats):
                for i in range(video_data.num_frames):
                    # print(f'send frame {i}')
                    start_ts = time.time()
                    vid_read_index = NULL_INDEX

                    send_separately = i % 4 == 0
                    send_sync = i % 8 == 0

                    if send_separately:
                        r = sender.write_audio(audio_data.samples_3d[i])
                        assert r is True
                        if send_sync:
                            r = sender.write_video(video_data.frames[i])
                        else:
                            r = sender.write_video_async(video_data.frames[i])
                        assert r is True
                    else:
                        r = sender.write_video_and_audio(video_data.frames[i], audio_data.samples_3d[i])
                        assert r is True

                    aud_write_index = (aud_write_index + 1) % MAX_FRAME_BUFFERS
                    vid_send_ready = not send_sync or not send_separately
                    if vid_send_ready:
                        vid_read_index = vid_write_index
                    else:
                        vid_read_index = NULL_INDEX
                    vid_write_index = (vid_write_index + 1) % MAX_FRAME_BUFFERS

                    _test_send_frame_status.check_audio_send_frame(af, aud_write_index, aud_read_index)
                    _test_send_frame_status.check_video_send_frame(vf, vid_write_index, vid_read_index)

                    elapsed = time.time() - start_ts
                    frame_times[cur_iteration, j] = elapsed
                    j += 1
            iter_end_ts = time.time()

        iter_duration = iter_end_ts - iter_start_ts
        expected_dur = one_frame * video_data.num_frames * num_frame_repeats
        print(f'{iter_duration=}, {float(expected_dur)=}')
        if not IS_CI_BUILD:
            dur_min = expected_dur - one_frame
            dur_max = expected_dur + one_frame
            assert dur_min <= iter_duration <= dur_max
        cur_iteration += 1

    fps_arr = 1 / frame_times[:,1:]
    # print(f'{fps_arr=}')
    print(f'{fps_arr.mean()=}, {frame_times.mean()=}, {fps_arr.min()=}, {fps_arr.max()=}')

    print('sender closed')
    del vf
    del af
    del sender
    time.sleep(1)

class SenderThread(threading.Thread):
    def __init__(
        self,
        sender: Sender,
        data: VideoParams|AudioParams,
        wait_time: float,
        num_frame_repeats: int,
        go_cond: threading.Condition,
        sync_rlock: RLock
    ):
        super().__init__()
        self.sender = sender
        self.data = data
        self.wait_time = wait_time
        self.num_frame_repeats = num_frame_repeats
        self.frame_times = np.zeros(num_frame_repeats*self.num_frames, dtype=np.float64)
        self.duration = None
        self.running = False
        self.ready = threading.Event()
        self.go = go_cond
        self.sync_rlock = sync_rlock
        self.sync_cond = Condition(sync_rlock)
        self.current_frame_count = 0
        self.dependent_cond = None
        self.dependent_thread = None
        self.stopped = threading.Event()
        self.exc = None

    @property
    def num_frames(self) -> int:
        return self.get_num_frames()

    def set_dependent_thread(self, oth_thread: 'SenderThread'):
        if oth_thread is None:
            self.dependent_thread = None
        else:
            self.dependent_thread = oth_thread

    def wait_for_dependent(self):
        oth_thread = self.dependent_thread
        if oth_thread is None:
            return
        cond = oth_thread.sync_cond
        def predicate(oth_thread, i):
            if oth_thread.exc is not None:
                return True
            return oth_thread.current_frame_count >= i
        with cond:
            if self.current_frame_count > oth_thread.current_frame_count:
                return
            p = partial(predicate, oth_thread, self.current_frame_count + 1)
            cond.wait_for(p)

    def run(self):
        try:
            self.running = True
            with self.go:
                self.ready.set()
                print(f'{self} waiting')
                self.go.wait()

            print(f'{self} running')
            iter_start_ts = time.time()
            num_frames = self.num_frames
            j = 0
            for x in range(self.num_frame_repeats):
                for i in range(num_frames):
                    # print(f'{self} send_frame {i}')
                    self.wait_for_dependent()
                    start_ts = time.time()
                    self.send(i)

                    elapsed = time.time() - start_ts
                    self.frame_times[j] = elapsed
                    j += 1
                    with self.sync_cond:
                        self.current_frame_count += 1
                        self.sync_cond.notify_all()
            iter_end_ts = time.time()
            self.duration = iter_end_ts - iter_start_ts
            self.fps_arr = 1 / self.frame_times[1:]
        except Exception as exc:
            with self.sync_cond:
                self.exc = exc
                self.sync_cond.notify_all()
            import traceback
            traceback.print_exc()
            raise
        finally:
            self.stopped.set()

    def get_num_frames(self) -> int:
        raise NotImplementedError()

    def send(self, i: int):
        raise NotImplementedError()

class VideoSenderThread(SenderThread):
    data: VideoParams
    def get_num_frames(self) -> int:
        return self.data.num_frames

    def send(self, i: int):
        data = self.data.frames[i]
        if i % 4 == 0:
            self.sender.write_video(data)
        else:
            self.sender.write_video_async(data)

class AudioSenderThread(SenderThread):
    data: AudioParams
    def get_num_frames(self) -> int:
        return self.data.num_segments

    def send(self, i: int):
        data = self.data.samples_3d[i]
        # print(f'aud_data shape: {data.shape}')
        self.sender.write_audio(data)


@pytest.mark.flaky(max_runs=3)
def test_send_video_and_audio_threaded(request, fake_av_frames: tuple[VideoParams, AudioParams]):
    video_data, audio_data = fake_av_frames

    sender = setup_sender(request, video_data, audio_data)
    vf = sender.video_frame
    af = sender.audio_frame

    num_frame_repeats = 1
    num_full_repeats = 1

    one_frame = 1 / video_data.frame_rate
    wait_time = float(one_frame)

    go_cond = threading.Condition()

    cur_iteration = 0
    while cur_iteration < num_full_repeats:
        with sender:
            sync_rlock = RLock()
            vid_thread = VideoSenderThread(sender, video_data, wait_time, num_frame_repeats, go_cond, sync_rlock)
            aud_thread = AudioSenderThread(sender, audio_data, wait_time, num_frame_repeats, go_cond, sync_rlock)
            aud_thread.set_dependent_thread(vid_thread)
            vid_thread.start()
            aud_thread.start()
            vid_thread.ready.wait()
            aud_thread.ready.wait()

            with go_cond:
                print('notify_all')
                go_cond.notify_all()
                time.sleep(.5)

            vid_thread.join()
            aud_thread.join()
            assert vid_thread.exc is None
            assert aud_thread.exc is None
            fps_arr, frame_times = vid_thread.fps_arr, vid_thread.frame_times
            print(f'vid_thread: {fps_arr.mean()=}, {frame_times.mean()=}, {fps_arr.min()=}, {fps_arr.max()=}')
            fps_arr, frame_times = aud_thread.fps_arr, aud_thread.frame_times
            print(f'aud_thread: {fps_arr.mean()=}, {frame_times.mean()=}, {fps_arr.min()=}, {fps_arr.max()=}')

        expected_dur = one_frame * video_data.num_frames * num_frame_repeats
        print(f'{vid_thread.duration=}, {aud_thread.duration=}, {float(expected_dur)=}')
        if not IS_CI_BUILD:
            dur_min = expected_dur - one_frame
            dur_max = expected_dur + one_frame
            assert vid_thread.duration is not None
            assert aud_thread.duration is not None
            assert dur_min <= vid_thread.duration <= dur_max
            assert dur_min <= aud_thread.duration <= dur_max
        cur_iteration += 1
