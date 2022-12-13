# cython: language_level=3
# distutils: language = c++

from libc.math cimport lround


__all__ = ('Sender',)


cdef class Sender:
    """Sends video and audio streams


    Attributes:
        ndi_name (str): The |NDI| source name to use
        ndi_source (Source): A source object representing the sender
        video_frame (VideoSendFrame):
        audio_frame (AudioSendFrame):
        metadata_frame (MetadataSendFrame):
        num_video_buffers (int): Number of video frames to allocate as buffers
        num_audio_buffers (int): Number of audio frames to allocate as buffers
        clock_video (bool): True if the video frames should clock themselves.
            If False, no rate limiting will be applied to keep within the
            desired frame rate
        clock_audio (bool): True if the audio frames should clock themselves.
            If False, no rate limiting will be applied to keep within the
            desired frame rate

    """
    def __cinit__(self, *args, **kwargs):
        self.ptr = NULL
        self.source_ptr = NULL
        self.has_video_frame = False
        self.has_audio_frame = False
        # self.has_metadata_frame = False
        self.video_frame = None
        self.audio_frame = None
        # self.metadata_frame = None
        self.last_async_sender = NULL

    def __init__(
        self,
        str ndi_name,
        str ndi_groups='',
        bint clock_video=True,
        bint clock_audio=True,
        size_t num_video_buffers=2,
        size_t num_audio_buffers=2,
    ):
        self.num_video_buffers = num_video_buffers
        self.num_audio_buffers = num_audio_buffers
        self.ndi_name = ndi_name
        self.ndi_groups = ndi_groups
        self._b_ndi_name = ndi_name.encode()
        self._b_ndi_groups = ndi_groups.encode()
        self.clock_video = clock_video
        self.clock_audio = clock_audio
        self.metadata_frame = MetadataSendFrame('')
        self.source = None
        send_t_initialize(&(self.send_create), self._b_ndi_name, NULL)
        if len(self._b_ndi_groups):
            self.send_create.ndi_groups = self._b_ndi_groups


    def __dealloc__(self):
        cdef NDIlib_send_instance_t ptr = self.ptr
        self.ptr = NULL
        if ptr is not NULL:
            NDIlib_send_destroy(ptr)
        self.audio_frame = None
        self.video_frame = None

    @property
    def name(self):
        """The current name of the source

        This may be different than what was supplied during initialization
        """
        if self.source is not None:
            return self.source.name
        return self.ndi_name

    @property
    def program_tally(self):
        """The current program tally state of the sender
        """
        if self.source is not None:
            return self.source.tally.on_program
        return False

    @property
    def preview_tally(self):
        """The current preview tally state of the sender
        """
        if self.source is not None:
            return self.source.tally.on_preview
        return False

    @property
    def has_any_frame(self):
        return self.has_video_frame or self.has_audio_frame

    def open(self):
        """Open the sender
        """
        self._open()

    def close(self):
        """Close the sender and free all resources
        """
        self._close()

    def __enter__(self):
        self._open()
        return self

    def __exit__(self, *args):
        self._close()

    cdef void _open(self) except *:
        if self._running:
            return
        if not self.has_video_frame and not self.has_audio_frame:
            raise_exception('Cannot start sender. No frame objects')
        self._running = True
        cdef NDIlib_send_instance_t ptr
        cdef void* source_ptr
        try:
            if self.has_video_frame:
                self.video_frame._set_sender_status(True)
            if self.has_audio_frame:
                self.audio_frame._set_sender_status(True)
            self.send_create.clock_video = self.clock_video
            self.send_create.clock_audio = self.clock_audio
            self.ptr = NDIlib_send_create(&(self.send_create))
            if self.ptr is NULL:
                raise_mem_err()

            # Cast from void* to avoid clang "const" compile errors
            source_ptr = <void*>NDIlib_send_get_source_name(self.ptr)
            self.source_ptr = <NDIlib_source_t*>source_ptr
            assert self.source_ptr is not NULL
            self.source = Source.create_no_parent(self.source_ptr)
        except Exception as exc:
            print('caught exc: ', exc)
            self._running = False
            ptr = self.ptr
            self.ptr = NULL
            if ptr is not NULL:
                NDIlib_send_destroy(ptr)
            self.video_frame._destroy()
            self.video_frame._set_sender_status(False)
            self.audio_frame._destroy()
            self.audio_frame._set_sender_status(False)
            raise

    cdef void _close(self) except *:
        if not self._running:
            return
        self._running = False
        cdef NDIlib_send_instance_t ptr = self.ptr
        self.ptr = NULL
        if ptr is not NULL:
            NDIlib_send_send_video_async_v2(ptr, NULL)
            self._clear_async_video_status()
            NDIlib_send_destroy(ptr)
        if self.has_video_frame:
            self.video_frame._destroy()
            self.video_frame._set_sender_status(False)
        if self.has_audio_frame:
            self.audio_frame._destroy()
            self.audio_frame._set_sender_status(False)

    cpdef set_video_frame(self, VideoSendFrame vf):
        """Set the :attr:`video_frame`
        """
        if self._running:
            raise Exception('Cannot add frame while sender is open')
        self.video_frame = vf
        self.has_video_frame = vf is not None

    cpdef set_audio_frame(self, AudioSendFrame af):
        """Set the :attr:`audio_frame`
        """
        if self._running:
            raise Exception('Cannot add frame while sender is open')
        self.audio_frame = af
        self.has_audio_frame = af is not None

    cdef bint _check_running(self) nogil except *:
        if not self._running:
            return False
        if self.ptr is NULL:
            raise_exception('ptr is NULL')
        return True

    cdef void _set_async_video_sender(self, VideoSendFrame_item_s* item) nogil except *:
        self._clear_async_video_status()
        self.last_async_sender = item

    cdef void _clear_async_video_status(self) nogil except *:
        cdef VideoSendFrame_item_s* item = self.last_async_sender
        if item is NULL:
            return
        self.last_async_sender = NULL
        self.video_frame._on_sender_write(item)

    def write_video_and_audio(self, cnp.uint8_t[:] video_data, cnp.float32_t[:,:] audio_data):
        """Write and send the given video and audio data

        The video data will be sent asynchronously (as described in
        :meth:`write_video_async`).

        Arguments:
            video_data: A 1-d array or memoryview of unsigned 8-bit integers
                formatted as described in :class:`.wrapper.ndi_structs.FourCC`
            audio_data: A 2-d array or memoryview of 32-bit floats with shape
                ``(num_channels, num_samples)``

        """
        return self._write_video_and_audio(video_data, audio_data)

    cdef bint _write_video_and_audio(
        self,
        cnp.uint8_t[:] video_data,
        cnp.float32_t[:,:] audio_data,
    ) except *:
        if not self._check_running():
            return False
        cdef VideoSendFrame_item_s* vid_item
        cdef AudioSendFrame_item_s* aud_item
        cdef NDIlib_video_frame_v2_t* vid_ptr = self.video_frame.ptr
        cdef NDIlib_audio_frame_v3_t aud_send_frame
        cdef bint vid_result = True, aud_result = True

        vid_item = self.video_frame._prepare_buffer_write()
        aud_item = self.audio_frame._prepare_buffer_write()
        cdef Py_ssize_t* outer_shape = self.audio_frame.send_status.shape
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
            NDIlib_send_send_audio_v3(self.ptr, &aud_send_frame)
            self._clear_async_video_status()
            self.audio_frame._on_sender_write(aud_item)

            vid_ptr.p_data = vid_item.frame_ptr.p_data
            NDIlib_send_send_video_async_v2(self.ptr, vid_ptr)
            self._set_async_video_sender(vid_item)

        return vid_result and aud_result

    def write_video(self, cnp.uint8_t[:] data):
        """Write the given video data and send it

        Arguments:
            data: A 1-d array or memoryview of unsigned 8-bit integers
                formatted as described in :class:`.wrapper.ndi_structs.FourCC`
        """
        return self._write_video(data)

    cdef bint _write_video(self, cnp.uint8_t[:] data) except *:
        if not self._check_running():
            return False
        cdef VideoSendFrame_item_s* item = self.video_frame._prepare_buffer_write()
        if item is NULL:
            raise_exception('send_status is NULL')
        cdef cnp.uint8_t[:] vid_memview = self.video_frame

        with nogil:
            vid_memview[...] = data
            self.video_frame._set_buffer_write_complete(item)
            NDIlib_send_send_video_v2(self.ptr, item.frame_ptr)
            self._clear_async_video_status()
            self.video_frame._on_sender_write(item)
        return True

    def write_video_async(self, cnp.uint8_t[:] data):
        """Write the given video data and send it asynchronously

        This call will return immediately and the required operations on the
        data will be handled separately by the |NDI| library.

        .. note::

            This is not an :keyword:`async def` function

        Arguments:
            data: A 1-d array or memoryview of unsigned 8-bit integers
                formatted as described in :class:`.wrapper.ndi_structs.FourCC`

        """
        return self._write_video_async(data)

    cdef bint _write_video_async(self, cnp.uint8_t[:] data) except *:
        if not self._check_running():
            return False
        cdef VideoSendFrame_item_s* item = self.video_frame._prepare_buffer_write()
        if item is NULL:
            raise_exception('send_status is NULL')
        cdef cnp.uint8_t[:] vid_memview = self.video_frame

        with nogil:
            vid_memview[...] = data
            self.video_frame._set_buffer_write_complete(item)
            NDIlib_send_send_video_async_v2(self.ptr, item.frame_ptr)
            self._set_async_video_sender(item)
        return True

    def send_video(self):
        return self._send_video()

    def send_video_async(self):
        return self._send_video_async()

    cdef bint _send_video(self) except *:
        if not self._check_running():
            return False
        if not self.video_frame._send_frame_available():
            return False
        cdef VideoSendFrame_item_s* item = self.video_frame._get_send_frame()
        if item is NULL:
            raise_exception('no send pointer')
        NDIlib_send_send_video_v2(self.ptr, item.frame_ptr)
        self._clear_async_video_status()
        self.video_frame._on_sender_write(item)
        return True

    cdef bint _send_video_async(self) except *:
        if not self._check_running():
            return False
        if not self.video_frame._send_frame_available():
            return False
        cdef VideoSendFrame_item_s* item = self.video_frame._get_send_frame()
        if item is NULL:
            raise_exception('no send pointer')
        NDIlib_send_send_video_async_v2(self.ptr, item.frame_ptr)
        self._set_async_video_sender(item)
        return True

    def write_audio(self, cnp.float32_t[:,:] data):
        """Write the given audio data and send it

        Arguments:
            data: A 2-d array or memoryview of 32-bit floats with shape
                ``(num_channels, num_samples)``
        """
        return self._write_audio(data)

    cdef bint _write_audio(self, cnp.float32_t[:,:] data) except *:
        if not self._check_running():
            return False
        cdef AudioSendFrame_item_s* item = self.audio_frame._prepare_buffer_write()
        if item is NULL:
            raise_exception(b'send_status is NULL')
        cdef cnp.float32_t[:,:] aud_memview = self.audio_frame
        cdef NDIlib_audio_frame_v3_t send_frame

        with nogil:
            audio_frame_copy(item.frame_ptr, &send_frame)
            self.audio_frame._set_shape_from_memview(item, data)
            aud_memview[...] = data
            self.audio_frame._set_buffer_write_complete(item)
            send_frame.p_data = <uint8_t*>item.frame_ptr.p_data
            NDIlib_send_send_audio_v3(self.ptr, &send_frame)
            self._clear_async_video_status()
            self.audio_frame._on_sender_write(item)
        return True

    def send_audio(self):
        return self._send_audio()

    cdef bint _send_audio(self) except *:
        if not self._check_running():
            return False
        if not self.audio_frame._send_frame_available():
            return False
        cdef AudioSendFrame_item_s* item = self.audio_frame._get_send_frame()
        if item is NULL:
            raise_exception('no send pointer')
        NDIlib_send_send_audio_v3(self.ptr, item.frame_ptr)
        self._clear_async_video_status()
        self.audio_frame._on_sender_write(item)
        return True

    def send_metadata(self, str tag, dict attrs):
        return self._send_metadata(tag, attrs)

    cdef bint _send_metadata(self, str tag, dict attrs) except *:
        self.metadata_frame._clear()
        self.metadata_frame.tag = tag
        self.metadata_frame.attrs.update(attrs)
        return self._send_metadata_frame(self.metadata_frame)

    def send_metadata_frame(self, MetadataSendFrame mf):
        return self._send_metadata_frame(mf)

    cdef bint _send_metadata_frame(self, MetadataSendFrame mf) except *:
        if not self._check_running():
            return False
        if not mf._serialize():
            return False
        NDIlib_send_send_metadata(self.ptr, mf.ptr)
        self._clear_async_video_status()
        return True

    def get_num_connections(self, double timeout):
        cdef uint32_t timeout_ms = lround(timeout)
        return self._get_num_connections(timeout_ms)

    cdef int _get_num_connections(self, uint32_t timeout_ms) nogil except *:
        return NDIlib_send_get_no_connections(self.ptr, timeout_ms)

    def update_tally(self, double timeout):
        cdef uint32_t timeout_ms = lround(timeout)
        return self._update_tally(timeout_ms)

    cdef bint _update_tally(self, uint32_t timeout_ms) nogil except *:
        if not self._check_running():
            self.source.tally.on_program = False
            self.source.tally.on_preview = False
            return False
        cdef NDIlib_tally_t* tally = &(self.source.tally)
        cdef bint pgm = tally.on_program, pvw = tally.on_preview
        NDIlib_send_get_tally(self.ptr, tally, timeout_ms)
        cdef bint changed = pgm is not tally.on_program or pvw is not tally.on_preview
        return changed
