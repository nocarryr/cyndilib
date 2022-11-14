# cython: language_level=3
# distutils: language = c++

from cython cimport view
from libc.stdint cimport *
from libcpp.deque cimport deque as cpp_deque
from libcpp.set cimport set as cpp_set
cimport numpy as cnp

from .wrapper cimport *
from .buffertypes cimport *
from .locks cimport RLock, Condition
from .send_frame_status cimport *


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
    cdef readonly size_t max_buffers
    cdef cpp_deque[size_t] read_indices
    cdef cpp_set[size_t] read_indices_set
    cdef cpp_deque[int64_t] frame_timestamps
    cdef audio_bfr_p audio_bfrs
    cdef audio_bfr_p read_bfr
    cdef audio_bfr_p write_bfr
    cdef readonly RLock read_lock
    cdef readonly RLock write_lock
    cdef readonly Condition read_ready
    cdef readonly Condition write_ready
    cdef cnp.ndarray all_frame_data
    cdef readonly cnp.ndarray current_frame_data
    cdef readonly uint32_t current_timecode
    cdef readonly uint32_t current_timestamp
    cdef Py_ssize_t[2] bfr_shape
    cdef Py_ssize_t[2] bfr_strides
    cdef Py_ssize_t[2] empty_bfr_shape
    cdef readonly size_t view_count

    cpdef size_t get_buffer_depth(self)
    cpdef (size_t, size_t) get_read_shape(self)
    cpdef size_t get_read_length(self)
    cpdef get_all_read_data(self)
    cdef (size_t, size_t) _fill_all_read_data(
        self,
        cnp.float32_t[:,:,:] all_frame_data,
        cnp.float32_t[:,:] result,
        cnp.int64_t[:] timestamps,
        size_t bfr_len,
    ) nogil except *

    cpdef get_read_data(self)
    cdef bint _check_read_array_size(self) except *
    cdef int64_t _fill_read_data(
        self,
        cnp.float32_t[:,:,:] all_frame_data,
        cnp.float32_t[:,:] dest,
        size_t bfr_idx,
        bint advance
    ) nogil except *
    cdef size_t _get_next_write_index(self) nogil except *
    cdef bint can_receive(self) nogil except *
    cdef void _check_write_array_size(self) except *
    cdef void _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except *
    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except *


cdef class AudioFrameSync(AudioFrame):
    cdef NDIlib_framesync_instance_t fs_ptr
    cdef readonly Py_ssize_t[2] shape
    cdef readonly Py_ssize_t[2] strides
    cdef size_t view_count

    cdef void _process_incoming(self, NDIlib_framesync_instance_t fs_ptr) nogil except *


cdef class AudioSendFrame(AudioFrame):
    cdef AudioSendFrame_status send_status
    cdef readonly AudioSendFrame parent_frame
    cdef readonly AudioSendFrame child_frame
    cdef view.array view
    cdef readonly bint has_child, has_parent
    cdef readonly size_t child_count
    cdef readonly size_t max_num_samples
    cdef Py_ssize_t[2] max_shape
    cdef Py_ssize_t[2] shape
    cdef Py_ssize_t[2] strides

    cpdef set_max_num_samples(self, size_t n)
    cdef void _destroy(self) except *
    cdef bint _write_available(self) nogil except *
    cdef void _set_shape_from_memview(
        self,
        AudioSendFrame_status* send_status,
        cnp.float32_t[:,:] data,
    ) nogil except *
    cdef AudioSendFrame _prepare_buffer_write(self)
    cdef void _set_buffer_write_complete(self, AudioSendFrame_status* send_status) nogil except *
    cdef AudioSendFrame _prepare_memview_write(self)
    cdef void _write_data_to_memview(
        self,
        cnp.float32_t[:,:] data,
        cnp.float32_t[:,:] view,
        AudioSendFrame_status* send_status
    ) nogil except *
    cdef AudioSendFrame_status* _get_next_write_frame(self) nogil except *
    cdef bint _send_frame_available(self) nogil except *
    cdef AudioSendFrame_status* _get_send_frame(self) nogil except *
    cdef void _on_sender_write(self, AudioSendFrame_status* s_ptr) nogil except *
    cdef void _set_sender_status(self, bint attached) except *
    cdef void _create_child_frames(self, size_t count) except *
    cdef void _create_child_frame(self) except *
    cdef void _on_child_created(self) nogil except *
    cdef void _rebuild_array(self) except *
