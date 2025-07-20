# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS
# distutils: define_macros=CYTHON_TRACE_NOGIL=1


cimport cython
from libc.math cimport sqrt, sin, M_PI_2

import time

from cyndilib.wrapper cimport *
import numpy as np
cimport numpy as cnp
from cyndilib.audio_frame cimport AudioRecvFrame, AudioFrameSync, AudioSendFrame
from cyndilib.send_frame_status cimport AudioSendFrame_item_s


def get_audio_send_frame_current_data(AudioSendFrame audio_frame):
    """Hook to read the data from an AudioSendFrame directly after
    writing to it, but before it's been sent.
    """
    cdef AudioSendFrame_item_s* item = audio_frame._get_send_frame()
    cdef NDIlib_audio_frame_v3_t* frame = item.frame_ptr
    if frame.p_data is NULL:
        raise ValueError("AudioSendFrame has no data")

    cdef cnp.ndarray np_data = np.zeros((
        audio_frame.num_channels, audio_frame.num_samples
    ), dtype=np.float32)
    cdef cnp.float32_t[:,:] data_view = np_data
    cdef float* float_data = <float*>frame.p_data
    cdef size_t i, j, k=0

    for i in range(audio_frame.num_channels):
        for j in range(audio_frame.num_samples):
            data_view[i,j] = float_data[k]
            k += 1
    return np_data


cdef int print_audio_frame_data(NDIlib_audio_frame_v3_t* p) except -1 nogil:
    with gil:
        print(f'''\
            timecode={p.timecode}
            timestamp={p.timestamp}
            sample_rate={p.sample_rate}
            no_channels={p.no_channels}
            no_samples={p.no_samples}
            stride={p.channel_stride_in_bytes}
        ''')
    return 0


def audio_frame_process_events(AudioRecvFrame audio_frame):
    cdef NDIlib_recv_instance_t recv_ptr = NULL

    audio_frame._prepare_incoming(recv_ptr)
    audio_frame._process_incoming(recv_ptr)

cdef int fill_audio_frame_struct(
    NDIlib_audio_frame_v3_t* frame,
    cnp.float32_t[:,:] samples,
    size_t sample_rate,
    double timestamp,
) except -1:
    cdef int32_t ndi_ts = posix_time_to_ndi(timestamp)
    cdef size_t nrows = samples.shape[0], ncols = samples.shape[1]

    frame.sample_rate = sample_rate
    frame.no_channels = nrows
    frame.no_samples = ncols
    frame.channel_stride_in_bytes = sizeof(float) * ncols
    frame.timecode = NDIlib_send_timecode_synthesize
    frame.FourCC = NDIlib_FourCC_audio_type_FLTP
    frame.timestamp = ndi_ts

    frame.p_data = <uint8_t*>mem_alloc(sizeof(float)*nrows*ncols)
    cdef float* float_data = <float*>frame.p_data

    cdef size_t i, j, k=0
    for i in range(nrows):
        for j in range(ncols):
            float_data[k] = samples[i,j]
            k += 1
    return 0


def fill_audio_frame(
    AudioRecvFrame audio_frame,
    cnp.float32_t[:,:] samples,
    size_t sample_rate,
    double timestamp,
    bint do_process=True,
    bint check_can_receive=False
):
    cdef NDIlib_audio_frame_v3_t* frame = audio_frame.ptr
    cdef NDIlib_recv_instance_t recv_ptr = NULL

    if check_can_receive:
        if not audio_frame.can_receive():
            return None, None

    ndi_ts = fill_audio_frame_struct(frame, samples, sample_rate, timestamp)

    if do_process:
        audio_frame_process_events(audio_frame)

    # print('processed')
    # time.sleep(.1)

    cdef list indices = []
    cdef size_t ix
    for ix in audio_frame.read_indices:
        indices.append(ix)
    return frame.timestamp, indices


def fill_audio_frame_sync(
    AudioFrameSync audio_frame,
    cnp.float32_t[:,:] samples,
    size_t sample_rate,
    double timestamp,
    bint do_process=True
):
    cdef NDIlib_audio_frame_v3_t* frame = audio_frame.ptr

    fill_audio_frame_struct(frame, samples, sample_rate, timestamp)

    if do_process:
        audio_frame._process_incoming()

    return frame.timestamp
