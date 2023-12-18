cimport cython
from libc.string cimport memcpy
from cpython.buffer cimport PyObject_GetBuffer, PyBuffer_Release

cimport numpy as cnp
import numpy as np


__all__ = ('AudioFrame', 'AudioRecvFrame', 'AudioFrameSync', 'AudioSendFrame')


cdef class AudioFrame:
    """Base class for audio frames
    """
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

    @property
    def sample_rate(self):
        """The current sample rate
        """
        return self._get_sample_rate()
    @sample_rate.setter
    def sample_rate(self, size_t value):
        self._set_sample_rate(value)

    cdef int _get_sample_rate(self) nogil:
        return self.ptr.sample_rate
    cdef void _set_sample_rate(self, int value) nogil:
        self.ptr.sample_rate = value

    @property
    def num_channels(self):
        """Number of audio channels
        """
        return self._get_num_channels()
    @num_channels.setter
    def num_channels(self, size_t value):
        self._set_num_channels(value)

    cdef int _get_num_channels(self) nogil:
        return self.ptr.no_channels
    cdef void _set_num_channels(self, int value) nogil:
        self.ptr.no_channels = value

    @property
    def num_samples(self):
        """Number of samples available for read or write
        """
        return self._get_num_samples()
    @num_samples.setter
    def num_samples(self, size_t value):
        self._set_num_samples(value)

    cdef int _get_num_samples(self) nogil:
        return self.ptr.no_samples
    cdef void _set_num_samples(self, int value) nogil:
        self.ptr.no_samples = value

    @property
    def timecode(self):
        """The frame's current :term:`ndi-timestamp`
        """
        return self._get_timecode()
    @timecode.setter
    def timecode(self, size_t value):
        self._set_timecode(value)

    cdef int64_t _get_timecode(self) nogil:
        return self.ptr.timecode
    cdef int64_t _set_timecode(self, int64_t value) nogil:
        self.ptr.timecode = value

    @property
    def channel_stride(self):
        """The number of bytes in the data pointer between channels

        Typically calculated as :code:`num_samples * sizeof(float32_t)`
        """
        return self._get_channel_stride()
    @channel_stride.setter
    def channel_stride(self, size_t value):
        self._set_channel_stride(value)

    cdef int _get_channel_stride(self) nogil:
        return self.ptr.channel_stride_in_bytes
    cdef void _set_channel_stride(self, int value) nogil:
        self.ptr.channel_stride_in_bytes = value

    cdef uint8_t* _get_data(self) nogil:
        return self.ptr.p_data
    cdef void _set_data(self, uint8_t* data) nogil:
        self.ptr.p_data = data

    cdef const char* _get_metadata(self) noexcept nogil:
        return self.ptr.p_metadata

    cdef bytes _get_metadata_bytes(self):
        cdef bytes result = self.ptr.p_metadata
        return result

    @property
    def timestamp(self):
        """The per-frame :term:`ndi-timestamp`
        """
        return self._get_timestamp()
    @timestamp.setter
    def timestamp(self, int value):
        self._set_timestamp(value)

    cdef int64_t _get_timestamp(self) nogil:
        return self.ptr.timestamp
    cdef void _set_timestamp(self, int64_t value) nogil:
        self.ptr.timestamp = value


cdef class AudioRecvFrame(AudioFrame):
    """Audio frame to be used with a :class:`.receiver.Receiver`

    Arguments:
        max_buffers (int, optional): The maximum number of items to store
            in the buffer. Defaults to ``8``

    Incoming data from the receiver is placed into temporary buffers so it can
    be read without possibly losing frames. Each buffer will be of shape
    (:attr:`~AudioFrame.num_channels` :attr:`~AudioFrame.num_samples`).

    The buffer items retain both the data frames and their corresponding timestamps.
    They can be read using the methods :meth:`get_read_data`,
    :meth:`get_all_read_data`, :meth:`fill_read_data` and :meth:`fill_all_read_data`.

    .. _frame-buffer-protocol:

    This object also implements the :ref:`buffer protocol <bufferobjects>`
    meaning it can be used anywhere a :class:`memoryview` is expeted. When used
    this way, the view will contain the same information as the :meth:`get_read_data`
    method.

    """
    def __cinit__(self, *args, **kwargs):
        self.audio_bfrs = av_frame_bfr_create(self.audio_bfrs)
        if self.audio_bfrs is NULL:
            raise MemoryError()
        self.read_bfr = av_frame_bfr_create(self.audio_bfrs)
        self.write_bfr = av_frame_bfr_create(self.read_bfr)
        self.current_timecode = 0
        self.current_timestamp = 0

    def __init__(self, size_t max_buffers=8, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.max_buffers = max_buffers
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

    # @property
    # def buffer_depth(self):
    #     """The current number of frames available in the read buffer
    #     """
    #     return self.get_buffer_depth()

    cpdef size_t get_buffer_depth(self):
        """The current number of frames available in the read buffer
        """
        return self.read_indices.size()

    def get_frame_timestamps(self) -> list[int]:
        """Get a list of the :term:`frame timestamps <ndi-timestamp>` in the
        read buffer
        """
        cdef int64_t ts
        cdef list l = [ts for ts in self.frame_timestamps]
        return l

    @property
    def read_length(self) -> int:
        """The total number of samples in the read buffer
        (not multiplied by :attr:`num_channels`)
        """
        return self.get_read_length()

    cpdef size_t get_read_length(self):
        cdef size_t bfr_len = self.read_indices.size()
        return bfr_len * self.all_frame_data.shape[2]

    cpdef (size_t, size_t) get_read_shape(self):
        """Get the read array shape as ``(num_channels, num_samples)``
        """
        cdef cnp.float32_t[:,:,:] arr = self.all_frame_data
        return arr.shape[1], arr.shape[2]

    cpdef get_all_read_data(self):
        """Get all available data in the read buffer as a 2-d array

        The shape of the result will be (:attr:`~AudioFrame.num_channels`, :attr:`read_length`)
        """
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
    ) noexcept nogil:
        """Copy all available read data into the given *result* array limited by
        *bfr_len*.

        Also copies the timestamps for each buffered item into the *timestamps*
        array

        Returns a tuple of

        * ``nbfrs``: The number of buffer items filled
        * ``col_idx``: The index of the last column (last axis) filled on the result

        """
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
        """Get the first available item in the read buffer

        Returns a tuple of

        * ``frame_data``: A 2-d array of float32 with shape of :meth:`get_read_shape`
        * ``timestamp``: The :term:`timestamp <ndi-timestamp>` of the data
        """
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
        """Copy the first available read item in the buffer into the given array

        The array must equal that of :meth:`get_read_shape`

        Returns the :term:`timestamp <ndi-timestamp>` of the data
        """
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
        """Copy all available read data into the given *dest* array and the
        item :term:`timestamps <ndi-timestamp>` into the given *timestamps* array.

        The shape of the *dest* array on the first axis should equal
        :attr:`num_channels` and the second should be at least :attr:`read_length`.

        The *timestamps* array should be of at least :attr:`read_length` size

        Returns a tuple of

        * ``nbfrs``: The number of buffer items filled
        * ``col_idx``: The index of the last column (last axis) filled on the result

        """
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
    cdef bint _check_read_array_size(self) except -1:
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
    ) except? -1 nogil:
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

    cdef size_t _get_next_write_index(self) except? -1 nogil:
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

    cdef bint can_receive(self) except -1 nogil:
        return self.read_indices.size() < self.max_buffers

    cdef int _check_write_array_size(self) except -1:
        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef cnp.float32_t[:,:,:] arr = self.all_frame_data
        cdef size_t nrows = self.ptr.no_channels, ncols = self.ptr.no_samples

        if arr.shape[1] == nrows and arr.shape[2] == ncols:
            return 0

        with self.read_lock:
            self.all_frame_data = np.zeros((self.max_buffers, nrows, ncols), dtype=np.float32)
            self.read_indices.clear()
            self.read_indices_set.clear()
            self.frame_timestamps.clear()
            if self.view_count == 0:
                self.current_frame_data = np.zeros((nrows, ncols), dtype=np.float32)
        return 0

    cdef int _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except -1:
        cdef size_t bfr_idx
        self._check_write_array_size()
        if self.read_indices.size() == self.max_buffers:
            with self.read_lock:
                if self.read_indices.size() == self.max_buffers:
                    bfr_idx = self.read_indices.front()
                    self.read_indices.pop_front()
                    self.read_indices_set.erase(bfr_idx)
                    self.frame_timestamps.pop_front()
        return 0

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef int _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except -1:
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
        return 0


cdef class AudioFrameSync(AudioFrame):
    """Audio frame for use with :class:`.framesync.FrameSync`

    Unlike :class:`AudioRecvFrame`, this object does not store or buffer any
    data. It will always contain the most recent audio data after a call to
    :meth:`.framesync.FrameSync.capture_audio` or
    :meth:`.framesync.FrameSync.capture_available_audio`.

    This is by design since the FrameSync methods utilize buffering from within
    the |NDI| library.

    Data can be read using the :meth:`get_array` method or by using the
    :ref:`buffer protocol <frame-buffer-protocol>`.
    """
    def __cinit__(self, *args, **kwargs):
        for i in range(2):
            self.shape[i] = 0
            self.strides[i] = 0
        self.view_count = 0

    def __dealloc__(self):
        self.fs_ptr = NULL

    def get_array(self):
        """Get the current data as a :class:`ndarray` of float32 with shape
        (:attr:`~AudioFrame.num_channels`, :attr:`~AudioFrame.num_samples`)
        """
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

    cdef int _process_incoming(self, NDIlib_framesync_instance_t fs_ptr) except -1 nogil:
        if self.view_count > 0:
            raise_withgil(PyExc_ValueError, 'cannot write with view active')

        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef size_t nrows = p.no_channels, ncols = p.no_samples
        self.shape[0] = nrows
        self.shape[1] = ncols
        self.strides[0] = ncols * sizeof(cnp.float32_t)
        self.strides[1] = sizeof(cnp.float32_t)
        self.fs_ptr = fs_ptr
        return 0



cdef class AudioSendFrame(AudioFrame):
    """Audio frame for use with :class:`.sender.Sender`

    .. note::

        Instances of this class are not intended to be created directly nor are
        its methods. They are instead called from the :class:`sender.Sender`
        write methods.

    Attributes:
        max_num_samples (int, readonly): The maximum :attr:`~AudioFrame.num_samples`
            to be used.

    """
    def __cinit__(self, *args, **kwargs):
        self.max_num_samples = 1602
        frame_status_init(&(self.send_status))
        self.send_status.ndim = 2
        self.send_status.strides[0] = 0
        self.send_status.strides[1] = sizeof(float32_t)
        self.buffer_write_item = NULL

    def __init__(self, size_t max_num_samples=1602, *args, **kwargs):
        self.max_num_samples = max_num_samples
        self.ptr.no_samples = max_num_samples
        super().__init__(*args, **kwargs)

    def __dealloc__(self):
        self.buffer_write_item = NULL
        frame_status_free(&(self.send_status))

    @property
    def attached_to_sender(self):
        return self.send_status.attached_to_sender

    @property
    def write_index(self):
        return self.send_status.write_index

    @property
    def read_index(self):
        return self.send_status.read_index

    @property
    def shape(self):
        cdef AudioSendFrame_status_s* ptr = &(self.send_status)
        cdef list l = ptr.shape
        return tuple(l[:ptr.ndim])

    @property
    def strides(self):
        cdef AudioSendFrame_status_s* ptr = &(self.send_status)
        cdef list l = ptr.strides
        return tuple(l[:ptr.ndim])

    @property
    def ndim(self):
        return self.send_status.ndim

    cpdef set_max_num_samples(self, size_t n):
        assert not self.attached_to_sender
        self.max_num_samples = n
        self.ptr.no_samples = n

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        cdef AudioSendFrame_item_s* item = self.buffer_write_item
        cdef AudioSendFrame_status_s* s_ptr = &(self.send_status)
        if item is NULL:
            item = self._prepare_buffer_write()
        assert item is not NULL
        item.view_count += 1
        buffer.buf = <char *>item.frame_ptr.p_data
        buffer.format = 'f'
        buffer.itemsize = sizeof(float32_t)
        buffer.len = sizeof(float32_t) * s_ptr.shape[0] * s_ptr.shape[1]
        buffer.ndim = self.send_status.ndim
        buffer.obj = self
        buffer.readonly = 0
        buffer.shape = s_ptr.shape
        buffer.strides = s_ptr.strides
        buffer.suboffsets = NULL
        buffer.internal = <void*>item

    def __releasebuffer__(self, Py_buffer *buffer):
        cdef AudioSendFrame_item_s* item
        if buffer.internal is not NULL:
            item = <AudioSendFrame_item_s*>buffer.internal
            assert item.view_count > 0
            item.view_count -= 1

    def destroy(self):
        self._destroy()

    cdef int _destroy(self) except -1:
        self.buffer_write_item = NULL
        frame_status_free(&(self.send_status))
        return 0

    def get_write_available(self):
        return self._write_available()

    cdef bint _write_available(self) except -1 nogil:
        cdef Py_ssize_t idx = frame_status_get_next_write_index(&(self.send_status))
        return idx != NULL_INDEX

    cdef int _set_shape_from_memview(
        self,
        AudioSendFrame_item_s* item,
        cnp.float32_t[:,:] data,
    ) except -1 nogil:
        return 0

    cdef AudioSendFrame_item_s* _prepare_buffer_write(self) except * nogil:
        if self.buffer_write_item is not NULL:
            raise_withgil(PyExc_RuntimeError, 'buffer_write_item is not null')
        cdef AudioSendFrame_item_s* item = self._get_next_write_frame()
        if item.view_count != 0:
            raise_withgil(PyExc_RuntimeError, 'buffer item view count nonzero')
        self.buffer_write_item = item
        return item

    cdef int _set_buffer_write_complete(self, AudioSendFrame_item_s* item) except -1 nogil:
        cdef AudioSendFrame_item_s* cur_item = self.buffer_write_item
        if cur_item is not NULL and cur_item.idx == item.idx:
            self.buffer_write_item = NULL
        self.send_status.read_index = item.idx
        frame_status_set_send_ready(&(self.send_status))
        return 0

    def write_data(self, cnp.float32_t[:,:] data):
        cdef AudioSendFrame_item_s* item = self._prepare_memview_write()
        cdef cnp.float32_t[:,:] view = self

        self._write_data_to_memview(data, view, item)

    cdef AudioSendFrame_item_s* _prepare_memview_write(self) except * nogil:
        return self._prepare_buffer_write()

    cdef int _write_data_to_memview(
        self,
        cnp.float32_t[:,:] data,
        cnp.float32_t[:,:] view,
        AudioSendFrame_item_s* item
    ) except -1 nogil:
        self._set_shape_from_memview(item, data)
        cdef size_t nrows = item.shape[0], ncols = item.shape[1]
        view[...] = data
        self._set_buffer_write_complete(item)
        return 0

    cdef AudioSendFrame_item_s* _get_next_write_frame(self) except * nogil:
        cdef Py_ssize_t idx = frame_status_get_next_write_index(&(self.send_status))
        if idx == NULL_INDEX:
            raise_withgil(PyExc_RuntimeError, 'no write frame available')
        self.send_status.write_index = idx
        return &(self.send_status.items[idx])

    cdef bint _send_frame_available(self) except -1 nogil:
        return self._get_send_frame() != NULL

    cdef AudioSendFrame_item_s* _get_send_frame(self) except * nogil:
        cdef Py_ssize_t idx = frame_status_get_next_read_index(&(self.send_status))
        if idx == NULL_INDEX:
            return NULL
        return &(self.send_status.items[idx])

    cdef int _on_sender_write(self, AudioSendFrame_item_s* s_ptr) except -1 nogil:
        frame_status_set_send_complete(&(self.send_status), s_ptr.idx)
        return 0

    cdef int _set_sender_status(self, bint attached) except -1 nogil:
        if attached:
            self._rebuild_array()
        self.send_status.attached_to_sender = attached
        return 0

    cdef int _rebuild_array(self) except -1 nogil:
        cdef size_t nrows = self.ptr.no_channels, ncols = self.max_num_samples
        cdef size_t total_size = sizeof(float32_t) * nrows * ncols
        cdef AudioSendFrame_status_s* s_ptr = &(self.send_status)
        s_ptr.shape[0] = nrows
        s_ptr.shape[1] = ncols
        s_ptr.strides[0] = sizeof(float32_t) * ncols
        s_ptr.strides[1] = sizeof(float32_t)
        self.ptr.no_channels = nrows
        self.ptr.no_samples = ncols
        self.ptr.channel_stride_in_bytes = s_ptr.strides[0]
        frame_status_copy_frame_ptr(s_ptr, self.ptr)
        frame_status_alloc_p_data(s_ptr)
        return 0



@cython.boundscheck(False)
@cython.wraparound(False)
cdef int float_ptr_to_memview_2d(float32_t* p, cnp.float32_t[:,:] dest) except -1 nogil:
    cdef size_t ncols = dest.shape[1], nrows = dest.shape[0]
    # cdef float *float_p = <float*>bfr.p_data
    cdef size_t i, j, k = 0

    for i in range(nrows):
        for j in range(ncols):
            dest[i,j] = p[k]
            k += 1
    return 0



cdef int audio_bfr_unpack_data(audio_bfr_p bfr, uint8_t* p_data) except -1 nogil:
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
    return 0
