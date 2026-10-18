"""
Simple tests to verify that the Cython bindings are working correctly.
These tests don't verify any functionality, just that the package has been built correctly.

This avoids building the entire test suite, which can be time consuming and
is run in a separate CI workflow.
"""
from fractions import Fraction


from cyndilib import (
    AudioFrame,
    AudioRecvFrame,
    AudioFrameSync,
    AudioSendFrame,
    AudioReference,
    Receiver,
    Sender,
    VideoFrame,
    VideoFrameSync,
    VideoRecvFrame,
    VideoSendFrame,
    FourCC,
)
from cyndilib.discovery.exceptions import DiscoveryServerUnavailableError
from cyndilib.discovery.run_server import get_run_server_path


def test_audio_frame():
    sample_rate = 48000
    num_channels = 2
    audio_reference = AudioReference.dBu

    audio_frame = AudioFrame()
    audio_frame.sample_rate = sample_rate
    audio_frame.num_channels = num_channels
    audio_frame.reference_level = audio_reference

    audio_recv_frame = AudioRecvFrame()
    audio_recv_frame.sample_rate = sample_rate
    audio_recv_frame.num_channels = num_channels
    audio_recv_frame.reference_level = audio_reference

    audio_frame_sync = AudioFrameSync()
    audio_frame_sync.sample_rate = sample_rate
    audio_frame_sync.num_channels = num_channels
    audio_frame_sync.reference_level = audio_reference

    audio_send_frame = AudioSendFrame()
    audio_send_frame.sample_rate = sample_rate
    audio_send_frame.num_channels = num_channels
    audio_send_frame.reference_level = audio_reference

    assert (
        audio_frame.sample_rate ==
        audio_recv_frame.sample_rate ==
        audio_frame_sync.sample_rate ==
        audio_send_frame.sample_rate ==
        sample_rate
    )
    assert (
        audio_frame.num_channels ==
        audio_recv_frame.num_channels ==
        audio_frame_sync.num_channels ==
        audio_send_frame.num_channels ==
        num_channels
    )
    assert (
        audio_frame.reference_level ==
        audio_recv_frame.reference_level ==
        audio_frame_sync.reference_level ==
        audio_send_frame.reference_level ==
        audio_reference
    )


def test_video_frame():
    width = 640
    height = 480
    frame_rate = Fraction(60, 1)
    fourcc = FourCC.RGBA

    video_frame = VideoFrame()
    video_frame.set_resolution(width, height)
    video_frame.set_frame_rate(frame_rate)
    video_frame.set_fourcc(fourcc)

    video_recv_frame = VideoRecvFrame()
    video_recv_frame.set_resolution(width, height)
    video_recv_frame.set_frame_rate(frame_rate)
    video_recv_frame.set_fourcc(fourcc)

    video_frame_sync = VideoFrameSync()
    video_frame_sync.set_resolution(width, height)
    video_frame_sync.set_frame_rate(frame_rate)
    video_frame_sync.set_fourcc(fourcc)

    video_send_frame = VideoSendFrame()
    video_send_frame.set_resolution(width, height)
    video_send_frame.set_frame_rate(frame_rate)
    video_send_frame.set_fourcc(fourcc)

    assert (
        video_frame.xres ==
        video_recv_frame.xres ==
        video_frame_sync.xres ==
        video_send_frame.xres ==
        width
    )

    assert (
        video_frame.yres ==
        video_recv_frame.yres ==
        video_frame_sync.yres ==
        video_send_frame.yres ==
        height
    )

    assert (
        video_frame.get_frame_rate() ==
        video_recv_frame.get_frame_rate() ==
        video_frame_sync.get_frame_rate() ==
        video_send_frame.get_frame_rate() ==
        frame_rate
    )

    assert (
        video_frame.fourcc ==
        video_recv_frame.fourcc ==
        video_frame_sync.fourcc ==
        video_send_frame.fourcc ==
        fourcc
    )


def test_sender():
    sender = Sender('Test Sender')
    vf = VideoSendFrame()
    vf.set_resolution(1920, 1080)
    sender.set_video_frame(vf)
    af = AudioSendFrame()
    sender.set_audio_frame(af)
    with sender:
        assert sender.has_video_frame
        assert sender.has_audio_frame
        assert sender.video_frame is vf
        assert sender.audio_frame is af


def test_receiver():
    receiver = Receiver()
    vf = VideoRecvFrame()
    receiver.set_video_frame(vf)
    af = AudioRecvFrame()
    receiver.set_audio_frame(af)

    assert receiver.has_video_frame
    assert receiver.has_audio_frame
    assert receiver.video_frame is vf
    assert receiver.audio_frame is af


def test_framesync():
    receiver = Receiver()
    vf = VideoFrameSync()
    receiver.frame_sync.set_video_frame(vf)
    af = AudioFrameSync()
    receiver.frame_sync.set_audio_frame(af)

    assert not receiver.has_video_frame
    assert not receiver.has_audio_frame
    assert receiver.frame_sync.video_frame is vf
    assert receiver.frame_sync.audio_frame is af


def test_discovery_server_exists():
    """Test that the discovery server binary exists in the packaged distribution
    """
    try:
        path = get_run_server_path()
        assert path.exists()
    except DiscoveryServerUnavailableError:
        # Discovery server is unavailable for this platform or configuration
        pass
