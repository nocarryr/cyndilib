#! /usr/bin/env python3

from __future__ import annotations
from typing import Literal, TypedDict
import os
import sys
import shlex
import json
import concurrent.futures
from contextlib import contextmanager
from pathlib import Path
import numpy
from Cython.Build import cythonize, Cythonize
from Cython.Build.Dependencies import extended_iglob
from Cython.Compiler import Options

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


# Copy of `Cythonize._interruptible_pool` instead of importing the private method
# https://github.com/cython/cython/blob/2a8ee41263f6bc898a32c75a9156071bee5e8788/Cython/Build/Cythonize.py#L72-L80
@contextmanager
def _interruptible_pool(pool_cm):
    with pool_cm as proc_pool:
        try:
            yield proc_pool
        except KeyboardInterrupt:
            proc_pool.terminate_workers()
            proc_pool.shutdown(cancel_futures=True)
            raise


class MetadataNotFound(Exception):
    pass


class NDIDistutilsMetadata(TypedDict):
    extra_compile_args: list[str]
    include_dirs: list[str]
    libraries: list[str]
    library_dirs: list[str]
    runtime_library_dirs: list[str]|None
    language: Literal['c', 'c++']


class CythonDistutilsMetadata(NDIDistutilsMetadata):
    depends: list[str]|None
    name: str|None
    sources: list[str]


class CythonMetadata(TypedDict):
    distutils: CythonDistutilsMetadata
    module_name: str


def get_cython_metadata(src_file: Path) -> CythonMetadata:
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
        raise ValueError(f"Invalid source file type: {src_file}")
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
                    raise MetadataNotFound(f"No metadata found in {src_file}")
            else:
                if 'END: Cython Metadata' in line:
                    end_found = True
                    break
                meta_lines.append(line)
    if not end_found or not len(meta_lines):
        raise MetadataNotFound(f"No metadata found in {src_file}")
    s = '\n'.join(meta_lines)
    return json.loads(s)


def get_ndi_metadata() -> NDIDistutilsMetadata:
    wrapper_dir = Path(cyndilib.get_include()).parent
    src_file = wrapper_dir / 'ndi_structs.cpp'
    if not src_file.exists():
        raise RuntimeError('cyndilib must be compiled first')
    metadata = get_cython_metadata(src_file)
    dist_meta = metadata['distutils']
    include_dirs = [cyndilib.get_include(), numpy.get_include()]
    meta_inc = dist_meta.get('include_dirs', [])
    if meta_inc is not None:
        include_dirs.extend(meta_inc)
    include_dirs = list(set(include_dirs))
    return NDIDistutilsMetadata(
        extra_compile_args=dist_meta.get('extra_compile_args', []),
        libraries=dist_meta.get('libraries', []),
        library_dirs=dist_meta.get('library_dirs', []),
        runtime_library_dirs=dist_meta.get('runtime_library_dirs', []),
        language=dist_meta.get('language', 'c++'),
        include_dirs=include_dirs,
    )


def cython_compile(path_pattern, options):
    parallel = options.parallel
    assert isinstance(parallel, int) and parallel >= 0
    distutils_meta = get_ndi_metadata()
    aliases = {f'DISTUTILS_{k.upper()}':v for k,v in distutils_meta.items()}
    print(f'{aliases=}')

    all_paths = map(os.path.abspath, extended_iglob(path_pattern))
    all_paths = [p for p in all_paths]
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

    # Make `ext_modules` match the output of `Cythonize._cython_compile_files()` in
    # https://github.com/cython/cython/blob/2a8ee41263f6bc898a32c75a9156071bee5e8788/Cython/Build/Cythonize.py#L35-L69
    ext_modules = [(base_dir, [m]) for m in ext_modules]


    # Remainder adapted from `Cythonize._build` in
    # https://github.com/cython/cython/blob/2a8ee41263f6bc898a32c75a9156071bee5e8788/Cython/Build/Cythonize.py#L84-L133
    modcount = sum(len(modules) for _, modules in ext_modules)

    if not modcount:
        print('No modules found to compile')
        return

    serial_execution_mode = modcount == 1 or parallel < 2

    try:
        pool_cm = (
            None if serial_execution_mode
            else concurrent.futures.ProcessPoolExecutor(max_workers=parallel)
        )
    except (OSError, ImportError):
        # `OSError` is a historic exception in `multiprocessing`
        # `ImportError` happens e.g. under pyodide (`ModuleNotFoundError`)
        serial_execution_mode = True

    if serial_execution_mode:
        for ext in ext_modules:
            run_distutils(ext)
        return

    with _interruptible_pool(pool_cm) as proc_pool:
        compiler_tasks = [
            proc_pool.submit(run_distutils, (base_dir, [ext]))
            for base_dir, modules in ext_modules
            for ext in modules
        ]

        concurrent.futures.wait(compiler_tasks, return_when=concurrent.futures.FIRST_EXCEPTION)

        worker_exceptions = []
        for task in compiler_tasks:  # discover any crashes
            try:
                task.result()
            except BaseException as proc_err:  # could be SystemExit
                worker_exceptions.append(proc_err)

        if worker_exceptions:
            exc_msg = 'Compiling Cython modules failed with these errors:\n\n'
            exc_msg += '\n\t* '.join(('', *map(str, worker_exceptions)))
            exc_msg += '\n\n'

            non_base_exceptions = [
                exc for exc in worker_exceptions
                if isinstance(exc, Exception)
            ]
            if sys.version_info[:2] >= (3, 11) and non_base_exceptions:
                raise ExceptionGroup(exc_msg, non_base_exceptions)
            else:
                raise RuntimeError(exc_msg) from worker_exceptions[0]


def build_opts():
    opts = ['-i', '-a', '-b']
    # opts.append(f'--option=include_path={INCLUDE_PATH}')
    for key, val in COMPILER_DIRECTIVES.items():
        opts.append(f'--directive={key}={val}')
    if CPU_COUNT is not None and CPU_COUNT > 1:
        opts.append(f'-j {CPU_COUNT}')
    return ' '.join(opts)

def do_cythonize(pyx_file, opts=None):
    if opts is None:
        opts = build_opts()

    opts = f'{opts} {pyx_file}'
    parsed, paths = Cythonize.parse_args(shlex.split(opts))
    assert parsed.parallel == CPU_COUNT
    if parsed.annotate:
        Options.annotate = True
    cython_compile(pyx_file, parsed)

def main():
    pattern = os.path.join(TESTS_PATH, '*.pyx')
    opts = build_opts()
    do_cythonize(pattern, opts)

if __name__ == '__main__':
    main()
