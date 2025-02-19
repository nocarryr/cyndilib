# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

ctypedef fused uint_ft:
    uint8_t
    uint16_t
