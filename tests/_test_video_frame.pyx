# cython: language_level=3
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS

cimport cython

from cyndilib.wrapper cimport *
import numpy as np
cimport numpy as cnp
from cyndilib.video_frame cimport VideoRecvFrame

import sys
import time

cdef packed struct RGBA_t:
    cnp.uint8_t r
    cnp.uint8_t g
    cnp.uint8_t b
    cnp.uint8_t a

RGBA_dtype = np.dtype([
    ('r', np.uint8),
    ('g', np.uint8),
    ('b', np.uint8),
    ('a', np.uint8),
], align=True)

cdef RGBA_t RED_s   = RGBA_t(0xff, 0x00, 0x00, 0xff)
cdef RGBA_t GREEN_s = RGBA_t(0x00, 0xff, 0x00, 0xff)
cdef RGBA_t BLUE_s  = RGBA_t(0x00, 0x00, 0xff, 0xff)
cdef RGBA_t GREY_s  = RGBA_t(0x80, 0x80, 0x80, 0xff)

cdef RGBA_t[4] BARS_s = [RED_s, GREEN_s, BLUE_s, GREY_s]


cdef void _rgba_copy(RGBA_t* src, RGBA_t* dst) noexcept nogil:
    dst.r = src.r
    dst.g = src.g
    dst.b = src.b
    dst.a = src.a


def build_test_frame(
    size_t width,
    size_t height,
    bint as_uint32=True,
    bint as_flat_uint8=False,
    bint as_structured=False,
    size_t x_offset=0,
):
    cdef cnp.ndarray arr
    cdef cnp.uint32_t[:,:] arr_view_uint32
    cdef cnp.uint8_t[:] arr_view_uint8_flat
    cdef cnp.uint8_t[:,:,:] arr_view_uint8
    cdef RGBA_t[:,:] arr_view_rgba

    if as_uint32:
        arr = np.empty((height, width), dtype=np.uint32)
        arr_view_uint32 = arr
        _build_test_frame_uint32_2d(arr_view_uint32, width, height, x_offset)
    elif as_flat_uint8:
        arr = np.empty(height*width*4, dtype=np.uint8)
        arr_view_uint8_flat = arr
        _build_test_frame_uint8_1d(arr_view_uint8_flat, width, height, x_offset)
    elif as_structured:
        arr = np.empty((height, width), dtype=RGBA_dtype)
        arr_view_rgba = arr
        _build_test_frame_structured(arr_view_rgba, width, height, x_offset)
    else:
        arr = np.empty((height, width, 4), dtype=np.uint8)
        arr_view_uint8 = arr
        _build_test_frame_uint8_3d(arr_view_uint8, width, height, x_offset)
    return arr


def build_test_frames(
    size_t width,
    size_t height,
    size_t num_frames,
    bint as_uint32=True,
    bint as_flat_uint8=False,
    bint as_structured=False,
):
    cdef size_t x_inc = width // num_frames, x_offset = 0, i
    cdef cnp.uint32_t[:,:,:] arr_view_uint32
    cdef cnp.uint8_t[:,:] arr_view_uint8_flat
    cdef cnp.uint8_t[:,:,:,:] arr_view_uint8
    cdef RGBA_t[:,:,:] arr_view_rgba

    if as_uint32:
        arr = np.empty((num_frames, height, width), dtype=np.uint32)
        arr_view_uint32 = arr
    elif as_flat_uint8:
        arr = np.empty((num_frames, height*width*4), dtype=np.uint8)
        arr_view_uint8_flat = arr
    elif as_structured:
        arr = np.empty((num_frames, height, width), dtype=RGBA_dtype)
        arr_view_rgba = arr
    else:
        arr = np.empty((num_frames, height, width, 4), dtype=np.uint8)
        arr_view_uint8 = arr

    for i in range(num_frames):
        if as_uint32:
            _build_test_frame_uint32_2d(arr_view_uint32[i], width, height, x_offset)
        elif as_flat_uint8:
            _build_test_frame_uint8_1d(arr_view_uint8_flat[i], width, height, x_offset)
        elif as_structured:
            _build_test_frame_structured(arr_view_rgba[i], width, height, x_offset)
        else:
            _build_test_frame_uint8_3d(arr_view_uint8[i], width, height, x_offset)
        x_offset += x_inc

    return arr


cdef int _build_test_frame_uint32_2d(
    cnp.uint32_t[:,:] arr_view, size_t width, size_t height, size_t x_offset=0,
) except -1:
    cdef RGBA_t[:] line_view = np.empty(width, dtype=RGBA_dtype)
    _build_test_data_struct(line_view, width, x_offset)
    _structured_to_uint32(line_view, arr_view[0], 1)
    arr_view[1:,...] = arr_view[0]
    return 0


cdef int _build_test_frame_uint32_1d(
    cnp.uint32_t[:] arr_view, size_t width, size_t height, size_t x_offset=0,
) except -1:
    cdef RGBA_t[:] line_view = np.empty(width, dtype=RGBA_dtype)
    _build_test_data_struct(line_view, width, x_offset)
    _structured_to_uint32(line_view, arr_view, height)
    return 0


cdef int _build_test_frame_uint8_2d(
    cnp.uint8_t[:,:] arr_view, size_t width, size_t height, size_t x_offset=0,
) except -1:
    cdef RGBA_t[:] line_view = np.empty(width, dtype=RGBA_dtype)
    _build_test_data_struct(line_view, width, x_offset)
    _structured_to_uint8(line_view, arr_view[0], 1)
    arr_view[1:,...] = arr_view[0]
    return 0


cdef int _build_test_frame_uint8_1d(
    cnp.uint8_t[:] arr_view, size_t width, size_t height, size_t x_offset=0,
) except -1:
    cdef RGBA_t[:] line_view = np.empty(width, dtype=RGBA_dtype)
    _build_test_data_struct(line_view, width, x_offset)
    _structured_to_uint8(line_view, arr_view, height)
    return 0


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _build_test_frame_uint8_3d(
    cnp.uint8_t[:,:,:] arr_view, size_t width, size_t height, size_t x_offset=0,
) except -1:
    cdef RGBA_t[:] line_view = np.empty(width, dtype=RGBA_dtype)
    cdef cnp.uint8_t[:,:] line_view_uint8 = np.empty((width, 4), dtype=np.uint8)
    cdef uint8_t* intptr = <uint8_t*>&line_view[0]
    cdef size_t i, j, k=0

    _build_test_data_struct(line_view, width, x_offset)
    for i in range(width):
        for j in range(4):
            line_view_uint8[i,j] = intptr[k]
            k += 1
    arr_view[...] = line_view_uint8
    return 0


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _build_test_frame_structured(
    RGBA_t[:,:] arr_view, size_t width, size_t height, size_t x_offset=0,
) except -1:
    cdef RGBA_t[:] line_view = np.empty(width, dtype=RGBA_dtype)

    _build_test_data_struct(line_view, width, x_offset)
    arr_view[...] = line_view
    return 0


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _build_test_data_struct(RGBA_t[:] arr, size_t width, size_t x_offset) except -1:
    cdef size_t i, j, k, start_idx, end_idx
    cdef size_t bar_width = width // 4
    cdef bint is_split
    cdef RGBA_t* arr_ptr
    cdef RGBA_t* color

    for i in range(4):
        color = &(BARS_s[i])
        start_idx = (i * bar_width + x_offset) % width
        end_idx = (start_idx + bar_width) % width
        if end_idx == 0:
            end_idx = width
        is_split = end_idx < start_idx
        if is_split:
            for j in range(start_idx, width):
                arr_ptr = &(arr[j])
                _rgba_copy(color, arr_ptr)
            start_idx = 0
        for j in range(start_idx, end_idx):
            arr_ptr = &(arr[j])
            _rgba_copy(color, arr_ptr)
    return 0


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _structured_to_uint8(RGBA_t[:] src, cnp.uint8_t[:] dest, size_t height) except -1:
    cdef size_t width = src.shape[0]
    cdef void* vptr
    cdef uint8_t* intptr
    cdef size_t i, j, k, l=0

    for i in range(height):
        for j in range(width):
            vptr = <void*>&(src[j])
            intptr = <uint8_t*>vptr
            for k in range(4):
                dest[l] = intptr[0]
                intptr += 1
                l += 1
    return 0


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int _structured_to_uint32(RGBA_t[:] src, cnp.uint32_t[:] dest, size_t height) except -1 nogil:
    cdef size_t width = src.shape[0]
    cdef uint32_t* vptr
    cdef uint32_t v
    cdef size_t i, j, k=0

    for i in range(width):
        vptr = <uint32_t*>&src[i]
        v = vptr[0]
        for j in range(height):
            dest[k] = v
            k += 1
    return 0


@cython.boundscheck(False)
@cython.wraparound(False)
def buffer_into_video_frame(VideoRecvFrame vf, size_t width, size_t height, uint8_t[:] arr, bint do_process=True):
    assert vf.can_receive() is True
    cdef uint8_t* data_p
    if vf.ptr.p_data is not NULL:
        data_p = vf.ptr.p_data
        vf.ptr.p_data = NULL
        mem_free(data_p)
        data_p = NULL
    cdef size_t size_in_bytes = sizeof(uint8_t) * arr.shape[0]
    assert size_in_bytes == sizeof(uint8_t) * width * height * 4
    vf.ptr.p_data = <uint8_t*>mem_alloc(size_in_bytes)
    if vf.ptr.p_data is NULL:
        raise_mem_err()
    cdef size_t n = arr.shape[0], i
    cdef uint8_t** data = &(vf.ptr.p_data)
    data_p = data[0]
    vf.ptr.xres = width
    vf.ptr.yres = height
    vf.ptr.FourCC = NDIlib_FourCC_video_type_RGBA
    vf.ptr.timecode = NDIlib_send_timecode_synthesize
    vf.ptr.picture_aspect_ratio = width / <double>height
    vf.ptr.frame_format_type = NDIlib_frame_format_type_progressive
    vf.ptr.line_stride_in_bytes = width * sizeof(uint8_t) * 4

    for i in range(n):
        data_p[i] = arr[i]

    if do_process:
        video_frame_process_events(vf)


def video_frame_process_events(VideoRecvFrame vf):
    cdef NDIlib_recv_instance_t recv_ptr = NULL
    vf._prepare_incoming(recv_ptr)
    vf._process_incoming(recv_ptr)
