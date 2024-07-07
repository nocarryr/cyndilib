import socket

import pytest

from cyndilib.sender import Sender
from cyndilib.video_frame import VideoSendFrame


HOST = socket.gethostname()
TEST_SOURCE_NAME = 'Example Video Source'

@pytest.fixture
def fake_sender():
    vf = VideoSendFrame()
    vf.set_resolution(1920, 1080)
    sender = Sender(TEST_SOURCE_NAME)
    sender.set_video_frame(vf)
    sender.open()
    yield sender.name
    sender.close()
