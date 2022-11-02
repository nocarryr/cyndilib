# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

from .wrapper cimport *

from .locks cimport Event
from .callback cimport Callback
from .receiver cimport Receiver, ReceiveFrameType
from .video_frame cimport VideoFrameSync
from .audio_frame cimport AudioFrameSync

cdef class FrameSync:
    cdef NDIlib_framesync_instance_t ptr
    cdef readonly Receiver receiver
    cdef readonly VideoFrameSync video_frame
    cdef readonly AudioFrameSync audio_frame

    cdef void _set_video_frame(self, VideoFrameSync video_frame) except *
    cdef void _set_audio_frame(self, AudioFrameSync audio_frame) except *
    cdef int _audio_samples_available(self) nogil except *
    cdef void _capture_video(self, FrameFormat fmt=*) except *
    cdef size_t _capture_available_audio(self) except *
    cdef size_t _capture_audio(self, size_t no_samples, bint limit=*, bint truncate=*) except *

    cdef void _do_capture_video(
        self,
        NDIlib_video_frame_v2_t* video_ptr,
        FrameFormat fmt=*,
    ) nogil except *

    cdef void _do_capture_audio(
        self,
        NDIlib_audio_frame_v3_t* audio_ptr,
        size_t no_samples,
    ) nogil except *

    cdef void _free_video(self, NDIlib_video_frame_v2_t* video_ptr) nogil except *
    cdef void _free_audio(self, NDIlib_audio_frame_v3_t* audio_ptr) nogil except *
