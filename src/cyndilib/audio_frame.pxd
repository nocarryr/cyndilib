# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *
cimport numpy as cnp

from .wrapper cimport *
from .buffertypes cimport *
from .locks cimport RLock, Condition


cdef class AudioFrame:
    cdef NDIlib_audio_frame_v3_t* ptr

    cdef int _get_sample_rate(self) nogil
    cdef void _set_sample_rate(self, int value) nogil
    cdef int _get_num_channels(self) nogil
    cdef void _set_num_channels(self, int value) nogil
    cdef int _get_num_samples(self) nogil
    cdef void _set_num_samples(self, int value) nogil
    cdef int64_t _get_timecode(self) nogil
    cdef int64_t _set_timecode(self, int64_t value) nogil
    cdef int _get_channel_stride(self) nogil
    cdef void _set_channel_stride(self, int value) nogil
    cdef uint8_t* _get_data(self) nogil
    cdef void _set_data(self, uint8_t* data) nogil
    cdef const char* _get_metadata(self) nogil except *
    cdef bytes _get_metadata_bytes(self)
    cdef int64_t _get_timestamp(self) nogil
    cdef void _set_timestamp(self, int64_t value) nogil


cdef class AudioRecvFrame(AudioFrame):
    cdef audio_bfr_p audio_bfrs
    cdef audio_bfr_p read_bfr
    cdef audio_bfr_p write_bfr
    cdef readonly RLock read_lock
    cdef readonly RLock write_lock
    cdef readonly Condition read_ready
    cdef readonly Condition write_ready
    cdef readonly cnp.ndarray current_frame_data
    cdef readonly cnp.ndarray next_frame_data
    cdef readonly uint32_t current_timecode
    cdef readonly uint32_t current_timestamp
    cdef Py_ssize_t[2] bfr_shape
    cdef Py_ssize_t[2] bfr_strides
    cdef size_t view_count

    cdef void _check_array_size(self, audio_bfr_p bfr) nogil except *
    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) nogil except *
    cdef void process_read_buffer(self, audio_bfr_p bfr) nogil except *
