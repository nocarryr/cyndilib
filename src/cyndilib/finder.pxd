# cython: language_level=3
# distutils: language = c++

from libcpp.string cimport string as cpp_string
from libcpp.list cimport list as cpp_list
from libcpp.utility cimport pair as cpp_pair
from libcpp.map cimport map as cpp_map

from .wrapper cimport *
from .locks cimport RLock, Condition, Event

ctypedef cpp_list[cpp_string] cpp_str_list
ctypedef cpp_map[cpp_string, NDIlib_source_t*] source_map_t
ctypedef cpp_pair[cpp_string, NDIlib_source_t*] source_pair_t

# cdef extern from "<mutex>" namespace "std" nogil:
#     cdef cppclass mutex:
#         mutex() except +
#         mutex(const mutex&) except +
#         mutex& operator=(const mutex&)# = delete
#
#         void lock()
#         bint try_lock()
#         void unlock()
#
#     cdef cppclass unique_lock[Mutex]:
#       unique_lock(Mutex&)
#       void unlock()
#
# cdef extern from "<condition_variable>" namespace "std" nogil:
#     cdef cppclass condition_variable:
#         condition_variable() except +
#         void notify_one()
#         void notify_all()
#         void wait(unique_lock[mutex]&)

cdef class Source:
    cdef NDIlib_source_t* ptr
    cdef readonly str name

    @staticmethod
    cdef Source create(NDIlib_source_t* ptr, str name)


cdef class Finder:
    cdef NDIlib_find_instance_t find_p
    cdef NDIlib_source_t* source_ptr
    # cdef readonly list source_names
    cdef cpp_str_list source_names
    cdef source_map_t source_map
    cdef readonly RLock lock
    cdef readonly Condition notify
    cdef readonly size_t num_sources
    # cdef mutex lock
    # cdef mutex notify_lock
    # cdef condition_variable notify
    cdef bint _initial_source_get
    cdef readonly Event finder_thread_running
    cdef readonly object finder_thread

    cpdef get_source_names(self)
    cpdef Source get_source(self, str name)
    cdef NDIlib_source_t* _get_source(self, cpp_string name) nogil except *
    cdef bint _update_sources(self) nogil except *
    cdef void _wait(self) nogil except *
    cdef bint _wait_timed(self, float timeout) nogil except *
    cdef bint _wait_for_sources(self, uint32_t timeout_ms) nogil except *
    cdef void build_finder(self) except *
    cdef void __notify_acquire(self) nogil except *
    cdef void __notify_notify(self) nogil except *
    cdef void __notify_notify_and_release(self) nogil except *
    cdef void __notify_release(self) nogil except *
