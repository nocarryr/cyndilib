# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

from ..wrapper.ndi_structs cimport FourCC
from .pixel_format cimport PixelFormatDef, PixelComponentDef



cdef struct Plane_s:
    uint32_t linesize
    uint32_t unpadded_linesize
    uint32_t offset_bytes
    uint32_t size_in_bytes
    uint32_t unpadded_size_in_bytes
    uint16_t height
    uint8_t index


cdef struct ImageComponent_s:
    uint16_t width
    uint16_t height
    bint is_chroma


cdef struct ImageFormat_s:
    PixelFormatDef* pix_fmt
    Plane_s planes[4]
    ImageComponent_s comp[4]
    uint32_t size_in_bytes
    uint32_t line_stride
    uint16_t width
    uint16_t height
    uint16_t chroma_width
    uint16_t chroma_height
    uint8_t max_comp_depth
    uint8_t bits_per_pixel
    uint8_t padded_bits_per_pixel
    bint is_16bit


cdef uint32_t get_linesize(
    PixelFormatDef* desc,
    uint32_t max_pixsteps[4],
    uint8_t max_pixstep_comps[4],
    uint16_t width,
    uint8_t plane
) except -1 nogil

cdef int fill_image_format(
    ImageFormat_s* image_format,
    FourCC fourcc,
    uint16_t width,
    uint16_t height,
    uint32_t line_stride=*
) except -1 nogil

cdef void get_image_read_shape(
    ImageFormat_s* image_format,
    uint16_t shape[3],
) noexcept nogil
