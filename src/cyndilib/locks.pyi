# import _cython_3_0_10
from typing_extensions import Self


class Lock:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    name: str
    def __init__(self) -> None: ...
    @property
    def locked(self) -> bool: ...
    def acquire(self, block: bool = ..., timeout: float = ...) -> bool: ...
    def release(self) -> bool: ...
    def _is_owned(self) -> bool: ...
    def __enter__(self) -> Self: ...
    def __exit__(self, *args) -> None: ...
    def __reduce__(self): ...

class RLock(Lock):
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self) -> None: ...

class Condition:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    rlock: RLock
    def __init__(self, init_lock: RLock|None = ..., *args, **kwargs) -> None: ...
    def acquire(self, block: bool = ..., timeout: float = ...) -> bool: ...
    def notify(self, n: int = ...) -> None: ...
    def notify_all(self) -> None: ...
    def release(self) -> bool: ...
    def wait(self, timeout=...) -> bool: ...
    def wait_for(self, predicate, timeout=...) -> bool: ...
    def __enter__(self) -> Self: ...
    def __exit__(self, *args) -> None: ...
    def __reduce__(self): ...

class Event:
    # __pyx_vtable__: ClassVar[PyCapsule] = ...
    def __init__(self) -> None: ...
    def clear(self) -> None: ...
    def is_set(self) -> bool: ...
    def set(self) -> None: ...
    def wait(self, timeout: float|None = ...) -> bool: ...
    def __reduce__(self): ...