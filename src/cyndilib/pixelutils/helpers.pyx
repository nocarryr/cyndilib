# cython: wraparound=False, boundscheck=False

DEF MAX_BFR_DIMS = 8

cimport cython
cimport numpy as cnp
import numpy as np

from libc.string cimport memcpy
from ..wrapper.common cimport (
    mem_alloc, mem_free, raise_mem_err, raise_withgil,
    PyExc_RuntimeError, PyExc_ValueError,
)
from ..wrapper.ndi_structs cimport fourcc_type_uncast, fourcc_type_cast
from .packing cimport image_read, image_write
from .image_format cimport fill_image_format, get_image_read_shape


cdef object uint8_dtype = np.uint8
cdef object uint16_dtype = np.uint16
cdef object np_zeros = np.zeros



cdef class ImageFormat:
    """Helper class to pack / unpack raw image data to and from image arrays

    Arguments:
        fourcc (FourCC): The initial :attr:`fourcc` value
        width (int): The initial :attr:`width` value
        height (int): The initial :attr:`height` value
        expand_chroma (bool): The initial :attr:`expand_chroma` value
        line_stride (int): The initial :attr:`line_stride` value. If ``0``, the
            line stride will be calculated based on the image format.

    """
    def __init__(
        self,
        FourCC fourcc,
        uint16_t width,
        uint16_t height,
        bint expand_chroma,
        uint32_t line_stride = 0
        # bint force_line_stride = False
    ):
        self._force_line_stride = line_stride != 0
        fill_image_format(&self._fmt, fourcc, width, height, line_stride)
        self._line_stride = self._fmt.line_stride
        self._expand_chroma = expand_chroma
        get_image_read_shape(&self._fmt, self._shape)

    @property
    def width(self):
        """Width in pixels
        """
        return self._fmt.width
    @width.setter
    def width(self, uint16_t value):
        if value == self._fmt.width:
            return
        self._set_resolution(value, self._fmt.height)

    @property
    def height(self):
        """Height in pixels
        """
        return self._fmt.height
    @height.setter
    def height(self, uint16_t value):
        if value == self._fmt.height:
            return
        self._set_resolution(self._fmt.width, value)

    @property
    def resolution(self):
        """Image resolution as a tuple of ``(width, height)``

        (read-only)
        """
        return self._fmt.width, self._fmt.height

    @property
    def chroma_width(self):
        """Width of the chroma (UV) components in pixels

        This is the same as the luma width for 4:4:4 formats.

        (read-only)
        """
        return self._fmt.chroma_width

    @property
    def chroma_height(self):
        """Height of the chroma (UV) components in pixels

        This is the same as the luma height for 4:4:4 and 4:2:2 formats.

        (read-only)
        """
        return self._fmt.chroma_height

    @property
    def fourcc(self):
        """The :class:`~.wrapper.ndi_structs.FourCC` for the pixel format
        """
        return self._fmt.pix_fmt.fourcc
    @fourcc.setter
    def fourcc(self, FourCC value):
        if value == self._fmt.pix_fmt.fourcc:
            return
        self._set_fourcc(value)

    @property
    def line_stride(self):
        """Line stride in bytes

        (read-only)
        """
        return self._line_stride

    @property
    def force_line_stride(self):
        """Whether :attr:`line_stride` is forced to a specific value

        This is a read-only property. To set the line stride, use the
        :meth:`set_line_stride` method.
        """
        return self._force_line_stride

    @property
    def size_in_bytes(self):
        """Size of the packed image in bytes

        (read-only)
        """
        return self._fmt.size_in_bytes

    @property
    def bits_per_pixel(self):
        """Bits per pixel

        (read-only)
        """
        return self._fmt.bits_per_pixel

    @property
    def padded_bits_per_pixel(self):
        """Padded bits per pixel

        (read-only)
        """
        return self._fmt.padded_bits_per_pixel

    @property
    def num_planes(self):
        """Number of planes in the image format

        (read-only)
        """
        return self._fmt.pix_fmt.num_planes

    @property
    def num_components(self):
        """Number of components in the image format

        This will be 3 for all formats that do not include alpha.

        (read-only)
        """
        return self._fmt.pix_fmt.num_components

    @property
    def is_16bit(self):
        """Whether the image format is 16-bit

        (read-only)
        """
        return self._fmt.is_16bit

    @property
    def expand_chroma(self):
        """If ``True``, the chroma components will be expanded (copied) to fill
        the width and height for 4:2:2 and 4:2:0 formats. Otherwise, they will
        remain in their original states.
        """
        return self._expand_chroma
    @expand_chroma.setter
    def expand_chroma(self, bint value):
        if value == self._expand_chroma:
            return
        self._expand_chroma = value

    @property
    def shape(self):
        """The expected shape for unpacked image arrays

        This will be ``(<height>, <width>, <comp>)`` where ``<comp>`` is the
        component (YUVA, RGBA, etc).
        """
        return self._shape[0], self._shape[1], self._shape[2]

    def set_resolution(self, uint16_t width, uint16_t height):
        """Set the :attr:`resolution`
        """
        self._set_resolution(width, height)

    def set_line_stride(self, uint32_t line_stride, bint force):
        """Set :attr:`line_stride` and :attr:`force_line_stride`

        This method may be used to ensure proper byte-alignment per-line.
        It exists primarily for use when receiving video with odd horizontal
        resolution.

        Arguments:
            line_stride: The line stride to set. If *force* is ``False``,
                this argument is ignored.
            force: The value to set for :attr:`force_line_stride`

        """
        self._set_line_stride(line_stride, force)

    cdef int _update_format(
        self,
        FourCC fourcc,
        uint16_t width,
        uint16_t height,
    ) except -1 nogil:
        cdef uint32_t line_stride = 0
        if self._force_line_stride:
            line_stride = self._line_stride
        fill_image_format(&self._fmt, fourcc, width, height, line_stride)
        if not self._force_line_stride:
            self._line_stride = self._fmt.line_stride
        get_image_read_shape(&self._fmt, self._shape)
        return 0

    cdef int _set_fourcc(self, FourCC fourcc) except -1 nogil:
        if fourcc == self._fmt.pix_fmt.fourcc:
            return 0
        self._update_format(fourcc, self._fmt.width, self._fmt.height)
        return 0

    cdef int _set_resolution(self, uint16_t width, uint16_t height) except -1 nogil:
        self._update_format(self._fmt.pix_fmt.fourcc, width, height)
        return 0

    cdef int _set_line_stride(self, uint32_t line_stride, bint force) except -1 nogil:
        if line_stride == self._line_stride and force == self._force_line_stride:
            return 0
        if force and line_stride == 0:
            raise_withgil(PyExc_ValueError, 'line_stride must be > 0')
        self._force_line_stride = force
        self._line_stride = line_stride
        self._update_format(
            fourcc=self._fmt.pix_fmt.fourcc, width=self._fmt.width,
            height=self._fmt.height,
        )
        return 0

    cdef int _unpack(self, const uint8_t[:] src, uint_ft[:,:,:] dest) except -1 nogil:
        image_read(
            image_format=&self._fmt, dest=dest, data=src,
            expand_chroma=self._expand_chroma,
        )
        return 0

    def unpack_into(self, const uint8_t[:] src, uint_ft[:,:,:] dest):
        """Unpack the raw data in *src* to the *dest* image array
        """
        self._unpack(src, dest)

    cdef int _pack(self, const uint_ft[:,:,:] src, uint8_t[:] dest) except -1 nogil:
        image_write(
            image_format=&self._fmt, src=src, dest=dest,
            src_is_444=self._expand_chroma,
        )
        return 0

    cdef object unpack_8_bit(self, const uint8_t[:] src):
        arr = np_zeros(self._shape, dtype=uint8_dtype)
        cdef uint8_t[:,:,:] arr_view = arr
        self._unpack(src, arr_view)
        return arr

    cdef object unpack_16_bit(self, const uint8_t[:] src):
        arr = np_zeros(self._shape, dtype=uint16_dtype)
        cdef uint16_t[:,:,:] arr_view = arr
        self._unpack(src, arr_view)
        return arr

    def unpack(self, const uint8_t[:] src):
        """Unpack the raw data in *src* to an image array

        Returns:
            numpy.ndarray: The unpacked image array with shape matching the
                :attr:`shape` property
        """
        if self._fmt.is_16bit:
            return self.unpack_16_bit(src)
        return self.unpack_8_bit(src)

    def pack_into(self, const uint_ft[:,:,:] src, uint8_t[:] dest):
        """Pack the image array *src* into the raw *dest* array
        """
        self._pack(src, dest)

    def pack(self, const uint_ft[:,:,:] src):
        """Pack the image array *src* into a raw array

        Arguments:
            src (numpy.ndarray): The image array to pack.  This must match the
                shape of the :attr:`shape` property

        Returns:
            numpy.ndarray: The packed raw image data
        """
        arr = np_zeros(self._fmt.size_in_bytes, dtype=uint8_dtype)
        cdef uint8_t[:] arr_view = arr
        self._pack(src, arr_view)
        return arr


cdef class ImageReader(ImageFormat):
    """Helper class to read raw image data from an NDI video frame
    """
    def __cinit__(self, *args, **kwargs):
        cdef size_t i
        for i in range(MAX_BFR_DIMS):
            self.bfr_shape[i] = 0

    def __init__(
        self,
        FourCC fourcc,
        uint16_t width,
        uint16_t height,
        bint expand_chroma,
    ):
        ImageFormat.__init__(self, fourcc, width, height, expand_chroma)
        self.c_buffer = CarrayBuffer()

    cdef int read_from_ndi_video_frame(
        self,
        NDIlib_video_frame_v2_t* ptr,
        uint_ft[:,:,:] dest
    ) except -1 nogil:
        cdef FourCC ptr_fourcc = fourcc_type_uncast(ptr.FourCC)
        if ptr_fourcc != self._fmt.pix_fmt.fourcc:
            raise_withgil(PyExc_ValueError, 'fourcc mismatch')
        if ptr.xres != self._fmt.width or ptr.yres != self._fmt.height:
            raise_withgil(PyExc_ValueError, 'frame resolution mismatch')
        self.read_from_c_pointer(ptr.p_data, dest)
        return 0

    cdef int write_to_ndi_video_frame(
        self,
        NDIlib_video_frame_v2_t* ptr,
        uint_ft[:,:,:] src
    ) except -1 nogil:
        # ptr.FourCC = fourcc_type_cast(self._fmt.pix_fmt.fourcc)
        # ptr.xres = self._fmt.width
        # ptr.yres = self._fmt.height
        # ptr.line_stride_in_bytes = self._fmt.size_in_bytes
        cdef FourCC ptr_fourcc = fourcc_type_uncast(ptr.FourCC)
        if ptr_fourcc != self._fmt.pix_fmt.fourcc:
            raise_withgil(PyExc_ValueError, 'fourcc mismatch')
        if ptr.xres != self._fmt.width or ptr.yres != self._fmt.height:
            raise_withgil(PyExc_ValueError, 'frame resolution mismatch')
        ptr.line_stride_in_bytes = self._fmt.size_in_bytes
        self.write_to_c_pointer(src, ptr.p_data)


    cdef int read_from_c_pointer(
        self,
        const uint8_t* src_ptr,
        uint_ft[:,:,:] dest
    ) except -1 nogil:
        self.bfr_shape[0] = self._fmt.size_in_bytes
        self.c_buffer.set_array_ptr(<char*>src_ptr, self.bfr_shape, ndim=1)
        cdef const uint8_t[:] src_view = self.c_buffer

        image_read(
            image_format=&self._fmt, dest=dest, data=src_view,
            expand_chroma=self._expand_chroma,
        )
        return 0

    cdef int write_to_c_pointer(
        self,
        const uint_ft[:,:,:] src,
        uint8_t* dest_ptr
    ) except -1 nogil:
        self.bfr_shape[0] = self._fmt.size_in_bytes
        self.c_buffer.set_array_ptr(<char*>dest_ptr, self.bfr_shape, ndim=1)
        cdef uint8_t[:] dest_view = self.c_buffer

        image_write(
            image_format=&self._fmt, src=src, dest=dest_view,
            src_is_444=self._expand_chroma,
        )
        return 0



cdef class CarrayBuffer:
    """Internal helper to wrap a c array pointer in a Python buffer (memoryview)
    """
    def __cinit__(self, *args, **kwargs):
        self.carr_ptr = NULL
        self.view_count = 0
        self.view_active = False
        cdef size_t i
        for i in range(MAX_BFR_DIMS):
            self.shape[i] = 0
            self.strides[i] = 1
        self.ndim = 1
        self.itemsize = 1
        self.size = 0
        self.format = 'B'
        self.readonly = True

    def __dealloc__(self):
        self.carr_ptr = NULL

    cdef int set_array_ptr(
        self,
        char *ptr,
        Py_ssize_t[MAX_BFR_DIMS] shape,
        size_t ndim = 1,
        size_t itemsize = 1,
        bint readonly = True
    ) except -1 nogil:
        if self.view_active:
            raise_withgil(PyExc_RuntimeError, 'buffer is in use')
        if ndim > MAX_BFR_DIMS:
            raise_withgil(PyExc_ValueError, 'too many axes')
        self.carr_ptr = ptr
        cdef size_t i = ndim - 1, stride = itemsize, size = 0
        while i >= 0:
            self.shape[i] = shape[i]
            self.strides[i] = stride
            size += shape[i]
            stride += itemsize * shape[i]
            if i == 0:
                break
            i -= 1
        self.size = size
        self.ndim = ndim
        self.readonly = readonly
        return 0

    cdef int release_array_ptr(self) except -1 nogil:
        # if self.view_count > 0:
        #     raise_withgil(PyExc_RuntimeError, 'buffer is in use')
        self.carr_ptr = NULL
        self.shape[0] = 0
        return 0

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        cdef char *ptr = self.carr_ptr
        if ptr is NULL:
            raise ValueError('buffer is NULL')
        buffer.buf = ptr
        buffer.format = 'B'
        buffer.internal = NULL
        buffer.itemsize = self.itemsize
        buffer.len = self.size
        buffer.ndim = self.ndim
        buffer.obj = self
        buffer.readonly = 1 if self.readonly else 0
        buffer.shape = <Py_ssize_t*>self.shape
        buffer.strides = <Py_ssize_t*>self.strides
        buffer.suboffsets = NULL
        self.view_count += 1
        self.view_active = True

    def __releasebuffer__(self, Py_buffer *buffer):
        self.view_count -= 1
        if self.view_count == 0:
            self.view_active = False
            if self.carr_ptr is not NULL:
                self.release_array_ptr()
