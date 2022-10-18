import time
import numpy as np
from cyndilib.video_frame import VideoRecvFrame
from _test_video_frame import check_read_data, test as cytest

def test():
    vf = VideoRecvFrame()
    expected_data = cytest(vf)
    print(f'{expected_data.shape=}')
    time.sleep(.1)
    check_read_data(vf, expected_data)
    print('read_data checked')
    time.sleep(.1)
