import os
import sys
import sysconfig
import shutil
import json
from pathlib import Path
from setuptools import setup, find_packages
from distutils.extension import Extension
from distutils.sysconfig import get_python_inc
from distutils.errors import CCompilerError

USE_CYTHON = True#'--use-cython' in sys.argv
if USE_CYTHON:
    # sys.argv.remove('--use-cython')
    from Cython.Build import cythonize
    from Cython.Compiler import Options
    try:
        from annotate_index import AnnotateIndex
    except ImportError:
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
LIB_DIRS = []
RUNTIME_LIB_DIRS = []
NDI_INCLUDE = PROJECT_PATH / 'src' / 'cyndilib' / 'wrapper' / 'include'
INCLUDE_PATH = [str(NDI_INCLUDE), get_python_inc()]


def get_ndi_libdir():
    if WIN32:
        p = Path(os.environ.get('PROGRAMFILES'))
        sdk_dir = p / 'NDI' / 'NDI 5 SDK'
        lib_sys = sdk_dir / 'Lib' / 'x64'
        dll_sys = sdk_dir / 'Bin' / 'x64'
        lib_dir = PROJECT_PATH / 'src' / 'cyndilib' / 'wrapper' / 'lib'
        dll_dir = lib_dir.parent / 'bin'

        if not len(list(lib_dir.glob('*.lib'))):
            assert lib_sys.exists()
            lib_sys = sdk_dir / 'Lib' / 'x64'
            dll_sys = sdk_dir / 'Bin' / 'x64'
            for src_p, dst_p in zip([lib_sys, dll_sys], [lib_dir, dll_dir]):
                for fn in src_p.iterdir():
                    if not fn.is_file():
                        continue
                    dest_fn = dst_p / fn.name
                    if dest_fn.exists():
                        continue
                    shutil.copy2(fn, dest_fn)
            LIB_DIRS.append(str(lib_dir))
        else:
            LIB_DIRS.append(str(lib_sys))
    else:
        lib_dir = PROJECT_PATH / 'src' / 'cyndilib' / 'wrapper' / 'bin'
        if not MACOS:
            arch = sysconfig.get_config_var('MULTIARCH')
            if arch:
                p = lib_dir / arch
                if p.exists():
                    lib_dir = p
        LIB_DIRS.append(str(lib_dir))
        RUNTIME_LIB_DIRS.append(str(lib_dir))

def get_ndi_libname():
    if WIN32:
        return 'Processing.NDI.Lib.x64'
    return 'ndi'

if IS_BUILD:
    get_ndi_libdir()

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


compiler_directives = {'embedsignature':True}

if USE_PROFILE:
    ext_macros = [('CYTHON_TRACE', 1), ('CYTHON_TRACE_NOGIL', 1)]
    compiler_directives.update({'profile':True, 'linetrace':True})
else:
    ext_macros = None

extra_compile_args = []

if WIN32:
    extra_compile_args.append('/Zc:strictStrings')
else:
    extra_compile_args.append('-fpermissive')

if not len(LIB_DIRS):
    LIB_DIRS = None
if not len(RUNTIME_LIB_DIRS):
    RUNTIME_LIB_DIRS = None

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

def build_annotate_index(extensions):
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
    ext_modules=ext_modules,
    include_package_data=True,
)
