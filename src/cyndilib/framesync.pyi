# import _cython_3_0_10
import threading

from typing import TYPE_CHECKING

from .wrapper import FrameFormat
from .audio_frame import AudioFrameSync
from .video_frame import VideoFrameSync
from .receiver import Receiver, ReceiveFrameType

if TYPE_CHECKING:
    from .callback import _CallbackType


class FrameSync:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    audio_frame: AudioFrameSync|None
    receiver: Receiver
    video_frame: VideoFrameSync|None
    def __init__(self, receiver: Receiver) -> None: ...
    def audio_samples_available(self) -> int: ...
    def capture_audio(self, no_samples: int) -> int: ...
    def capture_available_audio(self) -> int: ...
    def capture_video(self, fmt: FrameFormat = ...) -> None: ...
    def set_audio_frame(self, audio_frame: AudioFrameSync) -> None: ...
    def set_video_frame(self, video_frame: VideoFrameSync) -> None: ...
    def __reduce__(self): ...

class FrameSyncThread(threading.Thread):
    def __init__(self, frame_sync: FrameSync, ft: ReceiveFrameType) -> None: ...
    def remove_callback(self) -> None: ...
    def run(self) -> None: ...
    def set_callback(self, cb: _CallbackType) -> None: ...
    def stop(self) -> None: ...

class FrameSyncWorker:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self, *args, **kwargs) -> None: ...
    def __reduce__(self): ...

class AudioWorker(FrameSyncWorker):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self, *args, **kwargs) -> None: ...
    def __reduce__(self): ...

class VideoWorker(FrameSyncWorker):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self, *args, **kwargs) -> None: ...
    def __reduce__(self): ...
