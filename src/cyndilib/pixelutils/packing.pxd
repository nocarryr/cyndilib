# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

from .image_format cimport ImageFormat_s
from .types cimport uint_ft



cdef uint16_t image_read_line_component(
    ImageFormat_s* image_format,
    uint_ft[:] dest,
    const uint8_t[:] data,
    uint16_t x,
    uint16_t y,
    uint16_t max_count,
    uint8_t comp_index,
    bint expand_chroma
) noexcept nogil

cdef int image_read_line(
    ImageFormat_s* image_format,
    uint16_t comp_widths[4],
    uint_ft[:,:] dest,
    const uint8_t[:] data,
    uint16_t x,
    uint16_t y,
    uint16_t max_count,
    bint as_planar,
    bint expand_chroma
) noexcept nogil

cdef int image_read(
    ImageFormat_s* image_format,
    uint_ft[:,:,:] dest,
    const uint8_t[:] data,
    bint as_planar=*,
    bint expand_chroma=*
) except -1 nogil


cdef int image_write_line_component(
    ImageFormat_s* image_format,
    const uint_ft[:,:,:] src,
    uint8_t[:] dest,
    const uint16_t y,
    const uint8_t comp_index,
    const bint src_is_planar,
    const bint src_is_444
) except -1 nogil


cdef int image_write(
    ImageFormat_s* image_format,
    const uint_ft[:,:,:] src,
    uint8_t[:] dest,
    bint src_is_planar,
    bint src_is_444
) except -1 nogil
