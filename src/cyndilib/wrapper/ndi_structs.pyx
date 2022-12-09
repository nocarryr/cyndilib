from libc.math cimport llround

__all__ = ('FrameType', 'FourCC', 'FrameFormat', 'get_ndi_version')


def get_ndi_version():
    return NDIlib_version().decode('UTF-8')


cdef double ndi_time_to_posix(int64_t ndi_ts) nogil except *:
    cdef float128_t result = <float128_t>ndi_ts * 1e-7
    return <double>result

cdef int64_t posix_time_to_ndi(double ts) nogil except *:
    cdef long long result = llround(ts * 1e7)
    return result

cdef NDIlib_source_t* source_create() nogil except *:
    cdef NDIlib_source_t* p = <NDIlib_source_t*>mem_alloc(sizeof(NDIlib_source_t))
    if p is NULL:
        raise_mem_err()
    p.p_ndi_name = NULL
    p.p_url_address = NULL
    return p

cdef void source_destroy(NDIlib_source_t* p) nogil except *:
    if p is not NULL:
        mem_free(p)

cdef NDIlib_video_frame_v2_t* video_frame_create() nogil except *:
    cdef NDIlib_video_frame_v2_t* p = <NDIlib_video_frame_v2_t*>mem_alloc(sizeof(NDIlib_video_frame_v2_t))
    if p is NULL:
        raise_mem_err()
    return p

cdef NDIlib_video_frame_v2_t* video_frame_create_default() nogil except *:
    cdef NDIlib_video_frame_v2_t* p = video_frame_create()
    p.xres = 0
    p.yres = 0
    p.FourCC = fourcc_type_cast(FourCC.UYVY)
    p.frame_rate_N = 30000
    p.frame_rate_D = 1001
    p.picture_aspect_ratio = 0
    p.frame_format_type = frame_format_cast(FrameFormat.progressive)
    p.timecode = NDIlib_send_timecode_synthesize
    p.p_data = NULL
    p.line_stride_in_bytes = 0
    p.p_metadata = NULL
    p.timestamp = 0
    return p

cdef void video_frame_copy(
    NDIlib_video_frame_v2_t* src,
    NDIlib_video_frame_v2_t* dest
) nogil except *:
    dest.xres = src.xres
    dest.yres = src.yres
    dest.FourCC = src.FourCC
    dest.line_stride_in_bytes = src.line_stride_in_bytes
    dest.frame_rate_N = src.frame_rate_N
    dest.frame_rate_D = src.frame_rate_D
    dest.picture_aspect_ratio = src.picture_aspect_ratio
    dest.frame_format_type = src.frame_format_type
    dest.timecode = src.timecode
    dest.timestamp = src.timestamp


cdef void video_frame_destroy(NDIlib_video_frame_v2_t* p) nogil except *:
    pass
    # if p is not NULL:
    #     if p.p_data is not NULL:
    #         mem_free(p.p_data)
    #         p.p_data = NULL
    #     # if p.p_metadata is not NULL:
    #     #     mem_free(p.p_metadata)
    #     #     # p.p_metadata = NULL
    #     mem_free(p)


cdef NDIlib_audio_frame_v3_t* audio_frame_create() nogil except *:
    cdef NDIlib_audio_frame_v3_t* p = <NDIlib_audio_frame_v3_t*>mem_alloc(sizeof(NDIlib_audio_frame_v3_t))
    if p is NULL:
        raise_mem_err()
    return p

cdef NDIlib_audio_frame_v3_t* audio_frame_create_default() nogil except *:
    cdef NDIlib_audio_frame_v3_t* p = audio_frame_create()
    p.sample_rate = 48000
    p.no_channels = 2
    p.no_samples = 0
    p.timecode = NDIlib_send_timecode_synthesize
    p.FourCC = NDIlib_FourCC_audio_type_FLTP
    p.channel_stride_in_bytes = 0
    p.timestamp = 0
    p.p_data = NULL
    return p

cdef void audio_frame_copy(
    NDIlib_audio_frame_v3_t* src,
    NDIlib_audio_frame_v3_t* dest
) nogil except *:
    dest.sample_rate = src.sample_rate
    dest.no_channels = src.no_channels
    dest.no_samples = src.no_samples
    dest.timecode = src.timecode
    dest.FourCC = src.FourCC
    dest.channel_stride_in_bytes = src.channel_stride_in_bytes
    dest.timestamp = src.timestamp


cdef void audio_frame_destroy(NDIlib_audio_frame_v3_t* p) nogil except *:
    pass
    # if p is not NULL:
    #     if p.p_data is not NULL:
    #         mem_free(p.p_data)
    #         p.p_data = NULL
    #     # if p.p_metadata is not NULL:
    #     #     mem_free(p.p_metadata)
    #     #     # p.p_metadata = NULL
    #     mem_free(p)

cdef NDIlib_metadata_frame_t* metadata_frame_create() nogil except *:
    cdef NDIlib_metadata_frame_t* p = <NDIlib_metadata_frame_t*>mem_alloc(sizeof(NDIlib_metadata_frame_t))
    if p is NULL:
        raise_mem_err()
    p.length = 0
    p.timecode = NDIlib_send_timecode_synthesize
    p.p_data = NULL
    return p

cdef void metadata_frame_destroy(NDIlib_metadata_frame_t* p) nogil except *:
    pass
    # if p is not NULL:
    #     if p.p_data is not NULL:
    #         mem_free(p.p_data)
    #         p.p_data = NULL
    #     mem_free(p)

cdef FourCCPackInfo* fourcc_pack_info_create() nogil except *:
    cdef FourCCPackInfo* p = <FourCCPackInfo*>mem_alloc(sizeof(FourCCPackInfo))
    if p is NULL:
        raise_mem_err()
    fourcc_pack_info_init(p)
    return p

cdef void fourcc_pack_info_init(FourCCPackInfo* p) nogil except *:
    cdef size_t i
    p.fourcc = FourCC.UYVY
    p.xres = 0
    p.yres = 0
    p.bytes_per_pixel = 0
    p.num_planes = 0
    p.total_size = 0
    for i in range(4):
        p.line_strides[i] = 0
        p.stride_offsets[i] = 0

cdef void fourcc_pack_info_destroy(FourCCPackInfo* p) nogil except *:
    if p is not NULL:
        mem_free(p)


cdef FourCCPackInfo* get_fourcc_pack_info(FourCC fourcc, size_t xres, size_t yres) nogil except *:
    cdef FourCCPackInfo* p = fourcc_pack_info_create()
    p.fourcc = fourcc
    p.xres = xres
    p.yres = yres
    calc_fourcc_pack_info(p)
    return p


cdef void calc_fourcc_pack_info(FourCCPackInfo* p) nogil except *:
    cdef size_t xres = p.xres, yres = p.yres
    cdef size_t bytes_per_pixel

    if p.fourcc == FourCC.UYVY:
        p.num_planes = 1
        bytes_per_pixel = sizeof(uint8_t) * 4
        p.line_strides[0] = bytes_per_pixel * xres
        p.total_size = bytes_per_pixel * xres * yres
    elif p.fourcc == FourCC.UYVA:
        p.num_planes = 2
        bytes_per_pixel = sizeof(uint8_t) * 5           # YUVY + alpha plane
        p.line_strides[0] = sizeof(uint8_t) * 4 * xres
        p.line_strides[1] = sizeof(uint8_t) * xres
        p.stride_offsets[1] = p.line_strides[0] * yres
        p.total_size = bytes_per_pixel * xres * yres
    elif p.fourcc == FourCC.P216:
        p.num_planes = 2
        bytes_per_pixel = sizeof(uint16_t) * 2          # <uint16_t>Y + <uint16_t>UV (second plane)
        p.line_strides[0] = sizeof(uint16_t) * xres
        p.line_strides[1] = sizeof(uint16_t) * xres
        p.stride_offsets[1] = p.line_strides[0] * yres
        p.total_size = bytes_per_pixel * xres * yres
    elif p.fourcc == FourCC.PA16:
        p.num_planes = 3
        bytes_per_pixel = sizeof(uint16_t) * 3          # <uint16_t>Y + <uint16_t>UV + <uint16_t>A
        p.line_strides[0] = sizeof(uint16_t) * xres
        p.line_strides[1] = sizeof(uint16_t) * xres
        p.line_strides[2] = sizeof(uint16_t) * xres
        p.stride_offsets[1] = p.line_strides[0] * yres
        p.stride_offsets[2] = p.stride_offsets[1] + p.line_strides[1] * yres
        p.total_size = bytes_per_pixel * xres * yres
    elif p.fourcc == FourCC.YV12 or p.fourcc == FourCC.I420:
        p.num_planes = 3
        bytes_per_pixel = sizeof(uint8_t) * 2           # just google it
        p.line_strides[0] = sizeof(uint8_t) * xres
        p.line_strides[1] = p.line_strides[0] // 2
        p.line_strides[2] = p.line_strides[1]
        p.stride_offsets[1] = p.line_strides[0] * yres
        p.stride_offsets[2] = p.stride_offsets[1] + yres // 2
        p.total_size = p.stride_offsets[2] + p.line_strides[2] * yres // 2
    elif p.fourcc == FourCC.NV12:
        p.num_planes = 2
        bytes_per_pixel = sizeof(uint8_t) * 2           # <uint8_t>Y + <uint8_t>UV
        p.line_strides[0] = sizeof(uint8_t) * xres
        p.line_strides[1] = sizeof(uint8_t) * xres
        p.stride_offsets[1] = p.line_strides[0] * yres
        p.total_size = bytes_per_pixel * xres * yres
    elif p.fourcc == FourCC.BGRA or p.fourcc == FourCC.BGRX or p.fourcc == FourCC.RGBA or p.fourcc == FourCC.RGBX:
        p.num_planes = 1
        bytes_per_pixel = sizeof(uint8_t) * 4           # BGRX_BGRA, RGBX_RGBA
        p.line_strides[0] = sizeof(uint8_t) * 4 * xres
        p.total_size = p.line_strides[0] * yres
    else:
        raise_withgil(PyExc_ValueError, 'Unknown FourCC type')
    p.bytes_per_pixel = bytes_per_pixel
