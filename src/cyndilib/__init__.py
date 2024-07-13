import os
import sys
if sys.version_info < (3, 9):
    import importlib_resources
else:
    import importlib.resources as importlib_resources

if sys.platform == 'win32':
    dll_dir = importlib_resources.files('cyndilib.wrapper.bin')
    os.add_dll_directory(str(dll_dir))

def get_include() -> str:
    p = importlib_resources.files('cyndilib.wrapper.include')
    return str(p)


from .wrapper import *
from .audio_frame import *
from .finder import Source, Finder
from .framesync import FrameSync
from .metadata_frame import *
from .receiver import Receiver
from .sender import Sender
from .video_frame import *
