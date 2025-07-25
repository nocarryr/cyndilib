# import _cython_3_0_10
from typing_extensions import Self
from _typeshed import ReadableBuffer

import numpy.typing as npt
import numpy as np

from cyndilib.finder import Source
from cyndilib.audio_frame import AudioSendFrame
from cyndilib.video_frame import VideoSendFrame
from cyndilib.metadata_frame import MetadataSendFrame

_UintArray = npt.NDArray[np.uint8]
_FloatArray = npt.NDArray[np.float32]


class Sender:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    audio_frame: AudioSendFrame|None
    clock_audio: bool
    clock_video: bool
    has_audio_frame: bool
    has_video_frame: bool
    _running: bool
    ndi_groups: str
    ndi_name: str
    source: Source|None
    video_frame: VideoSendFrame|None
    def __init__(
        self,
        ndi_name: str,
        ndi_groups: str = ...,
        clock_video: bool = ...,
        clock_audio: bool = ...,
    ) -> None: ...
    @property
    def has_any_frame(self) -> bool: ...
    @property
    def name(self) -> str: ...
    @property
    def preview_tally(self) -> bool: ...
    @property
    def program_tally(self) -> bool: ...
    def close(self) -> None: ...
    def get_num_connections(self, timeout: float) -> int: ...
    def open(self) -> None: ...
    def send_audio(self) -> bool: ...
    def send_metadata(self, tag: str, attrs: dict) -> bool: ...
    def send_metadata_frame(self, mf: MetadataSendFrame) -> bool: ...
    def send_video(self) -> bool: ...
    def send_video_async(self) -> bool: ...
    def set_audio_frame(self, af: AudioSendFrame) -> None: ...
    def set_video_frame(self, vf: VideoSendFrame) -> None: ...
    def update_tally(self, timeout: float) -> bool: ...
    def write_audio(self, data: ReadableBuffer|_FloatArray) -> bool: ...
    def write_video(self, data: ReadableBuffer|_UintArray) -> bool: ...
    def write_video_and_audio(self, video_data: ReadableBuffer|_UintArray, audio_data: ReadableBuffer|_FloatArray) -> bool: ...
    def write_video_async(self, data: ReadableBuffer|_UintArray) -> bool: ...
    def __enter__(self) -> Self: ...
    def __exit__(self, *args) -> None: ...
    def __reduce__(self): ...
