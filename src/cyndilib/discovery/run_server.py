"""
Utilities for running the built-in :term:`Discovery Server`

.. versionadded:: 0.1.4
"""
from __future__ import annotations

import enum
import importlib.resources
import platform
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import cast

from .exceptions import DiscoveryServerUnavailableError


class Platform(enum.Enum):
    """Enumeration of supported platforms for running the :term:`Discovery Server`
    """
    win32 = enum.auto()
    """32-bit Windows platform"""
    win64 = enum.auto()
    """64-bit Windows platform"""
    macos = enum.auto()
    """macOS platform"""
    linux_i686 = enum.auto()
    """Linux platform (i686)"""
    linux_x86_64 = enum.auto()
    """Linux platform (x86_64)"""

    @classmethod
    def current(cls) -> Platform | None:
        """Get the member matching the current platform
        """
        is_x64 = sys.maxsize > 2**32
        if sys.platform == "win32":
            return cls.win64 if is_x64 else cls.win32
        elif sys.platform == "darwin":
            return cls.macos
        elif sys.platform == "linux":
            if platform.machine() == "x86_64":
                return cls.linux_x86_64
            elif platform.machine() == "i686":
                return cls.linux_i686




_platform_bin_map: dict[Platform, Path] = {
    Platform.win32: Path('utilities') / 'Win_x86' / "NDI Discovery Service.exe",
    Platform.win64: Path('utilities') / 'Win_x64' / "NDI Discovery Service.exe",
    Platform.macos: Path('utilities') / 'Apple' / "Application.Mac.NDI.DirectoryService",
    Platform.linux_i686: Path('i686-linux-gnu') / "ndi-discovery-server",
    Platform.linux_x86_64: Path('x86_64-linux-gnu') / "ndi-discovery-server",
}


def get_run_server_path() -> Path:
    """Get the path to the discovery server executable within the package

    Raises:
        DiscoveryServerUnavailableError: If the discovery server is unavailable
            for the current platform
    """
    _bin_path = importlib.resources.files("cyndilib.wrapper.bin")
    bin_path = cast(Path, _bin_path)
    plat = Platform.current()
    if plat is None:
        raise DiscoveryServerUnavailableError(
            "The built-in discovery server is unavailable for the current platform"
        )
    return bin_path / _platform_bin_map[plat]


def run() -> None:
    """Run the discovery server as a subprocess

    While running, the stdout and stderr of the discovery server will be
    displayed in the terminal.  The process will continue running until
    interrupted by the user (e.g., via :kbd:`Ctrl+C`).

    .. tip::

        This can be run directly by the following command:

        .. code-block:: console

            cyndilib-discovery-server

    Raises:
        DiscoveryServerUnavailableError: If the discovery server is unavailable
            for the current platform

    """
    path = get_run_server_path()
    creationflags = 0 if sys.platform != "win32" else subprocess.CREATE_NEW_PROCESS_GROUP

    proc = subprocess.Popen([str(path)], creationflags=creationflags)
    try:
        proc.poll()
        if proc.returncode is not None:
            raise RuntimeError(f"Discovery server exited with return code {proc.returncode}")
        while proc.returncode is None:
            proc.poll()
            time.sleep(0.1)
        if proc.returncode is not None:
            raise RuntimeError(f"Discovery server exited with return code {proc.returncode}")
    except KeyboardInterrupt:
        proc.send_signal(signal.SIGINT)
        proc.wait(5)
    finally:
        if proc.returncode is None:
            proc.terminate()
            proc.wait()



if __name__ == "__main__":
    run()
