# cython: language_level=3
# distutils: language = c++
# distutils: include_dirs=NUMPY_INCLUDE

cimport cython

from cyndilib.wrapper cimport *
import numpy as np
cimport numpy as cnp
from cyndilib.video_frame cimport VideoRecvFrame

import sys
import time


cdef uint32_t RED   = 0xff000000
cdef uint32_t GREEN = 0x00ff0000
cdef uint32_t BLUE  = 0x0000ff00
cdef uint32_t ALPHA = 0x000000ff

def build_test_data(size_t width, size_t height):
    cdef cnp.ndarray[cnp.uint32_t, ndim=2] arr = np.zeros((height, width), dtype=np.uint32)
    _build_test_data(arr)
    return arr


cdef void _build_test_data(cnp.ndarray[uint32_t, ndim=2] arr) except *:
    cdef size_t bar_width = arr.shape[1] // 3

    arr[:,:bar_width] = RED                 # |= 0xff0000ff
    arr[:,bar_width:bar_width*2] = GREEN    # |= 0x00ff00ff
    arr[:,bar_width*2:] = BLUE              # |= 0x0000ffff
    arr[...] |= ALPHA
    # arr[...]                     |= 0x000000ff


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void buffer_into_video_frame(NDIlib_video_frame_v2_t* p, uint32_t[:,:] arr) except *:
    cdef size_t nrows = arr.shape[0], ncols = arr.shape[1]
    cdef size_t i, j, k, x = 0
    cdef uint8_t* data_p = <uint8_t*>p.p_data
    cdef uint32_t v

    for i in range(nrows):
        for j in range(ncols):
            # for k in range(4):
            v = arr[i,j]
            data_p[x+0] = (v >> 24) & 0xff
            data_p[x+1] = (v >> 16) & 0xff
            data_p[x+2] = (v >>  8) & 0xff
            data_p[x+3] = (v >>  0) & 0xff
            # data_p[x+0] = v & 0xff000000 >> 24
            # data_p[x+1] = v & 0x00ff0000 >> 16
            # data_p[x+2] = v & 0x0000ff00 >> 8
            # data_p[x+3] = v & 0x000000ff
            x += 4
                # k += 1

# @cython.boundscheck(False)
# @cython.wraparound(False)
cdef void _check_read_data(uint32_t[:,:] src, uint8_t[:] result) except *:
    cdef size_t nrows = src.shape[0], ncols = src.shape[1]
    cdef size_t i, j, k = 0
    cdef uint32_t v_expected, v_result

    assert result.shape[0] == nrows * ncols * sizeof(uint8_t)

    for i in range(nrows):
        for j in range(ncols):
            v_expected = src[i,j]
            v_result =  result[k+0] << 24
            v_result |= result[k+1] << 16
            v_result |= result[k+2] << 8
            v_result |= result[k+3]
            k += 4

            # assert v_expected == v_result
            if v_expected != v_result:
                print(f'({i}, {j}), {v_expected:08X}, {v_result:08X}')
                # print(i, j, hex(v_expected), hex(v_result))
                assert v_expected == v_result

def check_read_data(VideoRecvFrame vf, uint32_t[:,:] src):
    cdef uint8_t[:] read_arr = vf
    _check_read_data(src, read_arr)


def test(VideoRecvFrame vf):
    cdef size_t width = 1920, height = 1080
    cdef size_t total_bytes = width * height * sizeof(uint8_t)
    print('ref_count: ', sys.getrefcount(vf))
    # vf = VideoRecvFrame()
    vf.ptr.xres = width
    vf.ptr.yres = height
    vf.ptr.FourCC = NDIlib_FourCC_video_type_RGBA
    vf.ptr.picture_aspect_ratio = 16/9
    vf.ptr.frame_format_type = NDIlib_frame_format_type_progressive
    vf.ptr.line_stride_in_bytes = width * sizeof(uint8_t)
    cdef NDIlib_recv_instance_t recv_ptr = NULL
    cdef cnp.ndarray[uint32_t, ndim=2] arr = np.zeros((height, width), dtype=np.uint32)
    cdef cnp.ndarray[uint8_t, ndim=1] read_arr = np.zeros(total_bytes, dtype=np.uint8)
    _build_test_data(arr)

    vf.ptr.p_data = <uint8_t*>mem_alloc(total_bytes)
    if vf.ptr.p_data is NULL:
        raise MemoryError()
    # try:
    print('ref_count: ', sys.getrefcount(vf))
    print('buffering to frame')
    time.sleep(.1)
    buffer_into_video_frame(vf.ptr, arr)
    print('ref_count: ', sys.getrefcount(vf))
    print('_process_incoming')
    time.sleep(.1)
    vf._process_incoming(recv_ptr)
    print('ref_count: ', sys.getrefcount(vf))
    print('free p_data')
    time.sleep(.1)
    mem_free(vf.ptr.p_data)
    vf.ptr.p_data = NULL
    time.sleep(.1)

    # print(vf.buffer_item.read_data)
    # time.sleep(.1)
    # read_arr[...] = vf
    # print('checking')
    # time.sleep(.1)
    # check_read_data(arr, read_arr)
    print('ref_count: ', sys.getrefcount(vf))
    print('exit')
    time.sleep(.1)
    # finally:
    #     pass
    #     # print('freeing mem')
    #     # time.sleep(.1)
    #     # mem_free(vf.ptr.p_data)
    #     # print('mem free')
    #     # time.sleep(.1)
    return np.asarray(arr)

def foo():
    cdef VideoRecvFrame vf = VideoRecvFrame()
    cdef cnp.ndarray[uint32_t, ndim=2] expected_data = test(vf)
    check_read_data(vf, expected_data)
