# cython: language_level=3
# distutils: language = c++

from .wrapper cimport *

cdef extern from *:
    """
    #define MAX_FRAME_BUFFERS 3
    #define NULL_ID 0
    #define NULL_INDEX 0x7fff
    """
    cdef const size_t MAX_FRAME_BUFFERS
    cdef const Py_intptr_t NULL_ID
    cdef const Py_ssize_t NULL_INDEX


cdef struct SendFrame_item_s:
    Py_ssize_t idx
    Py_ssize_t view_count
    Py_ssize_t alloc_size
    bint write_available
    bint read_available
    Py_ssize_t[3] shape
    Py_ssize_t[3] strides


cdef struct SendFrame_status_s:
    Py_ssize_t num_buffers
    Py_ssize_t write_index
    Py_ssize_t read_index
    Py_ssize_t ndim
    Py_ssize_t[3] shape
    Py_ssize_t[3] strides
    bint attached_to_sender

cdef struct VideoSendFrame_item_s:
    SendFrame_item_s data
    NDIlib_video_frame_v2_t* frame_ptr

cdef struct VideoSendFrame_status_s:
    SendFrame_status_s data
    VideoSendFrame_item_s[MAX_FRAME_BUFFERS] items

cdef struct AudioSendFrame_item_s:
    SendFrame_item_s data
    NDIlib_audio_frame_v3_t* frame_ptr

cdef struct AudioSendFrame_status_s:
    SendFrame_status_s data
    AudioSendFrame_item_s[MAX_FRAME_BUFFERS] items


ctypedef fused SendFrame_status_s_ft:
    VideoSendFrame_status_s
    AudioSendFrame_status_s

ctypedef fused SendFrame_item_s_ft:
    VideoSendFrame_item_s
    AudioSendFrame_item_s


cdef int frame_status_init(SendFrame_status_s_ft* ptr) except -1 nogil
cdef int frame_status_free(SendFrame_status_s_ft* ptr) except -1 nogil
cdef int frame_status_copy_frame_ptr(
    SendFrame_status_s_ft* ptr,
    NDIlib_frame_type_ft* frame_ptr,
) except -1 nogil
cdef int frame_status_alloc_p_data(SendFrame_status_s_ft* ptr) except -1 nogil
cdef int frame_status_set_send_ready(SendFrame_status_s_ft* ptr) except -1 nogil
cdef int frame_status_set_send_complete(
    SendFrame_status_s_ft* ptr,
    Py_ssize_t idx,
) except -1 nogil
cdef Py_ssize_t frame_status_get_next_write_index(
    SendFrame_status_s_ft* ptr,
) except? -1 nogil
cdef Py_ssize_t frame_status_get_next_read_index(
    SendFrame_status_s_ft* ptr,
) except? -1 nogil
