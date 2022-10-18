#! /usr/bin/env python3

import os
import glob
import shlex
import multiprocessing
from distutils.sysconfig import get_python_inc
import numpy
from Cython.Build import cythonize, Cythonize

ROOT_PATH = os.path.abspath(os.path.dirname(__file__))
TESTS_PATH = os.path.join(ROOT_PATH, 'tests')
CPU_COUNT = os.cpu_count()
if CPU_COUNT is None:
    CPU_COUNT = 0

INCLUDE_PATH = [numpy.get_include()]

CYTHONIZE_CMD = 'cythonize {opts} {pyx_file}'

COMPILER_DIRECTIVES = {
    'linetrace':True,
}

run_distutils = Cythonize.run_distutils
_FakePool = Cythonize._FakePool
extended_iglob = Cythonize.extended_iglob

def cython_compile(path_pattern, options):
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
            aliases={'NUMPY_INCLUDE':INCLUDE_PATH},
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
        Cythonize.Options.annotate = True
    cython_compile(pyx_file, parsed)

def main():
    pattern = os.path.join(TESTS_PATH, '*.pyx')
    opts = build_opts()
    do_cythonize(pattern, opts)

if __name__ == '__main__':
    main()
