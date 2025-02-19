# cython: wraparound=False, boundscheck=False
# cython: auto_pickle=False
# cython: binding=False
"""
This module provides definitions for pixel formats and related utilities
and is primarily based on FFMpeg's `libavutil/pixdesc.h` and `libavutil/pixdesc.c`.
"""

DEF NUM_FORMATS = 11

from libc.string cimport memcpy
from libcpp.map cimport map as cpp_map
from libcpp.pair cimport pair as cpp_pair

from ..wrapper.common cimport (
    raise_withgil, PyExc_KeyError,
)

ctypedef cpp_pair[FourCC, const PixelFormatDef*] pix_fmt_pair_t
ctypedef cpp_map[FourCC, const PixelFormatDef*] pix_fmt_map_t

_defs_built = False

cdef PixelFormatDef[NUM_FORMATS] pixel_format_defs
cdef pix_fmt_map_t PixelFormatMap


# Initialize definitions within a function to avoid
# multiple module-level executions on import
cdef _build_pixel_format_defs():
    cdef PixelFormatDef[NUM_FORMATS] _pixel_format_defs = [
        # UYVY: 4:2:2 Packed YUV, 16bpp, (Cb, Y0, Cr, Y1)
        PixelFormatDef(
            num_components=3, num_planes=1, log2_chroma_w=1, log2_chroma_h=0,
            fourcc=FourCC.UYVY, flags=FormatFlags_YUV422,
            comp=[
                # (plane, step, offset, shift, depth)
                PixelComponentDef( 0, 2, 1, 0, 8 ),        # /* Y */
                PixelComponentDef( 0, 4, 0, 0, 8 ),        # /* U */
                PixelComponentDef( 0, 4, 2, 0, 8 ),        # /* V */
                PixelComponentDef( 0, 0, 0, 0, 0 ),        # /* unused */
            ]
        ),
        # UYVA: 4:2:2:4 Packed YUV + Alpha, 24bpp, ((Cb, Y0, Cr, Y1) + A)
        PixelFormatDef(
            num_components=4, num_planes=2, log2_chroma_w=1, log2_chroma_h=0,
            fourcc=FourCC.UYVA, flags=FormatFlags_YUVA422,
            comp=[
                PixelComponentDef( 0, 2, 1, 0, 8 ),        # /* Y */
                PixelComponentDef( 0, 4, 0, 0, 8 ),        # /* U */
                PixelComponentDef( 0, 4, 2, 0, 8 ),        # /* V */
                PixelComponentDef( 1, 1, 0, 0, 8 ),        # /* A */
            ]
        ),
        # P216: 4:2:2 Semi-Planar 16-bit YUV, 24bpp, ((Y) + (U, V))
        PixelFormatDef(
            num_components=3, num_planes=2, log2_chroma_w=1, log2_chroma_h=0,
            fourcc=FourCC.P216, flags=FormatFlags_YUV422,
            comp=[
                PixelComponentDef( 0, 2, 0, 0, 16 ),       # /* Y */
                PixelComponentDef( 1, 4, 0, 0, 16 ),       # /* U */
                PixelComponentDef( 1, 4, 2, 0, 16 ),       # /* V */
                PixelComponentDef( 0, 0, 0, 0, 0 ),        # /* unused */
            ]
        ),
        # PA16: 4:2:2:4 Semi-Planar 16-bit YUV + Alpha, 48bpp, ((Y) + (U, V) + A)
        PixelFormatDef(
            num_components=4, num_planes=3, log2_chroma_w=1, log2_chroma_h=0,
            fourcc=FourCC.PA16, flags=FormatFlags_YUVA422,
            comp=[
                PixelComponentDef( 0, 2, 0, 0, 16 ),       # /* Y */
                PixelComponentDef( 1, 4, 0, 0, 16 ),       # /* U */
                PixelComponentDef( 1, 4, 2, 0, 16 ),       # /* V */
                PixelComponentDef( 2, 2, 0, 0, 16 ),       # /* A */
            ]
        ),
        # YV12: 4:2:0 Planar YUV, 12bpp, ((Y), (V), (U))
        PixelFormatDef(
            num_components=3, num_planes=3, log2_chroma_w=1, log2_chroma_h=1,
            fourcc=FourCC.YV12, flags=FormatFlags_YUV420,
            comp=[
                PixelComponentDef( 0, 1, 0, 0, 8 ),        # /* Y */
                PixelComponentDef( 2, 1, 0, 0, 8 ),        # /* U */
                PixelComponentDef( 1, 1, 0, 0, 8 ),        # /* V */
                PixelComponentDef( 0, 0, 0, 0, 0 ),        # /* unused */
            ]
        ),
        # I420: 4:2:0 Planar YUV, 12bpp, ((Y), (U), (V))
        PixelFormatDef(
            num_components=3, num_planes=3, log2_chroma_w=1, log2_chroma_h=1,
            fourcc=FourCC.I420, flags=FormatFlags_YUV420,
            comp=[
                PixelComponentDef( 0, 1, 0, 0, 8 ),        # /* Y */
                PixelComponentDef( 1, 1, 0, 0, 8 ),        # /* U */
                PixelComponentDef( 2, 1, 0, 0, 8 ),        # /* V */
                PixelComponentDef( 0, 0, 0, 0, 0 ),        # /* unused */
            ]
        ),
        # NV12: 4:2:0 Semi-Planar YUV, 12bpp, ((Y), (U, V))
        PixelFormatDef(
            num_components=3, num_planes=2, log2_chroma_w=1, log2_chroma_h=1,
            fourcc=FourCC.NV12, flags=FormatFlags_YUV420,
            comp=[
                PixelComponentDef( 0, 1, 0, 0, 8 ),        # /* Y */
                PixelComponentDef( 1, 2, 0, 0, 8 ),        # /* U */
                PixelComponentDef( 1, 2, 1, 0, 8 ),        # /* V */
                PixelComponentDef( 0, 0, 0, 0, 0 ),        # /* unused */
            ]
        ),
        # BGRA: 4:4:4:4 Packed RGBA, 32bpp, (B, G, R, A)
        PixelFormatDef(
            num_components=4, num_planes=1, log2_chroma_w=0, log2_chroma_h=0,
            fourcc=FourCC.BGRA, flags=FormatFlags_RGBA32,
            comp=[
                PixelComponentDef( 0, 4, 2, 0, 8 ),        # /* R */
                PixelComponentDef( 0, 4, 1, 0, 8 ),        # /* G */
                PixelComponentDef( 0, 4, 0, 0, 8 ),        # /* B */
                PixelComponentDef( 0, 4, 3, 0, 8 ),        # /* A */
            ]
        ),
        # BGRX: 4:4:4 Packed RGB, 24bpp + padding, (B, G, R, X)
        PixelFormatDef(
            num_components=3, num_planes=1, log2_chroma_w=0, log2_chroma_h=0,
            fourcc=FourCC.BGRX, flags=FormatFlags_is_rgb,
            comp=[
                PixelComponentDef( 0, 4, 2, 0, 8 ),        # /* R */
                PixelComponentDef( 0, 4, 1, 0, 8 ),        # /* G */
                PixelComponentDef( 0, 4, 0, 0, 8 ),        # /* B */
                PixelComponentDef( 0, 0, 0, 0, 0 ),        # /* unused */
            ]
        ),
        # RGBA: 4:4:4:4 Packed RGBA, 32bpp, (R, G, B, A)
        PixelFormatDef(
            num_components=4, num_planes=1, log2_chroma_w=0, log2_chroma_h=0,
            fourcc=FourCC.RGBA, flags=FormatFlags_RGBA32,
            comp=[
                PixelComponentDef( 0, 4, 0, 0, 8 ),        # /* R */
                PixelComponentDef( 0, 4, 1, 0, 8 ),        # /* G */
                PixelComponentDef( 0, 4, 2, 0, 8 ),        # /* B */
                PixelComponentDef( 0, 4, 3, 0, 8 ),        # /* A */
            ]
        ),
        # RGBX: 4:4:4 Packed RGB, 24bpp + padding, (R, G, B, X)
        PixelFormatDef(
            num_components=3, num_planes=1, log2_chroma_w=0, log2_chroma_h=0,
            fourcc=FourCC.RGBX, flags=FormatFlags_is_rgb,
            comp=[
                PixelComponentDef( 0, 4, 0, 0, 8 ),        # /* R */
                PixelComponentDef( 0, 4, 1, 0, 8 ),        # /* G */
                PixelComponentDef( 0, 4, 2, 0, 8 ),        # /* B */
                PixelComponentDef( 0, 0, 0, 0, 0 ),        # /* unused */
            ]
        ),
    ]
    cdef size_t i
    cdef void *src
    cdef void *dst
    for i in range(NUM_FORMATS):
        src = &(_pixel_format_defs[i])
        dst = &(pixel_format_defs[i])
        memcpy(dst, src, sizeof(PixelFormatDef))
        _add_fmt_to_map(&(pixel_format_defs[i]))

cdef int _add_fmt_to_map(const PixelFormatDef* fmt_ptr) except -1:
    cdef FourCC fourcc = fmt_ptr.fourcc
    if PixelFormatMap.count(fourcc) > 0:
        raise_withgil(PyExc_KeyError, 'PixelFormatDef already exists')
    cdef pix_fmt_pair_t pair = pix_fmt_pair_t(fourcc, fmt_ptr)
    PixelFormatMap.insert(pair)
    return 0


def _init_defs():
    global _defs_built
    if _defs_built:
        return
    _build_pixel_format_defs()
    _defs_built = True

_init_defs()




cdef const PixelFormatDef* pixel_format_def_get(FourCC fourcc) except NULL nogil:
    """Get the :c:struct:`PixelFormatDef` matching the given FourCC

    Raises:
        KeyError: If the FourCC is not found

    """
    if PixelFormatMap.count(fourcc) == 0:
        raise_withgil(PyExc_KeyError, 'PixelFormatDef not found')
    return PixelFormatMap[fourcc]


cdef uint8_t get_bits_per_pixel(PixelFormatDef* pixdesc) noexcept nogil:
    """Get the bits per pixel for the given :c:struct:`PixelFormatDef`

    The result includes bits per pixel for all components, excluding padding.
    """
    cdef uint32_t c, s, bits = 0
    cdef uint8_t log2_pixels = pixdesc.log2_chroma_w + pixdesc.log2_chroma_h

    for c in range(pixdesc.num_components):
        s = 0 if c == 1 or c == 2 else log2_pixels
        bits += pixdesc.comp[c].depth << s

    return bits >> log2_pixels;


cdef uint8_t get_padded_bits_per_pixel(PixelFormatDef* pixdesc) noexcept nogil:
    """Get the padded bits per pixel for the given :c:struct:`PixelFormatDef`

    The result includes bits per pixel for all components, including padding.
    """
    cdef uint32_t c, s, bits = 0
    cdef uint8_t log2_pixels = pixdesc.log2_chroma_w + pixdesc.log2_chroma_h
    cdef uint8_t[4] steps = [0, 0, 0, 0]
    cdef PixelComponentDef* comp

    for c in range(pixdesc.num_components):
        comp = &(pixdesc.comp[c])
        s = 0 if c == 1 or c == 2 else log2_pixels
        steps[comp.plane] = comp.step << s

    for c in range(4):
        bits += steps[c]

    bits *= 8

    return bits >> log2_pixels;
