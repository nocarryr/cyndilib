# import _cython_3_0_10

from typing import Iterator, TYPE_CHECKING
from typing_extensions import Self, deprecated
import threading

from .locks import RLock, Condition, Event

if TYPE_CHECKING:
    from .callback import _CallbackType

class Source:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    name: str
    valid: bool
    def __init__(self) -> None: ...
    @property
    def host_name(self) -> str: ...
    @property
    def preview_tally(self) -> bool: ...
    @property
    def program_tally(self) -> bool: ...
    @property
    def stream_name(self) -> str: ...
    @deprecated("Use Receiver.set_source_tally_preview()")
    def set_preview_tally(self, value: bool) -> None: ...
    @deprecated("Use Receiver.set_source_tally_program()")
    def set_program_tally(self, value: bool) -> None: ...
    def update(self) -> bool: ...
    def __reduce__(self): ...


class Finder:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    finder_thread: FinderThread|None
    finder_thread_running: Event
    is_open: bool
    lock: RLock
    notify: Condition
    num_sources: int
    def __init__(self) -> None: ...
    def close(self) -> None: ...
    def get_source(self, name: str) -> Source: ...
    def get_source_names(self) -> list[str]: ...
    def iter_sources(self) -> Iterator[Source]: ...
    def open(self) -> None: ...
    def set_change_callback(self, cb: _CallbackType) -> None: ...
    def update_sources(self) -> list[str]: ...
    def wait(self, timeout: float|None = ...) -> bool: ...
    def wait_for_sources(self, timeout: float) -> bool: ...
    def __enter__(self) -> Self: ...
    def __exit__(self, *args) -> None: ...
    def __iter__(self) -> Iterator[Source]: ...
    def __len__(self) -> int: ...
    def __reduce__(self): ...


class FinderThread(threading.Thread):
    def __init__(self, finder: Finder) -> None: ...
    def run(self) -> None: ...
    def stop(self) -> None: ...

class FinderThreadWorker:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self, finder: Finder) -> None: ...
    def stop(self) -> None: ...
    def __reduce__(self): ...
