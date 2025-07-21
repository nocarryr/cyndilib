# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS
# distutils: define_macros=CYTHON_TRACE_NOGIL=1

# from cyndilib.wrapper.common cimport *


class InvalidExceptionType(TypeError):
    pass



cdef struct MyStruct:
    int foo
    int bar

# cdef MyStruct my_struct = {'foo': 1, 'bar': 2}



# cdef MyStruct* do_something(
#     PyObject *exc_type,
#     char *msg,
#     bint raise_exc
# ) except NULL nogil:
#     """Raise `exc_type` if the `raise_exc` flag is set
#     Otherwise return a pointer to `my_struct` (defined above)
#     """
#     cdef MyStruct* result = &my_struct
#     if raise_exc:
#         raise_withgil(exc_type, msg)
#     return result


# # This is a bit un-pythonic, but ¯\_(ツ)_/¯
# cdef PyObject* exc_ptr_from_py_obj(object exc_type):
#     if exc_type is Exception:
#         return PyExc_Exception
#     elif exc_type is RuntimeError:
#         return PyExc_RuntimeError
#     elif exc_type is KeyError:
#         return PyExc_KeyError
#     elif exc_type is IndexError:
#         return PyExc_IndexError
#     elif exc_type is ValueError:
#         return PyExc_ValueError
#     elif exc_type is TypeError:
#         return PyExc_TypeError
#     elif exc_type is MemoryError:
#         return PyExc_MemoryError
#     elif exc_type is ZeroDivisionError:
#         return PyExc_ZeroDivisionError

#     raise InvalidExceptionType(repr(exc_type))



# def raise_py_exc(object exc_type, str msg = '1234'):
#     # Get the PyObject* pointer for the `exc_type`
#     cdef PyObject* c_exc_type = exc_ptr_from_py_obj(exc_type)
#     cdef bytes b_msg = msg.encode('UTF-8')
#     cdef char* c_msg = b_msg

#     cdef MyStruct* ptr = NULL

#     with nogil:
#         # First call the function without `raise_exc` set and
#         # make sure it returns what it's supposed to
#         ptr = do_something(c_exc_type, c_msg, False)
#         assert ptr is not NULL
#         assert ptr.foo == my_struct.foo
#         assert ptr.bar == my_struct.bar

#         # Now call it with `raise_exc` set and allow the
#         # exception to propagate up
#         ptr = NULL
#         ptr = do_something(c_exc_type, c_msg, True)
