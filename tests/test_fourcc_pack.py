from __future__ import annotations
from typing import Literal, Iterable, Iterator
from fractions import Fraction
import pytest

from cyndilib.video_frame import VideoSendFrame
from cyndilib.wrapper.ndi_structs import FourCC


def build_resolutions(
    start_w: int,
    end_w: int,
    step: int = 2,
    rotate: bool = False,
    aspect: Fraction = Fraction(16, 9)
) -> Iterator[tuple[int, int]]:
    """Generate valid resolutions with the given aspect ratio

    Only results with width and height divisible by zero are included.

    Arguments:
        start_w: Resolution width to start from
        end_w: Resolution width to end at (inclusive)
        step: Increase *start_w* by this amount each iteration
        rotate: If ``True``, include an inverted resolution (rotated by 90deg)
        aspect: The desired aspect ratio

    """

    def build_resolution(w: int, aspect: Fraction) -> tuple[int, int]|Literal[False]:
        if w % 2 != 0:
            return False
        h = w / aspect
        if h % 1 != 0 or h % 2 != 0:
            return False
        return w, int(h)

    assert end_w > start_w
    w = start_w
    while w <= end_w:
        r = build_resolution(w, aspect)
        if r is not False:
            yield r
            if rotate:
                _w, _h = r
                yield _h, _w
        w += step


@pytest.fixture(params=[
    (320, 1920, 4, Fraction(16, 9)),
    (320, 720, 16, Fraction(4, 3)),
    (640, 1920, 32, Fraction(16, 10)),
])
def extended_resolutions(request) -> Iterator[tuple[int, int]]:
    start_w, end_w, step, aspect = request.param
    return build_resolutions(start_w, end_w, step, rotate=True, aspect=aspect)


@pytest.fixture(params=[m for m in FourCC])
def fourcc(request) -> FourCC:
    return request.param



def test_pack_info(extended_resolutions, fourcc):
    vf = VideoSendFrame()
    res_count = 0
    for resolution in extended_resolutions:
        print(f'{resolution=}')
        res_count += 1
        xres, yres = resolution
        vf.set_resolution(xres, yres)

        is_422 = fourcc in [FourCC.UYVA, FourCC.UYVY, FourCC.P216, FourCC.PA16]
        is_420 = fourcc in [FourCC.YV12, FourCC.I420, FourCC.NV12]
        is_16_bit = fourcc in [FourCC.P216, FourCC.PA16]
        is_rgb = not is_422 and not is_420
        has_alpha = fourcc in [FourCC.UYVA, FourCC.PA16, FourCC.RGBA, FourCC.BGRA]
        print(f'{fourcc=}, {is_422=}, {is_420=}, {is_16_bit=}, {is_rgb=}, {has_alpha=}')

        vf.set_fourcc(fourcc)
        bfr_size = vf.get_buffer_size()
        bpp = vf.bits_per_pixel
        p_bpp = vf.padded_bits_per_pixel

        # RGBA/RGBX - ensure bpp and padded bpp are correct
        if is_rgb:
            if has_alpha:
                assert bpp == 32
            else:
                assert bpp == 24
            assert bfr_size == (p_bpp / 8) * xres * yres
            continue

        # YUV 4:2:2 / 4:2:2:4 / 4:2:0 formats
        chroma_width, chroma_height = xres, yres
        y_bytes = 2 if is_16_bit else 1
        if is_422:
            chroma_width = -((-xres) >> 1)
        elif is_420:
            chroma_width = -((-xres) >> 1)
            chroma_height = -((-yres) >> 1)
        print(f'{y_bytes=}, {chroma_width=}, {chroma_height=}')

        y_size = xres * yres * y_bytes
        chroma_size = chroma_width * chroma_height * y_bytes
        alpha_size = xres * yres * y_bytes if has_alpha else 0

        total_size = y_size + chroma_size + chroma_size + alpha_size
        assert bfr_size == total_size

    # just to be sure the fixture generated something
    assert res_count > 0
