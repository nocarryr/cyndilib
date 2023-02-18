#! /usr/bin/env python3

import typing as tp
import sys
from pathlib import Path
import shutil
import argparse

BASE_PATH = Path(__file__).resolve().parent
SRC_PATH = BASE_PATH / 'src'
TEST_PATH = BASE_PATH / 'tests'
DEFAULT_EXTS = ['c', 'cpp', 'html']
if sys.platform == 'win32':
    DEFAULT_EXTS.append('pyd')
elif sys.platform == 'darwin':
    DEFAULT_EXTS.extend(['dylib', 'so'])
else:
    DEFAULT_EXTS.append('so')

def get_filenames(root_dir: Path, rm_exts:tp.Iterable[str]) -> tp.Iterator[Path]:
    for ext in rm_exts:
        for p in root_dir.glob(f'**/*.{ext}'):
            pyx_path = None
            if ext in ['pyd', 'dylib', 'so']:
                pyx_path = p.with_name('.'.join([p.name.split('.')[0], 'pyx']))
            else:
                pyx_path = p.with_suffix('.pyx')
            if pyx_path is not None and pyx_path.exists():
                yield p

def clean(filenames: tp.Iterable[Path]):
    for fn in filenames:
        if fn.is_dir():
            shutil.rmtree(fn)
        else:
            fn.unlink()

def main():
    p = argparse.ArgumentParser()
    p.add_argument('-y', dest='force_yes', action='store_true', help='Disable prompt')
    p.add_argument(
        '--ext', dest='extensions', nargs='*',
        default=DEFAULT_EXTS, choices=DEFAULT_EXTS,
    )
    args = p.parse_args()
    build_dirs = [BASE_PATH / 'build', TEST_PATH / 'build']
    print('Removing Cython build files...')
    filenames = []
    for p in [SRC_PATH, TEST_PATH]:
        filenames.extend([fn for fn in get_filenames(p, args.extensions)])
    filenames.extend([p for p in build_dirs if p.exists()])
    if not len(filenames):
        print('No files found')
        return
    print(*filenames, sep='\n')
    assert len(set(filenames)) == len(filenames)

    if args.force_yes:
        clean(filenames)
        print('complete')
    else:
        s = input('proceed (y/n) --> ')
        if s.lower() == 'y':
            clean(filenames)
            print('complete')
        else:
            print('aborted')


if __name__ == '__main__':
    main()
