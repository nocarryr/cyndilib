from __future__ import annotations
from typing import Callable
from fractions import Fraction

import numpy as np
import pytest
from cyndilib import AudioReference
from cyndilib.video_frame import VideoSendFrame
from cyndilib.audio_frame import AudioSendFrame
from cyndilib.wrapper import FourCC
from _bench_helpers import BenchSender      # type: ignore[missing-import]
from conftest import VideoParams, VideoInitParams, AudioInitParams, AudioParams


@pytest.fixture(params=list(AudioReference), ids=lambda ar: ar.name)
def audio_reference(request) -> AudioReference:
    return request.param


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


@pytest.fixture
def fake_audio_data_bench(fake_audio_builder: Callable[[AudioInitParams], AudioParams]) -> AudioParams:
    num_seconds = 8
    params = AudioInitParams()
    num_samples = params.sample_rate * num_seconds
    num_segments = num_samples // params.s_perseg
    params = params._replace(num_samples=num_samples, num_segments=num_segments)
    return fake_audio_builder(params)


def test_audio_send_benchmark(benchmark, fake_audio_data_bench: AudioParams):
    num_channels = fake_audio_data_bench.num_channels
    num_segments = fake_audio_data_bench.num_segments
    s_perseg = fake_audio_data_bench.s_perseg
    samples = fake_audio_data_bench.samples_3d

    af = AudioSendFrame()
    af.sample_rate = fake_audio_data_bench.sample_rate
    af.num_channels = num_channels
    af.set_max_num_samples(s_perseg)
    assert af.num_samples == s_perseg
    sender = BenchSender()
    sender.set_audio_frame(af)

    def run_audio_test():
        for i in range(num_segments):
            sender.write_audio(samples[i])

    with sender:
        benchmark(run_audio_test)

    af.destroy()



def test_audio_send_reference_convert_benchmark(
    benchmark,
    fake_audio_data_bench: AudioParams,
    audio_reference: AudioReference
):
    num_channels = fake_audio_data_bench.num_channels
    num_segments = fake_audio_data_bench.num_segments
    s_perseg = fake_audio_data_bench.s_perseg
    samples = fake_audio_data_bench.samples_3d

    af = AudioSendFrame()
    af.reference_level = audio_reference
    af.sample_rate = fake_audio_data_bench.sample_rate
    af.num_channels = num_channels
    af.set_max_num_samples(s_perseg)
    assert af.num_samples == s_perseg
    sender = BenchSender()
    sender.set_audio_frame(af)

    def run_audio_test():
        for i in range(num_segments):
            sender.write_audio(samples[i])

    with sender:
        benchmark(run_audio_test)

    af.destroy()


def test_video_send_benchmark(benchmark, fake_video_frames_bench: VideoParams):
    width, height, fr, num_frames, fake_frames = fake_video_frames_bench

    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)
    assert vf.get_line_stride() == width * 4

    sender = BenchSender()
    sender.set_video_frame(vf)

    def run_video_test():
        for i in range(num_frames):
            sender.write_video(fake_frames[i])

    with sender:
        benchmark(run_video_test)

    vf.destroy()


def test_video_and_audio_send_benchmark(
    benchmark,
    fake_video_frames_bench: VideoParams,
    fake_audio_data_bench: AudioParams
):
    width, height, fr, num_frames, fake_frames = fake_video_frames_bench

    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)

    af = AudioSendFrame()
    af.sample_rate = fake_audio_data_bench.sample_rate
    af.num_channels = fake_audio_data_bench.num_channels
    af.set_max_num_samples(fake_audio_data_bench.s_perseg)

    sender = BenchSender()
    sender.set_video_frame(vf)
    sender.set_audio_frame(af)

    max_frames = min(num_frames, fake_audio_data_bench.num_segments)

    def run_bench():
        for i in range(max_frames):
            sender.write_video_and_audio(
                video_data=fake_frames[i],
                audio_data=fake_audio_data_bench.samples_3d[i]
            )

    with sender:
        benchmark(run_bench)

    vf.destroy()
    af.destroy()
