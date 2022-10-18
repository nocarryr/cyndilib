# cython: language_level=3
# distutils: language = c++

cdef struct rational_t:
    int numerator
    int denominator

ctypedef rational_t frame_rate_t

ctypedef fused frame_rate_ft:
    frame_rate_t
    int[2]
