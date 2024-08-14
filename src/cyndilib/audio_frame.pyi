from __future__ import annotations
# import _cython_3_0_10
from typing_extensions import Buffer
import numpy.typing as npt
import numpy as np

from . import locks


_FloatArray = npt.NDArray[np.float32]
_IntArray = npt.NDArray[np.integer]

class AudioFrame:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self, *args, **kwargs) -> None: ...
    @property
    def channel_stride(self) -> int: ...
    @channel_stride.setter
    def channel_stride(self, value: int) -> None: ...
    @property
    def num_channels(self) -> int: ...
    @num_channels.setter
    def num_channels(self, value: int) -> None: ...
    @property
    def num_samples(self) -> int: ...
    @num_samples.setter
    def num_samples(self, value: int) -> None: ...
    @property
    def sample_rate(self) -> int: ...
    @sample_rate.setter
    def sample_rate(self, value: int) -> None: ...
    @property
    def timecode(self) -> int: ...
    @timecode.setter
    def timecode(self, value: int) -> None: ...
    @property
    def timestamp(self) -> int: ...
    @timestamp.setter
    def timestamp(self, int) -> None: ...
    def __reduce__(self): ...


class AudioFrameSync(AudioFrame, Buffer):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    shape: tuple[int, int]
    strides: tuple[int, int]
    def get_array(self) -> _FloatArray: ...


class AudioRecvFrame(AudioFrame, Buffer):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    current_frame_data: npt.NDArray
    current_timecode: int
    current_timestamp: int
    max_buffers: int
    read_lock: locks.RLock
    read_ready: locks.Condition
    view_count: int
    write_lock: locks.RLock
    write_ready: locks.Condition
    @property
    def read_length(self) -> int: ...
    def fill_all_read_data(self, dest: Buffer|_FloatArray, timestamps: Buffer|_IntArray) -> tuple[int, int]: ...
    def fill_read_data(self, dest: Buffer|_FloatArray) -> int: ...
    def get_all_read_data(self) -> tuple[_FloatArray, _IntArray]: ...
    def get_buffer_depth(self) -> int: ...
    def get_frame_timestamps(self) -> list[int]: ...
    def get_read_data(self) -> tuple[_FloatArray, _IntArray]: ...
    def get_read_length(self) -> int: ...
    def get_read_shape(self) -> tuple[int, int]: ...


class AudioSendFrame(AudioFrame, Buffer):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    max_num_samples: int
    def __init__(self, max_num_samples: int=..., *args, **kwargs) -> None: ...
    @property
    def attached_to_sender(self) -> bool: ...
    @property
    def ndim(self) -> int: ...
    @property
    def read_index(self) -> int: ...
    @property
    def shape(self) -> tuple[int,...]: ...
    @property
    def strides(self) -> tuple[int,...]: ...
    @property
    def write_index(self) -> int: ...
    def destroy(self) -> None: ...
    def get_write_available(self) -> bool: ...
    def set_max_num_samples(self, n: int) -> None: ...
    def write_data(self, data: Buffer|_FloatArray) -> None: ...