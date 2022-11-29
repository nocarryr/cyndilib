import os
import sys
from pathlib import Path
from pkg_resources import resource_filename

if sys.platform == 'win32':
    dll_dir = Path(resource_filename(__name__, '')) / 'wrapper' / 'bin'
    os.add_dll_directory(dll_dir)

def get_include() -> str:
    return resource_filename('cyndilib.wrapper.include', '')
