# cython: wraparound=False, boundscheck=False

# cimport numpy as cnp
# import numpy as np

from ..wrapper.common cimport (
    raise_withgil, PyExc_Exception, PyExc_IndexError, PyExc_ValueError,
)
from .pixel_format cimport (
    FormatFlags,
    pixel_format_def_get,
    get_bits_per_pixel,
    get_padded_bits_per_pixel,
)
# from .packing cimport image_read, image_write, uint_ft



cdef void fill_pixsteps(
    PixelFormatDef* pixdesc,
    uint32_t max_pixsteps[4],
    uint8_t max_pixstep_comps[4]
) noexcept nogil:
    cdef size_t i
    cdef PixelComponentDef* comp
    for i in range(4):
        max_pixsteps[i] = 0
        max_pixstep_comps[i] = 0

    for i in range(pixdesc.num_components):
        comp = &(pixdesc.comp[i])
        if comp.step > max_pixsteps[comp.plane]:
            max_pixsteps[comp.plane] = comp.step
            max_pixstep_comps[comp.plane] = i


cdef uint32_t get_linesize(
    PixelFormatDef* desc,
    uint32_t max_pixsteps[4],
    uint8_t max_pixstep_comps[4],
    uint16_t width,
    uint8_t plane
) except -1 nogil:
    """Get the linesize of a plane in bytes for the given format and width

    Arguments:
        desc: The pixel format description
        max_pixsteps: A pre-allocated (but not filled) array of ``uint32_t[4]``
        max_pixstep_comps: A pre-allocated (but not filled) array of ``uint8_t[4]``
        width: The width of the image in pixels
        plane: The index of the plane to get the linesize for

    Returns:
        linesize (uint32_t): The linesize of the plane in bytes

    Raises:
        IndexError: If the plane index is invalid
    """
    if plane >= desc.num_planes:
        raise_withgil(PyExc_IndexError, 'invalid plane index')
    return get_linesize_no_check(
        desc, max_pixsteps, max_pixstep_comps, width, plane,
    )


cdef uint32_t get_linesize_no_check(
    PixelFormatDef* desc,
    uint32_t max_pixsteps[4],
    uint8_t max_pixstep_comps[4],
    uint16_t width,
    uint8_t plane
) noexcept nogil:
    if width == 0:
        return 0
    cdef uint32_t s, shifted_w, linesize
    if max_pixstep_comps[plane] == 1 or max_pixstep_comps[plane] == 2:
        s = desc.log2_chroma_w
    else:
        s = 0
    shifted_w = ((width + (1 << s) - 1)) >> s
    linesize = max_pixsteps[plane] * shifted_w
    return linesize


cdef uint32_t fill_planes(
    PixelFormatDef* desc,
    Plane_s planes[4],
    uint16_t width,
    uint16_t height,
    uint16_t line_stride=0
) noexcept nogil:
    """Fill the fields of a :c:struct:`Plane_s` array for the given format
    and dimensions

    Arguments:
        desc: The pixel format description
        planes: A pre-allocated array of :c:struct:`Plane_s` of length 4
        width: The width of the image in pixels
        height: The height of the image in pixels

    Returns:
        offset_bytes (uint32_t): The total size in bytes of all planes

    """
    cdef uint32_t max_pixsteps[4]
    cdef uint8_t max_pixstep_comps[4]
    cdef size_t i
    cdef uint32_t linesize, plane_height, s, offset_bytes = 0
    fill_pixsteps(desc, max_pixsteps, max_pixstep_comps)

    for i in range(4):
        planes[i].linesize = 0
        planes[i].unpadded_linesize = 0
        planes[i].offset_bytes = 0
        planes[i].size_in_bytes = 0
        planes[i].unpadded_size_in_bytes = 0
        planes[i].height = 0
        planes[i].index = i
    for i in range(desc.num_planes):
        if height == 0:
            plane_height = 0
        elif i == 0:
            plane_height = height
        else:
            s = desc.log2_chroma_h if i == 1 or i == 2 else 0
            plane_height = (height + (1 << s) - 1) >> s
        linesize = get_linesize_no_check(
            desc, max_pixsteps, max_pixstep_comps, width, i,
        )
        planes[i].unpadded_linesize = linesize
        planes[i].unpadded_size_in_bytes = linesize * plane_height
        if line_stride > 0:
            linesize = max(linesize, line_stride)
        planes[i].linesize = linesize
        planes[i].offset_bytes = offset_bytes
        planes[i].size_in_bytes = linesize * plane_height
        planes[i].height = plane_height
        offset_bytes += planes[i].size_in_bytes
    return offset_bytes


cdef void fill_comps(ImageFormat_s* image_format) noexcept nogil:
    cdef PixelFormatDef* pix_fmt = image_format.pix_fmt
    cdef ImageComponent_s* comp
    cdef bint is_yuv = pix_fmt.flags & FormatFlags.FormatFlags_is_yuv != 0
    cdef size_t i
    for i in range(4):
        comp = &(image_format.comp[i])
        if i >= image_format.pix_fmt.num_components:
            comp.width = 0
            comp.height = 0
            comp.is_chroma = False
            continue
        if is_yuv and (i == 1 or i == 2):
            comp.is_chroma = True
            comp.width = image_format.chroma_width
            comp.height = image_format.chroma_height
        else:
            comp.is_chroma = False
            comp.width = image_format.width
            comp.height = image_format.height


cdef int fill_image_format(
    ImageFormat_s* image_format,
    FourCC fourcc,
    uint16_t width,
    uint16_t height,
    uint32_t line_stride=0
) except -1 nogil:
    """Initialize all fields of an :c:struct:`ImageFormat_s` for the given fourcc
    and resolution
    """
    cdef const PixelFormatDef* pix_fmt = pixel_format_def_get(fourcc)
    cdef uint32_t size_in_bytes
    cdef uint8_t max_comp_depth = 0
    for i in range(pix_fmt.num_components):
        if pix_fmt.comp[i].depth > max_comp_depth:
            max_comp_depth = pix_fmt.comp[i].depth
    if max_comp_depth != 8 and max_comp_depth != 16:
        raise_withgil(PyExc_Exception, 'error calculating max_comp_depth')
    image_format.is_16bit = max_comp_depth == 16
    image_format.pix_fmt = <PixelFormatDef*>pix_fmt
    image_format.width = width
    image_format.height = height
    image_format.chroma_width = _get_chroma_width(image_format)
    image_format.chroma_height = _get_chroma_height(image_format)
    fill_comps(image_format)

    image_format.max_comp_depth = max_comp_depth
    size_in_bytes = fill_planes(
        image_format.pix_fmt, image_format.planes, width, height, line_stride,
    )
    cdef uint32_t max_line_stride = 0
    for i in range(image_format.pix_fmt.num_planes):
        if image_format.planes[i].linesize > max_line_stride:
            max_line_stride = image_format.planes[i].linesize
    image_format.line_stride = max_line_stride
    # if line_stride > 0:
    #     if line_stride < max_line_stride:
    #         raise_withgil(PyExc_ValueError, 'line_stride is too small')
    #     image_format.line_stride = line_stride
    # else:
    #     image_format.line_stride = max_line_stride
    image_format.size_in_bytes = size_in_bytes
    image_format.bits_per_pixel = get_bits_per_pixel(image_format.pix_fmt)
    image_format.padded_bits_per_pixel = get_padded_bits_per_pixel(
        image_format.pix_fmt
    )
    return 0


cdef void get_image_read_shape(
    ImageFormat_s* image_format,
    uint16_t shape[3],
) noexcept nogil:
    """Get the expected shape for an :c:struct:`ImageFormat_s`

    The shape will be ``(<height>, <width>, <comp>)``.
    """
    cdef uint8_t num_components = image_format.pix_fmt.num_components
    shape[0] = image_format.height
    shape[1] = image_format.width
    shape[2] = num_components


cdef uint16_t _get_chroma_height(
    ImageFormat_s* image_format
) noexcept nogil:
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef uint8_t s = desc.log2_chroma_h
    cdef uint32_t r = (image_format.height + (1 << s) - 1) >> s
    return r


cdef uint16_t _get_chroma_width(
    ImageFormat_s* image_format
) noexcept nogil:
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef uint8_t s = desc.log2_chroma_w
    cdef uint32_t r = (image_format.width + (1 << s) - 1) >> s
    return r
