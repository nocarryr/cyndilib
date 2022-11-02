# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

from .wrapper cimport *

from .locks cimport RLock, Condition, Event
from .finder cimport Source
from .video_frame cimport VideoRecvFrame
from .audio_frame cimport AudioRecvFrame
from .callback cimport Callback


cpdef enum ReceiveFrameType:
    nothing = 0
    recv_video = 1
    recv_audio = 2
    recv_metadata = 4
    recv_status_change = 8
    recv_error = 16
    recv_buffers_full = 32
    recv_all = recv_video | recv_audio | recv_metadata

cdef NDIlib_frame_type_e recv_frame_type_cast(ReceiveFrameType ft) nogil except *
cdef ReceiveFrameType recv_frame_type_uncast(NDIlib_frame_type_e ft) nogil except *

cdef class RecvCreate:
    cdef public str source_name
    cdef public RecvColorFormat color_format
    cdef public RecvBandwidth bandwidth
    cdef public bint allow_video_fields
    cdef public str recv_name

    cdef NDIlib_recv_create_v3_t* build_create_p(self) except *


cdef class Receiver:
    cdef RecvCreate settings
    cdef readonly VideoRecvFrame video_frame
    cdef readonly AudioRecvFrame audio_frame
    cdef readonly str source_name
    cdef readonly bint has_video_frame, has_audio_frame, has_metadata_frame
    cdef readonly RLock connection_lock
    cdef readonly Condition connection_notify
    cdef readonly Source source
    cdef NDIlib_source_t* source_ptr
    cdef bint _connected, _probably_connected
    cdef size_t _num_empty_recv
    cdef NDIlib_recv_instance_t ptr
    cdef NDIlib_recv_create_v3_t recv_create

    cpdef set_video_frame(self, VideoRecvFrame vf)
    cpdef set_audio_frame(self, AudioRecvFrame af)
    cpdef set_source(self, Source src)
    cpdef connect_to(self, Source src)
    cdef void _connect_to(self, NDIlib_source_t* src) except *
    cdef void _disconnect(self) nogil except *
    cdef void _reconnect(self) nogil except *
    cdef bint _is_connected(self) nogil except *
    cdef void _set_connected(self, bint value) nogil except *
    cdef int _get_num_connections(self) nogil except *
    cdef bint _wait_for_connect(self, float timeout) nogil except *
    cdef void _update_performance(self) nogil except *
    cpdef ReceiveFrameType receive(
        self, ReceiveFrameType recv_type, uint32_t timeout_ms
    )
    cdef ReceiveFrameType _receive(
        self, ReceiveFrameType recv_type, uint32_t timeout_ms
    ) except *

    cdef ReceiveFrameType _do_receive(
        self,
        NDIlib_video_frame_v2_t* video_frame,
        NDIlib_audio_frame_v3_t* audio_frame,
        NDIlib_metadata_frame_t* metadata_frame,
        uint32_t timeout_ms
    ) nogil except *

    cdef void free_video(self, NDIlib_video_frame_v2_t* p) nogil except *
    cdef void free_audio(self, NDIlib_audio_frame_v3_t* p) nogil except *
    cdef void free_metadata(self, NDIlib_metadata_frame_t* p) nogil except *
