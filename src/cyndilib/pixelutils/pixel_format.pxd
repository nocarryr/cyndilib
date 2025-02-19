# cython: language_level=3
# cython: auto_pickle=False
# cython: binding=False
# distutils: language = c++


from libc.stdint cimport *
from ..wrapper.ndi_structs cimport FourCC


cdef enum FormatFlags:
    FormatFlags_unknown     = 0
    FormatFlags_is_yuv      = 1 << 0
    FormatFlags_is_rgb      = 1 << 1
    FormatFlags_is_422      = 1 << 2
    FormatFlags_is_420      = 1 << 3
    FormatFlags_has_alpha   = 1 << 4

    FormatFlags_YUV422 = FormatFlags_is_yuv | FormatFlags_is_422
    FormatFlags_YUV420 = FormatFlags_is_yuv | FormatFlags_is_420
    FormatFlags_YUVA422 = FormatFlags_YUV422 | FormatFlags_has_alpha
    FormatFlags_RGBA32 = FormatFlags_is_rgb | FormatFlags_has_alpha


# Information for a single component within a :c:struct:`PixelFormatDef`
cdef struct PixelComponentDef:
    # Which of the 4 planes contains the component.
    uint8_t plane

    # Number of bytes between 2 horizontally consecutive pixels.
    uint8_t step

    # Number of bytes before the component of the first pixel.
    uint8_t offset

    # Number of least significant bits that must be shifted away
    # to get the value.
    uint8_t shift

    # Number of bits in the component.
    uint8_t depth



# Information for a pixel format
cdef struct PixelFormatDef:

    # Number of components in the format
    uint8_t num_components

    # Number of planes in the format
    uint8_t num_planes

    # Number of bits to shift luma width by to get chroma width
    uint8_t log2_chroma_w

    # Number of bits to shift luma height by to get chroma height
    uint8_t log2_chroma_h

    # The :class:`~cyndilib.wrapper.ndi_structs.FourCC` code for the format
    FourCC fourcc

    # :c:enum:`FormatFlags` for the format
    FormatFlags flags

    # Information for each component in the format
    PixelComponentDef comp[4]



cdef const PixelFormatDef* pixel_format_def_get(FourCC fourcc) except NULL nogil
cdef uint8_t get_bits_per_pixel(PixelFormatDef* pixdesc) noexcept nogil
cdef uint8_t get_padded_bits_per_pixel(PixelFormatDef* pixdesc) noexcept nogil
