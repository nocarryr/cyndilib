# cython: language_level=3
# distutils: language = c++

cdef class Callback:
    cdef bint has_callback
    cdef bint is_weakref
    cdef object cb, weak_cb

    cdef void set_callback(self, object cb) except *
    cdef void remove_callback(self) except *
    cdef void trigger_callback(self) except *

cdef class WeakMethod:
    cdef object obj_ref, func_ref, meth_type
    cdef bint alive

    cdef bint trigger_callback(self) except *
