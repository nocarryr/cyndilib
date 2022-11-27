import pytest
import threading
import time
from fractions import Fraction
import numpy as np

from cyndilib.wrapper.ndi_structs import FourCC
from cyndilib.sender import Sender
from cyndilib.video_frame import VideoSendFrame
from cyndilib.audio_frame import AudioSendFrame

from conftest import AudioParams, VideoParams

import _test_sender


def test_send_video(fake_video_frames):
    width, height, fr, num_frames, fake_frames = fake_video_frames

    sender = Sender('test_send_video')
    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    assert vf.get_fourcc() == FourCC.RGBA
    print(f'{vf.get_fourcc()=}')

    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)
    sender.set_video_frame(vf)

    one_frame = 1 / fr
    wait_time = float(one_frame)

    print('opening sender')
    with sender:
        pass

    with sender:
        iter_start_ts = time.time()
        for i in range(num_frames):
            start_ts = time.time()
            # print(f'send frame {i}')
            r = sender.write_video_async(fake_frames[i])
            assert r is True
            elapsed = time.time() - start_ts
            if elapsed < wait_time:
                sleep_time = wait_time - elapsed - .0005
                if sleep_time < 0:
                    continue
                # print(f'{sleep_time=}')
                time.sleep(sleep_time)
        iter_end_ts = time.time()

    iter_duration = iter_end_ts - iter_start_ts
    expected_dur = one_frame * num_frames
    print(f'{iter_duration=}, {float(expected_dur)=}')
    assert expected_dur - .5 <= iter_duration <= expected_dur + .5

    print('sender closed')


def setup_sender(
    request: pytest.FixtureRequest,
    video_data: VideoParams,
    audio_data: AudioParams,
) -> Sender:
    # name = 'test_send_video'
    name = request.node.nodeid.split('::')[-1]
    print(f'{name=}')
    sender = Sender(name)
    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    assert vf.get_fourcc() == FourCC.RGBA
    print(f'{vf.get_fourcc()=}')

    vf.set_frame_rate(video_data.frame_rate)
    vf.set_resolution(video_data.width, video_data.height)
    sender.set_video_frame(vf)

    af = AudioSendFrame()
    af.sample_rate = audio_data.sample_rate
    af.num_channels = audio_data.num_channels
    af.set_max_num_samples(audio_data.s_perseg)
    sender.set_audio_frame(af)

    return sender

def test_send_video_and_audio_cy(request, fake_av_frames):
    video_data, audio_data = fake_av_frames

    sender = setup_sender(request, video_data, audio_data)

    num_frame_repeats = 2
    num_full_repeats = 1
    one_frame = 1 / video_data.frame_rate

    start_ts = time.time()
    frame_times = _test_sender.test_send_video_and_audio(
        sender, video_data.frames, audio_data.samples_3d, video_data.frame_rate,
        num_frame_repeats, num_full_repeats,
    )
    end_ts = time.time()

    duration = end_ts - start_ts
    expected_dur = one_frame * video_data.num_frames * num_frame_repeats * num_full_repeats
    print(f'{duration=}, {float(expected_dur)=}')
    assert expected_dur - .5 <= duration <= expected_dur + .5

    fps_arr = 1 / frame_times[:,1:]
    # print(f'{fps_arr=}')
    print(f'{fps_arr.mean()=}, {frame_times.mean()=}, {fps_arr.min()=}, {fps_arr.max()=}')

    print('sender closed')


def test_send_video_and_audio_py(request, fake_av_frames):
    video_data, audio_data = fake_av_frames

    sender = setup_sender(request, video_data, audio_data)
    vf = sender.video_frame
    af = sender.audio_frame

    num_frame_repeats = 2
    num_full_repeats = 1
    one_frame = 1 / video_data.frame_rate

    frame_times = np.zeros((num_full_repeats, num_frame_repeats*video_data.num_frames), dtype=np.float64)

    cur_iteration = 0
    while cur_iteration < num_full_repeats:
        j = 0
        with sender:
            # time.sleep(.5)
            assert sender._running is True
            print(f'{sender.source.name=}')
            print('loop_start')
            # time.sleep(.5)
            iter_start_ts = time.time()
            for x in range(num_frame_repeats):
                for i in range(video_data.num_frames):
                    # print(f'send frame {i}')
                    start_ts = time.time()

                    r = sender.write_video_and_audio(video_data.frames[i], audio_data.samples_3d[i])

                    elapsed = time.time() - start_ts
                    frame_times[cur_iteration, j] = elapsed
                    j += 1
            iter_end_ts = time.time()

        iter_duration = iter_end_ts - iter_start_ts
        expected_dur = one_frame * video_data.num_frames * num_frame_repeats
        print(f'{iter_duration=}, {float(expected_dur)=}')
        assert expected_dur - .5 <= iter_duration <= expected_dur + .5
        cur_iteration += 1

    fps_arr = 1 / frame_times[:,1:]
    # print(f'{fps_arr=}')
    print(f'{fps_arr.mean()=}, {frame_times.mean()=}, {fps_arr.min()=}, {fps_arr.max()=}')

    print('sender closed')

class SenderThread(threading.Thread):
    def __init__(
        self,
        sender: Sender,
        data: VideoParams|AudioParams,
        wait_time: float,
        num_frame_repeats: int,
        go_cond: threading.Condition,
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
        self.stopped = threading.Event()
        self.exc = None

    @property
    def num_frames(self) -> int:
        return self.get_num_frames()

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
                    start_ts = time.time()
                    self.send(i)

                    elapsed = time.time() - start_ts
                    self.frame_times[j] = elapsed
                    j += 1
            iter_end_ts = time.time()
            self.duration = iter_end_ts - iter_start_ts
            fps_arr = 1 / self.frame_times[1:]
            # print(f'{self}: {fps_arr=}')
            print(f'{self}: {fps_arr.mean()=}, {self.frame_times.mean()=}, {fps_arr.min()=}, {fps_arr.max()=}')
        except Exception as exc:
            self.exc = exc
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
    def get_num_frames(self) -> int:
        return self.data.num_frames

    def send(self, i: int):
        data = self.data.frames[i]
        self.sender.write_video(data)

class AudioSenderThread(SenderThread):
    def get_num_frames(self) -> int:
        return self.data.num_segments

    def send(self, i: int):
        data = self.data.samples_3d[i]
        # print(f'aud_data shape: {data.shape}')
        self.sender.write_audio(data)


def test_send_video_and_audio_threaded(request, fake_av_frames):
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
            vid_thread = VideoSenderThread(sender, video_data, wait_time, num_frame_repeats, go_cond)
            aud_thread = AudioSenderThread(sender, audio_data, wait_time, num_frame_repeats, go_cond)
            vid_thread.start()
            aud_thread.start()
            vid_thread.ready.wait()
            aud_thread.ready.wait()
            # time.sleep(.1)
            with go_cond:
                print('notify_all')
                go_cond.notify_all()
                time.sleep(.5)
            # vid_thread.stopped.wait()
            # aud_thread.stopped.wait()
            vid_thread.join()
            aud_thread.join()
            assert vid_thread.exc is None
            assert aud_thread.exc is None

        expected_dur = one_frame * video_data.num_frames * num_frame_repeats
        print(f'{vid_thread.duration=}, {aud_thread.duration=}, {float(expected_dur)=}')
        assert expected_dur - .5 <= vid_thread.duration <= expected_dur + .5
        assert expected_dur - .5 <= aud_thread.duration <= expected_dur + .5
        cur_iteration += 1
