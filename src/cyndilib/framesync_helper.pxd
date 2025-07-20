# cython: language_level=3
# distutils: language = c++

from .wrapper cimport *


ctypedef void (*free_video_data_func)(
    FrameSyncVideoInstance_s* instance, NDIlib_video_frame_v2_t* video_ptr
) noexcept nogil

ctypedef void (*free_audio_data_func)(
    FrameSyncAudioInstance_s* instance, NDIlib_audio_frame_v3_t* audio_ptr
) noexcept nogil



cdef struct FrameSyncVideoInstance_s:
    NDIlib_framesync_instance_t fs_ptr
    free_video_data_func free_data

cdef struct FrameSyncAudioInstance_s:
    NDIlib_framesync_instance_t fs_ptr
    free_audio_data_func free_data


cdef void _free_video_default_func(
    FrameSyncVideoInstance_s* instance,
    NDIlib_video_frame_v2_t* video_ptr
) noexcept nogil


cdef void _free_audio_default_func(
    FrameSyncAudioInstance_s* instance,
    NDIlib_audio_frame_v3_t* audio_ptr
) noexcept nogil
