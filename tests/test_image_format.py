from __future__ import annotations

import numpy as np
import pytest

from cyndilib.wrapper.ndi_structs import FourCC
from cyndilib.pixelutils import ImageFormat, ImageReader
from yuv_builder import DataFile, DataFiles



@pytest.fixture(
    params=DataFiles.data_files,
    ids=[f'{df.fourcc.name}_{df.resolution}' for df in DataFiles],
)
def data_file(request) -> DataFile:
    return request.param


@pytest.fixture(params=[False, True], ids=['packed', 'planar'])
def planar(request) -> bool:
    return request.param


@pytest.fixture(params=[False, True], ids=['no_expand', 'expand'])
def expand_chroma(request) -> bool:
    return request.param


@pytest.fixture(params=[8, 16])
def dest_dtype(request):
    return np.uint8 if request.param == 8 else np.uint16



def test_image_format_attrs(data_file, planar):
    w, h = data_file.width, data_file.height
    img_fmt = ImageFormat(
        fourcc=data_file.fourcc,
        width=w, height=h, planar=planar, expand_chroma=True,
    )
    assert img_fmt.fourcc == data_file.fourcc
    assert img_fmt.width == w
    assert img_fmt.height == h
    assert img_fmt.planar == planar
    assert img_fmt.resolution == data_file.resolution
    assert img_fmt.chroma_width == data_file.chroma_width
    assert img_fmt.chroma_height == data_file.chroma_height
    assert img_fmt.is_16bit == data_file.is_16_bit
    assert img_fmt.num_components == data_file.num_components
    if planar:
        assert img_fmt.shape == (data_file.num_components, h, w)
    else:
        assert img_fmt.shape == (h, w, data_file.num_components)
    assert img_fmt.size_in_bytes == data_file.get_packed_size()


def test_unpack(data_file, planar, expand_chroma, dest_dtype):
    w, h = data_file.resolution
    data_arr = data_file.get_src_array()

    unpacker = ImageReader(
        fourcc=data_file.fourcc,
        width=w, height=h, planar=planar, expand_chroma=expand_chroma,
    )
    unpacked_arr = np.zeros(unpacker.shape, dtype=dest_dtype)
    unpacker.unpack_into(src=data_arr, dest=unpacked_arr)

    if data_file.is_rgb:
        rgb_data = np.fromfile(data_file.get_filename(), dtype=np.uint8)
        rgb_data = np.reshape(rgb_data, (h, w, 4))

        if data_file.fourcc in [FourCC.BGRA, FourCC.BGRX]:
            rgb_data = np.stack((
                rgb_data[...,2],    # B
                rgb_data[...,1],    # G
                rgb_data[...,0],    # R
                rgb_data[...,3],    # A
            ), axis=2)

        if not data_file.has_alpha:
            rgb_data = rgb_data[...,:3]

        if planar:
            # Change shape to ``(component, h, w)``
            rgb_data = np.moveaxis(rgb_data, -1, 0)

        assert rgb_data.shape == unpacker.shape
        assert unpacked_arr.shape == rgb_data.shape
        assert np.array_equal(unpacked_arr, rgb_data)
        return

    yuv_data = data_file.get_plane_arrays(expand_chroma=expand_chroma, planar=planar)
    assert unpacked_arr.shape == yuv_data.shape

    if data_file.is_16_bit and dest_dtype is np.uint8:
        yuv_data >>= 8

    if expand_chroma:
        # yuv_data from data_file has expanded chroma so it should match exactly
        assert np.array_equal(unpacked_arr, yuv_data)
    else:
        # compare components separately since chroma resolution is smaller
        cw, ch = data_file.chroma_resolution
        has_alpha = data_file.has_alpha
        if not planar:
            unpacked_arr = np.moveaxis(unpacked_arr, -1, 0)
            yuv_data = np.moveaxis(yuv_data, -1, 0)
        uv_slice = np.s_[1:3, :ch, :cw]
        ya_slice = np.s_[0::3] if has_alpha else np.s_[0]
        assert np.array_equal(unpacked_arr[uv_slice], yuv_data[uv_slice])
        assert np.array_equal(unpacked_arr[ya_slice], yuv_data[ya_slice])


def test_pack(data_file, planar, expand_chroma):
    w, h = data_file.width, data_file.height
    fourcc = data_file.fourcc
    src_dtype = data_file.dtype

    packer = ImageReader(
        fourcc=fourcc, width=w, height=h,
        planar=planar, expand_chroma=expand_chroma,
    )

    data_arr = data_file.get_src_array()
    assert data_arr.nbytes == packer.size_in_bytes

    src_arr = np.zeros(packer.shape, dtype=src_dtype)
    packer.unpack_into(src=data_arr, dest=src_arr)

    dest_arr = np.zeros(packer.size_in_bytes, dtype=np.uint8)

    packer.pack_into(src=src_arr, dest=dest_arr)

    assert data_arr.shape == dest_arr.shape
    assert np.array_equal(data_arr, dest_arr)
