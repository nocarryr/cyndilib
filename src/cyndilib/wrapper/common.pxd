# cython: language_level=3
# distutils: language = c++

from libc.stdlib cimport malloc, free
from cpython cimport PyObject

cdef extern from 'Python.h':
    PyObject *PyExc_Exception
    PyObject *PyExc_RuntimeError
    PyObject *PyExc_KeyError
    PyObject *PyExc_IndexError
    PyObject *PyExc_ValueError
    PyObject *PyExc_TypeError
    PyObject *PyExc_MemoryError
    PyObject *PyExc_ZeroDivisionError


cdef inline int raise_withgil(PyObject *error, char *msg) except -1 with gil:
    raise (<object>error)(msg.decode('ascii'))

cdef inline int raise_exception(char *msg) except -1 nogil:
    raise_withgil(PyExc_Exception, msg)

cdef inline int raise_mem_err() except -1 nogil:
    raise_withgil(PyExc_MemoryError, b'')


cdef inline void* mem_alloc(size_t c) noexcept nogil:
    return malloc(c)

cdef inline void mem_free(void *p) noexcept nogil:
    free(p)
