# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *
cimport numpy as cnp

from .wrapper cimport *
from .finder cimport Source
from .send_frame_status cimport (
    VideoSendFrame_status_s, VideoSendFrame_item_s,
    AudioSendFrame_status_s, AudioSendFrame_item_s,
)
from .video_frame cimport VideoSendFrame
from .audio_frame cimport AudioSendFrame
from .metadata_frame cimport MetadataSendFrame


cdef class Sender:
    cdef NDIlib_send_create_t send_create
    cdef NDIlib_send_instance_t ptr
    cdef NDIlib_source_t* source_ptr
    cdef readonly Source source
    cdef readonly str ndi_name, ndi_groups
    cdef readonly bint clock_video, clock_audio
    cdef bytes _b_ndi_name, _b_ndi_groups
    cdef readonly VideoSendFrame video_frame
    cdef readonly AudioSendFrame audio_frame
    cdef MetadataSendFrame metadata_frame
    cdef readonly bint has_video_frame, has_audio_frame
    cdef readonly bint _running
    cdef readonly size_t num_video_buffers, num_audio_buffers
    cdef VideoSendFrame_item_s* last_async_sender

    cdef void _open(self) except *
    cdef void _close(self) except *
    cpdef set_video_frame(self, VideoSendFrame vf)
    cpdef set_audio_frame(self, AudioSendFrame af)
    cdef bint _check_running(self) nogil except *
    cdef void _set_async_video_sender(self, VideoSendFrame_item_s* item) nogil except *
    cdef void _clear_async_video_status(self) nogil except *
    cdef bint _write_video_and_audio(
        self,
        cnp.uint8_t[:] video_data,
        cnp.float32_t[:,:] audio_data,
    ) except *
    cdef bint _write_video(self, cnp.uint8_t[:] data) except *
    cdef bint _write_video_async(self, cnp.uint8_t[:] data) except *
    cdef bint _send_video(self) except *
    cdef bint _send_video_async(self) except *
    cdef bint _write_audio(self, cnp.float32_t[:,:] data) except *
    cdef bint _send_audio(self) except *
    cdef bint _send_metadata(self, str tag, dict attrs) except *
    cdef bint _send_metadata_frame(self, MetadataSendFrame mf) except *
    cdef int _get_num_connections(self, uint32_t timeout_ms) nogil except *
    cdef bint _update_tally(self, uint32_t timeout_ms) nogil except *
