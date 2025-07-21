#! /usr/bin/env python3

import os
import sys
import glob
import shlex
import json
import multiprocessing
from pathlib import Path
import numpy
from Cython.Build import cythonize, Cythonize

import cyndilib

WIN32 = sys.platform == 'win32'
MACOS = sys.platform == 'darwin'


ROOT_PATH = os.path.abspath(os.path.dirname(__file__))
TESTS_PATH = os.path.join(ROOT_PATH, 'tests')
CPU_COUNT = os.cpu_count()
if CPU_COUNT is None:
    CPU_COUNT = 0

CYTHONIZE_CMD = 'cythonize {opts} {pyx_file}'

COMPILER_DIRECTIVES = {
    'linetrace':True,
    'embedsignature':True,
}

run_distutils = Cythonize.run_distutils
_FakePool = Cythonize._FakePool
extended_iglob = Cythonize.extended_iglob

def get_cython_metadata(src_file: Path):
    """Read the distutils metadata embedded in cythonized sources

    The JSON-formatted "Cython Metadata" contains all of the necessary compiler
    and linker options discovered by "cythonize()" to be passed as kwargs to
    recreate Extension objects without Cython installed

    ::
        /* BEGIN: Cython Metadata
            {
                "distutils": {
                    "depends": ["..."],
                    "extra_compile_args": ["..."],
                    "include_dirs": ["..."],
                    "language": "c/c++",
                    "name": "...",
                    "sources": ["..."]
                }
            }
        END: Cython Metadata */

    """
    if not isinstance(src_file, Path):
        src_file = Path(src_file)
    if src_file.suffix not in ['.c', '.cpp']:
        return None
    start_found = False
    end_found = False
    meta_lines = []
    i = -1
    with src_file.open('rt') as f:
        for line in f:
            i += 1
            if not start_found:
                if 'BEGIN: Cython Metadata' in line:
                    start_found = True
                elif i > 100:
                    return None
            else:
                if 'END: Cython Metadata' in line:
                    end_found = True
                    break
                meta_lines.append(line)
    if not end_found or not len(meta_lines):
        return None
    s = '\n'.join(meta_lines)
    return json.loads(s)

def get_ndi_metadata():
    wrapper_dir = Path(cyndilib.get_include()).parent
    src_file = wrapper_dir / 'ndi_structs.cpp'
    if not src_file.exists():
        raise RuntimeError('cyndilib must be compiled first')
    metadata = get_cython_metadata(src_file)
    keys = [
        'extra_compile_args', 'include_dirs', 'libraries',
        'library_dirs', 'runtime_library_dirs',
    ]
    data = {key:metadata['distutils'].get(key) for key in keys}
    data['include_dirs'] = [cyndilib.get_include(), numpy.get_include()]
    return data

def cython_compile(path_pattern, options):
    distutils_meta = get_ndi_metadata()
    aliases = {f'DISTUTILS_{k.upper()}':v for k,v in distutils_meta.items()}
    print(f'{aliases=}')

    pool = None
    all_paths = map(os.path.abspath, extended_iglob(path_pattern))
    all_paths = [p for p in all_paths]
    try:
        base_dir = os.path.dirname(path_pattern)

        ext_modules = cythonize(
            all_paths,
            nthreads=options.parallel,
            exclude_failures=options.keep_going,
            exclude=options.excludes,
            aliases=aliases,
            compiler_directives=options.directives,
            compile_time_env=options.compile_time_env,
            force=options.force,
            quiet=options.quiet,
            **options.options)

        if ext_modules and options.build:
            if len(ext_modules) > 1 and options.parallel > 1:
                if pool is None:
                    try:
                        pool = multiprocessing.Pool(options.parallel)
                    except OSError:
                        pool = _FakePool()
                pool.map_async(run_distutils, [
                    (base_dir, [ext]) for ext in ext_modules])
            else:
                run_distutils((base_dir, ext_modules))
    except:
        if pool is not None:
            pool.terminate()
        raise
    else:
        if pool is not None:
            pool.close()
            pool.join()

def build_opts():
    opts = ['-i', '-a', '-b']
    # opts.append(f'--option=include_path={INCLUDE_PATH}')
    for key, val in COMPILER_DIRECTIVES.items():
        opts.append(f'--directive={key}={val}')
    # if CPU_COUNT is not None and CPU_COUNT > 1:
    #     opts.append(f'-j {CPU_COUNT}')
    return ' '.join(opts)

def do_cythonize(pyx_file, opts=None):
    if opts is None:
        opts = build_opts()

    opts = f'{opts} {pyx_file}'
    parsed, paths = Cythonize.parse_args(shlex.split(opts))
    parsed.parallel = 1
    if parsed.annotate:
        Cythonize.Options.annotate = True
    cython_compile(pyx_file, parsed)

def main():
    pattern = os.path.join(TESTS_PATH, '*.pyx')
    opts = build_opts()
    do_cythonize(pattern, opts)

if __name__ == '__main__':
    main()
