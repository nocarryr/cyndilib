# cython: language_level=3
# distutils: language = c++

from .wrapper cimport *

cdef Py_intptr_t NULL_ID = 0

cdef struct VideoSendFrame_status:
    Py_intptr_t id
    Py_intptr_t next_send_id
    Py_intptr_t last_send_id
    bint write_available
    bint send_ready
    bint attached_to_sender
    NDIlib_video_frame_v2_t** frame_ptr
    VideoSendFrame_status* next
    VideoSendFrame_status* prev

cdef struct AudioSendFrame_status:
    Py_intptr_t id
    Py_intptr_t next_send_id
    Py_intptr_t last_send_id
    bint write_available
    bint send_ready
    bint attached_to_sender
    NDIlib_audio_frame_v3_t** frame_ptr
    Py_ssize_t[2] shape
    Py_ssize_t[2] strides
    AudioSendFrame_status* next
    AudioSendFrame_status* prev

ctypedef fused SendFrame_status_ft:
    VideoSendFrame_status
    AudioSendFrame_status

cdef void frame_status_set_send_id(SendFrame_status_ft* ptr, Py_intptr_t send_id) nogil except *
cdef void frame_status_clear_write(SendFrame_status_ft* ptr, Py_intptr_t send_id) nogil except *
cdef SendFrame_status_ft* frame_status_get_writer(SendFrame_status_ft* ptr) nogil except *
cdef SendFrame_status_ft* frame_status_get_sender(SendFrame_status_ft* ptr) nogil except *
