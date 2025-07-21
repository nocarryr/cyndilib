# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS
# distutils: define_macros=CYTHON_TRACE_NOGIL=1

from libc.stdint cimport uint8_t
cimport cython
cimport numpy as cnp

from cyndilib.wrapper cimport *
from cyndilib.framesync_helper cimport FrameSyncVideoInstance_s, FrameSyncAudioInstance_s
from cyndilib.video_frame cimport VideoFrameSync
from cyndilib.audio_frame cimport AudioFrameSync




@cython.boundscheck(False)
@cython.wraparound(False)
cdef int fill_audio_frame_struct(
    NDIlib_audio_frame_v3_t* frame,
    cnp.float32_t[:,:] samples,
    size_t sample_rate,
    double timestamp,
) except -1 nogil:
    cdef int32_t ndi_ts = posix_time_to_ndi(timestamp)
    cdef size_t nrows = samples.shape[0], ncols = samples.shape[1]

    frame.sample_rate = sample_rate
    frame.no_channels = nrows
    frame.no_samples = ncols
    frame.channel_stride_in_bytes = sizeof(float) * ncols
    frame.timecode = NDIlib_send_timecode_synthesize
    frame.FourCC = NDIlib_FourCC_audio_type_FLTP
    frame.timestamp = ndi_ts

    frame.p_data = <uint8_t*>mem_alloc(sizeof(float)*nrows*ncols)
    cdef float* float_data = <float*>frame.p_data

    cdef size_t i, j, k=0
    for i in range(nrows):
        for j in range(ncols):
            float_data[k] = samples[i,j]
            k += 1
    return 0



@cython.boundscheck(False)
@cython.wraparound(False)
cdef int buffer_into_video_frame(
    NDIlib_video_frame_v2_t* frame,
    size_t width,
    size_t height,
    uint8_t[:] arr,
    double timestamp
) except -1 nogil:
    cdef int32_t ndi_ts = posix_time_to_ndi(timestamp)
    cdef size_t n = arr.shape[0], i
    cdef uint8_t* data_p = <uint8_t*>frame.p_data

    frame.timestamp = ndi_ts
    frame.timecode = NDIlib_send_timecode_synthesize
    frame.frame_format_type = NDIlib_frame_format_type_progressive
    for i in range(n):
        data_p[i] = arr[i]


# Tracker for AudioFrameSyncHelper to count how many frames were
# sent vs freed (by the audio frame)
cdef struct FrameSyncFreeTracker:
    int num_allocs
    int num_frees
    bint enable_dealloc


# Function to overload the default free function with the
# FrameSyncFreeTracker injected as `FrameSyncAudioInstance_s.fs_ptr`
cdef void track_audio_frame_sync_free(
    FrameSyncAudioInstance_s* instance,
    NDIlib_audio_frame_v3_t* audio_ptr
) noexcept nogil:
    if instance is NULL:
        return
    cdef FrameSyncFreeTracker* tracker = <FrameSyncFreeTracker*>instance.fs_ptr
    if tracker.enable_dealloc:
        if audio_ptr is not NULL and audio_ptr.p_data is not NULL:
            mem_free(audio_ptr.p_data)
    audio_ptr.p_data = NULL
    tracker.num_frees += 1


cdef void track_video_frame_sync_free(
    FrameSyncVideoInstance_s* instance,
    NDIlib_video_frame_v2_t* video_ptr
) noexcept nogil:
    if instance is NULL:
        return
    cdef FrameSyncFreeTracker* tracker = <FrameSyncFreeTracker*>instance.fs_ptr
    if tracker.enable_dealloc:
        if video_ptr is not NULL and video_ptr.p_data is not NULL:
            mem_free(video_ptr.p_data)
    video_ptr.p_data = NULL
    tracker.num_frees += 1



cdef class BaseFrameSyncHelper:
    cdef FrameSyncFreeTracker tracker
    def __cinit__(self, *args, **kwargs):
        self.tracker.num_allocs = 0
        self.tracker.num_frees = 0
        self.tracker.enable_dealloc = True

    @property
    def num_allocs(self):
        """Number of frames sent"""
        return self.tracker.num_allocs

    @property
    def num_frees(self):
        """Number of frames freed by the audio frame"""
        return self.tracker.num_frees

    @property
    def num_outstanding(self):
        """Number of frames that were sent but not freed yet"""
        return self.tracker.num_allocs - self.tracker.num_frees

    cdef bint _has_outstanding(self) noexcept nogil:
        """Check if there are outstanding frames"""
        return (self.tracker.num_allocs - self.tracker.num_frees) > 0


cdef class AudioFrameSyncHelper(BaseFrameSyncHelper):
    cdef readonly AudioFrameSync audio_frame

    def set_audio_frame(self, AudioFrameSync audio_frame):
        self.audio_frame = audio_frame
        if audio_frame is None:
            return
        # Cast self.tracker to <NDIlib_framesync_instance_t> so the
        # parameters match
        cdef FrameSyncAudioInstance_s* instance = &audio_frame.framesync_instance
        instance.fs_ptr = <NDIlib_framesync_instance_t>&self.tracker
        instance.free_data = track_audio_frame_sync_free

    def fill_data(
        self,
        cnp.float32_t[:,:] samples,
        size_t sample_rate,
        double timestamp,
    ):
        """Fill audio frame with data and simulate the processing that
        occurs within the `FrameSync` and `AudioFrameSync` classes.
        """
        assert self.audio_frame is not None, "audio_frame is not set"
        cdef NDIlib_audio_frame_v3_t* frame = self.audio_frame.ptr

        fill_audio_frame_struct(frame, samples, sample_rate, timestamp)
        self.tracker.num_allocs += 1
        self.audio_frame._process_incoming()

    def free_previous(self):
        """Free the previously allocated audio frame, if any"""
        if self.audio_frame is None:
            return
        if self.audio_frame.ptr.p_data is NULL:
            return
        self.audio_frame._free_framesync_data()



cdef class VideoFrameSyncHelper(BaseFrameSyncHelper):
    cdef readonly VideoFrameSync video_frame
    cdef uint8_t *buffer
    cdef size_t buffer_size
    def __cinit__(self, *args, **kwargs):
        self.buffer = NULL
        self.buffer_size = 0

    def __init__(self, *args, **kwargs):
        # Important since the frame buffer is owned by this class
        self.tracker.enable_dealloc = False

    def __dealloc__(self):
        if self.buffer is not NULL:
            mem_free(self.buffer)
            self.buffer = NULL
            self.buffer_size = 0

    def set_video_frame(self, VideoFrameSync video_frame):
        self.video_frame = video_frame
        if video_frame is None:
            return
        # Cast self.tracker to <NDIlib_framesync_instance_t> so the
        # parameters match
        cdef FrameSyncVideoInstance_s* instance = &video_frame.framesync_instance
        instance.fs_ptr = <NDIlib_framesync_instance_t>&self.tracker
        instance.free_data = track_video_frame_sync_free

    def fill_data(
        self,
        uint8_t[:] arr,
        size_t width,
        size_t height,
        double timestamp,
    ):
        """Fill video frame with data and simulate the processing that
        occurs within the `FrameSync` and `VideoFrameSync` classes.
        """
        assert self.video_frame is not None, "video_frame is not set"
        cdef NDIlib_video_frame_v2_t* frame = self.video_frame.ptr

        self.video_frame._set_resolution(width, height)
        cdef size_t size_in_bytes = self.video_frame._get_buffer_size()
        self._realloc_buffer(size_in_bytes)

        frame.p_data = self.buffer
        buffer_into_video_frame(frame, width, height, arr, timestamp)
        self.tracker.num_allocs += 1
        self.video_frame._process_incoming()

    cdef int _realloc_buffer(self, size_t new_size) except -1 nogil:
        if new_size == self.buffer_size:
            return 0
        if self.buffer is not NULL:
            if self._has_outstanding():
                raise_withgil(PyExc_RuntimeError, 'cannot resize while frame in use')
            mem_free(self.buffer)
            self.buffer = NULL
        self.buffer_size = new_size
        self.buffer = <uint8_t *>mem_alloc(self.buffer_size)
        if self.buffer is NULL:
            raise_mem_err()
        return 0

    def free_previous(self):
        """Free the previously allocated video frame, if any"""
        if self.video_frame is None:
            return
        if self.video_frame.ptr.p_data is NULL:
            return
        self.video_frame._free_framesync_data()
