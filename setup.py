import os
import sys
import platform
import shutil
import json
from pathlib import Path
from setuptools import setup, find_packages
from setuptools.command.build_ext import build_ext
from distutils.extension import Extension
from distutils.sysconfig import get_python_inc
from distutils.errors import CCompilerError
from distutils.util import get_platform

USE_CYTHON = True#'--use-cython' in sys.argv
if USE_CYTHON:
    # sys.argv.remove('--use-cython')
    from Cython.Build import cythonize
    from Cython.Compiler import Options
    try:
        from annotate_index import AnnotateIndex
    except (ImportError, SyntaxError):
        AnnotateIndex = False
    Options.fast_fail = True

    USE_PROFILE = '--use-profile' in sys.argv
    if USE_PROFILE:
        sys.argv.remove('--use-profile')
    ANNOTATE = '--annotate' in sys.argv
    if ANNOTATE:
        sys.argv.remove('--annotate')
else:
    USE_PROFILE = False

PROJECT_PATH = Path(__file__).parent
WIN32 = sys.platform == 'win32'
MACOS = sys.platform == 'darwin'
IS_BUILD = True
LIB_DIRS: list[str] = []
RUNTIME_LIB_DIRS: list[str] = []
NDI_INCLUDE = PROJECT_PATH / 'src' / 'cyndilib' / 'wrapper' / 'include'
INCLUDE_PATH = [str(NDI_INCLUDE), get_python_inc()]
PACKAGE_DATA = {
    '*':[
        'LICENSE', 'README*', 'libndi_licenses.txt',
        '*.pxd', '*.pyx', '*.c', '*.cpp',
    ],
    'cyndilib.wrapper.include':['*.h'],
    'cyndilib.wrapper.bin':['*.txt'],
    'cyndilib.wrapper.lib':[],
}

def get_ndi_libdir():
    lib_pkg_data = []
    bin_pkg_data = []
    lib_dirs = []
    runtime_lib_dirs = []
    if WIN32:
        lib_dir = PROJECT_PATH / 'src' / 'cyndilib' / 'wrapper' / 'lib'
        dll_dir = lib_dir.parent / 'bin'
        lib_dirs.extend([str(dll_dir.resolve()), str(lib_dir.resolve())])
        bin_pkg_data.append('*.dll')
        lib_pkg_data.append('*.lib')
    else:
        lib_dir = PROJECT_PATH / 'src' / 'cyndilib' / 'wrapper' / 'bin'
        if MACOS:
            bin_pkg_data.append('*.dylib')
        else:
            platform_str = get_platform()
            if not platform_str.startswith('linux-'):
                raise Exception(f'Unknown platform: "{platform_str}"')
            if 'i686' in platform_str:
                arch = 'i686-linux-gnu'
            elif 'x86_64' in platform_str:
                arch = 'x86_64-linux-gnu'
            elif 'aarch64' in platform_str:
                arch = 'aarch64-rpi4-linux-gnueabi'
            else:
                raise Exception(f'Unsupported platform: "{platform_str}"')
            lib_dir = lib_dir / arch
            bin_pkg_data.append(f'{arch}/*.so')
        lib_dir = lib_dir.resolve()
        lib_dirs.append(str(lib_dir))
        runtime_lib_dirs.append(str(lib_dir))

    bin_pkg_data.append('*.txt')
    package_data = PACKAGE_DATA.copy()
    package_data.update({
        'cyndilib.wrapper.bin':bin_pkg_data,
        'cyndilib.wrapper.lib':lib_pkg_data,
    })
    return package_data, lib_dirs, runtime_lib_dirs


def get_ndi_libname():
    if WIN32:
        return 'Processing.NDI.Lib.x64'
    return 'ndi'

if IS_BUILD:
    PACKAGE_DATA, LIB_DIRS, RUNTIME_LIB_DIRS = get_ndi_libdir()

try:
    import numpy
except ImportError:
    numpy = None
if numpy is not None:
    INCLUDE_PATH.append(numpy.get_include())

class CyBuildError(CCompilerError):
    def __init__(self, msg):
        self.msg = msg
    def __str__(self):
        return '{}  (try building with "--use-cython")'.format(self.msg)


compiler_directives = {'embedsignature':True, 'embedsignature.format':'python'}
ext_macros: list[tuple[str, str|None]] | None
if USE_PROFILE:
    ext_macros = [('CYTHON_TRACE', '1'), ('CYTHON_TRACE_NOGIL', '1')]
    compiler_directives.update({'profile':True, 'linetrace':True})
else:
    ext_macros = None

extra_compile_args = []

if WIN32:
    extra_compile_args.append('/Zc:strictStrings')
else:
    extra_compile_args.append('-fpermissive')


ext_modules = [
    Extension(
        '*', ['src/**/*.pyx'],
        include_dirs=INCLUDE_PATH,
        extra_compile_args=extra_compile_args,
        libraries=[get_ndi_libname()],
        library_dirs=LIB_DIRS,
        runtime_library_dirs=RUNTIME_LIB_DIRS,
        define_macros=ext_macros,
        # define_macros=[('CYTHON_TRACE', 1), ('CYTHON_TRACE_NOGIL', 1)]
    ),
]

ext_modules = cythonize(
    ext_modules,
    annotate=ANNOTATE,
    compiler_directives=compiler_directives,
)

# From https://github.com/scikit-learn/scikit-learn/blob/3ee60a720aab3598668af3a3d7eb01d6958859be/setup.py#L106-L117
class build_ext_subclass(build_ext):
    def finalize_options(self):
        build_ext.finalize_options(self)

        if self.parallel is None:
            # Do not override self.parallel if already defined by
            # command-line flag (--parallel or -j)
            if os.environ.get('READTHEDOCS', '').lower() == 'true':
                parallel = 'auto'
            else:
                parallel = os.environ.get("CYNDILIB_BUILD_PARALLEL")
            if parallel == 'auto':
                self.parallel = os.cpu_count()
            elif parallel:
                self.parallel = int(parallel)
        if self.parallel:
            print("setting parallel=%d " % self.parallel)


def build_annotate_index(extensions):
    assert callable(AnnotateIndex)
    root = AnnotateIndex('', root_dir=PROJECT_PATH / 'src')
    for ext in extensions:
        pkg_dir = Path(ext.sources[0]).parent
        pkg = root.add_module(ext.name)
    for c in root.walk():
        print('{} -> {}'.format(c, c.to_path('index.html')))
        c.write_html()
if ANNOTATE and AnnotateIndex is not None:
    build_annotate_index(ext_modules)

setup(
    cmdclass={
        'build_ext':build_ext_subclass,
    },
    ext_modules=ext_modules,
    include_package_data=True,
    package_data=PACKAGE_DATA,
)
