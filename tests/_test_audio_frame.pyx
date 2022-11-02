# cython: language_level=3
# distutils: language = c++
# distutils: include_dirs=NUMPY_INCLUDE

cimport cython
from libc.math cimport sqrt, sin, M_PI_2

import time

from cyndilib.wrapper cimport *
import numpy as np
cimport numpy as cnp
from cyndilib.audio_frame cimport AudioRecvFrame, AudioFrameSync



cdef void print_audio_frame_data(NDIlib_audio_frame_v3_t* p) nogil except *:
    with gil:
        print(f'''\
            timecode={p.timecode}
            timestamp={p.timestamp}
            sample_rate={p.sample_rate}
            no_channels={p.no_channels}
            no_samples={p.no_samples}
            stride={p.channel_stride_in_bytes}
        ''')


def audio_frame_process_events(AudioRecvFrame audio_frame):
    cdef NDIlib_recv_instance_t recv_ptr = NULL

    audio_frame._prepare_incoming(recv_ptr)
    audio_frame._process_incoming(recv_ptr)

cdef void fill_audio_frame_struct(
    NDIlib_audio_frame_v3_t* frame,
    cnp.float32_t[:,:] samples,
    size_t sample_rate,
    double timestamp,
) except *:
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


def fill_audio_frame(
    AudioRecvFrame audio_frame,
    cnp.float32_t[:,:] samples,
    size_t sample_rate,
    double timestamp,
    bint do_process=True
):
    cdef NDIlib_audio_frame_v3_t* frame = audio_frame.ptr
    cdef NDIlib_recv_instance_t recv_ptr = NULL

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
    cdef NDIlib_framesync_instance_t fs_ptr = NULL

    fill_audio_frame_struct(frame, samples, sample_rate, timestamp)

    if do_process:
        audio_frame._process_incoming(fs_ptr)

    return frame.timestamp
