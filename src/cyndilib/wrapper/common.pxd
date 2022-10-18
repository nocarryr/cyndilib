# cython: language_level=3
# distutils: language = c++

from libc.stdlib cimport malloc, free

cdef extern from 'Python.h':
    ctypedef struct PyObject
    PyObject *PyExc_Exception
    PyObject *PyExc_ValueError
    PyObject *PyExc_TypeError
    PyObject *PyExc_MemoryError
    PyObject *PyExc_ZeroDivisionError


cdef inline int raise_withgil(PyObject *error, char *msg) except -1 with gil:
    raise (<object>error)(msg.decode('ascii'))

cdef inline int raise_exception(char *msg) nogil except -1:
    raise_withgil(PyExc_Exception, msg)

cdef inline int raise_mem_err() nogil except -1:
    raise_withgil(PyExc_MemoryError, '')


cdef inline void* mem_alloc(size_t c) nogil:
    return malloc(c)

cdef inline void mem_free(void *p) nogil:
    free(p)
