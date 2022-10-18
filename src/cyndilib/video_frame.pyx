cimport cython
from libc.string cimport memcpy

import numpy as np

cdef class VideoFrame:
    # cdef NDIlib_video_frame_v2_t* ptr
    # cdef frame_rate_t frame_rate

    def __cinit__(self, *args, **kwargs):
        self.ptr = video_frame_create_default()
        if self.ptr is NULL:
            raise MemoryError()
        self.frame_rate.numerator = self.ptr.frame_rate_N
        self.frame_rate.denominator = self.ptr.frame_rate_D

    def __init__(self, *args, **kwargs):
        pass

    def __dealloc__(self):
        cdef NDIlib_video_frame_v2_t* p = self.ptr
        self.ptr = NULL
        if p is not NULL:
            video_frame_destroy(p)

    cdef (int, int) _get_resolution(self) nogil except *:
        return (self.ptr.xres, self.ptr.yres)
    cdef void _set_resolution(self, int xres, int yres) nogil:
        self.ptr.xres = xres
        self.ptr.yres = yres

    @property
    def xres(self):
        return self._get_xres()

    @property
    def yres(self):
        return self._get_yres()

    cdef int _get_xres(self) nogil:
        return self.ptr.xres
    cdef void _set_xres(self, int value) nogil:
        self.ptr.xres = value

    cdef int _get_yres(self) nogil:
        return self.ptr.yres
    cdef void _set_yres(self, int value) nogil:
        self.ptr.yres = value

    cdef FourCC _get_fourcc(self) nogil except *:
        return fourcc_type_uncast(self.ptr.FourCC)
    cdef void _set_fourcc(self, FourCC value) nogil except *:
        self.ptr.FourCC = fourcc_type_cast(value)

    cdef frame_rate_t _get_frame_rate(self) nogil except *:
        self.frame_rate.numerator = self.ptr.frame_rate_N
        self.frame_rate.denominator = self.ptr.frame_rate_D
        return self.frame_rate

    cdef void _set_frame_rate(self, frame_rate_ft fr) nogil except *:
        if frame_rate_ft is frame_rate_t:
            self.ptr.frame_rate_N = fr.numerator
            self.ptr.frame_rate_D = fr.denominator
        else:
            self.ptr.frame_rate_N = fr[0]
            self.ptr.frame_rate_D = fr[1]
        self.frame_rate.numerator = self.ptr.frame_rate_N
        self.frame_rate.denominator = self.ptr.frame_rate_D

    cdef float _get_aspect(self) nogil:
        return self.ptr.picture_aspect_ratio
    cdef void _set_aspect(self, float value) nogil:
        self.ptr.picture_aspect_ratio = value

    cdef FrameFormat _get_frame_format(self) nogil except *:
        return frame_format_uncast(self.ptr.frame_format_type)
    cdef void _set_frame_format(self, FrameFormat fmt) nogil except *:
        self.ptr.frame_format_type = frame_format_cast(fmt)

    cdef int64_t _get_timecode(self) nogil:
        return self.ptr.timecode
    cdef int64_t _set_timecode(self, int64_t value) nogil:
        self.ptr.timecode = value

    cdef int _get_line_stride(self) nogil:
        return self.ptr.line_stride_in_bytes
    cdef void _set_line_stride(self, int value) nogil:
        self.ptr.line_stride_in_bytes = value

    cdef uint8_t* _get_data(self) nogil:
        return self.ptr.p_data
    cdef void _set_data(self, uint8_t* data) nogil:
        self.ptr.p_data = data

    cdef const char* _get_metadata(self) nogil except *:
        return self.ptr.p_metadata

    cdef bytes _get_metadata_bytes(self):
        cdef bytes result = self.ptr.p_metadata
        return result

    cdef int64_t _get_timestamp(self) nogil:
        return self.ptr.timestamp
    cdef void _set_timestamp(self, int64_t value) nogil:
        self.ptr.timestamp = value

    cdef size_t _get_data_size(self) nogil:
        return self.ptr.line_stride_in_bytes * self.ptr.yres
    cpdef size_t get_data_size(self):
        return self._get_data_size()


cdef class VideoRecvFrame(VideoFrame):
    def __cinit__(self, *args, **kwargs):
        self.video_bfrs = av_frame_bfr_create(self.video_bfrs)
        self.write_bfr = av_frame_bfr_create(self.video_bfrs)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.view_count = 0

    def __dealloc__(self):
        cdef video_bfr_p bfr = self.video_bfrs
        if self.video_bfrs is not NULL:
            self.video_bfrs = NULL
            self.write_bfr = NULL
            av_frame_bfr_destroy(bfr)

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        self.bfr_shape[0] = self.write_bfr.total_size
        self.bfr_strides[0] = self.bfr_shape[0]
        buffer.buf = <char *>self.write_bfr.p_data
        buffer.format = 'B'
        buffer.internal = NULL
        buffer.itemsize = sizeof(uint8_t)
        buffer.len = self.write_bfr.total_size
        buffer.ndim = 1
        buffer.obj = self
        buffer.readonly = 1
        buffer.shape = self.bfr_shape
        buffer.strides = self.bfr_strides
        buffer.suboffsets = NULL
        self.view_count += 1

    def __releasebuffer__(self, Py_buffer *buffer):
        self.view_count -= 1

    @cython.boundscheck(False)
    @cython.wraparound(False)
    def fill_p_data(self, cnp.uint8_t[:] dest):
        if self.write_bfr.p_data is NULL:
            return 0
        cdef size_t arr_size = self.write_bfr.total_size
        if dest.shape[0] < arr_size:
            raise ValueError("Destination size must be {arr_size} or greater")
        cdef size_t i
        for i in range(arr_size):
            dest[i] = self.write_bfr.p_data[i]
        return arr_size

    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) nogil except *:
        cdef video_bfr_p write_bfr = self.write_bfr
        cdef NDIlib_video_frame_v2_t* p = self.ptr
        cdef frame_rate_t fr = self.frame_rate
        cdef size_t size_in_bytes = p.line_stride_in_bytes * p.yres

        if self.view_count > 0:
            if recv_ptr is not NULL:
                NDIlib_recv_free_video_v2(recv_ptr, self.ptr)
            raise_withgil(PyExc_ValueError, 'Cannot write if buffer view active')

        fr.numerator = p.frame_rate_N
        fr.denominator = p.frame_rate_D

        write_bfr.timecode = p.timecode
        write_bfr.timestamp = p.timestamp
        write_bfr.line_stride = p.line_stride_in_bytes
        write_bfr.format = frame_format_uncast(p.frame_format_type)
        write_bfr.fourcc = fourcc_type_uncast(p.FourCC)
        write_bfr.xres = p.xres
        write_bfr.yres = p.yres
        write_bfr.aspect = p.picture_aspect_ratio
        video_bfr_unpack_data(write_bfr, p.p_data, size_in_bytes)
        write_bfr.valid = True

        if recv_ptr is not NULL:
            NDIlib_recv_free_video_v2(recv_ptr, self.ptr)


cdef void copy_char_array(const uint8_t** src, uint8_t** dst, size_t size) nogil:
    cdef const uint8_t* src_p = src[0]
    cdef uint8_t* dst_p = dst[0]
    cdef size_t i
    for i in range(size):
        dst_p[0] = src_p[0]
        dst_p += 1
        src_p += 1

cdef void video_bfr_unpack_data(video_bfr_p bfr, uint8_t* p_data, size_t size_in_bytes) nogil except *:
    if bfr.p_data is not NULL:
        if bfr.total_size != size_in_bytes:
            mem_free(bfr.p_data)
    if bfr.p_data is NULL:
        bfr.p_data = <uint8_t*>mem_alloc(sizeof(uint8_t) * size_in_bytes)
        if bfr.p_data is NULL:
            raise_mem_err()
    copy_char_array(&p_data, &(bfr.p_data), size_in_bytes)
    # memcpy(bfr.p_data, p_data, size_in_bytes)
    bfr.total_size = size_in_bytes






# def uint32_2d_to_uint8_3d(cnp.ndarray[cnp.uint32_t, ndim=2] in_arr):
#     cdef cnp.ndarray[uint8_t, ndim=3] out_arr = np.empty((in_arr.shape[0], in_arr.shape[1], 4), dtype=np.uint8)
#     _uint32_2d_to_uint8_3d(in_arr, out_arr)
#     return out_arr
#
# @cython.boundscheck(False)
# @cython.wraparound(False)
# cdef _uint32_2d_to_uint8_3d(cnp.uint32_t[:,:] src, cnp.uint8_t[:,:,:] dest):
#     cdef size_t nrows = src.shape[0], ncols = src.shape[1]
#     cdef size_t i, j, k
#     cdef uint32_t v
#
#     for i in range(nrows):
#         for j in range(ncols):
#             v = src[i,j]
#             dest[i,j,0] = (v >> 24) & 0xff
#             dest[i,j,1] = (v >> 16) & 0xff
#             dest[i,j,2] = (v >>  8) & 0xff
#             dest[i,j,3] = (v >>  0) & 0xff
