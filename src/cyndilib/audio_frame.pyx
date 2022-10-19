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

    cdef int _get_sample_rate(self) nogil:
        return self.ptr.sample_rate
    cdef void _set_sample_rate(self, int value) nogil:
        self.ptr.sample_rate = value

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

    cdef int64_t _get_timestamp(self) nogil:
        return self.ptr.timestamp
    cdef void _set_timestamp(self, int64_t value) nogil:
        self.ptr.timestamp = value


cdef class AudioRecvFrame(AudioFrame):
    def __cinit__(self, *args, **kwargs):
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
        self.current_frame_data = np.zeros((2,0), dtype=np.float32)
        self.next_frame_data = np.zeros((2,0), dtype=np.float32)
        self.view_count = 0

    def __dealloc__(self):
        self.read_bfr = NULL
        self.write_bfr = NULL
        cdef audio_bfr_p bfr = self.audio_bfrs
        if self.audio_bfrs is not NULL:
            self.audio_bfrs = NULL
            av_frame_bfr_destroy(bfr)

    def __getbuffer__(self, Py_buffer *buffer, int flags):
        # PyObject_GetBuffer(self.current_frame_data, buffer, flags)
        # self.view_count += 1
        cdef cnp.ndarray[cnp.float32_t, ndim=2] frame_data = self.current_frame_data
        cdef size_t i, ndim = frame_data.ndim
        for i in range(ndim):
            self.bfr_shape[i] = frame_data.shape[i]
            self.bfr_strides[i] = frame_data.strides[i]

        # self.bfr_strides[0] = self.ptr.channel_stride_in_bytes
        buffer.buf = <char *>frame_data.data
        buffer.format = 'f'
        buffer.internal = NULL
        buffer.itemsize = sizeof(cnp.float32_t)
        buffer.len = self.bfr_shape[0] * self.bfr_shape[1] * sizeof(cnp.float32_t)
        buffer.ndim = ndim
        buffer.obj = self
        buffer.readonly = 1
        buffer.shape = self.bfr_shape
        buffer.strides = self.bfr_strides
        buffer.suboffsets = NULL
        self.view_count += 1

    def __releasebuffer__(self, Py_buffer *buffer):
        # self.view_count -= 1
        # self.current_frame_data.__releasebuffer__(buffer)
        # PyBuffer_Release(buffer)
        self.view_count -= 1

    cdef void _check_array_size(self, audio_bfr_p bfr) nogil except *:
        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef cnp.float32_t[:,:] next_arr = self.next_frame_data

        if next_arr.shape[0] == self.ptr.no_channels and next_arr.shape[1] == self.ptr.no_samples:
            return
        with gil:
            self.next_frame_data = np.zeros((p.no_channels, p.no_samples), dtype=np.float32)


    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) nogil except *:
        cdef audio_bfr_p write_bfr = self.write_bfr
        cdef NDIlib_audio_frame_v3_t* p = self.ptr

        write_bfr.sample_rate = p.sample_rate
        write_bfr.num_channels = p.no_channels
        write_bfr.num_samples = p.no_samples
        write_bfr.timecode = p.timecode
        write_bfr.timestamp = p.timestamp
        write_bfr.total_size = p.no_channels * p.channel_stride_in_bytes
        write_bfr.p_data = <float*>p.p_data
        self._check_array_size(write_bfr)
        write_bfr.valid = True
        self.process_read_buffer(write_bfr)

        if recv_ptr is not NULL:
            NDIlib_recv_free_audio_v3(recv_ptr, self.ptr)

    cdef void process_read_buffer(self, audio_bfr_p bfr) nogil except *:
        cdef NDIlib_audio_frame_v3_t* p = self.ptr
        cdef size_t ncols = p.no_samples, nrows = p.no_channels
        cdef cnp.float32_t[:,:] next_arr = self.next_frame_data
        cdef cnp.float32_t[:,:] cur_arr = self.current_frame_data

        float_ptr_to_memview_2d(<float*>p.p_data, next_arr)
        with gil:
            with self.read_ready:
                if self.view_count > 0:
                    raise ValueError('Cannot write if buffer view active')
                # print(f'read_lock acquired, bfr_size={bfr.total_size}')
                # print('next_arr.shape: ', next_arr.shape[0], next_arr.shape[1])

                if cur_arr.shape[0] != next_arr.shape[0] or cur_arr.shape[1] != next_arr.shape[1]:
                # if self.current_frame_data.size != bfr.total_size:
                    self.current_frame_data = self.next_frame_data.copy()
                    # assert np.array_equal(self.current_frame_data, self.next_frame_data)
                    # print(f'data.size={self.current_frame_data.size}')
                else:
                    cur_arr[...] = next_arr
                    # print('data copy shape: ', cur_arr.shape[0], cur_arr.shape[1])
                self.current_timestamp = p.timestamp
                self.current_timecode = p.timecode
                self.read_bfr.total_size = bfr.total_size
                self.read_ready.notify_all()
                # l = av_frame_bfr_count(self.audio_bfrs)
                # print('bfr count: ', l)
                # print('notify_all')




@cython.boundscheck(False)
@cython.wraparound(False)
cdef void float_ptr_to_memview_2d(float* p, cnp.float32_t[:,:] dest) nogil except *:
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
