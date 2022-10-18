# cython: language_level=3
# distutils: language = c++
# distutils: include_dirs=NUMPY_INCLUDE

cimport cython
from libc.math cimport sqrt, sin, M_PI_2

from cyndilib.wrapper cimport *
import numpy as np
cimport numpy as cnp
from cyndilib.audio_frame cimport AudioRecvFrame



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


cdef void gen_fake_data(NDIlib_audio_frame_v3_t* frame) nogil except *:
    cdef double fc = 2000.
    cdef double mult = 1. / frame.sample_rate
    cdef double amp = 2*sqrt(2)
    cdef double offset = frame.timestamp * mult
    cdef double t, v
    cdef size_t i, j, k
    cdef float* float_data = <float*>frame.p_data

    for i in range(frame.no_samples):
        t = i * mult + offset
        v = amp * sin(M_PI_2*fc*t)
        float_data[i] = v
        float_data[i+frame.no_samples] = v


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void _test(AudioRecvFrame audio_frame, cnp.float32_t[:,:,:] samples, cnp.float32_t[:,:,:] results) nogil except *:
    # cdef audio_bfr_p bfr_root
    # cdef audio_bfr_p bfr = av_frame_bfr_create(bfr_root)
    # bfr.sample_rate = 48000
    # bfr.num_channels = 2
    # bfr.num_samples = 6000

    # cdef NDIlib_audio_frame_v3_t frame
    cdef cnp.float32_t[:,:] sample_view
    cdef cnp.float32_t[:,:] recv_view
    cdef NDIlib_audio_frame_v3_t* frame = audio_frame.ptr
    cdef NDIlib_recv_instance_t recv_ptr = NULL
    cdef size_t num_segments = samples.shape[0]
    frame.sample_rate = 48000
    frame.no_channels = samples.shape[1]
    frame.no_samples = samples.shape[2]
    frame.channel_stride_in_bytes = sizeof(float) * frame.no_samples
    frame.timecode = NDIlib_send_timecode_synthesize
    frame.FourCC = NDIlib_FourCC_audio_type_FLTP
    frame.timestamp = 0
    # print(f'num_segments={num_segments}, frame: {frame.no_channels} ch, {frame.no_samples} samp')
    # print('malloc')
    # time.sleep(.1)
    frame.p_data = <uint8_t*>mem_alloc(sizeof(float)*frame.no_channels*frame.no_samples)
    # cdef uint8_t[sizeof(float)] tmp
    cdef float* float_data = <float*>frame.p_data

    # print('gen_fake_data')
    # time.sleep(.1)
    cdef size_t i, j, k, l
    for i in range(num_segments):
        # sample_view = samples[i]
        # print(i)
        # time.sleep(.1)
        l = 0
        for j in range(frame.no_channels):
            for k in range(frame.no_samples):
                float_data[l] = samples[i,j,k]
                l += 1
        audio_frame._process_incoming(recv_ptr)
        # print('audio_frame.len: ', audio_frame.current_frame_data.size)
        recv_view = audio_frame#.current_frame_data
        results[i,...] = recv_view
        frame.timestamp += frame.no_samples
        recv_view = None
    # gen_fake_data(frame)
    # print('_process_incoming')
    # time.sleep(.1)
    # audio_frame._process_incoming()
    # print('process complete')
    # time.sleep(.1)
    # frame.timestamp += frame.no_samples

    # print('mem_free')
    # time.sleep(.1)
    # mem_free(frame.p_data)

    # print('freed')
    # time.sleep(.1)

def run_test(AudioRecvFrame audio_frame, cnp.float32_t[:,:,:] samples, cnp.float32_t[:,:,:] results):
    _test(audio_frame, samples, results)
