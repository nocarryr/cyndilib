from __future__ import annotations
# import _cython_3_0_10
from typing_extensions import Buffer
import numpy.typing as npt
import numpy as np

from cyndilib import locks

# __reduce_cython__: _cython_3_0_10.cython_function_or_method
# __setstate_cython__: _cython_3_0_10.cython_function_or_method
# __test__: dict
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


class AudioFrameSync(AudioFrame):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    shape: tuple[int, int]
    strides: tuple[int, int]

    def get_array(self) -> _FloatArray:
        """Get the current data as a :class:`ndarray` of float32 with shape
        (:attr:`~AudioFrame.num_channels`, :attr:`~AudioFrame.num_samples`)
        """



class AudioRecvFrame(AudioFrame):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    current_frame_data: npt.NDArray
    current_timecode: int
    current_timestamp: int
    max_buffers: int
    @property
    def read_length(self) -> int: ...
    read_lock: locks.RLock
    read_ready: locks.Condition
    view_count: int
    write_lock: locks.RLock
    write_ready: locks.Condition

    def fill_all_read_data(self, dest: Buffer|_FloatArray, timestamps: Buffer|_IntArray) -> tuple[int, int]:
        """Copy all available read data into the given *dest* array and the
        item :term:`timestamps <ndi-timestamp>` into the given *timestamps* array.

        The shape of the *dest* array on the first axis should equal
        :attr:`num_channels` and the second should be at least :attr:`read_length`.

        The *timestamps* array should be of at least :attr:`read_length` size

        Returns a tuple of

        * ``nbfrs``: The number of buffer items filled
        * ``col_idx``: The index of the last column (last axis) filled on the result

        """
    def fill_read_data(self, dest: Buffer|_FloatArray) -> int:
        """Copy the first available read item in the buffer into the given array

        The array must equal that of :meth:`get_read_shape`

        Returns the :term:`timestamp <ndi-timestamp>` of the data
        """
    def get_all_read_data(self) -> tuple[_FloatArray, _IntArray]:
        """Get all available data in the read buffer as a 2-d array

        The shape of the result will be (:attr:`~AudioFrame.num_channels`, :attr:`read_length`)

        Returns a tuple of

        * ``data``: The sample data
        * ``timestamps``: An array of :term:`timestamps <ndi-timestamp>` for each
            column in ``data``

        """
    def get_buffer_depth(self) -> int:
        """The current number of frames available in the read buffer
        """
    def get_frame_timestamps(self) -> list[int]:
        """Get a list of the :term:`frame timestamps <ndi-timestamp>` in the
        read buffer
        """
    def get_read_data(self) -> tuple[_FloatArray, _IntArray]:
        """Get the first available item in the read buffer

        Returns a tuple of

        * ``frame_data``: A 2-d array of float32 with shape of :meth:`get_read_shape`
        * ``timestamp``: The :term:`timestamp <ndi-timestamp>` of the data
        """
    def get_read_length(self) -> int: ...
    def get_read_shape(self) -> tuple[int, int]:
        """Get the read array shape as ``(num_channels, num_samples)``
        """


class AudioSendFrame(AudioFrame):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self, max_num_samples: int=..., *args, **kwargs) -> None: ...
    @property
    def attached_to_sender(self) -> bool: ...
    max_num_samples: int
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
    def set_max_num_samples(self, n: int) -> None:
        """Set the :attr:`max_num_samples`, altering the :attr:`shape`
        expected for data writes

        .. note::

            This method may only be called before calling
            :meth:`.sender.Sender.set_audio_frame`

        """
    def write_data(self, data: Buffer|_FloatArray) -> None:
        """Write audio data to the internal buffer

        The buffered data will then be sent on the next call to
        :meth:`.sender.Sender.send_audio`

        Arguments:
            data: A 2-d array or memoryview of 32-bit floats with shape
                ``(num_channels, num_samples)``

        .. note::

            This method is available for flexibility, but using
            :meth:`.sender.Sender.write_audio`
            may be more desirable as the audio data will be buffered and
            sent immediately

        """
