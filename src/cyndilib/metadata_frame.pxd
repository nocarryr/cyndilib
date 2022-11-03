# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

from .wrapper cimport *

cdef class MetadataFrame:
    cdef NDIlib_metadata_frame_t* ptr
    cdef readonly str tag
    cdef readonly dict attrs
    cdef char* _get_data(self) nogil
    cdef void _set_data(self, char* data) nogil
    cdef int64_t _get_timecode(self) nogil
    cdef void _set_timecode(self, int64_t value) nogil

cdef class MetadataRecvFrame(MetadataFrame):
    cdef bint can_receive(self) nogil except *
    cdef void _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except *
    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except *
