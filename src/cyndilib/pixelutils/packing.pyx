# cython: wraparound=False, boundscheck=False
"""
This module provides functions for reading and writing raw image data
and is primarily based on FFMpeg's `libavutil/imgutils.c` and `libavutil/pixdesc.c`
"""

cimport cython
from libc.math cimport lroundf

from ..wrapper.common cimport (
    raise_withgil, PyExc_Exception, PyExc_IndexError,
)
from .image_format cimport (
    ImageComponent_s,
    Plane_s,
    get_image_read_shape,
)
from .pixel_format cimport (
    PixelFormatDef,
    PixelComponentDef,
    FormatFlags,
)
from ..wrapper.ndi_structs cimport FourCC



cdef uint16_t image_read_line_component(
    ImageFormat_s* image_format,
    uint_ft[:] dest,
    const uint8_t[:] data,
    uint16_t x,
    uint16_t y,
    uint16_t max_count,
    uint8_t comp_index,
    bint expand_chroma
) noexcept nogil:
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef PixelComponentDef* comp = &(desc.comp[comp_index])
    cdef ImageComponent_s* image_comp = &(image_format.comp[comp_index])
    cdef uint8_t step = comp.step
    cdef int num_requested = max_count - x
    cdef int num_avail = image_comp.width - x

    if num_avail <= 0:
        return 0
    if num_requested > num_avail:
        num_requested = num_avail
    if num_requested <= 0:
        return 0

    cdef Plane_s* plane_ptr = &(image_format.planes[comp.plane])

    if (
        image_comp.is_chroma and
        desc.log2_chroma_h != 0 and
        y >= image_format.chroma_height
    ):
        return 0

    cdef size_t data_ix = (
        plane_ptr.offset_bytes + y * plane_ptr.linesize +
        x * step + comp.offset
    )

    cdef bint is_chroma_expand = (
        desc.log2_chroma_w != 0 and image_comp.is_chroma
    )
    cdef size_t dest_ix = 0
    # cdef bint is_8bit = image_format.max_comp_depth == 8
    # cdef bint is_16bit = image_format.max_comp_depth == 16
    cdef bint is_16bit = image_format.is_16bit
    cdef uint32_t val
    cdef size_t i
    cdef uint16_t comps_filled = 0

    for i in range(num_requested):
        # if data_shape_0 <= data_ix:
        #     raise_withgil(PyExc_IndexError, 'index error')
        val = data[data_ix]

        # note: we're assuming big-endian here
        if is_16bit:
            val += data[data_ix+1] << 8
            if uint_ft is uint8_t:
                val >>= 8

        dest[dest_ix] = val

        if expand_chroma and is_chroma_expand:
            dest[dest_ix+1] = val
            dest_ix += 1
            comps_filled += 1
        dest_ix += 1
        data_ix += step
        comps_filled += 1
    return comps_filled


cdef int image_read_line(
    ImageFormat_s* image_format,
    uint16_t comp_widths[4],
    uint_ft[:,:] dest,
    const uint8_t[:] data,
    uint16_t x,
    uint16_t y,
    uint16_t max_count,
    bint expand_chroma
) noexcept nogil:
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef uint8_t i, num_components = desc.num_components
    cdef ImageComponent_s* image_comp
    cdef uint16_t n

    for i in range(4):
        if i >= num_components:
            comp_widths[i] = 0
            continue

        image_comp = &(image_format.comp[i])
        if y >= image_comp.height or x >= image_comp.width:
            comp_widths[i] = 0
            continue
        n = image_read_line_component(
            image_format,
            dest=dest[:,i], data=data,
            x=x, y=y, max_count=max_count, comp_index=i,
            expand_chroma=expand_chroma,
        )
        comp_widths[i] = n
    return 0

cdef int _unpack_rgb(
    ImageFormat_s* image_format,
    uint8_t[:,:,:] dest,
    const uint8_t[:] data,
) noexcept nogil:
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef PixelComponentDef* comp
    cdef uint8_t offsets[4]
    cdef uint8_t num_components = desc.num_components, step = 4
    cdef uint16_t height = image_format.height, width = image_format.width
    cdef uint16_t linestep = width * step
    cdef size_t i, j, k, data_ix = 0
    for k in range(num_components):
        comp = &(desc.comp[k])
        offsets[k] = comp.offset

    for i in range(height):
        for j in range(width):
            data_ix = i * linestep + j * step
            for k in range(num_components):
                dest[i,j,k] = data[data_ix+offsets[k]]
    return 0


cdef int image_read(
    ImageFormat_s* image_format,
    uint_ft[:,:,:] dest,
    const uint8_t[:] data,
    bint expand_chroma = True
) except -1 nogil:
    """Fill *dest* array from raw *data*

    Arguments:
        image_format (ImageFormat_s*): The image format pointer
        dest: The 3d memoryview to read into.  Its shape should match that of
            :c:func:`get_image_read_shape` and type should match the largest
            component of the pixel format.
        data: The source data to read from as an array/memoryview of ``uint8_t``
        expand_chroma: If ``True``, the chroma components will be expanded
            (copied) to fill the width and height (for 4:2:2 and 4:2:0 formats).
            Otherwise, they will remain in their original states.

    """
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef uint16_t width = image_format.width, height = image_format.height
    cdef uint16_t read_shape[3]
    get_image_read_shape(image_format, read_shape)

    cdef bint is_420 = desc.log2_chroma_h != 0
    cdef uint16_t comp_widths[4]
    cdef bint is_rgb = desc.flags & FormatFlags.FormatFlags_is_rgb != 0
    if data.shape[0] < image_format.size_in_bytes:
        raise_withgil(PyExc_Exception, 'invalid src shape')

    for i in range(3):
        if dest.shape[i] < read_shape[i]:
            raise_withgil(PyExc_Exception, 'invalid dest shape')

    with nogil(True):
        if uint_ft is uint8_t:
            if is_rgb:
                _unpack_rgb(image_format, dest, data)
                return 0

        for i in range(height):
            image_read_line(
                image_format, comp_widths, dest[i], data,
                x=0, y=i, max_count=width, expand_chroma=expand_chroma,
            )

        if is_420 and expand_chroma:
            # Copy each line's u/v values to their following rows
            # starting with chroma_height (height//2) so it can be done in-place
            # without overwritting any data
            _expand_chroma_height(image_format, dest)
    return 0


cdef void _expand_chroma_height(
    ImageFormat_s* image_format,
    uint_ft[:,:,:] dest,
) noexcept nogil:
    cdef uint16_t width = image_format.width, height = image_format.height
    cdef uint16_t chroma_height = image_format.chroma_height
    cdef size_t i, j, k, chroma_index

    i = chroma_height
    while i > 0:
        chroma_index = i * 2
        for j in range(width):
            for k in range(1, 3):
                dest[chroma_index-1,j,k] = dest[i-1,j,k]
                dest[chroma_index-2,j,k] = dest[i-1,j,k]
        i -= 1



cdef int _pack_rgb(
    ImageFormat_s* image_format,
    const uint8_t[:,:,:] src,
    uint8_t[:] dest,
) noexcept nogil:
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef PixelComponentDef* comp
    cdef uint8_t offsets[4]
    cdef uint8_t value
    cdef uint8_t num_components = desc.num_components, step = 4
    cdef uint16_t height = image_format.height, width = image_format.width
    cdef uint16_t linestep = width * step
    cdef bint fill_alpha = num_components == 3
    cdef size_t i, j, k, data_ix = 0
    for k in range(num_components):
        comp = &(desc.comp[k])
        offsets[k] = comp.offset
    if fill_alpha:
        offsets[3] = 3

    for i in range(height):
        for j in range(width):
            data_ix = (i * linestep + j * step)
            for k in range(4):
                if fill_alpha and k == 3:
                    value = 255
                else:
                    value = src[i,j,k]
                dest[data_ix + offsets[k]] = value
    return 0


cdef int image_write_line_component(
    ImageFormat_s* image_format,
    const uint_ft[:,:,:] src,
    uint8_t[:] dest,
    const uint16_t y,
    const uint8_t comp_index,
    const bint src_is_444
) except -1 nogil:
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef PixelComponentDef* comp = &(desc.comp[comp_index])
    cdef ImageComponent_s* image_comp = &(image_format.comp[comp_index])
    cdef uint8_t step = comp.step
    cdef Plane_s* plane_ptr = &(image_format.planes[comp.plane])
    cdef uint16_t num_to_write = image_comp.width
    cdef bint is_420 = desc.log2_chroma_h != 0
    cdef bint is_422 = desc.log2_chroma_w != 0
    cdef bint is_16bit = image_format.is_16bit


    cdef bint need_uv_avg_w = (
        src_is_444 and image_comp.is_chroma and
        (is_420 or is_422)
    )
    cdef bint need_uv_avg_h = (
        src_is_444 and image_comp.is_chroma and is_420
    )
    cdef size_t dest_shape_0 = dest.shape[0]

    if is_420 and image_comp.is_chroma:
        if y >= image_format.chroma_height:
            return 0
    cdef uint16_t chroma_y = y
    if need_uv_avg_h:
        chroma_y *= 2

    cdef size_t data_ix = (
        plane_ptr.offset_bytes + y * plane_ptr.linesize + comp.offset
    )
    cdef uint32_t val
    cdef size_t i

    for i in range(num_to_write):
        if dest_shape_0 <= data_ix:
            raise_withgil(PyExc_IndexError, 'index error')
        if need_uv_avg_w:
            val = src[chroma_y, i*2, comp_index]
        else:
            val = src[y, i, comp_index]

        # note: we're assuming big-endian here
        if uint_ft is uint8_t:
            if is_16bit:
                dest[data_ix] = 0
                dest[data_ix+1] = val << 8
            else:
                dest[data_ix] = val
        else:
            if is_16bit:
                dest[data_ix] = val & 0xff
                dest[data_ix+1] = val >> 8
            else:
                dest[data_ix] = val >> 8

        prev_val = val
        data_ix += step
    return 0


cdef int image_write(
    ImageFormat_s* image_format,
    const uint_ft[:,:,:] src,
    uint8_t[:] dest,
    bint src_is_444
) except -1 nogil:
    """Pack data from *src* into the raw *dest* array

    Arguments:
        image_format (ImageFormat_s*): The image format pointer
        src: The image data
        dest: Array/memoryview of ``uint8_t`` to write the raw data into
        src_is_444: If ``True`` the chroma components in *src* should fill the
            resolution.  Otherwise, they are assumed to match the expected
            width/height of the image format (4:2:2 / 4:2:0).
    """
    cdef PixelFormatDef* desc = image_format.pix_fmt
    cdef uint16_t height = image_format.height
    cdef uint8_t num_components = desc.num_components
    cdef uint16_t read_shape[3]
    get_image_read_shape(image_format, read_shape)

    cdef bint is_rgb = desc.flags & FormatFlags.FormatFlags_is_rgb != 0
    if dest.shape[0] < image_format.size_in_bytes:
        raise_withgil(PyExc_Exception, 'invalid src shape')

    cdef size_t i, j, k

    for i in range(3):
        if src.shape[i] < read_shape[i]:
            raise_withgil(PyExc_Exception, 'invalid dest shape')


    with nogil:
        if uint_ft is uint8_t:
            if is_rgb:
                _pack_rgb(image_format, src, dest)
                return 0

        for i in range(height):
            for j in range(num_components):
                image_write_line_component(
                    image_format=image_format, src=src, dest=dest,
                    y=i, comp_index=j, src_is_444=src_is_444
                )
    return 0
