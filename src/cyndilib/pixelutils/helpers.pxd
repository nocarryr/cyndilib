# cython: language_level=3
# distutils: language = c++
DEF MAX_BFR_DIMS = 8


from libc.stdint cimport *
from cython cimport view

cimport numpy as cnp

from ..wrapper.ndi_structs cimport FourCC, NDIlib_video_frame_v2_t
from .image_format cimport ImageFormat_s
from .types cimport uint_ft


cdef class ImageFormat:
    cdef ImageFormat_s _fmt
    cdef uint16_t _shape[3]
    cdef uint32_t _line_stride
    cdef bint _force_line_stride
    cdef bint _expand_chroma
    cdef readonly CarrayBuffer c_buffer
    cdef readonly Py_ssize_t[MAX_BFR_DIMS] bfr_shape

    cdef int _update_format(
        self,
        FourCC fourcc,
        uint16_t width,
        uint16_t height,
    ) except -1 nogil
    cdef int _set_line_stride(self, uint32_t line_stride, bint force) except -1 nogil
    cdef int _set_fourcc(self, FourCC fourcc) except -1 nogil
    cdef int _set_resolution(self, uint16_t width, uint16_t height) except -1 nogil
    cdef int _unpack(self, const uint8_t[:] src, uint_ft[:,:,:] dest) except -1 nogil
    cdef int _pack(self, const uint_ft[:,:,:] src, uint8_t[:] dest) except -1 nogil
    cdef object unpack_8_bit(self, const uint8_t[:] src)
    cdef object unpack_16_bit(self, const uint8_t[:] src)

    cdef int read_from_ndi_video_frame(
        self,
        NDIlib_video_frame_v2_t* ptr,
        uint_ft[:,:,:] dest
    ) except -1
    cdef int write_to_ndi_video_frame(
        self,
        NDIlib_video_frame_v2_t* ptr,
        const uint_ft[:,:,:] src
    ) except -1
    cdef int read_from_c_pointer(
        self,
        const uint8_t* src_ptr,
        uint_ft[:,:,:] dest
    ) except -1
    cdef int write_to_c_pointer(
        self,
        const uint_ft[:,:,:] src,
        uint8_t* dest_ptr
    ) except -1


cdef class ImageReader(ImageFormat):
    pass


cdef class CarrayBuffer:
    cdef char *carr_ptr
    cdef readonly Py_ssize_t[MAX_BFR_DIMS] shape
    cdef readonly Py_ssize_t[MAX_BFR_DIMS] strides
    cdef readonly size_t ndim
    cdef readonly size_t itemsize
    cdef readonly Py_ssize_t size
    cdef readonly format
    cdef readonly bint readonly
    cdef readonly int view_count
    cdef readonly bint view_active
    cdef bint free_ptr_on_release

    cdef int set_array_ptr(
        self,
        char *ptr,
        Py_ssize_t[MAX_BFR_DIMS] shape,
        size_t ndim = *,
        size_t itemsize = *,
        bint readonly = *
    ) except -1 nogil
    cdef int release_array_ptr(self) except -1 nogil
