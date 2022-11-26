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


cdef class VideoFrame:
    cdef NDIlib_video_frame_v2_t* ptr
    cdef FourCCPackInfo pack_info
    cdef frame_rate_t frame_rate

    cpdef str get_format_string(self)
    cdef (int, int) _get_resolution(self) nogil except *
    cdef void _set_resolution(self, int xres, int yres) nogil
    cdef int _get_xres(self) nogil
    cdef void _set_xres(self, int value) nogil except *
    cdef int _get_yres(self) nogil
    cdef void _set_yres(self, int value) nogil except *
    cdef FourCC _get_fourcc(self) nogil except *
    cdef void _set_fourcc(self, FourCC value) nogil except *
    cdef frame_rate_t* _get_frame_rate(self) nogil except *
    cdef void _set_frame_rate(self, frame_rate_ft fr) nogil except *
    cdef float _get_aspect(self) nogil
    cdef void _set_aspect(self, float value) nogil
    cdef FrameFormat _get_frame_format(self) nogil except *
    cdef void _set_frame_format(self, FrameFormat fmt) nogil except *
    cdef int64_t _get_timecode(self) nogil
    cdef int64_t _set_timecode(self, int64_t value) nogil
    cdef int _get_line_stride(self) nogil
    cdef void _set_line_stride(self, int value) nogil
    cdef size_t _get_buffer_size(self) nogil except *
    cdef uint8_t* _get_data(self) nogil
    cdef void _set_data(self, uint8_t* data) nogil
    cdef const char* _get_metadata(self) nogil except *
    cdef bytes _get_metadata_bytes(self)
    cdef int64_t _get_timestamp(self) nogil
    cdef void _set_timestamp(self, int64_t value) nogil
    cdef size_t _get_data_size(self) nogil
    cpdef size_t get_data_size(self)
    cdef void _recalc_pack_info(self) nogil except *

cdef class VideoRecvFrame(VideoFrame):
    cdef readonly size_t max_buffers
    cdef cpp_deque[size_t] read_indices
    cdef cpp_set[size_t] read_indices_set
    cdef video_bfr_p video_bfrs
    cdef video_bfr_p read_bfr
    cdef video_bfr_p write_bfr
    cdef readonly RLock read_lock
    cdef readonly RLock write_lock
    cdef readonly Condition read_ready
    cdef readonly Condition write_ready
    cdef cnp.ndarray all_frame_data
    cdef readonly cnp.ndarray current_frame_data
    cdef Py_ssize_t[1] bfr_shape
    cdef Py_ssize_t[1] bfr_strides
    cdef size_t view_count

    cdef void _check_read_array_size(self) except *
    cdef void _fill_read_data(self, bint advance) nogil except *
    cdef size_t _get_next_write_index(self) nogil except *
    cdef bint can_receive(self) nogil except *
    cdef void _check_write_array_size(self) except *
    cdef void _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except *
    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except *


cdef class VideoFrameSync(VideoFrame):
    cdef NDIlib_framesync_instance_t fs_ptr
    cdef readonly Py_ssize_t[1] shape
    cdef readonly Py_ssize_t[1] strides
    cdef size_t view_count

    cdef void _process_incoming(self, NDIlib_framesync_instance_t fs_ptr) nogil except *


cdef class VideoSendFrame(VideoFrame):
    cdef VideoSendFrame_status send_status
    cdef readonly VideoSendFrame parent_frame
    cdef readonly VideoSendFrame child_frame
    cdef view.array view
    cdef readonly bint has_child, has_parent
    cdef readonly size_t child_count
    cdef Py_ssize_t[1] shape
    cdef Py_ssize_t[1] strides

    cdef void _destroy(self) except *
    cdef bint _write_available(self) nogil except *
    cdef VideoSendFrame _prepare_buffer_write(self)
    cdef void _set_buffer_write_complete(self, VideoSendFrame_status* send_status) nogil except *
    cdef VideoSendFrame _prepare_memview_write(self)
    cdef void _write_data_to_memview(
        self,
        cnp.uint8_t[:] data,
        cnp.uint8_t[:] view,
        VideoSendFrame_status* send_status
    ) nogil except *
    cdef VideoSendFrame_status* _get_next_write_frame(self) nogil except *
    cdef bint _send_frame_available(self) nogil except *
    cdef VideoSendFrame_status* _get_send_frame(self) nogil except *
    cdef void _on_sender_write(self, VideoSendFrame_status* s_ptr) nogil except *
    cdef void _set_sender_status(self, bint attached) except *
    cdef void _create_child_frames(self, size_t count) except *
    cdef void _create_child_frame(self) except *
    cdef void _on_child_created(self) nogil except *
    cdef void _rebuild_array(self) except *
