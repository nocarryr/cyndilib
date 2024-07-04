# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS
# distutils: define_macros=CYTHON_TRACE_NOGIL=1


from libc.string cimport memcpy

from cyndilib.wrapper cimport mem_alloc, mem_free
from cyndilib.buffertypes cimport (
    audio_bfr_p, audio_frame_bfr_create, av_frame_bfr_destroy,
    av_frame_bfr_get_head, av_frame_bfr_get_tail, av_frame_bfr_remove,
)

import time



cdef void test_fill_audio_bfr(audio_bfr_p bfr, float start_val) except *:
    bfr.num_samples = 20
    bfr.num_channels = 2
    bfr.total_size = bfr.num_channels * bfr.num_samples
    bfr.p_data = <float*>mem_alloc(sizeof(float) * bfr.total_size)
    cdef float* tmp = <float*>mem_alloc(sizeof(float) * bfr.total_size)
    memcpy(<void*>bfr.p_data, <void*>tmp, sizeof(float) * bfr.total_size)
    mem_free(tmp)


cpdef test():
    print('create nullBfr...')
    time.sleep(.5)
    cdef audio_bfr_p nullBfr = NULL# = <audio_bfr_p>mem_alloc(sizeof(audio_bfr_t))
    print('create bfr')
    time.sleep(.5)
    cdef audio_bfr_p bfr = audio_frame_bfr_create(nullBfr)
    print('bfr created')
    cdef size_t i
    cdef audio_bfr_p child_bfr
    cdef audio_bfr_p tmp = bfr
    bfr.timecode = 0
    test_fill_audio_bfr(bfr, 0)
    print(bfr.timecode)
    for i in range(10):
        child_bfr = audio_frame_bfr_create(tmp)
        child_bfr.timecode = i + 1
        test_fill_audio_bfr(child_bfr, i+1)
        assert child_bfr.prev is not NULL
        assert child_bfr.prev.timecode == tmp.timecode == i
        print(child_bfr.timecode)
        tmp = child_bfr

    time.sleep(.5)
    print('get tail')
    cdef audio_bfr_p bfr2 = av_frame_bfr_get_tail(bfr)
    print('tail: ', bfr2.timecode)
    bfr2 = av_frame_bfr_get_head(child_bfr)
    print('head: ', bfr2.timecode)
    bfr2 = bfr.next.next
    print('remove: ', bfr2.timecode)
    av_frame_bfr_remove(bfr2)
    bfr2 = NULL


    tmp = bfr
    while tmp.next is not NULL:
        print(tmp.timecode)
        if tmp.timecode == 4:
            bfr2 = tmp
        tmp = tmp.next
    print('destroy')
    time.sleep(.1)
    av_frame_bfr_destroy(bfr2)
    assert bfr2.prev is NULL
    assert bfr2.next is NULL
    print('destroyed')
    time.sleep(.5)
    # mem_free(nullBfr)
