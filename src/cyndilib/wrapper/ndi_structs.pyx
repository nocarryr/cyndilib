from libc.math cimport llround


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
    return p

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
