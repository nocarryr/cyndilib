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
    cdef (int, int) _get_resolution(self) noexcept nogil
    cdef int _set_resolution(self, int xres, int yres) except -1 nogil
    cdef int _get_xres(self) nogil
    cdef int _set_xres(self, int value) except -1 nogil
    cdef int _get_yres(self) nogil
    cdef int _set_yres(self, int value) except -1 nogil
    cdef FourCC _get_fourcc(self) noexcept nogil
    cdef int _set_fourcc(self, FourCC value) except -1 nogil
    cdef frame_rate_t* _get_frame_rate(self) noexcept nogil
    cdef int _set_frame_rate(self, frame_rate_ft fr) except -1 nogil
    cdef float _get_aspect(self) nogil
    cdef void _set_aspect(self, float value) noexcept nogil
    cdef FrameFormat _get_frame_format(self) noexcept nogil
    cdef void _set_frame_format(self, FrameFormat fmt) noexcept nogil
    cdef int64_t _get_timecode(self) nogil
    cdef int64_t _set_timecode(self, int64_t value) nogil
    cdef int _get_line_stride(self) nogil
    cdef void _set_line_stride(self, int value) nogil
    cdef size_t _get_buffer_size(self) except? -1 nogil
    cdef uint8_t* _get_data(self) nogil
    cdef void _set_data(self, uint8_t* data) nogil
    cdef const char* _get_metadata(self) noexcept nogil
    cdef bytes _get_metadata_bytes(self)
    cdef int64_t _get_timestamp(self) nogil
    cdef void _set_timestamp(self, int64_t value) nogil
    cdef size_t _get_data_size(self) nogil
    cpdef size_t get_data_size(self)
    cdef int _recalc_pack_info(self) except -1 nogil

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

    cdef int _check_read_array_size(self) except -1
    cdef int _fill_read_data(self, bint advance) except -1 nogil
    cdef size_t _get_next_write_index(self) except? -1 nogil
    cdef bint can_receive(self) except -1 nogil
    cdef int _check_write_array_size(self) except -1
    cdef int _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except -1
    cdef int _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except -1


cdef class VideoFrameSync(VideoFrame):
    cdef NDIlib_framesync_instance_t fs_ptr
    cdef readonly Py_ssize_t[1] shape
    cdef readonly Py_ssize_t[1] strides
    cdef size_t view_count

    cdef int _process_incoming(self, NDIlib_framesync_instance_t fs_ptr) except -1 nogil


cdef class VideoSendFrame(VideoFrame):
    cdef VideoSendFrame_status_s send_status
    cdef VideoSendFrame_item_s* buffer_write_item

    cdef int _destroy(self) except -1
    cdef bint _write_available(self) except -1 nogil
    cdef VideoSendFrame_item_s* _prepare_buffer_write(self) except NULL nogil
    cdef int _set_buffer_write_complete(self, VideoSendFrame_item_s* item) except -1 nogil
    cdef VideoSendFrame_item_s* _prepare_memview_write(self) except NULL nogil
    cdef int _write_data_to_memview(
        self,
        cnp.uint8_t[:] data,
        cnp.uint8_t[:] view,
        VideoSendFrame_item_s* item,
    ) except -1 nogil
    cdef VideoSendFrame_item_s* _get_next_write_frame(self) except NULL nogil
    cdef bint _send_frame_available(self) except -1 nogil
    cdef VideoSendFrame_item_s* _get_send_frame(self) except? NULL nogil
    cdef int _on_sender_write(self, VideoSendFrame_item_s* s_ptr) except -1 nogil
    cdef int _set_sender_status(self, bint attached) except -1 nogil
    cdef int _rebuild_array(self) except -1 nogil
