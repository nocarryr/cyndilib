# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS
# distutils: define_macros=CYTHON_TRACE_NOGIL=1

cimport cython
cimport numpy as cnp
import numpy as np

from cyndilib.wrapper cimport *

from cyndilib.send_frame_status cimport *
from cyndilib.audio_frame cimport AudioSendFrame
from cyndilib.video_frame cimport VideoSendFrame
from cyndilib.pixelutils.image_format cimport ImageFormat_s, fill_image_format

def get_max_frame_buffers():
    return MAX_FRAME_BUFFERS

def get_null_idx():
    return NULL_INDEX

def set_send_frame_sender_status(object frame, bint attached):
    cdef VideoSendFrame vf
    cdef AudioSendFrame af
    if isinstance(frame, VideoSendFrame):
        vf = frame
        vf._set_sender_status(attached)
        if not attached:
            _check_item_view_counts(&vf.send_status)
    elif isinstance(frame, AudioSendFrame):
        af = frame
        af._set_sender_status(attached)
        if not attached:
            _check_item_view_counts(&af.send_status)
    else:
        raise Exception()

def set_send_frame_send_complete(object frame):
    cdef VideoSendFrame vf
    cdef AudioSendFrame af
    cdef VideoSendFrame_item_s* vitem
    cdef AudioSendFrame_item_s* aitem
    if isinstance(frame, VideoSendFrame):
        vf = frame
        assert vf._send_frame_available()
        vitem = vf._get_send_frame()
        vf._on_sender_write(vitem)
    elif isinstance(frame, AudioSendFrame):
        af = frame
        assert af._send_frame_available()
        aitem = af._get_send_frame()
        af._on_sender_write(aitem)
    else:
        raise Exception()

def write_audio_frame_memview(AudioSendFrame af, cnp.float32_t[:,:] data):
    cdef AudioSendFrame_item_s* item = af._prepare_memview_write()
    assert item.data.view_count == 0
    cdef cnp.float32_t[:,:] view = af
    assert item.data.view_count == 1
    view[...] = data
    view = data[:0,:0]
    assert item.data.view_count == 0
    af._set_buffer_write_complete(item)


def get_audio_frame_data(AudioSendFrame af, cnp.float32_t[:,:] dest_arr):
    assert af._send_frame_available()
    cdef AudioSendFrame_item_s* item = af._get_send_frame()
    assert item is not NULL
    cdef float32_t* flt_ptr = <float32_t*>item.frame_ptr.p_data
    unpack_audio(&flt_ptr, dest_arr)

def get_video_frame_data(VideoSendFrame vf, cnp.uint8_t[:] dest_arr):
    assert vf._send_frame_available()
    cdef VideoSendFrame_item_s* item = vf._get_send_frame()
    assert item is not NULL
    assert dest_arr.shape[0] == vf.image_reader.size_in_bytes
    unpack_video(&(item.frame_ptr.p_data), dest_arr)


def check_audio_send_frame(AudioSendFrame af, write_index=None, read_index=None):
    if write_index is None:
        write_index = af.write_index
    if read_index is None:
        read_index = af.read_index
    cdef Py_ssize_t w = write_index, r = read_index
    _check_send_frame(&af.send_status, af.ptr, w, r)


def check_video_send_frame(VideoSendFrame vf, write_index=None, read_index=None):
    if write_index is None:
        write_index = vf.write_index
    if read_index is None:
        read_index = vf.read_index
    cdef Py_ssize_t w = write_index, r = read_index
    _check_send_frame(&vf.send_status, vf.ptr, w, r)


def assert_equal(a, b, msg=''):
    if len(msg):
        msg = f' ({msg})'
    if a != b:
        raise AssertionError(f'assert {a} == {b}{msg}')

def assert_not_equal(a, b, msg=''):
    if len(msg):
        msg = f' ({msg})'
    if a == b:
        raise AssertionError(f'assert {a} != {b}{msg}')

def assert_in_range(a, vmin, vmax, msg=''):
    if len(msg):
        msg = f' ({msg})'
    if a < vmin or a > vmax:
        raise AssertionError(f'assert {vmin} <= {a} <= {vmax})')


def test_indexing():
    cdef VideoSendFrame_status_s vid_s
    cdef VideoSendFrame_status_s* vid_ptr = &vid_s
    cdef AudioSendFrame_status_s aud_s
    cdef AudioSendFrame_status_s* aud_ptr = &aud_s
    frame_status_init(vid_ptr)
    frame_status_init(aud_ptr)

    _test_indexing(vid_ptr)
    _test_indexing(aud_ptr)


cdef _check_next_ix_err_result(SendFrame_status_s_ft* s_ptr):
    cdef Py_ssize_t tmp
    tmp = frame_status_get_next_write_index(s_ptr)
    if tmp != NULL_INDEX:
        assert_in_range(tmp, 0, MAX_FRAME_BUFFERS-1)
    tmp = frame_status_get_next_read_index(s_ptr)
    if tmp != NULL_INDEX:
        assert_in_range(tmp, 0, MAX_FRAME_BUFFERS-1)


cdef _test_indexing(SendFrame_status_s_ft* s_ptr):
    cdef Py_ssize_t max_iter = s_ptr.data.num_buffers * 8, i
    cdef Py_ssize_t write_index=0, read_index=NULL_INDEX

    for i in range(max_iter):
        _check_next_ix_err_result(s_ptr)
        # print(f'loop_start: {i}')
        assert_equal(write_index, s_ptr.data.write_index)
        assert_equal(read_index, s_ptr.data.read_index)
        assert_equal(write_index, frame_status_get_next_write_index(s_ptr))
        assert_equal(read_index, NULL_INDEX)
        assert_equal(read_index, frame_status_get_next_read_index(s_ptr))
        _check_item_flags(s_ptr, write_index, read_index)

        # print('set_send_ready')
        frame_status_set_send_ready(s_ptr)
        _check_next_ix_err_result(s_ptr)
        read_index = write_index
        write_index += 1
        if write_index >= s_ptr.data.num_buffers:
            write_index = 0
        print(f'w = {write_index}, r = {read_index}')
        _check_item_flags(s_ptr, write_index, read_index)
        assert_equal(write_index, s_ptr.data.write_index)
        assert_equal(read_index, s_ptr.data.read_index)
        assert_equal(write_index, frame_status_get_next_write_index(s_ptr))
        assert_equal(read_index, frame_status_get_next_read_index(s_ptr))

        # print('set_send_complete')
        frame_status_set_send_complete(s_ptr, read_index)
        _check_next_ix_err_result(s_ptr)
        read_index = NULL_INDEX
        assert_equal(write_index, s_ptr.data.write_index)
        assert_equal(read_index, s_ptr.data.read_index)
        assert_equal(write_index, frame_status_get_next_write_index(s_ptr))
        assert_equal(read_index, frame_status_get_next_read_index(s_ptr))
        _check_item_flags(s_ptr, write_index, read_index)

cdef _check_item_view_counts(SendFrame_status_s_ft* s_ptr):
    cdef size_t i

    for i in range(s_ptr.data.num_buffers):
        assert_equal(s_ptr.items[i].data.view_count, 0)

cdef _check_item_flags(SendFrame_status_s_ft* s_ptr, Py_ssize_t write_index, Py_ssize_t read_index):
    cdef size_t i
    cdef bint avail

    assert_not_equal(write_index, read_index)

    for i in range(s_ptr.data.num_buffers):
        avail = read_index != i
        if s_ptr.items[i].data.write_available is not avail:
            raise AssertionError(f'write_available should be {avail} for i={i}, write_index={write_index}')

        avail = read_index == i
        if s_ptr.items[i].data.read_available is not avail:
            raise AssertionError(f'read_available should be {avail} for i={i}, write_index={write_index}')

cdef _check_send_frame(SendFrame_status_s_ft* s_ptr, NDIlib_frame_type_ft* source_frame, Py_ssize_t write_index, Py_ssize_t read_index):
    assert_equal(write_index, s_ptr.data.write_index)
    assert_equal(read_index, s_ptr.data.read_index)
    assert_equal(write_index, frame_status_get_next_write_index(s_ptr))
    assert_equal(read_index, frame_status_get_next_read_index(s_ptr))
    cdef Py_ssize_t chk_item_write_index = write_index, chk_item_read_index = read_index
    _check_item_flags(s_ptr, chk_item_write_index, chk_item_read_index)

    cdef Py_ssize_t[3] shape = [0, 0, 0]
    cdef Py_ssize_t[3] strides = [0, 0, 0]
    cdef size_t i, j
    cdef ImageFormat_s image_format

    if SendFrame_status_s_ft is VideoSendFrame_status_s and NDIlib_frame_type_ft is NDIlib_video_frame_v2_t:
        fill_image_format(&image_format, fourcc_type_uncast(source_frame.FourCC), source_frame.xres, source_frame.yres)
        assert_equal(s_ptr.data.ndim, image_format.pix_fmt.num_planes)
        shape[0] = image_format.size_in_bytes
        strides[0] = sizeof(uint8_t)
        assert_equal(image_format.width * image_format.height * sizeof(uint8_t) * 4, image_format.size_in_bytes)
        assert_equal(source_frame.line_stride_in_bytes, image_format.width*4)

    elif SendFrame_status_s_ft is AudioSendFrame_status_s and NDIlib_frame_type_ft is NDIlib_audio_frame_v3_t:
        assert_equal(s_ptr.data.ndim, source_frame.no_channels)
        shape[0] = s_ptr.data.ndim
        shape[1] = source_frame.no_samples
        strides[0] = sizeof(float32_t) * shape[1]
        strides[1] = sizeof(float32_t)
        assert_equal(source_frame.channel_stride_in_bytes, strides[0])

    for i in range(s_ptr.data.ndim):
        assert_equal(shape[i], s_ptr.data.shape[i], f'shape[{i}]')
        assert_equal(strides[i], s_ptr.data.strides[i], f'strides[{i}]')

    for i in range(s_ptr.data.num_buffers):
        _check_send_frame_item(&(s_ptr.items[i]), i, s_ptr.data.ndim, shape, strides, source_frame)

cdef _check_send_frame_item(
    SendFrame_item_s_ft* item,
    size_t idx,
    size_t ndim,
    Py_ssize_t[3] shape,
    Py_ssize_t[3] strides,
    NDIlib_frame_type_ft* source_frame,
):

    cdef size_t expected_alloc, i
    assert_equal(item.data.idx, idx)

    expected_alloc = strides[ndim-1]

    for i in range(ndim):
        assert_equal(item.data.shape[i], shape[i])
        assert_equal(item.data.strides[i], strides[i])
        expected_alloc *= item.data.shape[i]

    if SendFrame_item_s_ft is VideoSendFrame_item_s and NDIlib_frame_type_ft is NDIlib_video_frame_v2_t:
        assert_equal(item.frame_ptr.xres, source_frame.xres)
        assert_equal(item.frame_ptr.yres, source_frame.yres)
        assert_equal(item.frame_ptr.FourCC, source_frame.FourCC)
        assert_equal(item.frame_ptr.frame_rate_N, source_frame.frame_rate_N)
        assert_equal(item.frame_ptr.frame_rate_D, source_frame.frame_rate_D)
        assert_equal(item.frame_ptr.picture_aspect_ratio, source_frame.picture_aspect_ratio)
        assert_equal(item.frame_ptr.frame_format_type, source_frame.frame_format_type)
        assert_equal(item.frame_ptr.line_stride_in_bytes, source_frame.line_stride_in_bytes)
    elif SendFrame_item_s_ft is AudioSendFrame_item_s and NDIlib_frame_type_ft is NDIlib_audio_frame_v3_t:
        assert_equal(item.frame_ptr.sample_rate, source_frame.sample_rate)
        assert_equal(item.frame_ptr.no_channels, source_frame.no_channels)
        assert_equal(item.frame_ptr.no_samples, source_frame.no_samples)
        assert_equal(item.frame_ptr.channel_stride_in_bytes, source_frame.channel_stride_in_bytes)

    assert_equal(item.data.alloc_size, expected_alloc)
    assert item.frame_ptr.p_data is not NULL



@cython.boundscheck(False)
@cython.wraparound(False)
cdef int unpack_audio(float32_t** src, cnp.float32_t[:,:] dst) except -1:
    cdef size_t nrows = dst.shape[0], ncols = dst.shape[1], i, j, k=0
    cdef float32_t* src_p = src[0]

    for i in range(nrows):
        for j in range(ncols):
            dst[i,j] = src_p[k]
            k += 1
    return 0


@cython.boundscheck(False)
@cython.wraparound(False)
cdef int unpack_video(uint8_t** src, cnp.uint8_t[:] dst) except -1:
    # cdef size_t nrows = dst.shape[0], ncols = dst.shape[1], i, j, k=0
    cdef size_t i
    cdef uint8_t* src_p = src[0]

    for i in range(dst.shape[0]):
        dst[i] = src_p[i]
    return 0
