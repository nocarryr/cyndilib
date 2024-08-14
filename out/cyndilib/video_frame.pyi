# import _cython_3_0_10
from _typeshed import Incomplete
from typing_extensions import Buffer
from fractions import Fraction
from typing import Any, ClassVar
import numpy.typing as npt
import numpy as np

from cyndilib.wrapper import FourCC
from cyndilib.locks import RLock, Condition

# __reduce_cython__: _cython_3_0_10.cython_function_or_method
# __setstate_cython__: _cython_3_0_10.cython_function_or_method
# __test__: dict

class VideoFrame:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    fourcc: FourCC
    def __init__(self, *args, **kwargs) -> None: ...
    @property
    def xres(self) -> int: ...
    @property
    def yres(self) -> int: ...
    def get_buffer_size(self) -> int: ...
    def get_data_size(self) -> int: ...
    def get_format_string(self) -> str:
        '''Get the video format as a string based off of resolution, frame rate
                and field format ("1080i59.94", etc)
        '''
    def get_fourcc(self) -> FourCC:
        """Get the :class:`~.wrapper.ndi_structs.FourCC` format type
        """
    def get_frame_rate(self) -> Fraction:
        """Get the video frame rate
        """
    def get_line_stride(self) -> int: ...
    def get_resolution(self) -> tuple[int, int]:
        """Get the video resolution as a tuple of ``(width, height)``
        """
    def get_timecode_posix(self) -> float:
        """Get the current :term:`timecode <ndi-timecode>` converted to float
        seconds (posix)
        """
    def get_timestamp_posix(self) -> float:
        """Get the current :term:`timestamp <ndi-timestamp>` converted to float
        seconds (posix)
        """
    def set_fourcc(self, value: FourCC) -> None:
        """Set the :class:`~.wrapper.ndi_structs.FourCC` format type
        """
    def set_frame_rate(self, value: Fraction) -> None:
        """set_frame_rate(self, value: Fraction)
        Set the video frame rate
        """
    def set_resolution(self, xres: int, yres: int) -> None:
        """Set the video resolution
        """
    def __reduce__(self): ...


class VideoFrameSync(VideoFrame):
    shape: tuple[int]
    strides: tuple[int]
    def __init__(self, *args, **kwargs) -> None: ...
    def get_array(self) -> npt.NDArray[np.uint8]:
        """Get the video frame data as an :class:`numpy.ndarray` of unsigned
        8-bit integers
        """
    def __reduce__(self): ...


class VideoRecvFrame(VideoFrame):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    current_frame_data: npt.NDArray[np.uint8]
    max_buffers: int
    read_lock: RLock
    read_ready: Condition
    write_lock: RLock
    write_ready: Condition
    def __init__(self, *args, **kwargs) -> None: ...
    def buffer_full(self) -> bool:
        """Returns True if the buffers are all in use
        """
    def fill_p_data(self, dest: Buffer) -> bool:
        """Copy the first buffered frame data into the given
        destination array (or memoryview).

        The array should be typed as unsigned 8-bit integers sized to match
        that of :meth:`~VideoFrame.get_buffer_size`
        """
    def get_buffer_depth(self) -> int:
        """Get the number of buffered frames
        """
    def get_view_count(self) -> int: ...
    def skip_frames(self, eager: bool) -> int:
        """Discard buffered frame(s)

        If the buffers remain full and the application can't keep up,
        this can be used as a last resort.

        Arguments:
            eager (bool): If True, discard all buffered frames except one
                (the most recently received). If False, only discard one frame

        Returns the number of frames skipped
        """
    def __reduce__(self): ...


class VideoSendFrame(VideoFrame):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self, *args, **kwargs) -> None: ...
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
    def write_data(self, data: Buffer) -> None:
        """Write a frame of video data to the internal buffer

        The buffered data will then be sent on the next call to
        :meth:`.sender.Sender.send_video` or :meth:`.sender.Sender.send_video_async`

        Arguments:
            data: A 1-d array or memoryview of unsigned 8-bit integers
                formatted as described in :class:`.wrapper.ndi_structs.FourCC`

        .. note::

            This method is available for flexibility, but using
            :meth:`.sender.Sender.write_video` or :meth:`.sender.Sender.write_video_async`
            may be more desirable as the video data will be buffered and
            sent immediately

        """
    def __reduce__(self): ...
