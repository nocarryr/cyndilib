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

    def get_buffer_size(self):
        return self._get_buffer_size()

    cdef size_t _get_buffer_size(self) nogil except *:
        return self.ptr.line_stride_in_bytes * self.ptr.yres

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
        self.read_bfr = av_frame_bfr_create(self.video_bfrs)
        self.write_bfr = av_frame_bfr_create(self.read_bfr)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.max_buffers = kwargs.get('max_buffers', 4)
        self.read_lock = RLock()
        self.write_lock = RLock()
        self.read_ready = Condition(self.read_lock)
        self.write_ready = Condition(self.write_lock)
        self.all_frame_data = np.zeros((self.max_buffers, 0), dtype=np.uint8)
        self.current_frame_data = np.zeros(0, dtype=np.uint8)
        self.view_count = 0

    def __dealloc__(self):
        cdef video_bfr_p bfr = self.video_bfrs
        if self.video_bfrs is not NULL:
            self.video_bfrs = NULL
            self.write_bfr = NULL
            av_frame_bfr_destroy(bfr)

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        # buffer view is flattened on first axis
        cdef size_t bfr_len, size_in_bytes
        cdef bint is_empty
        cdef cnp.ndarray[cnp.uint8_t, ndim=1] frame_data
        with self.read_lock:
            bfr_len = self.read_indices.size()
            is_empty = bfr_len == 0
            if not is_empty:
                if self.view_count == 0:
                    self._check_read_array_size()
                    frame_data = self.current_frame_data
                    if frame_data.shape[0] == 0:
                        is_empty = True
                    else:
                        self._fill_read_data(advance=True)
            if is_empty:
                raise ValueError('Buffer empty')
            self.view_count += 1

        frame_data = self.current_frame_data
        self.bfr_shape[0] = frame_data.shape[0]
        self.bfr_strides[0] = frame_data.strides[0]
        size_in_bytes = frame_data.strides[0] * frame_data.shape[0]

        buffer.buf = <uint8_t *>frame_data.data
        buffer.format = 'B'
        buffer.internal = NULL
        buffer.itemsize = frame_data.strides[0]
        buffer.len = size_in_bytes
        buffer.ndim = frame_data.ndim
        buffer.obj = self
        buffer.readonly = 1
        buffer.shape = self.bfr_shape
        buffer.strides = self.bfr_strides
        buffer.suboffsets = NULL

    def __releasebuffer__(self, Py_buffer *buffer):
        with self.read_lock:
            self.view_count -= 1

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef void _check_read_array_size(self) except *:
        cdef cnp.uint8_t[:,:] all_frame_data = self.all_frame_data
        cdef cnp.uint8_t[:] read_data = self.current_frame_data
        cdef size_t ncols = all_frame_data.shape[1]
        if read_data.shape[0] != ncols:
            with self.read_lock:
                self.current_frame_data = np.zeros(ncols, dtype=np.uint8)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef void _fill_read_data(self, bint advance) nogil except *:
        cdef cnp.uint8_t[:,:] all_frame_data = self.all_frame_data
        cdef cnp.uint8_t[:] arr = self.current_frame_data
        cdef size_t bfr_idx = self.read_indices.front()
        with nogil:
            if advance:
                self.read_indices.pop_front()
                self.read_indices_set.erase(bfr_idx)

            arr[...] = all_frame_data[bfr_idx,...]

    def get_buffer_depth(self):
        return self.read_indices.size()

    def buffer_full(self):
        return self.read_indices.size() >= self.max_buffers

    def skip_frames(self, bint eager):
        cdef size_t idx, max_remain, cur_size, num_skipped = 0
        with self.read_lock:
            cur_size = self.read_indices.size()
            if not cur_size:
                return
            if eager:
                max_remain = 1
            else:
                max_remain = cur_size - 1
            while True:
                idx = self.read_indices.front()
                self.read_indices.pop_front()
                self.read_indices_set.erase(idx)
                num_skipped += 1
                if not eager:
                    break
                if self.read_indices.size() <= max_remain:
                    break
        return num_skipped

    @cython.boundscheck(False)
    @cython.wraparound(False)
    def fill_p_data(self, cnp.uint8_t[:] dest):
        cdef size_t bfr_len, vc, bfr_idx
        cdef cnp.uint8_t[:,:] all_frame_data = self.all_frame_data
        cdef cnp.uint8_t[:] read_view = self.current_frame_data
        cdef bint valid = False
        with self.read_lock:
            vc = self.view_count
            self.view_count += 1
            try:
                with nogil:
                    bfr_len = self.read_indices.size()
                    if vc == 0:
                        if bfr_len > 0:
                            bfr_idx = self.read_indices.front()
                            self.read_indices.pop_front()
                            self.read_indices_set.erase(bfr_idx)
                            dest[:] = all_frame_data[bfr_idx,:]
                            valid = True
                    else:
                        dest[:] = read_view
                        valid = True
            finally:
                self.view_count -= 1
            return valid

    cdef size_t _get_next_write_index(self) nogil except *:
        cdef size_t idx, niter, result, bfr_len = self.read_indices.size()

        if bfr_len > 0:
            result = self.read_indices.back() + 1
            if result >= self.max_buffers:
                result = 0
        else:
            result = 0
        niter = 0
        while self.read_indices_set.count(result) != 0:
            result += 1
            if result >= self.max_buffers:
                result = 0
            niter += 1
            if niter > self.max_buffers * 2:
                raise_withgil(PyExc_ValueError, 'could not get write index')
        return result

    cdef bint can_receive(self) nogil except *:
        return self.read_indices.size() < self.max_buffers

    cdef void _check_write_array_size(self) except *:
        cdef cnp.uint8_t[:,:] arr = self.all_frame_data
        cdef size_t ncols = self._get_buffer_size()

        if arr.shape[1] == ncols:
            return
        with self.read_lock:
            self.all_frame_data = np.zeros((self.max_buffers, ncols), dtype=np.uint8)
            self.read_indices.clear()
            self.read_indices_set.clear()
            if self.view_count == 0:
                self.current_frame_data = np.zeros(ncols, dtype=np.uint8)

    cdef void _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except *:
        cdef size_t bfr_idx
        self._check_write_array_size()
        if self.read_indices.size() == self.max_buffers:
            with self.read_lock:
                if self.read_indices.size() == self.max_buffers:
                    bfr_idx = self.read_indices.front()
                    self.read_indices.pop_front()
                    self.read_indices_set.erase(bfr_idx)

    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except *:
        cdef video_bfr_p write_bfr = self.write_bfr
        cdef video_bfr_p read_bfr = self.read_bfr
        cdef NDIlib_video_frame_v2_t* p = self.ptr
        cdef frame_rate_t fr = self.frame_rate
        cdef size_t size_in_bytes = self._get_buffer_size()
        cdef size_t buffer_index = self._get_next_write_index()
        cdef cnp.uint8_t[:,:] all_frame_data = self.all_frame_data
        cdef cnp.uint8_t[:] write_view = all_frame_data[buffer_index]

        with nogil:
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
            write_bfr.total_size = size_in_bytes
            uint8_ptr_to_memview_1d(p.p_data, write_view)
            self.read_bfr.total_size = self.write_bfr.total_size
            self.read_indices.push_back(buffer_index)
            self.read_indices_set.insert(buffer_index)

            write_bfr.valid = True

            if recv_ptr is not NULL:
                NDIlib_recv_free_video_v2(recv_ptr, self.ptr)

cdef class VideoFrameSync(VideoFrame):
    def __cinit__(self, *args, **kwargs):
        self.shape[0] = 0
        self.strides[0] = 0
        self.view_count = 0
        self.fs_ptr = NULL

    def __dealloc__(self):
        self.fs_ptr = NULL

    def get_array(self):
        cdef cnp.ndarray[cnp.uint8_t, ndim=1] arr = np.empty(self.shape, dtype=np.uint8)
        cdef cnp.uint8_t[:] arr_view = arr
        cdef cnp.uint8_t[:] self_view = self
        arr_view[...] = self_view
        return arr

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        cdef NDIlib_video_frame_v2_t* p = self.ptr

        buffer.buf = <char *>p.p_data
        buffer.format = 'B'
        buffer.internal = NULL
        buffer.itemsize = sizeof(uint8_t)
        buffer.len = self.shape[0]
        buffer.ndim = 1
        buffer.obj = self
        buffer.readonly = 1
        buffer.shape = <Py_ssize_t*>self.shape
        buffer.strides = <Py_ssize_t*>self.strides
        buffer.suboffsets = NULL

        self.view_count += 1

    def __releasebuffer__(self, Py_buffer *buffer):
        cdef NDIlib_framesync_instance_t fs_ptr = self.fs_ptr
        self.view_count -= 1
        if self.view_count == 0:
            if fs_ptr is not NULL:
                self.fs_ptr = NULL
                NDIlib_framesync_free_video(fs_ptr, self.ptr)

    cdef void _process_incoming(self, NDIlib_framesync_instance_t fs_ptr) nogil except *:
        if self.view_count > 0:
            raise_withgil(PyExc_ValueError, 'cannot write with view active')

        cdef NDIlib_video_frame_v2_t* p = self.ptr
        cdef size_t size_in_bytes = self._get_buffer_size()
        self.shape[0] = size_in_bytes
        self.strides[0] = sizeof(uint8_t)
        self.fs_ptr = fs_ptr

@cython.boundscheck(False)
@cython.wraparound(False)
cdef void uint8_ptr_to_memview_1d(uint8_t* p, cnp.uint8_t[:] dest) nogil except *:
    cdef size_t ncols = dest.shape[0]
    cdef size_t i

    for i in range(ncols):
        dest[i] = p[i]






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
