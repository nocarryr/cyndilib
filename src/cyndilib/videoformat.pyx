# cython: language_level=3
# cython: cdivision=True
# cython: boundscheck=False
# cython: wraparound=False
# distutils: language = c++

cimport cython
from cython cimport view
from cpython cimport array
import array

from libc.stdint cimport *
from libc.math cimport llrint
from libcpp.vector cimport vector
from libcpp.string cimport string as cpp_string
from libcpp.utility cimport pair as cpp_pair
from libcpp.map cimport map as cpp_map

cimport numpy as cnp
import numpy as np

from .wrapper cimport *
from .video_frame cimport *


ctypedef fused video_input_ft:
    uint8_t
    uint32_t

ctypedef fused real_n_ft:
    cython.integral
    cython.floating

cpdef enum ColorStandard:
    Rec601 = 1
    Rec709 = 2
    Rec2020 = 4
    sRGB = 8

cdef struct Coeff_s:
    double Kb
    double Kr
    double Kg

cdef void Coeff_s_setup(Coeff_s* ptr, double Kb, double Kr) nogil except *:
    ptr.Kb = Kb
    ptr.Kr = Kr
    ptr.Kg = 1 - Kb - Kr

cdef Coeff_s Rec601Coeff
cdef Coeff_s Rec709Coeff
cdef Coeff_s Rec2020Coeff
Coeff_s_setup(&Rec601Coeff, 0.299, 0.587)
Coeff_s_setup(&Rec709Coeff, 0.0722, 0.2126)
Coeff_s_setup(&Rec2020Coeff, 0.0593, 0.2627)

ctypedef cpp_map[cpp_string, Coeff_s*] coeff_map_t
ctypedef cpp_pair[cpp_string, Coeff_s*] coeff_pair_t

cdef coeff_map_t CoeffMap
CoeffMap[b'Rec601'] = &Rec601Coeff
CoeffMap[b'Rec709'] = &Rec709Coeff
CoeffMap[b'Rec2020'] = &Rec2020Coeff

# ctypedef vector[vector[double]] vec2d
# ctypedef double[3][3] vec3x3
cdef struct transform_s:
    double[3][3] to_rgb
    double[3][3] to_yuv

ctypedef cpp_map[cpp_string, transform_s*] transform_map_t
ctypedef cpp_pair[cpp_string, transform_s*] transform_pair_t

cdef transform_map_t TransformMap

@cython.cdivision(False)
cdef void calc_yuv_transform(Coeff_s* c, double[3][3] result) except *:
    cdef view.array result_view = <double[:3, :3]>&(result[0][0])
    cdef cnp.float64_t[:,:] tmp = np.array([
        [c.Kr, c.Kg, c.Kb],                                     # [Y_R, Y_G, Y_B]
        [(c.Kr/(1-c.Kb))/-2, (c.Kg/(1-c.Kb))/-2, 1/2],          # [U_R, U_G, U_B]
        [1/2, (c.Kg/(1-c.Kr))/-2, (c.Kb/(1-c.Kr))/-2],          # [V_R, V_G, V_B]
    ], dtype=np.float64)
    # cdef double[:,:] tmp_view = tmp
    result_view[...] = tmp


@cython.cdivision(False)
cdef void calc_rgb_transform(Coeff_s* c, double[3][3] result) except *:
    cdef view.array result_view = <double[:3, :3]>&(result[0][0])
    cdef cnp.float64_t[:,:] tmp = np.array([
        [1, 0, 2-2*c.Kr],                                       # [Y_R, U_R, V_R]
        [1, -(c.Kb/c.Kg)*(2-2*c.Kb), -(c.Kr/c.Kg)*(2-2*c.Kr)],  # [Y_G, U_G, V_G]
        [1, 2-2*c.Kb, 0],                                       # [Y_B, U_B, V_B]
    ], dtype=np.float64)
    # cdef double[:,:] tmp_view = tmp
    # result[...] = tmp_view[...]
    result_view[...] = tmp

# cdef void _build_rgb_transform(Coeff_s* c, cpp_string key) except *:
#     cdef double[3][3] arr
#     cdef double[:,:] arr_view = arr
#     calc_rgb_transform(c, arr_view)
#     cdef transform_pair_t p = transform_pair_t(key, arr)
#     RGBTransformMap.insert(p)
#     # RGBTransformMap[key] = arr

# cdef void _build_yuv_transform(Coeff_s* c, cpp_string key) except *:
#     cdef double[3][3] arr
#     cdef double[:,:] arr_view = arr
#     calc_yuv_transform(c, arr_view)
#     cdef transform_pair_t p = transform_pair_t(key, arr)
#     YUVTransformMap.insert(p)
#     # YUVTransformMap[key] = arr

cdef transform_s Rec601Transforms
cdef transform_s Rec709Transforms
cdef transform_s Rec2020Transforms
calc_rgb_transform(&Rec601Coeff, Rec601Transforms.to_rgb)
calc_yuv_transform(&Rec601Coeff, Rec601Transforms.to_yuv)
calc_rgb_transform(&Rec709Coeff, Rec709Transforms.to_rgb)
calc_yuv_transform(&Rec709Coeff, Rec709Transforms.to_yuv)
calc_rgb_transform(&Rec2020Coeff, Rec2020Transforms.to_rgb)
calc_yuv_transform(&Rec2020Coeff, Rec2020Transforms.to_yuv)

TransformMap[b'Rec601'] = &Rec601Transforms
TransformMap[b'Rec709'] = &Rec709Transforms
TransformMap[b'Rec2020'] = &Rec2020Transforms
# cdef void build_transforms() except *:
#     cdef bytes key
#     cdef cpp_string cppkey
#     cdef Coeff_s* c

#     for key in [b'Rec601', b'Rec709', b'Rec2020']:
#         cppkey = key
#         c = CoeffMap[key]
#         _build_rgb_transform(c, key)
#         _build_yuv_transform(c, key)



cdef real_n_ft clip_value(real_n_ft value, int32_t vmin, int32_t vmax) nogil except *:
    if value > vmax:
        value = vmax
    elif value < vmin:
        value = vmin
    return value


cdef struct Bounds_s:
    uint32_t min
    uint32_t max
    uint32_t center
    double scale


cdef void Bounds_s_init(Bounds_s* ptr) nogil except *:
    ptr.min = 0
    ptr.max = 1
    ptr.scale = 1
    ptr.center = 0


cdef void Bounds_s_setup(
    Bounds_s* ptr,
    uint32_t vmin,
    uint32_t vmax,
    bint is_uv,
) nogil except *:

    ptr.min = vmin
    ptr.max = vmax
    ptr.scale = vmax - vmin
    ptr.center = <uint32_t>(vmin + ptr.scale / 2.)
    # if is_uv:
    #     # ptr.scale = (vmax - vmin) / 2.

    #     # ptr.center = vmin + ptr.scale / 2.
    #     ptr.center = <uint32_t>(vmin + ptr.scale)
    #     # ptr.scale /= 2.
    # else:
    #     # ptr.scale = vmax - vmin

    #     ptr.center = <uint32_t>(vmin + ptr.scale)


cdef struct Scaling_s:
    char* id
    uint8_t bpp
    bint full_scale
    uint32_t max_value
    Bounds_s y
    Bounds_s uv
    Bounds_s rgb
    uint32_t[4] yuv_offset
    double[4] yuv_scale


cdef void Scaling_s_init(Scaling_s* ptr) nogil except *:
    cdef size_t i

    ptr.id = NULL
    ptr.bpp = 0
    ptr.full_scale = False
    ptr.max_value = 0
    Bounds_s_init(&ptr.y)
    Bounds_s_init(&ptr.uv)
    Bounds_s_init(&ptr.rgb)
    
    for i in range(4):
        ptr.yuv_offset[i] = 0
        ptr.yuv_scale[i] = 1


cdef void Scaling_s_setup(Scaling_s* ptr, uint8_t bpp, bint full_scale) nogil except *:
    cdef uint32_t vmin, vmax
    cdef size_t i

    ptr.bpp = bpp
    ptr.full_scale = full_scale
    ptr.max_value = (1 << bpp) - 1
    
    vmin = 0 if full_scale else (16 << (bpp - 8))
    vmax = ptr.max_value if full_scale else (235 << (bpp - 8))
    Bounds_s_setup(&ptr.rgb, vmin, vmax, False)
    Bounds_s_setup(&ptr.y, vmin, vmax, False)

    vmax = ptr.max_value if full_scale else (240 << (bpp - 8))
    Bounds_s_setup(&ptr.uv, vmin, vmax, True)

    ptr.yuv_offset[0] = ptr.y.min
    ptr.yuv_offset[1] = ptr.uv.center
    ptr.yuv_offset[2] = ptr.uv.center
    ptr.yuv_offset[3] = 0

    ptr.yuv_scale[0] = ptr.y.scale
    ptr.yuv_scale[1] = ptr.uv.scale
    ptr.yuv_scale[2] = ptr.uv.scale
    ptr.yuv_scale[3] = ptr.max_value



cdef void Scaling_s_to_float(
    Scaling_s* ptr,
    video_input_ft[:,:] in_arr,
    double[:,:] out_arr,
    bint is_yuv,
) nogil except *:
    cdef size_t nrows = in_arr.shape[0], ncols = in_arr.shape[1]
    cdef size_t i, j, k = 0
    cdef double value

    for i in range(nrows):
        for j in range(ncols):
            # k = (i * ncols + j) % 4
            value = in_arr[i,j]
            if False:#k % 4 == 3:
                out_arr[i,j] = value / <double>(ptr.max_value)
            elif is_yuv:
                out_arr[i,j] = (value - ptr.yuv_offset[k]) / <double>(ptr.yuv_scale[k])
            else:
                out_arr[i,j] = (value - ptr.rgb.min) / <double>(ptr.rgb.scale)
            k = (k + 1) % 4
            # k += 1
            # if k == 3:
            #     k = 0




cdef void Scaling_s_from_float(
    Scaling_s* ptr,
    double[:,:] in_arr,
    video_input_ft[:,:] out_arr,
    bint is_yuv,
) nogil except *:

    cdef size_t nrows = in_arr.shape[0], ncols = in_arr.shape[1]
    cdef size_t i, j, k = 0
    cdef int32_t vmin = 0, vmax = ptr.max_value
    cdef double value
    cdef int32_t int_value

    for i in range(nrows):
        for j in range(ncols):
            # k = (i * ncols + j) % 4
            if False:#k % 4 == 3:
                # out_arr[i,j] = in_arr[i,j]
                vmin = 0
                vmax = ptr.max_value
                value = in_arr[i,j] * vmax
            elif is_yuv:
                # vmin = ptr.yuv_offset[k]
                # vmax = vmin + <int32_t>ptr.yuv_scale[k]
                value = in_arr[i,j] * ptr.yuv_scale[k] + ptr.yuv_offset[k]
                # int_value = clip_value(round(value), ptr.yuv_offset[k], vmax)
            else:
                # vmin = ptr.rgb.min
                # vmax = ptr.rgb.max
                value = in_arr[i,j] * ptr.rgb.scale + ptr.rgb.min

                # int_value = clip_value(round(value), ptr.rgb.min, ptr.rgb.max)
            # int_value = clip_value(round(value), vmin, vmax)
            # out_arr[i,j] = int_value
            # int_value = llrint(value)
            int_value = <int32_t>value
            out_arr[i,j] = clip_value(int_value, vmin, vmax)
            # k += 1
            # if k == 3:
            #     k = 0
            k = (k + 1) % 4



cdef struct VideoFormat_s:
    char* id
    ColorStandard color_standard
    Scaling_s* scaling
    transform_s* transform

cdef void VideoFormat_s_to_rgb(
    VideoFormat_s* src_fmt,
    VideoFormat_s* dst_fmt,
    video_input_ft[:,:] in_arr,
    video_input_ft[:,:] out_arr,
) except *:

    cdef size_t nrows = in_arr.shape[0], ncols = in_arr.shape[1]
    cdef double[:,:] flt_view = view.array((nrows, ncols), itemsize=sizeof(double), format='d')
    cdef double[:,:] transform_view = <double[:3, :3]> &(src_fmt.transform.to_rgb[0][0])
    cdef double[:,:] transform_tmp = view.array((3, nrows), itemsize=sizeof(double), format='d')

    # with nogil:
    Scaling_s_to_float(src_fmt.scaling, in_arr, flt_view, True)         # YUV -> float
    do_transform(transform_view, flt_view[:,:3].T, transform_tmp)       # dot product
    flt_view[:,:3] = transform_tmp.T
    Scaling_s_from_float(dst_fmt.scaling, flt_view, out_arr, False)     # float -> RGB


cdef void VideoFormat_s_to_yuv(
    VideoFormat_s* src_fmt,
    VideoFormat_s* dst_fmt,
    video_input_ft[:,:] in_arr,
    video_input_ft[:,:] out_arr,
) except *:

    cdef size_t nrows = in_arr.shape[0], ncols = in_arr.shape[1]
    cdef double[:,:] flt_view = view.array((nrows, ncols), itemsize=sizeof(double), format='d')
    cdef double[:,:] transform_view = <double[:3, :3]> &(dst_fmt.transform.to_yuv[0][0])
    cdef double[:,:] transform_tmp = view.array((3, nrows), itemsize=sizeof(double), format='d')

    # with nogil:
    Scaling_s_to_float(src_fmt.scaling, in_arr, flt_view, False)            # RGB -> float
    do_transform(transform_view, flt_view[:,:3].T, transform_tmp)           # dot product
    flt_view[:,:3] = transform_tmp.T
    Scaling_s_from_float(dst_fmt.scaling, flt_view, out_arr, True)          # float -> YUV


cdef void do_transform(double[:,:] transform_arr, double[:,:] data, double[:,:] tmp) nogil except *:
    """
    A = ``transform_arr``
    B = ``data``
    C = ``tmp``

    A.shape = (3, 3)
    B.shape = (3, n)
    C.shape = (n, 3)
    """
    cdef size_t b_rows = data.shape[0], b_cols = data.shape[1]                      # (3, n)
    cdef size_t a_rows = transform_arr.shape[0], a_cols = transform_arr.shape[1]    # (3, 3)
    cdef size_t c_rows = tmp.shape[0], c_cols = tmp.shape[1]

    if a_cols != b_rows:
        raise_withgil(PyExc_ValueError, b'Incorrect A<->B shape')
    if c_rows != a_rows:
        raise_withgil(PyExc_ValueError, b'Incorrect A<->C shape')
    if c_cols != b_cols:
        # raise_withgil(PyExc_ValueError, b'Incorrect B<->C shape')
        with gil:
            raise ValueError(f'Incorrect B<->C shape: C.cols={c_cols}, B.cols={b_cols}')

    # cdef double[3] tmp
    # cdef size_t a_i, a_j, b_i, b_j
    cdef size_t i, j, k
    tmp[...] = 0

    for i in range(a_rows):         # 3
        for j in range(b_cols):     # n
            for k in range(a_cols): # 3
                tmp[i,j] += transform_arr[i,k] * data[k,j]



cdef Scaling_s yuv_8bpp_scaling
cdef Scaling_s rgb_8bpp_scaling
Scaling_s_setup(&yuv_8bpp_scaling, 8, False)
Scaling_s_setup(&rgb_8bpp_scaling, 8, True)

cdef VideoFormat_s Rec709_8bpp
Rec709_8bpp.id = b'Rec709_8bpp'
Rec709_8bpp.color_standard = ColorStandard.Rec709
Rec709_8bpp.scaling = &yuv_8bpp_scaling
Rec709_8bpp.transform = &Rec709Transforms

cdef VideoFormat_s sRGB_8bpp
sRGB_8bpp.id = b'RGB_8bpp'
sRGB_8bpp.color_standard = ColorStandard.sRGB
sRGB_8bpp.scaling = &rgb_8bpp_scaling
sRGB_8bpp.transform = NULL


cdef void yuv_to_rgb(uint8_t[:,:] in_arr, uint8_t[:,:] out_arr) except *:
    VideoFormat_s_to_rgb(&Rec709_8bpp, &sRGB_8bpp, in_arr, out_arr)

cdef void rgb_to_yuv(uint8_t[:,:] in_arr, uint8_t[:,:] out_arr) except *:
    VideoFormat_s_to_yuv(&sRGB_8bpp, &Rec709_8bpp, in_arr, out_arr)

def yuv_to_rgb_py(uint8_t[:,:] in_arr):
    out_arr = np.zeros((in_arr.shape[0], in_arr.shape[1]), dtype=np.uint8)
    cdef uint8_t[:,:] out_view = out_arr
    VideoFormat_s_to_rgb(&Rec709_8bpp, &sRGB_8bpp, in_arr, out_view)
    return out_arr

def rgb_to_yuv_py(uint8_t[:,:] in_arr):
    out_arr = np.zeros((in_arr.shape[0], in_arr.shape[1]), dtype=np.uint8)
    cdef uint8_t[:,:] out_view = out_arr
    VideoFormat_s_to_yuv(&sRGB_8bpp, &Rec709_8bpp, in_arr, out_view)
    return out_arr


# Note:
# This class was cobbled together as a test and is not fully fleshed out yet
# (also it segfaults currently)
cdef class Decoder:
    cdef VideoFrameSync vf
    cdef size_t npixels
    cdef cnp.ndarray in_data, out_data

    def __init__(self, VideoFrameSync vf):
        self.vf = vf
        self.in_data = np.zeros((0,4), dtype=np.uint8)
        self.out_data = np.zeros((0,4), dtype=np.uint8)
        self.npixels = 0

    def decode(self):
        self._decode()
        return self.data.flatten()

    cdef void _decode(self) except *:
        self.check_data()
        if self.npixels == 0:
            return
        # cdef uint8_t[:] data1d = self.vf
        # cdef uint8_t[:,:] data2d = self.data
        # cdef size_t npixels = self.vf._get_xres() * self.vf._get_yres()
        cdef uint8_t[:] data = self.vf
        cdef uint8_t[:,:] in_data = self.in_data
        cdef uint8_t[:,:] out_data = self.out_data
        cdef FourCC fcc = self.vf._get_fourcc()
        cdef bint has_alpha = fcc == FourCC.UYVA
        cdef size_t nrows = in_data.shape[0], ncols = in_data.shape[1]
        cdef size_t i, j = 0
        for i in range(nrows):
            in_data[i,0] = data[j+1]
            in_data[i,1] = data[j]
            in_data[i,2] = data[j+2]
            if has_alpha:
                in_data[i,3] = data[j+3]
            else:
                in_data[i,3] = 255
            j += 4

        VideoFormat_s_to_rgb(&Rec709_8bpp, &sRGB_8bpp, in_data, out_data)


    cdef void check_data(self) except *:
        self.npixels = self.vf._get_xres() * self.vf._get_yres()
        # cdef size_t nbytes = npixels * 4
        cdef uint8_t[:,:] data
        if self.in_data is not None:
            data = self.in_data
            if data.shape[0] == self.npixels:
                return
        self.in_data = np.zeros((self.npixels, 4), dtype=np.uint8)
        self.out_data = np.zeros((self.npixels, 4), dtype=np.uint8)
