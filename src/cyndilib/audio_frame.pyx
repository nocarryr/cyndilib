cimport cython
from libc.string cimport memcpy
from cpython.buffer cimport PyObject_GetBuffer, PyBuffer_Release

cimport numpy as cnp
import numpy as np


cdef class AudioFrame:

    def __cinit__(self, *args, **kwargs):
        self.ptr = audio_frame_create_default()
        if self.ptr is NULL:
            raise MemoryError()

    def __init__(self, *args, **kwargs):
        pass

    def __dealloc__(self):
        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        self.ptr = NULL
        if p is not NULL:
            audio_frame_destroy(p)

    def get_sample_rate(self):
        return self._get_sample_rate()
    def set_sample_rate(self, size_t value):
        self._set_sample_rate(value)

    cdef int _get_sample_rate(self) nogil:
        return self.ptr.sample_rate
    cdef void _set_sample_rate(self, int value) nogil:
        self.ptr.sample_rate = value

    def get_num_channels(self):
        return self._get_num_channels()
    def set_num_channels(self, size_t value):
        self._set_num_channels(value)

    cdef int _get_num_channels(self) nogil:
        return self.ptr.no_channels
    cdef void _set_num_channels(self, int value) nogil:
        self.ptr.no_channels = value

    cdef int _get_num_samples(self) nogil:
        return self.ptr.no_samples
    cdef void _set_num_samples(self, int value) nogil:
        self.ptr.no_samples = value

    cdef int64_t _get_timecode(self) nogil:
        return self.ptr.timecode
    cdef int64_t _set_timecode(self, int64_t value) nogil:
        self.ptr.timecode = value

    cdef int _get_channel_stride(self) nogil:
        return self.ptr.channel_stride_in_bytes
    cdef void _set_channel_stride(self, int value) nogil:
        self.ptr.channel_stride_in_bytes = value

    cdef uint8_t* _get_data(self) nogil:
        return self.ptr.p_data
    cdef void _set_data(self, uint8_t* data) nogil:
        self.ptr.p_data = data

    cdef const char* _get_metadata(self) nogil except *:
        return self.ptr.p_metadata

    cdef bytes _get_metadata_bytes(self):
        cdef bytes result = self.ptr.p_metadata
        return result

    def get_timestamp(self):
        return self._get_timestamp()
    cdef int64_t _get_timestamp(self) nogil:
        return self.ptr.timestamp
    cdef void _set_timestamp(self, int64_t value) nogil:
        self.ptr.timestamp = value


cdef class AudioRecvFrame(AudioFrame):
    def __cinit__(self, *args, **kwargs):
        self.max_buffers = kwargs.get('max_buffers', 8)
        self.audio_bfrs = av_frame_bfr_create(self.audio_bfrs)
        if self.audio_bfrs is NULL:
            raise MemoryError()
        self.read_bfr = av_frame_bfr_create(self.audio_bfrs)
        self.write_bfr = av_frame_bfr_create(self.read_bfr)
        self.current_timecode = 0
        self.current_timestamp = 0

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.read_lock = RLock()
        self.write_lock = RLock()
        self.read_ready = Condition(self.read_lock)
        self.write_ready = Condition(self.write_lock)
        self.all_frame_data = np.zeros((self.max_buffers, 2, 0), dtype=np.float32)
        self.current_frame_data = np.zeros((2,0), dtype=np.float32)
        self.view_count = 0

    def __dealloc__(self):
        self.read_bfr = NULL
        self.write_bfr = NULL
        cdef audio_bfr_p bfr = self.audio_bfrs
        if self.audio_bfrs is not NULL:
            self.audio_bfrs = NULL
            av_frame_bfr_destroy(bfr)

    cpdef size_t get_buffer_depth(self):
        return self.read_indices.size()

    def get_frame_timestamps(self):
        cdef int64_t ts
        cdef list l = [ts for ts in self.frame_timestamps]
        return l

    cpdef size_t get_read_length(self):
        cdef size_t bfr_len = self.read_indices.size()
        return bfr_len * self.all_frame_data.shape[2]

    cpdef (size_t, size_t) get_read_shape(self):
        cdef cnp.float32_t[:,:,:] arr = self.all_frame_data
        return arr.shape[1], arr.shape[2]

    cpdef get_all_read_data(self):
        cdef size_t bfr_len
        cdef cnp.ndarray[cnp.float32_t, ndim=2] result
        cdef cnp.ndarray[cnp.int64_t, ndim=1] timestamps
        cdef cnp.float32_t[:,:] result_view
        cdef cnp.int64_t[:] timestamp_view
        cdef cnp.float32_t[:,:,:] all_frame_data
        with self.read_lock:
            bfr_len = self.read_indices.size()
            if not bfr_len:
                return None
            all_frame_data = self.all_frame_data

        cdef size_t nrows = all_frame_data.shape[1]
        cdef size_t ncols = all_frame_data.shape[2] * bfr_len
        result = np.empty((nrows, ncols), dtype=np.float32)
        timestamps = np.empty(self.max_buffers, dtype=np.int64)
        result_view = result
        timestamp_view = timestamps
        cdef size_t nbfrs_filled, ncols_filled

        with nogil:
            nbfrs_filled, ncols_filled = self._fill_all_read_data(
                all_frame_data, result_view, timestamp_view, bfr_len,
            )

        if ncols_filled != ncols:
            result = result[:,:ncols_filled]
        if nbfrs_filled != bfr_len:
            timestamps = timestamps[:nbfrs_filled]
        cdef tuple r = (result, timestamps)
        return r

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef (size_t, size_t) _fill_all_read_data(
        self,
        cnp.float32_t[:,:,:] all_frame_data,
        cnp.float32_t[:,:] result,
        cnp.int64_t[:] timestamps,
        size_t bfr_len,
    ) nogil except *:
        cdef size_t nbfr_cols = all_frame_data.shape[2]
        cdef size_t col_idx=0, nbfrs=0, bfr_idx, i

        for i in range(bfr_len):
            if not self.read_indices.size():
                break
            nbfrs += 1
            bfr_idx = self.read_indices.front()
            self.read_indices.pop_front()
            self.read_indices_set.erase(bfr_idx)

            timestamps[i] = self.frame_timestamps.front()
            self.frame_timestamps.pop_front()
            result[:, col_idx:col_idx+nbfr_cols] = all_frame_data[bfr_idx,:,:]
            col_idx += nbfr_cols
        return nbfrs, col_idx

    cpdef get_read_data(self):
        cdef cnp.float32_t[:,:,:] all_frame_data = self.all_frame_data
        cdef bint advance = False
        cdef size_t bfr_idx, bfr_len = self.read_indices.size()
        cdef cnp.float32_t[:,:] arr = self.current_frame_data
        cdef int64_t timestamp
        if not bfr_len:
            return None

        with self.read_lock:
            bfr_idx = self.read_indices.front()
            if self.view_count == 0:
                if self._check_read_array_size():
                    arr = self.current_frame_data
                advance = True

        with nogil:
            timestamp = self._fill_read_data(
                all_frame_data, arr, bfr_idx, advance=advance
            )
        return self.current_frame_data, timestamp

    def fill_read_data(self, cnp.float32_t[:,:] dest):
        if not self.read_indices.size():
            raise IndexError('No data')
        cdef cnp.float32_t[:,:,:] all_frame_data = self.all_frame_data
        cdef size_t ncols, nrows, bfr_idx
        cdef int64_t timestamp
        cdef bint advance = True
        with self.read_lock:
            ncols, nrows = self.get_read_shape()
            bfr_idx = self.read_indices.front()

        if dest.shape[0] != ncols or dest.shape[1] != nrows:
            raise IndexError('Array shape does not match')

        with nogil:
            timestamp = self._fill_read_data(all_frame_data, dest, bfr_idx, advance=True)
        return timestamp

    def fill_all_read_data(self, cnp.float32_t[:,:] dest, cnp.int64_t[:] timestamps):
        cdef cnp.float32_t[:,:,:] all_frame_data = self.all_frame_data
        cdef size_t bfr_len, nbfrs_filled, col_idx
        with self.read_lock:
            bfr_len = self.read_indices.size()

        with nogil:
            nbfrs_filled, col_idx = self._fill_all_read_data(
                all_frame_data, dest, timestamps, bfr_len,
            )
        return nbfrs_filled, col_idx

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef bint _check_read_array_size(self) except *:
        cdef cnp.float32_t[:,:,:] all_frame_data = self.all_frame_data
        cdef cnp.float32_t[:,:] read_data = self.current_frame_data
        cdef size_t nrows = all_frame_data.shape[1]
        cdef size_t ncols = all_frame_data.shape[2]
        if read_data.shape[0] != nrows or read_data.shape[1] != ncols:
            with self.read_lock:
                self.current_frame_data = np.zeros((nrows, ncols), dtype=np.float32)
                return True
        return False

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef int64_t _fill_read_data(
        self,
        cnp.float32_t[:,:,:] all_frame_data,
        cnp.float32_t[:,:] dest,
        size_t bfr_idx,
        bint advance
    ) nogil except *:
        cdef int64_t ts
        ts = self.frame_timestamps.front()
        if advance:
            self.read_indices.pop_front()
            self.frame_timestamps.pop_front()
            self.read_indices_set.erase(bfr_idx)

            dest[...] = all_frame_data[bfr_idx,...]
        return ts

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        cdef cnp.float32_t[:,:,:] all_frame_data = self.all_frame_data
        cdef size_t bfr_len, bfr_idx
        cdef bint is_empty
        cdef cnp.ndarray[cnp.float32_t, ndim=2] frame_data = self.current_frame_data
        with self.read_lock:
            bfr_len = self.read_indices.size()
            is_empty = bfr_len == 0
            if not is_empty:
                if self.view_count == 0:
                    if self._check_read_array_size():
                        frame_data = self.current_frame_data
                    if frame_data.shape[2] == 0:
                        is_empty = True
                    else:
                        bfr_idx = self.read_indices.front()
                        self._fill_read_data(all_frame_data, frame_data, bfr_idx, advance=False)
            if is_empty:
                raise ValueError('Buffer empty')
            self.view_count += 1

        cdef size_t i, arr_size, ndim = frame_data.ndim
        arr_size =  frame_data.shape[0] * frame_data.shape[1]
        for i in range(ndim):
            if is_empty:
                self.empty_bfr_shape[i] = frame_data.shape[i]
            else:
                self.bfr_shape[i] = frame_data.shape[i]
            self.bfr_strides[i] = frame_data.strides[i]

        buffer.buf = <char *>frame_data.data
        buffer.format = 'f'
        buffer.internal = NULL
        buffer.itemsize = sizeof(cnp.float32_t)
        buffer.len = arr_size * sizeof(cnp.float32_t)
        buffer.ndim = ndim
        buffer.obj = self
        buffer.readonly = 1
        if is_empty:
            buffer.shape = self.empty_bfr_shape
        else:
            buffer.shape = self.bfr_shape
        buffer.strides = self.bfr_strides
        buffer.suboffsets = NULL

    def __releasebuffer__(self, Py_buffer *buffer):
        with self.read_lock:
            self.view_count -= 1

    cdef size_t _get_next_write_index(self) nogil except *:
        cdef size_t result, niter, bfr_len = self.read_indices.size()

        if bfr_len > 0:
            result = self.read_indices.back() + 1
            if result >= self.max_buffers:
                result = 0
        else:
            result = 0

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
        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef cnp.float32_t[:,:,:] arr = self.all_frame_data
        cdef size_t nrows = self.ptr.no_channels, ncols = self.ptr.no_samples

        if arr.shape[1] == nrows and arr.shape[2] == ncols:
            return

        with self.read_lock:
            self.all_frame_data = np.zeros((self.max_buffers, nrows, ncols), dtype=np.float32)
            self.read_indices.clear()
            self.read_indices_set.clear()
            self.frame_timestamps.clear()
            if self.view_count == 0:
                self.current_frame_data = np.zeros((nrows, ncols), dtype=np.float32)

    cdef void _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except *:
        cdef size_t bfr_idx
        self._check_write_array_size()
        if self.read_indices.size() == self.max_buffers:
            with self.read_lock:
                if self.read_indices.size() == self.max_buffers:
                    bfr_idx = self.read_indices.front()
                    self.read_indices.pop_front()
                    self.read_indices_set.erase(bfr_idx)
                    self.frame_timestamps.pop_front()

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except *:
        cdef audio_bfr_p write_bfr = self.write_bfr
        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef size_t buffer_index = self._get_next_write_index()
        cdef cnp.float32_t[:,:,:] all_frame_data = self.all_frame_data
        cdef cnp.float32_t[:,:] write_view = all_frame_data[buffer_index]

        with nogil:
            write_bfr.sample_rate = p.sample_rate
            write_bfr.num_channels = p.no_channels
            write_bfr.num_samples = p.no_samples
            write_bfr.timecode = p.timecode
            write_bfr.timestamp = p.timestamp
            write_bfr.total_size = p.no_channels * p.channel_stride_in_bytes
            write_bfr.p_data = <float*>p.p_data
            write_bfr.valid = True
            float_ptr_to_memview_2d(<float*>p.p_data, write_view)

            self.current_timestamp = p.timestamp
            self.current_timecode = p.timecode
            self.read_bfr.total_size = write_bfr.total_size

            self.read_indices.push_back(buffer_index)
            self.read_indices_set.insert(buffer_index)
            self.frame_timestamps.push_back(p.timestamp)

            if recv_ptr is not NULL:
                NDIlib_recv_free_audio_v3(recv_ptr, self.ptr)


cdef class AudioFrameSync(AudioFrame):

    def __cinit__(self, *args, **kwargs):
        for i in range(2):
            self.shape[i] = 0
            self.strides[i] = 0
        self.view_count = 0

    def __dealloc__(self):
        self.fs_ptr = NULL

    def get_array(self):
        cdef cnp.ndarray[cnp.float32_t, ndim=2] arr = np.empty(self.shape, dtype=np.float32)
        cdef cnp.float32_t[:,:] arr_view = arr
        cdef cnp.float32_t[:,:] self_view = self
        arr_view[...] = self_view
        return arr

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef size_t nitems = self.shape[0] * self.shape[1]

        buffer.buf = <char *>p.p_data
        buffer.format = 'f'
        buffer.internal = NULL
        buffer.itemsize = sizeof(cnp.float32_t)
        buffer.len = nitems * sizeof(cnp.float32_t)
        buffer.ndim = 2
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
                NDIlib_framesync_free_audio_v2(fs_ptr, self.ptr)

    cdef void _process_incoming(self, NDIlib_framesync_instance_t fs_ptr) nogil except *:
        if self.view_count > 0:
            raise_withgil(PyExc_ValueError, 'cannot write with view active')

        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef size_t nrows = p.no_channels, ncols = p.no_samples
        self.shape[0] = nrows
        self.shape[1] = ncols
        self.strides[0] = ncols * sizeof(cnp.float32_t)
        self.strides[1] = sizeof(cnp.float32_t)
        self.fs_ptr = fs_ptr



cdef class AudioSendFrame(AudioFrame):
    def __cinit__(self, *args, **kwargs):
        self.send_status.id = NULL_ID
        self.send_status.next_send_id = NULL_ID
        self.send_status.last_send_id = NULL_ID
        self.send_status.write_available = True
        self.send_status.send_ready = False
        self.send_status.attached_to_sender = False
        self.send_status.next = NULL
        self.send_status.prev = NULL
        self.send_status.frame_ptr = &(self.ptr)
        self.max_num_samples = 1602
        self.max_shape[0] = 2
        self.max_shape[1] = 0
        self.shape[0] = self.send_status.shape[0] = 2
        self.shape[1] = self.send_status.shape[0] = 0
        self.strides[0] = self.send_status.strides[0] = 0
        self.strides[1] = self.send_status.strides[1] = sizeof(float32_t)

    def __init__(self, AudioSendFrame parent_frame=None, *args, **kwargs):
        cdef void* self_ptr = <void*>self
        self.send_status.id = <Py_intptr_t>self_ptr
        self.parent_frame = parent_frame
        self.has_parent = parent_frame is not None
        if self.has_parent:
            self.max_num_samples = parent_frame.max_num_samples
            self.send_status.prev = &(parent_frame.send_status)
            audio_frame_copy(parent_frame.ptr, self.ptr)
        super().__init__(*args, **kwargs)
        self.view = None
        self.child_count = 0
        self.child_frame = None
        self.has_child = False

    def __dealloc__(self):
        self.send_status.prev = NULL
        self.send_status.next = NULL
        self.send_status.frame_ptr = NULL
        self.child_frame = None
        self.parent_frame = None

    @property
    def id(self):
        return self.send_status.id

    @property
    def write_available(self):
        return self.send_status.write_available
    @write_available.setter
    def write_available(self, bint value):
        self.send_status.write_available = value

    @property
    def attached_to_sender(self):
        return self.send_status.attached_to_sender

    cpdef set_max_num_samples(self, size_t n):
        assert not self.attached_to_sender
        self.max_num_samples = n

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        cdef AudioSendFrame_status* send_status = self._get_next_write_frame()
        if send_status is NULL:
            raise_exception('no send pointer')
        cdef NDIlib_audio_frame_v3_t* ptr = send_status.frame_ptr[0]
        cdef PyObject* obj_ptr = <PyObject*>send_status.id
        buffer.buf = ptr.p_data
        buffer.format = 'f'
        buffer.internal = NULL
        buffer.itemsize = sizeof(float32_t)
        buffer.len = self.shape[0] * self.shape[1] * sizeof(float32_t)
        buffer.ndim = 2
        buffer.obj = <object>obj_ptr
        buffer.readonly = 0
        buffer.shape = self.shape
        buffer.strides = self.strides
        buffer.suboffsets = NULL

    def __releasebuffer__(self, Py_buffer *buffer):
        pass

    def destroy(self):
        self._destroy()

    cdef void _destroy(self) except *:
        self.send_status.next = NULL
        self.send_status.prev = NULL
        if self.has_child:
            self.child_frame.has_parent = False
            self.child_frame._destroy()
            self.has_child = False
            self.child_frame = None
        if self.has_parent:
            self.parent_frame.has_child = False
            self.parent_frame._destroy()
            self.has_parent = False
            self.parent_frame = None
        self.child_count = 0

    def get_write_available(self):
        return self._write_available()

    cdef bint _write_available(self) nogil except *:
        return self.send_status.next_send_id == NULL_ID

    cdef void _set_shape_from_memview(
        self,
        AudioSendFrame_status* send_status,
        cnp.float32_t[:,:] data,
    ) nogil except *:
        cdef NDIlib_audio_frame_v3_t* ptr = send_status.frame_ptr[0]
        cdef size_t nrows = data.shape[0], ncols = data.shape[1]
        ptr.no_channels = send_status.shape[0] = nrows
        ptr.no_samples = send_status.shape[1] = ncols
        ptr.channel_stride_in_bytes = nrows * send_status.strides[1]

    def __enter__(self):
        cdef AudioSendFrame obj = self._prepare_buffer_write()
        return obj

    def __exit__(self, exc_type, exc, tb):
        if exc_type is None:
            self._set_buffer_write_complete(&(self.send_status))

    cdef AudioSendFrame _prepare_buffer_write(self):
        cdef AudioSendFrame_status* send_status = self._get_next_write_frame()
        cdef PyObject* obj_ptr = <PyObject*>send_status.id
        cdef AudioSendFrame obj = <object>obj_ptr
        return obj

    cdef void _set_buffer_write_complete(self, AudioSendFrame_status* send_status) nogil except *:
        frame_status_set_send_id(send_status, send_status.id)

    cdef AudioSendFrame _prepare_memview_write(self):
        cdef AudioSendFrame obj = self._prepare_buffer_write()
        obj.view.data = <char *>obj.ptr.p_data
        return obj

    cdef void _write_data_to_memview(
        self,
        cnp.float32_t[:,:] data,
        cnp.float32_t[:,:] view,
        AudioSendFrame_status* send_status
    ) nogil except *:
        self._set_shape_from_memview(send_status, data)
        cdef size_t nrows = send_status.shape[0], ncols = send_status.shape[1]
        view[:nrows, :ncols] = data
        self.view.data = NULL
        self._set_buffer_write_complete(send_status)

    cdef AudioSendFrame_status* _get_next_write_frame(self) nogil except *:
        return frame_status_get_writer(&(self.send_status))

    cdef bint _send_frame_available(self) nogil except *:
        return self.send_status.next_send_id != NULL_ID

    cdef AudioSendFrame_status* _get_send_frame(self) nogil except *:
        cdef AudioSendFrame_status* r = frame_status_get_sender(&(self.send_status))
        return r

    cdef void _on_sender_write(self, AudioSendFrame_status* s_ptr) nogil except *:
        frame_status_clear_write(s_ptr, s_ptr.id)

    cdef void _set_sender_status(self, bint attached) except *:
        if attached:
            self._rebuild_array()
        self.send_status.attached_to_sender = attached
        if self.has_child:
            self.child_frame._set_sender_status(attached)

    cdef void _create_child_frames(self, size_t count) except *:
        if count > 0:
            self._create_child_frame()
            self.child_frame._create_child_frames(count - 1)

    cdef void _create_child_frame(self) except *:
        assert not self.has_child
        self.child_frame = AudioSendFrame(self)
        self.send_status.next = &(self.child_frame.send_status)
        self._on_child_created()

    cdef void _on_child_created(self) nogil except *:
        self.child_count += 1
        self.has_child = True
        if self.has_parent:
            self.parent_frame._on_child_created()

    cdef void _rebuild_array(self) except *:
        assert not self.attached_to_sender
        cdef size_t nrows = self.ptr.no_channels, ncols = self.max_num_samples
        if self.max_shape[0] == nrows and self.max_shape[1] == ncols:
            return
        cdef size_t total_size = sizeof(float32_t) * nrows * ncols
        cdef uint8_t* p_data = self.ptr.p_data
        if p_data is not NULL:
            self.ptr.p_data = NULL
            mem_free(p_data)
            p_data = NULL
        self.ptr.p_data = <uint8_t*>mem_alloc(total_size)
        if self.ptr.p_data is NULL:
            raise_mem_err()
        self.max_shape[0] = nrows
        self.max_shape[1] = ncols
        self.shape[0] = self.send_status.shape[0] = nrows
        self.shape[1] = self.send_status.shape[1] = ncols
        self.strides[0] = self.send_status.strides[0] = sizeof(float32_t) * ncols
        self.strides[1] = self.send_status.strides[1] = sizeof(float32_t)
        self.view = view.array(
            shape=(nrows,ncols),
            itemsize=sizeof(float32_t),
            format='f',
            allocate_buffer=False,
        )



@cython.boundscheck(False)
@cython.wraparound(False)
cdef void float_ptr_to_memview_2d(float32_t* p, cnp.float32_t[:,:] dest) nogil except *:
    cdef size_t ncols = dest.shape[1], nrows = dest.shape[0]
    # cdef float *float_p = <float*>bfr.p_data
    cdef size_t i, j, k = 0

    for i in range(nrows):
        for j in range(ncols):
            dest[i,j] = p[k]
            k += 1



cdef void audio_bfr_unpack_data(audio_bfr_p bfr, uint8_t* p_data) nogil except *:
    if bfr.p_data is not NULL:
        raise_withgil(PyExc_ValueError, 'float buffer exists')
    cdef size_t size_in_samples = bfr.num_channels * bfr.num_samples
    cdef size_t size_in_bytes = bfr.num_channels * bfr.num_samples * sizeof(float)
    bfr.p_data = <float*>mem_alloc(size_in_bytes)
    if bfr.p_data is NULL:
        raise_mem_err()
    memcpy(<void*>bfr.p_data, <void*>p_data, size_in_bytes)
    # g = (float)((data[0] << 24) | (data[1] << 16) | (data[2] << 8) | (data[3]) );
    # size_t ch_idx, samp_idx
    # for ch_idx in range(bfr.num_channels):
