from libc.string cimport strdup
import threading


cdef NDIlib_frame_type_e recv_frame_type_cast(ReceiveFrameType ft) nogil except *:
    if ft == ReceiveFrameType.recv_video:
        return NDIlib_frame_type_video
    elif ft == ReceiveFrameType.recv_audio:
        return NDIlib_frame_type_audio
    elif ft == ReceiveFrameType.recv_metadata:
        return NDIlib_frame_type_metadata
    elif ft == ReceiveFrameType.recv_status_change:
        return NDIlib_frame_type_status_change
    elif ft == ReceiveFrameType.recv_error:
        return NDIlib_frame_type_error
    elif ft == ReceiveFrameType.nothing:
        return NDIlib_frame_type_none
    # return NULL

cdef ReceiveFrameType recv_frame_type_uncast(NDIlib_frame_type_e ft) nogil except *:
    if ft == NDIlib_frame_type_video:
        return ReceiveFrameType.recv_video
    elif ft == NDIlib_frame_type_audio:
        return ReceiveFrameType.recv_audio
    elif ft == NDIlib_frame_type_metadata:
        return ReceiveFrameType.recv_metadata
    elif ft == NDIlib_frame_type_status_change:
        return ReceiveFrameType.recv_status_change
    elif ft == NDIlib_frame_type_error:
        return ReceiveFrameType.recv_error
    elif ft == NDIlib_frame_type_none:
        return ReceiveFrameType.nothing
    # return NULL



cdef class RecvCreate:
    # cdef public str source_name
    # cdef public RecvColorFormat color_format
    # cdef public RecvBandwidth bandwidth
    # cdef public bint allow_video_fields
    # cdef public str recv_name

    def __init__(
        self,
        str source_name='',
        color_format=RecvColorFormat.UYVY_BGRA,
        RecvBandwidth bandwidth=RecvBandwidth.highest,
        bint allow_video_fields=True,
        str recv_name=''
    ):
        self.source_name = source_name
        self.color_format = color_format
        self.bandwidth = bandwidth
        self.allow_video_fields = allow_video_fields
        self.recv_name = recv_name

    cdef NDIlib_recv_create_v3_t* build_create_p(self) except *:
        cdef NDIlib_recv_create_v3_t* p = recv_t_create_default()
        # cdef bytes src_name_py = self.source_name.encode()
        # cdef const char* src_name_c = src_name_py

        cdef bytes recv_name_py = self.recv_name.encode()
        cdef const char* recv_name_c = recv_name_py

        # if len(src_name_py):
        #     p.source_to_connect_to.p_ndi_name = src_name_c

        if len(recv_name_py):
            p.p_ndi_recv_name = recv_name_c
        p.color_format = recv_format_cast(self.color_format)
        p.bandwidth = recv_bandwidth_cast(self.bandwidth)
        p.allow_video_fields = self.allow_video_fields

        return p


cdef class Receiver:
    # cdef RecvCreate settings
    # cdef readonly VideoRecvFrame video_frame
    # cdef readonly AudioRecvFrame audio_frame
    # cdef readonly str source_name
    # cdef readonly bint has_video_frame, has_audio_frame, has_metadata_frame
    # cdef NDIlib_recv_instance_t ptr
    # cdef NDIlib_recv_create_v3_t recv_create

    def __init__(
        self,
        str source_name='',
        color_format=RecvColorFormat.UYVY_BGRA,
        RecvBandwidth bandwidth=RecvBandwidth.lowest,
        bint allow_video_fields=True,
        str recv_name=''
    ):
        self.connection_lock = RLock()
        self.connection_notify = Condition(self.connection_lock)
        self._connected = False
        self._probably_connected = False
        self._num_empty_recv = 0
        self.settings = RecvCreate(
            source_name, color_format, bandwidth,
            allow_video_fields, recv_name,
        )
        self.source_name = source_name
        self.has_video_frame = False
        self.has_audio_frame = False
        self.has_metadata_frame = False

        cdef NDIlib_recv_create_v3_t* src_p = self.settings.build_create_p()
        try:
            recv_t_copy(src_p, &(self.recv_create))
        except:
            import traceback
            traceback.print_exc()
            raise
        finally:
            recv_t_destroy(src_p)
        # self._update_source_name()
        self.ptr = NDIlib_recv_create_v3(&(self.recv_create))
        if self.ptr is NULL:
            raise MemoryError()

    def __dealloc__(self):
        cdef NDIlib_recv_instance_t p = self.ptr
        if self.ptr is not NULL:
            self.ptr = NULL
            NDIlib_recv_destroy(p)

    cpdef set_video_frame(self, VideoRecvFrame vf):
        # if self.video_frame is not None:
        #     self.video_ptr = NULL
        self.video_frame = vf
        # if vf is not None:
        #     self.video_ptr = vf.ptr
        self.has_video_frame = vf is not None

    cpdef set_audio_frame(self, AudioRecvFrame af):
        # if self.audio_frame is not None:
        #     self.audio_ptr = NULL
        self.audio_frame = af
        # if af is not None:
        #     self.audio_ptr = af.ptr
        self.has_audio_frame = af is not None

    cpdef connect_to(self, Source src):
        self._connect_to(src.ptr)

    cdef void _connect_to(self, NDIlib_source_t* src) except *:
        cdef bytes src_name = src.p_ndi_name
        self.source_name = src_name.decode()
        # cdef char* src_name = strdup(src.p_ndi_name)
        # self.recv_create.source_to_connect_to.p_ndi_name = src_name
        # self._update_source_name()
        NDIlib_recv_connect(self.ptr, src)
        self._probably_connected = True
        self._set_connected(True)

    def disconnect(self):
        self._disconnect()

    cdef void _disconnect(self) nogil except *:
        # if not self._is_connected():
        #     return
        NDIlib_recv_connect(self.ptr, NULL)
        self._probably_connected = False
        self._num_empty_recv = 0
        self._set_connected(False)

    def reconnect(self):
        self._reconnect()

    cdef void _reconnect(self) nogil except *:
        if self._is_connected():
            return
        NDIlib_recv_connect(self.ptr, &(self.recv_create.source_to_connect_to))
        self._is_connected()

    cdef void _update_source_name(self) except *:
        pass
        # if self.recv_create.source_to_connect_to is NULL:
        #     return
        # if self.recv_create.source_to_connect_to.p_ndi_name is NULL:
        #     return
        # cdef bytes name_c = self.recv_create.source_to_connect_to.p_ndi_name
        # cdef str name_py = name_c.decode()
        # self.source_name = self.settings.source_name = name_py

    def is_connected(self):
        return self._is_connected()

    cdef bint _is_connected(self) nogil except *:
        cdef bint r = self._get_num_connections() > 0
        if r is not self._connected:
            self._set_connected(r)
        return r

    cdef void _set_connected(self, bint value) nogil except *:
        if value is self._connected:
            return
        with gil:
            with self.connection_lock:
                self._connected = value
                self.connection_notify.notify_all()

    cdef bint _wait_for_connect(self, float timeout) nogil except *:
        if self._connected:
            return True
        if self._is_connected():
            return True
        cdef bint r
        with gil:
            with self.connection_lock:
                self.connection_lock.wait(timeout)
        return self._connected


    def get_num_connections(self):
        return self._get_num_connections()

    cdef int _get_num_connections(self) nogil except *:
        cdef int r = NDIlib_recv_get_no_connections(self.ptr)
        return r

    cpdef ReceiveFrameType receive(self, ReceiveFrameType recv_type, uint32_t timeout_ms):
        return self._receive(recv_type, timeout_ms)
        # cdef NDIlib_frame_type_e ft = self._receive(recv_type, timeout_ms)
        #
        # return recv_frame_type_uncast(ft)

    cdef ReceiveFrameType _receive(
        self, ReceiveFrameType recv_type, uint32_t timeout_ms
    ) nogil except *:
        cdef NDIlib_video_frame_v2_t* video_ptr
        cdef NDIlib_audio_frame_v3_t* audio_ptr
        cdef NDIlib_metadata_frame_t* metadata_ptr = NULL

        if recv_type & ReceiveFrameType.recv_video and self.has_video_frame:
            video_ptr = self.video_frame.ptr
        else:
            video_ptr = NULL

        if recv_type & ReceiveFrameType.recv_audio and self.has_audio_frame:
            audio_ptr = self.audio_frame.ptr
        else:
            audio_ptr = NULL

        # cdef NDIlib_frame_type_e recv_t
        # recv_t = self._do_receive(video_ptr, audio_ptr, metadata_ptr, timeout_ms)
        # cdef ReceiveFrameType ft = recv_frame_type_uncast(recv_t)
        cdef ReceiveFrameType ft = self._do_receive(
            video_ptr, audio_ptr, metadata_ptr, timeout_ms
        )

        if ft == ReceiveFrameType.recv_video:
            if self.has_video_frame:
                self.video_frame._process_incoming(self.ptr)
            else:
                self.free_video(video_ptr)
        elif ft == ReceiveFrameType.recv_audio:
            if self.has_audio_frame:
                self.audio_frame._process_incoming(self.ptr)
            else:
                self.free_audio(audio_ptr)
        elif ft == ReceiveFrameType.recv_metadata:
            self.free_metadata(metadata_ptr)

        return ft

    cdef ReceiveFrameType _do_receive(
        self,
        NDIlib_video_frame_v2_t* video_frame,
        NDIlib_audio_frame_v3_t* audio_frame,
        NDIlib_metadata_frame_t* metadata_frame,
        uint32_t timeout_ms
    ) nogil except *:
        cdef NDIlib_frame_type_e r = NDIlib_recv_capture_v3(
            self.ptr, video_frame, audio_frame, metadata_frame, timeout_ms
        )
        cdef ReceiveFrameType ft = recv_frame_type_uncast(r)
        if ft & ReceiveFrameType.recv_all:
            self._num_empty_recv = 0
            self._probably_connected = True
        elif ft & ReceiveFrameType.recv_status_change == 0:
            self._num_empty_recv += 1
        return ft

    cdef void free_video(self, NDIlib_video_frame_v2_t* p) nogil except *:
        NDIlib_recv_free_video_v2(self.ptr, p)

    cdef void free_audio(self, NDIlib_audio_frame_v3_t* p) nogil except *:
        NDIlib_recv_free_audio_v3(self.ptr, p)

    cdef void free_metadata(self, NDIlib_metadata_frame_t* p) nogil except *:
        NDIlib_recv_free_metadata(self.ptr, p)

cdef class RecvThreadWorker:
    cdef Receiver receiver
    cdef uint32_t timeout_ms
    cdef ReceiveFrameType recv_frame_type
    cdef bint running

    def __init__(self, Receiver receiver, ReceiveFrameType recv_frame_type, uint32_t timeout_ms):
        self.receiver = receiver
        assert recv_frame_type & (ReceiveFrameType.recv_video | ReceiveFrameType.recv_audio | ReceiveFrameType.recv_metadata)
        self.recv_frame_type = recv_frame_type
        self.timeout_ms = timeout_ms

    cdef void run(self) nogil except *:
        self.running = True
        while self.running:
            if self.receiver._is_connected():
                self.receiver._receive(self.recv_frame_type, self.timeout_ms)
            else:
                self.receiver._wait_for_connect(1)

    cdef void stop(self) nogil except *:
        self.running = False

class RecvThread(threading.Thread):
    def __init__(
        self,
        Receiver receiver,
        uint32_t timeout_ms,
        int recv_frame_type = ReceiveFrameType.recv_video | ReceiveFrameType.recv_audio | ReceiveFrameType.recv_metadata,
    ):
        super().__init__()
        self.worker = RecvThreadWorker(receiver, recv_frame_type, timeout_ms)
        self.stopped = threading.Event()

    def run(self):
        cdef RecvThreadWorker worker = self.worker
        cdef int recv_frame_type = worker.recv_frame_type
        cdef Receiver receiver = worker.receiver

        if recv_frame_type & ReceiveFrameType.recv_video:
            assert receiver.has_video_frame
        if recv_frame_type & ReceiveFrameType.recv_audio:
            assert receiver.has_audio_frame
        worker.run()
        self.stopped.set()

    def stop(self):
        cdef RecvThreadWorker w = self.worker
        w.stop()
        self.stopped.wait()

def test():
    import time
    from cyndilib.finder import Finder


    cdef str src_name = "BIRDDOG-1F8A1 (CAM)"
    finder = Finder()
    src = None
    # finder.open()
    i = 0
    while i<10:
        if i == 0:
            finder.update_sources()
        else:
            finder.wait_for_sources(3)
        for _src in finder.iter_sources():
            if 'CAM' in _src.name:
                src = _src
                break
        if src:
            break
        # src = finder.get_source(src_name)
        # if src:
        #     break
        print(i)
        time.sleep(1)
        i += 1
        # if not src:
        #     finder.wait()
        #     src = finder.get_source(src_name)
    print('src: ', src)
    print('closing finder')
    # finder.close()

    if not src:
        raise Exception('no source')

    print('building receiver')
    cdef ReceiveFrameType recv_type = ReceiveFrameType.recv_all #ReceiveFrameType.recv_video | ReceiveFrameType.recv_audio
    cdef Receiver receiver = Receiver(color_format=RecvColorFormat.RGBX_RGBA)

    cdef VideoRecvFrame vframe = VideoRecvFrame()
    cdef AudioRecvFrame aframe = AudioRecvFrame()
    receiver.set_audio_frame(aframe)
    receiver.set_video_frame(vframe)
    print('connecting src')
    receiver.connect_to(src)
    cdef ReceiveFrameType frame_type
    for i in range(10):
        print('recv.source_name: ', receiver.source_name)
        nc = receiver.get_num_connections()
        connected = receiver.is_connected()
        print(f'connected: {connected}, num_connections: {nc}')
        print('receive..')
        frame_type = receiver._receive(recv_type, 100)
        print('frame_type: ', frame_type)
        # if connected:
        #     break
        time.sleep(1)
    print('exit')
