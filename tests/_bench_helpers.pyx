# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS
# distutils: define_macros=CYTHON_TRACE_NOGIL=1

cimport cython

from cyndilib.wrapper cimport *
cimport numpy as cnp

from cyndilib.send_frame_status cimport *
from cyndilib.video_frame cimport VideoSendFrame, VideoFrameSync
from cyndilib.audio_frame cimport AudioSendFrame, AudioFrameSync


cdef class BenchSender:
    cdef readonly VideoSendFrame video_frame
    cdef readonly AudioSendFrame audio_frame
    cdef bint has_video_frame, has_audio_frame
    cdef VideoSendFrame_item_s* last_async_sender
    def __cinit__(self, *args, **kwargs):
        self.video_frame = None
        self.audio_frame = None
        self.has_video_frame = False
        self.has_audio_frame = False
        self.last_async_sender = NULL

    def __enter__(self):
        if self.has_video_frame:
            self.video_frame._set_sender_status(True)
        if self.has_audio_frame:
            self.audio_frame._set_sender_status(True)
        return self

    def __exit__(self, *args):
        self._clear_async_video_status()
        if self.has_video_frame:
            self.video_frame._set_sender_status(False)
        if self.has_audio_frame:
            self.audio_frame._set_sender_status(False)

    def set_video_frame(self, VideoSendFrame vf):
        self.video_frame = vf
        self.has_video_frame = vf is not None

    def set_audio_frame(self, AudioSendFrame af):
        self.audio_frame = af
        self.has_audio_frame = af is not None

    def write_video_and_audio(
        self,
        cnp.uint8_t[:] video_data,
        cnp.float32_t[:,:] audio_data,
    ):
        if not self.has_video_frame or not self.has_audio_frame:
            raise_exception('video_frame or audio_frame is None')
        cdef VideoSendFrame_item_s* vid_item
        cdef AudioSendFrame_item_s* aud_item
        cdef NDIlib_video_frame_v2_t* vid_ptr = self.video_frame.ptr
        cdef NDIlib_audio_frame_v3_t aud_send_frame
        cdef bint vid_result = True, aud_result = True

        vid_item = self.video_frame._prepare_buffer_write()
        aud_item = self.audio_frame._prepare_buffer_write()
        cdef size_t* outer_shape = self.audio_frame.send_status.data.shape
        cdef cnp.uint8_t[:] vid_memview = self.video_frame
        cdef cnp.float32_t[:,:] aud_memview = self.audio_frame

        vid_result = vid_item is not NULL
        aud_result = aud_item is not NULL
        if not vid_result or not aud_result:
            raise_exception('send_status is NULL')


        with nogil:
            self.audio_frame._set_shape_from_memview(aud_item, audio_data)
            aud_memview[...] = audio_data
            self.audio_frame._set_buffer_write_complete(aud_item)
            vid_memview[...] = video_data
            self.video_frame._set_buffer_write_complete(vid_item)

            audio_frame_copy(aud_item.frame_ptr, &aud_send_frame)
            aud_send_frame.p_data = <uint8_t*>aud_item.frame_ptr.p_data
            # NDIlib_send_send_audio_v3(self.ptr, &aud_send_frame)
            self._clear_async_video_status()
            self.audio_frame._on_sender_write(aud_item)

            vid_ptr.p_data = vid_item.frame_ptr.p_data
            # NDIlib_send_send_video_async_v2(self.ptr, vid_ptr)
            self._set_async_video_sender(vid_item)

        # return vid_result and aud_result

    def write_video(self, cnp.uint8_t[:] data):
        if not self.has_video_frame:
            raise_exception('video_frame is None')
        cdef NDIlib_video_frame_v2_t* vid_ptr = self.video_frame.ptr
        cdef VideoSendFrame_item_s* item = self.video_frame._prepare_buffer_write()
        cdef cnp.uint8_t[:] vid_memview = self.video_frame

        with nogil:
            vid_memview[...] = data
            self.video_frame._set_buffer_write_complete(item)
            item.frame_ptr.p_metadata = vid_ptr.p_metadata
            # NDIlib_send_send_video_v2(self.ptr, item.frame_ptr)
            self._clear_async_video_status()
            self.video_frame._on_sender_write(item)
        # return True

    def write_video_async(self, cnp.uint8_t[:] data):
        if not self.has_video_frame:
            raise_exception('video_frame is None')
        cdef NDIlib_video_frame_v2_t* vid_ptr = self.video_frame.ptr
        cdef VideoSendFrame_item_s* item = self.video_frame._prepare_buffer_write()
        cdef cnp.uint8_t[:] vid_memview = self.video_frame

        with nogil:
            vid_memview[...] = data
            self.video_frame._set_buffer_write_complete(item)
            item.frame_ptr.p_metadata = vid_ptr.p_metadata
            # NDIlib_send_send_video_async_v2(self.ptr, item.frame_ptr)
            self._set_async_video_sender(item)
        # return True

    def write_audio(self, cnp.float32_t[:,:] data):
        if not self.has_audio_frame:
            raise_exception('audio_frame is None')
        cdef AudioSendFrame_item_s* item = self.audio_frame._prepare_buffer_write()
        cdef cnp.float32_t[:,:] aud_memview = self.audio_frame
        cdef NDIlib_audio_frame_v3_t send_frame

        with nogil:
            audio_frame_copy(item.frame_ptr, &send_frame)
            self.audio_frame._set_shape_from_memview(item, data)
            aud_memview[...] = data
            self.audio_frame._set_buffer_write_complete(item)
            send_frame.p_data = <uint8_t*>item.frame_ptr.p_data
            # NDIlib_send_send_audio_v3(self.ptr, &send_frame)
            self._clear_async_video_status()
            self.audio_frame._on_sender_write(item)
        # return True

    cdef void _set_async_video_sender(self, VideoSendFrame_item_s* item) noexcept nogil:
        self._clear_async_video_status()
        self.last_async_sender = item

    cdef void _clear_async_video_status(self) noexcept nogil:
        cdef VideoSendFrame_item_s* item = self.last_async_sender
        if item is NULL:
            return
        self.last_async_sender = NULL
        self.video_frame._on_sender_write(item)
