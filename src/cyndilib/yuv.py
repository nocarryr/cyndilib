from __future__ import annotations
import enum
import dataclasses
from dataclasses import dataclass
# from collections import namedtuple
import typing as tp
from typing import NamedTuple

import numpy as np

class Coeff(tp.NamedTuple):
    Kb: float
    Kr: float
    Kg: float

# ColorStandard = tp.Literal['Rec601']
class ColorStandard(enum.Enum):
    Rec601 = enum.auto()
    Rec709 = enum.auto()
    Rec2020 = enum.auto()
    RGB = enum.auto()

    @property
    def is_yuv(self) -> bool:
        members = [getattr(ColorStandard, k) for k in ['Rec601', 'Rec709', 'Rec2020']]
        return self in members


    @classmethod
    def create(cls, value: ColorStandard|str|int) -> ColorStandard:
        if isinstance(value, ColorStandard):
            return value
        elif isinstance(value, str):
            members = {k.lower():v for k,v in cls.__members__.items()}
            value = members[value.lower()]
        elif isinstance(value, int):
            value = cls(value)
        else:
            raise ValueError('Invalid argument')
        return value

# Coeff = namedtuple('Coeff', ['Kb', 'Kr', 'Kg'])
Coefficients = {
    ColorStandard.Rec601:  Coeff(0.299, 0.587, None),
    ColorStandard.Rec709:  Coeff(0.0722, 0.2126, None),
    ColorStandard.Rec2020: Coeff(0.0593, 0.2627, None),
}
for key in Coefficients:
    c = Coefficients[key]
    Kg = 1 - c.Kb - c.Kr
    Coefficients[key] = c._replace(Kg=Kg)


def get_n_bytes(n: int, pairs: bool = False) -> int:
    nb = n // 8
    if n % 8 != 0:
        nb += 1
    if pairs and nb % 2 != 0:
        nb += 1
    return nb

ScalingKey = tuple[int, bool]

@dataclass
class Scaling:
    bpp: int
    full_scale: bool
    max_value: int
    y_min: int
    y_max: int
    y_scale: int
    c_min: int
    c_max: int
    c_scale: float
    c_center: float
    y_offset: int
    rgb_scale: int
    yuv_offset: np.ndarray
    yuv_scale: np.ndarray

    np_dtype: np.dtype
    _instances: tp.ClassVar[dict[ScalingKey, Scaling]] = {}

    @property
    def id(self) -> ScalingKey:
        return self._get_id(self.bpp, self.full_scale)

    @staticmethod
    def _get_id(bpp: int, full_scale: bool) -> str:
        extra = '_full' if full_scale else ''
        return f'{bpp}bit{extra}'

    @classmethod
    def create(cls, bpp: int, full_scale: bool) -> Scaling:
        key = cls._get_id(bpp, full_scale)
        if key in cls._instances:
            obj = cls._instances[key]
            assert obj.id == key
            return obj
        max_value = (1 << bpp) - 1
        nbytes = get_n_bytes(bpp)
        kw = dict(
            bpp = bpp,
            max_value = max_value,
            full_scale = full_scale,
            y_offset = 0 if full_scale else (16 << (bpp - 8)),
            y_min = (0 if full_scale else 16) << (bpp - 8),
            y_max = max_value if full_scale else (235 << (bpp - 8)),
            c_min = 0 if full_scale else (16 << (bpp - 8)),
            c_max = max_value if full_scale else (240 << (bpp - 8)),
            np_dtype = np.dtype(f'u{nbytes}'),
            rgb_scale = max_value,
        )
        y_min, y_max = kw['y_min'], kw['y_max']
        c_min, c_max = kw['c_min'], kw['c_max']

        c_scale_full = c_max - c_min
        c_scale_half = c_scale_full / 2
        y_scale = kw['y_scale'] = y_max - y_min
        kw['c_scale'] = c_scale_half
        c_center = kw['c_center'] = c_min + c_scale_half
        yuv_offset = np.array([y_min, c_center, c_center])
        kw['yuv_offset'] = yuv_offset# + (1/(max_value+1))
        kw['yuv_scale'] = np.array([y_scale, c_scale_full, c_scale_full], dtype=float)
        obj = cls(**kw)
        cls._instances[obj.id] = obj
        return obj

    def scale_from_float(self, in_arr, is_yuv: bool):
        if is_yuv:
            scale_arr = self.yuv_scale
            offset_arr = self.yuv_offset# + (1/(self.max_value+1))
        else:
            scale_arr = self.rgb_scale
            offset_arr = self.y_offset
        result = in_arr * scale_arr + offset_arr
        result = np.rint(np.clip(result, 0, self.max_value))
        return np.asarray(result, dtype=self.np_dtype)

    def scale_to_float(self, in_arr, is_yuv: bool):
        if is_yuv:
            scale_arr = self.yuv_scale
            offset_arr = self.yuv_offset
        else:
            scale_arr = self.rgb_scale
            offset_arr = self.y_offset
        result = np.array(in_arr, dtype=float, copy=True)
        result -= offset_arr
        result /= scale_arr
        return result

# def clamp(n, vmin, vmax):
#     n = max(n, vmin)
#     return min(n, vmax)

# def scaled_clip(n, nbits, vmax):
#     offset = 1 << nbits
#     # return clamp(((n + offset) >> 16), 0, vmax)
#     return np.clip((n + offset) >> 16, 0, vmax)
# # return (uint8_t)clamp((i + 32768) >> 16, 0, 255);

ColorFormatKey = tuple[str, ScalingKey]

class ColorFormat:
    color_standard: ColorStandard
    scaling: Scaling
    rgb_transform: np.ndarray
    yuv_transform: np.ndarray
    _instances: tp.ClassVar[ColorFormatKey, ColorFormat] = {}
    def __init__(
        self,
        color_standard: ColorStandard|str,
        bpp: int = 8,
        full_scale: bool = False,
    ):
        color_standard = ColorStandard.create(color_standard)
        self.color_standard = color_standard
        self.scaling = Scaling.create(bpp, full_scale)
        self.rgb_transform, self.yuv_transform = None, None

    @classmethod
    def create(
        cls,
        color_standard: ColorStandard|str,
        bpp: int = 8,
        full_scale: bool = False,
    ) -> ColorFormat:
        color_standard = ColorStandard.create(color_standard)
        scaling = Scaling.create(bpp, full_scale)
        key = cls._get_id(color_standard, scaling)
        if key in cls._instances:
            obj = cls._instances[key]
            assert obj.id == key
            return obj
        obj = cls(color_standard, bpp, full_scale)
        cls._instances[obj.id] = obj
        return obj

    @property
    def id(self) -> ColorFormatKey:
        return self._get_id(self.color_standard, self.scaling)

    @staticmethod
    def _get_id(color_standard: ColorStandard, scaling: Scaling) -> str:
        return f'{color_standard.name}_{scaling.id}'

    @property
    def bpp(self) -> int:
        return self.scaling.bpp

    @property
    def full_scale(self) -> bool:
        return self.scaling.full_scale

    @property
    def is_yuv(self) -> bool:
        return self.color_standard.is_yuv

    def get_rgb_transform(self):
        t = self.rgb_transform
        if t is None:
            t = self.rgb_transform = Transforms[self.color_standard]['RGB']
        return t

    def get_yuv_transform(self):
        t = self.yuv_transform
        if t is None:
            t = self.yuv_transform = Transforms[self.color_standard]['YUV']
        return t

    def guess_convert_to(self, color_standard=None, bpp=None, full_scale=None):
        if bpp is None:
            bpp = self.bpp
        if self.is_yuv:
            if full_scale is None:
                full_scale = True
            if color_standard is None:
                color_standard = ColorStandard.RGB
        else:
            if full_scale is None:
                full_scale = False
            if color_standard is None:
                color_standard = ColorStandard.Rec709
        return ColorFormat.create(color_standard, bpp, full_scale)

    def to_rgb(self, in_arr, full_scale: bool = True):
        if self.is_yuv:
            other = self.guess_convert_to(full_scale=full_scale)
            return self.to_other(in_arr, other)
        else:
            if full_scale is self.full_scale:
                return in_arr
            other = self.guess_convert_to(ColorStandard.RGB, full_scale=full_scale)
            return self.to_other(in_arr, other)

    def to_yuv(self, in_arr, color_standard=None, full_scale: bool = False):
        if self.is_yuv:
            if full_scale is self.full_scale:
                return in_arr
            other = self.guess_convert_to(color_standard, full_scale=full_scale)
            return self.to_other(in_arr, other)
        else:
            other = self.guess_convert_to(color_standard, full_scale=full_scale)
            return self.to_other(in_arr, other)

    def to_other(self, in_arr, other: ColorFormat|str):
        if isinstance(other, str):
            other = ColorFormat._instances[other]
        if other is self:
            return in_arr
        in_arr = self._pre_scale(in_arr, other)
        transform = None
        if self.is_yuv:
            if other.color_standard.is_yuv:
                if other.color_standard != self.color_standard:
                    raise ValueError('converting between standards not yet implemented')
                out_arr = in_arr
            else:
                out_arr = self._transform_to_rgb(in_arr, other)
        else:
            if not other.color_standard.is_yuv:
                out_arr = in_arr
            else:
                out_arr = self._transform_to_yuv(in_arr, other)
        return other._post_scale(out_arr, other)

    def _pre_scale(self, in_arr, other: ColorFormat):
        return self.scaling.scale_to_float(in_arr, self.is_yuv)

    def _post_scale(self, out_arr, other: ColorFormat):
        return self.scaling.scale_from_float(out_arr, self.is_yuv)

    def _transform_to_rgb(self, in_arr, other: ColorFormat):
        transform = self.get_rgb_transform()
        return self._do_transform(in_arr, transform)

    def _transform_to_yuv(self, in_arr, other: ColorFormat):
        transform = other.get_yuv_transform()
        return self._do_transform(in_arr, transform)


    def _do_transform(self, in_arr, transform):
        # return in_arr @ transform
        in_size = in_arr.size
        in_shape = in_arr.shape
        assert in_size % 3 == 0
        nrows = in_size // 3
        new_shape = (nrows, 3)
        # assert in_arr.shape == new_shape
        in_arr = np.reshape(in_arr, (nrows, 3))
        # return in_arr @ transform
        result = transform @ in_arr.T
        return result.T

    def __repr__(self):
        return f'<{self.__class__.__name__}: "{self}">'

    def __str__(self):
        return f'{self.color_standard.name} - {self.bpp}bpp, full_scale={self.full_scale}'

def build_formats():
    for std in ColorStandard:
        for bpp in [8, 10, 12]:
            ColorFormat.create(std, bpp, False)
            if not std.is_yuv:
                ColorFormat.create(std, bpp, True)
build_formats()




def get_yuv_transform(c: Coeff):
    Kb, Kr, Kg = c
    return np.array([
        [Kr, Kg, Kb],                                   # [Y_R, Y_G, Y_B]
        [(Kr/(1-Kb))/-2, (Kg/(1-Kb))/-2, 1/2],          # [U_R, U_G, U_B]
        [1/2, (Kg/(1-Kr))/-2, (Kb/(1-Kr))/-2],          # [V_R, V_G, V_B]
    ])

def get_rgb_transform(c: Coeff):
    Kb, Kr, Kg = c
    return np.array([
        [1, 0, 2-2*Kr],                                 # [Y_R, U_R, V_R]
        [1, -(Kb/Kg)*(2-2*Kb), -(Kr/Kg)*(2-2*Kr)],      # [Y_G, U_G, V_G]
        [1, 2-2*Kb, 0],                                 # [Y_B, U_B, V_B]
    ])

Transforms = {
    k: {'YUV':get_yuv_transform(c), 'RGB':get_rgb_transform(c)}
        for k, c in Coefficients.items()
}
Transforms[ColorStandard.RGB] = {k:np.ones((3,3), dtype=float) for k in ['YUV', 'RGB']}


# yuv_bars = np.array([
#     [180, 128, 128],      # 75w
#     [168,  44, 136],      # YL
#     [145, 147,  44],      # CY
#     [133,  63,  52],      # G
#     [ 63, 193, 204],      # MG
#     [ 51, 109, 212],      # R
#     [ 28, 212, 120],      # B
#     [104, 128, 128],      # 40GY
#     [188, 154,  16],      # 100% CY
#     [ 32, 240, 118],      # 100% B
#     [219,  16, 138],      # 100% YL
#     [ 63, 102, 240],      # 100% R
# ], dtype=np.uint8)


def test():
    assert_array_equal = np.testing.assert_array_equal
    assert_allclose = np.testing.assert_allclose

    rgb_bars_100 = np.array([
        [1, 1, 1],              # W
        [1, 1, 0],              # YL
        [0, 1, 1],              # CY
        [0, 1, 0],              # G
        [1, 0, 1],              # MG
        [1, 0, 0],              # R
        [0, 0, 1],              # B
    ], dtype=float)
    rgb_bars_75 = rgb_bars_100 * .75

    rgb_bars = np.concatenate((rgb_bars_100, rgb_bars_75), axis=0)
    rgb_bars = np.resize(rgb_bars, (rgb_bars.shape[0] + 4, rgb_bars.shape[1]))
    rgb_bars[-4] = [0.4, 0.4, 0.4]  # 40% Grey
    rgb_bars[-3] = [0.0, 0.0, 0.0]  # Blk
    rgb_bars[-2] = [.02, .02, .02]  # +2 Pluge
    rgb_bars[-1] = [.04, .04, .04]  # +4 Pluge

    rgb_bars_full = np.asarray(rgb_bars * 255, dtype=np.uint32)
    rgb_bars_offset = np.asarray(rgb_bars * 219 + 16, dtype=np.uint32)

    # Values taken from SMPTE RP219:2002
    yuv_bars = np.array([
        # 100%
        [235, 128, 128],        # W
        [219,  16, 138],        # YL
        [188, 154,  16],        # CY
        [173,  42,  26],        # G     http://avisynth.nl/index.php/ColorBars_theory
        [ 78, 214, 230],        # MG    http://avisynth.nl/index.php/ColorBars_theory
        [ 63, 102, 240],        # R
        [ 32, 240, 118],        # B

        # 75%
        [180, 128, 128],        # W
        [168,  44, 136],        # YL
        [145, 147,  44],        # CY
        [133,  63,  52],        # G
        [ 63, 193, 204],        # MG
        [ 51, 109, 212],        # R
        [ 28, 212, 120],        # B

        # Others
        [104, 128, 128],        # 40% Grey
        [ 16, 128, 128],        # Blk
        [ 20, 128, 128],        # +2 Pluge
        [ 25, 128, 128],        # +4 Pluge
    ])

    yuv_offset = np.array([16, 128, 128])
    yuv_scale = np.array([219, 224, 224])
    yuv_bars_flt = (yuv_bars - yuv_offset) / yuv_scale
    yuv_bars_fs = np.asarray(np.rint(yuv_bars_flt * 255), int)
    tmp = np.asarray(np.rint(yuv_bars_flt * yuv_scale + yuv_offset), dtype=int)
    assert_array_equal(yuv_bars, tmp)


    # print(rgb_bars_full)
    # print(rgb_bars_offset)

    yuv_fmt = ColorFormat.create('Rec709', 8, False)
    # print(f'{yuv_fmt.scaling=}')
    rgb_fmt_fs = ColorFormat.create('RGB', 8, True)
    rgb_fmt_os = ColorFormat.create('RGB', 8, False)
    assert yuv_fmt.guess_convert_to() is rgb_fmt_fs
    assert yuv_fmt.guess_convert_to(full_scale=False) is rgb_fmt_os
    assert rgb_fmt_fs.guess_convert_to() is yuv_fmt
    assert rgb_fmt_os.guess_convert_to() is yuv_fmt

    # print('rgb_bars_full:')
    # print(rgb_bars_full)
    rgb_out = yuv_fmt.to_rgb(yuv_bars, full_scale=True)
    # print('rgb_out:')
    # print(rgb_out)

    assert_allclose(rgb_bars_full, rgb_out, rtol=1, atol=1)
    yuv_out1 = rgb_fmt_fs.to_yuv(rgb_bars_full, color_standard='Rec709', full_scale=False)
    assert_allclose(yuv_out1, yuv_bars, rtol=1, atol=1)
    yuv_out2 = rgb_fmt_os.to_yuv(rgb_bars_offset, color_standard='Rec709', full_scale=False)
    assert_allclose(yuv_out2, yuv_bars, rtol=1, atol=1)

    yuv_8bpp = yuv_fmt
    rgb_8bpp = rgb_fmt_fs

    for bpp in [10, 12]:
        tol = 1 << (bpp - 8)
        # y_offset = 16 << (bpp - 8)
        # y_scale = 219 << (bpp - 8)
        _yuv_offset = yuv_offset << (bpp - 8)
        _yuv_scale = yuv_scale << (bpp - 8)

        # _rgb_bars_full = np.asarray(np.rint(rgb_bars * (1 << bpp)), dtype=int)
        _rgb_bars_full = rgb_bars_full << (bpp - 8)
        _rgb_bars_offset = np.asarray(np.rint(rgb_bars * _yuv_scale[0] + _yuv_offset[0]), dtype=int)
        # _rgb_bars_full = np.clip(_rgb_bars_full, 0, (1 << bpp) - 1)

        _yuv_bars = yuv_bars_flt * _yuv_scale + _yuv_offset
        _yuv_bars = np.asarray(np.rint(_yuv_bars), dtype=int)
        yuv_fmt = ColorFormat.create('Rec709', bpp, False)
        rgb_fmt_fs = ColorFormat.create('RGB', bpp, True)
        rgb_fmt_os = ColorFormat.create('RGB', bpp, False)

        rgb_out = yuv_fmt.to_rgb(_yuv_bars, full_scale=True)
        assert_allclose(_rgb_bars_full, rgb_out, rtol=tol, atol=tol)

        yuv_out = rgb_fmt_fs.to_yuv(_rgb_bars_full, color_standard='Rec709', full_scale=False)
        assert_allclose(yuv_out, _yuv_bars, rtol=tol, atol=tol)

        yuv_out = rgb_fmt_os.to_yuv(_rgb_bars_offset, color_standard='Rec709', full_scale=False)
        assert_allclose(yuv_out, _yuv_bars, rtol=tol, atol=tol)

        yuv_out = yuv_8bpp.to_other(yuv_bars, yuv_fmt)
        assert_array_equal(yuv_out, _yuv_bars)

        yuv_out = yuv_fmt.to_other(_yuv_bars, yuv_8bpp)
        assert_array_equal(yuv_out, yuv_bars)

        rgb_out = rgb_8bpp.to_other(rgb_bars_full, rgb_fmt_fs)
        assert_allclose(rgb_out, _rgb_bars_full, rtol=tol, atol=tol)

        rgb_out = rgb_fmt_fs.to_other(_rgb_bars_full, rgb_8bpp)
        assert_allclose(rgb_out, rgb_bars_full, rtol=tol, atol=tol)
