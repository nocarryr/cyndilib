from __future__ import annotations
from typing import ClassVar, Literal, Iterator, get_args
from pathlib import Path
import glob
import shutil
import subprocess
import shlex
import logging
import difflib

logging.basicConfig(level=logging.INFO, format='%(lineno)04d - %(message)s')
logger = logging.getLogger(__name__)

import click


HERE = Path(__file__).parent.resolve()

WRAPPER_ROOT = HERE / 'src' / 'cyndilib' / 'wrapper'


FileType = Literal['lib', 'dll', 'doc', 'header']
FileDirection = Literal['src', 'dst']
PlatformType = Literal['win', 'linux', 'mac']
PlatformTypes: list[PlatformType] = list(get_args(PlatformType))


def run_git(cmd: str, file_path: Path) -> None:
    """Run a git command on the given file path."""
    if not file_path.is_absolute():
        assert file_path.is_relative_to(HERE), f'File path {file_path} must be absolute or relative to {HERE}.'
    else:
        file_path = file_path.relative_to(HERE)
    cmd = f'git {cmd} {file_path}'
    logger.info(f'Running command: {cmd}')
    pr = subprocess.run(shlex.split(cmd), check=True, capture_output=True, text=True)
    if pr.stdout:
        logger.info(f'Command output: {pr.stdout.strip()}')
    if pr.stderr:
        logger.error(f'Command error: {pr.stderr.strip()}')
    if pr.returncode != 0:
        raise RuntimeError(f'Git command failed: {cmd}')



class FileHandler:
    LIB_SOURCES: ClassVar[Path]
    LIB_DESTS: ClassVar[Path]
    DOC_SOURCES: ClassVar[Path]
    DOC_DESTS: ClassVar[Path]
    HEADER_SOURCES: ClassVar[Path]|None = None
    HEADER_DESTS: ClassVar[Path]|None = None
    DLL_SOURCES: ClassVar[Path]|None = None
    DLL_DESTS: ClassVar[Path]|None = None
    FILE_TYPES: ClassVar[list[FileType]]
    def __init__(self, src_dir: Path, git_enable: bool = True, dry_run: bool = False) -> None:
        self.src_dir = src_dir
        self.dry_run = dry_run
        self.git_enable = git_enable

    @classmethod
    def get_platform_cls(cls, platform: PlatformType) -> type[FileHandler]:
        """Get the appropriate subclass for the given platform."""
        if platform == 'win':
            return WindowsFileHandler
        elif platform == 'linux':
            return LinuxFileHandler
        elif platform == 'mac':
            return MacFileHandler
        else:
            raise ValueError(f'Unknown platform: {platform}')

    @classmethod
    def get_path_definition(cls, file_type: FileType, file_direction: FileDirection) -> Path:
        """Get the source or destination path for the given file type and direction."""
        d: dict[FileType, dict[FileDirection, Path|None]] = {
            'lib': {'src': cls.LIB_SOURCES, 'dst': cls.LIB_DESTS},
            'dll': {'src': cls.DLL_SOURCES, 'dst': cls.DLL_DESTS},
            'doc': {'src': cls.DOC_SOURCES, 'dst': cls.DOC_DESTS},
            'header': {'src': cls.HEADER_SOURCES, 'dst': cls.HEADER_DESTS}
        }
        p = d[file_type][file_direction]
        if p is None:
            raise ValueError(f'File type {file_type} does not have a {file_direction} path defined.')
        return p

    def src_file(self, suffix: Path) -> Path:
        """Get the absolute source file path with the given suffix."""
        return self.src_dir / suffix

    def iter_sources(self, file_type: FileType) -> Iterator[Path]:
        """Iterate over source files for the given file type."""
        src = self.get_path_definition(file_type, 'src')
        src = self.src_file(src)
        if glob.has_magic(str(src)):
            parts = src.parts
            glob_part = parts[-1]
            src_parts = parts[:-1]
            src = Path(*src_parts)
            assert glob.has_magic(glob_part)
            assert not glob.has_magic(str(src))
            yield from src.glob(glob_part)
        else:
            yield src

    def iter_pairs(self, file_type: FileType) -> Iterator[tuple[Path, Path]]:
        """Iterate over pairs of source and destination files for the given file type."""
        dst = self.get_path_definition(file_type, 'dst')
        for src_path in self.iter_sources(file_type):
            if not src_path.exists():
                raise FileNotFoundError(f'Source file {src_path} does not exist.')
            dst_path = dst / src_path.name
            yield src_path, dst_path

    def copy_files(self, *file_types: FileType) -> None:
        """Copy files of the specified types from source to destination."""
        for file_type in file_types:
            logger.info(f'{self.__class__.__name__} copying files: {file_type}')
            for src_path, dst_path in self.iter_pairs(file_type):
                if dst_path.exists():
                    assert dst_path.is_file(), f'Destination path {dst_path} is not a file.'
                self.copy_file(src_path, dst_path, file_type)
                if file_type == 'doc' and src_path.name == 'libndi_licenses.txt':
                    # Special case for the license file, copy it to the root of the repository
                    dst_root = HERE / src_path.name
                    assert dst_root.exists()
                    self.copy_file(src_path, dst_root, file_type)
            self.after_copy_files(file_type)

    def after_copy_files(self, file_type: FileType) -> None:
        """Hook for any additional actions after copying files of a specific type."""
        pass

    def copy_file(self, src_path: Path, dst_path: Path, file_type: FileType) -> None:
        """Copy a single file from source to destination."""
        assert src_path.is_absolute(), f'Source path {src_path} must be absolute.'
        assert dst_path.is_absolute(), f'Destination path {dst_path} must be absolute.'
        src_rel = src_path.relative_to(self.src_dir)
        if not dst_path.is_relative_to(WRAPPER_ROOT):
            assert dst_path.is_relative_to(HERE)
            dst_rel = dst_path.relative_to(HERE)
        else:
            dst_rel = dst_path.relative_to(WRAPPER_ROOT)
        is_text = file_type in ['doc', 'header']

        if is_text:
            if not self.check_text_file(src_path, dst_path):
                logger.info(f'File {src_rel} has no modifications, skipping copy.')
                return
        logger.info(f'Copy {src_rel} -> {dst_rel}')
        if self.dry_run:
            return
        if is_text:
            logger.info(f'Copying text file {src_rel} -> {dst_rel}')
            txt = self.get_trimmed_text(src_path)
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            dst_path.write_text(txt, encoding='utf-8')
        else:
            shutil.copy2(src_path, dst_path)
        if self.git_enable:
            run_git('add', dst_path)

    def check_text_file(self, src_path: Path, dst_path: Path) -> bool:
        """Check if the text file has any modifications."""
        if not dst_path.exists():
            return False
        src_text = self.get_trimmed_text(src_path)
        dst_text = self.get_trimmed_text(dst_path)
        if src_text == dst_text:
            return False
        src_lines, dst_lines = src_text.splitlines(), dst_text.splitlines()
        diff = difflib.unified_diff(src_lines, dst_lines, fromfile=src_path.name, tofile=dst_path.name)
        diff_lines = list(diff)
        if len(diff_lines) == 0:
            return False
        return True

    def get_trimmed_text(self, path: Path) -> str:
        """Get the text from the file, trimmed of trailing whitespace."""
        txt = path.read_text(encoding='utf-8')
        lines = '\n'.join(line.rstrip() for line in txt.splitlines())
        return lines.rstrip() + '\n'  # Ensure the last line ends with a newline character

    def __call__(self) -> None:
        """Run the file copying process for all file types."""
        logger.info(f'Copying files for {self.__class__.__name__}...')
        self.copy_files(*self.FILE_TYPES)
        logger.info(f'Finished copying files for {self.__class__.__name__}.')



class WindowsFileHandler(FileHandler):
    LIB_SOURCES = Path('Lib') / 'x64' / 'Processing.NDI.Lib.*.lib'
    LIB_DESTS = WRAPPER_ROOT / 'lib'
    DLL_SOURCES = Path('Bin') / 'x64' / 'Processing.NDI.Lib.*.dll'
    DLL_DESTS = WRAPPER_ROOT / 'bin'
    DOC_SOURCES = Path('Bin') / 'x64' / 'Processing.NDI.Lib.Licenses.txt'
    DOC_DESTS = WRAPPER_ROOT / 'bin'
    HEADER_SOURCES = Path('Include') / '*.h'
    FILE_TYPES = ['lib', 'dll', 'doc']

    def copy_file(self, src_path: Path, dst_path: Path, file_type: FileType) -> None:
        assert dst_path.exists(), f'Destination path {dst_path} does not exist.'
        return super().copy_file(src_path, dst_path, file_type)



class LinuxFileHandler(FileHandler):
    LIB_SOURCES = Path('lib') / '__arch__' / 'libndi.so.*'
    LIB_DESTS = WRAPPER_ROOT / 'bin' / '__arch__'
    DOC_SOURCES = Path('licenses') / '*'# 'libndi_licenses.txt'
    DOC_DESTS = WRAPPER_ROOT / 'bin'
    HEADER_SOURCES = Path('include') / '*.h'
    HEADER_DESTS = WRAPPER_ROOT / 'include'
    FILE_TYPES = ['lib', 'doc', 'header']

    lib_filename: str|None = None
    old_lib_filename: str|None = None

    def _iter_arch_patterns(self, path: Path) -> Iterator[tuple[Path, Path]]:
        """Iterate over architecture-specific patterns in the given path."""
        parts = path.parts
        if parts[-1] == '__arch__':
            arch_parent = Path(*parts[:-1])
            arch_suffix = None
        else:
            arch_index = parts.index('__arch__')
            arch_parent = Path(*parts[:arch_index])
            arch_suffix = parts[arch_index + 1:]
            assert len(arch_suffix) == 1
            arch_suffix = arch_suffix[0]
        for arch_dir in arch_parent.iterdir():
            if not arch_dir.is_dir():
                continue
            if arch_suffix is None:
                yield arch_dir, arch_dir
            else:
                if glob.has_magic(str(arch_suffix)):
                    for p in arch_dir.glob(arch_suffix):
                        yield arch_dir, p
                else:
                    yield arch_dir, arch_dir / arch_suffix

    def iter_sources(self, file_type: FileType) -> Iterator[Path]:
        if file_type != 'lib':
            yield from super().iter_sources(file_type)
            return
        src = self.get_path_definition(file_type, 'src')
        if '__arch__' not in src.parts:
            yield from super().iter_sources(file_type)
            return
        src = self.src_file(src)
        for arch_dir, p in self._iter_arch_patterns(src):
            yield p

    def iter_pairs(self, file_type: FileType) -> Iterator[tuple[Path, Path]]:
        if file_type != 'lib':
            yield from super().iter_pairs(file_type)
            return
        src_rel = self.get_path_definition(file_type, 'src')
        dst = self.get_path_definition(file_type, 'dst')
        if '__arch__' not in dst.parts:
            yield from super().iter_pairs(file_type)
            return
        src = self.src_file(src_rel)
        sources_by_arch: dict[str, list[Path]] = {}
        for arch_dir, p in self._iter_arch_patterns(src):
            arch_name = arch_dir.name
            if arch_name not in sources_by_arch:
                sources_by_arch[arch_name] = []
            sources_by_arch[arch_name].append(p)
        dests_by_arch: dict[str, Path] = {}
        for arch_dir, p in self._iter_arch_patterns(dst):
            arch_name = arch_dir.name
            if arch_name not in dests_by_arch:
                dests_by_arch[arch_name] = arch_dir
        for arch_name, src_paths in sources_by_arch.items():
            assert arch_name in dests_by_arch, f'No destination path for architecture {arch_name} in {dests_by_arch.keys()}'
            dst_path = dests_by_arch[arch_name]
            assert dst_path.is_dir(), f'Destination path {dst_path} is not a directory.'
            for src_path in src_paths:
                yield src_path, dst_path / src_path.name

    def copy_file(self, src_path: Path, dst_path: Path, file_type: FileType) -> None:
        def find_dst_binary():
            dst_dir = dst_path.parent
            paths = [p for p in dst_dir.glob('libndi.so*') if not p.is_symlink()]
            assert len(paths) == 1, f'Multiple binaries found in {dst_path}: {paths} ({src_path=})'
            return paths[0]

        if file_type != 'lib':
            return super().copy_file(src_path, dst_path, file_type)

        if src_path.is_symlink():
            assert dst_path.is_symlink(), f'Source path {src_path} is a symlink, but destination path {dst_path} is not.'
            src_target, dst_target = src_path.resolve(), dst_path.resolve()
            if src_path.resolve() == dst_path.resolve():
                logger.info(f'Skipping symlink {src_path} -> {dst_path} (same target)')
                return
            src_path_rel = src_path.relative_to(self.src_dir)
            dst_path_rel = dst_path.relative_to(WRAPPER_ROOT)
            src_target = src_target.relative_to(self.src_dir)
            dst_target = dst_target.relative_to(WRAPPER_ROOT)
            logger.info(f'Symlink {src_path_rel} ({src_target}) -> {dst_path_rel} ({dst_target})')
        else:
            # Handle possible renaming of the lib's binary file.
            # Symlinks will likely be broken, but that's handled in `after_copy_files`.
            lib_filename = src_path.name
            if self.lib_filename is None:
                self.lib_filename = lib_filename
            else:
                assert self.lib_filename == lib_filename, f'Library filename {lib_filename} does not match previous {self.lib_filename}.'
            cur_binary = find_dst_binary()
            if cur_binary.name != src_path.name:
                old_lib_filename = cur_binary.name
                if self.old_lib_filename is None:
                    self.old_lib_filename = old_lib_filename
                else:
                    assert self.old_lib_filename == old_lib_filename, f'Old library filename {old_lib_filename} does not match previous {self.old_lib_filename}.'
                logger.info(f'Removing old binary {cur_binary.relative_to(WRAPPER_ROOT)} before copying {src_path.name}')
                if not self.dry_run:
                    if self.git_enable:
                        run_git('rm', cur_binary)
                        assert not cur_binary.exists(), f'Failed to remove old binary {cur_binary}'
                        shutil.copy2(src_path, dst_path)
                        run_git('add', dst_path)
                        if cur_binary.exists():
                            cur_binary.unlink()
                        return
                    else:
                        cur_binary.unlink()
            else:
                assert dst_path.exists(), f'Destination path {dst_path} does not exist.'
        return super().copy_file(src_path, dst_path, file_type)

    def after_copy_files(self, file_type: FileType) -> None:
        logger.info(f'Running after_copy_files for {file_type} in {self.__class__.__name__}')
        if file_type != 'lib':
            return
        if self.lib_filename is None:
            logger.warning('No library files copied, skipping after_copy_files.')
            return
        src = self.get_path_definition(file_type, 'src')
        src = self.src_file(src)
        assert '__arch__' in src.parts
        for arch_dir, p in self._iter_arch_patterns(src):
            arch_name = arch_dir.name
            dst = self.get_path_definition(file_type, 'dst').parent
            dst = dst / arch_name
            assert dst.is_dir(), f'Destination path {dst} is not a directory.'
            if self.old_lib_filename is not None:
                # This happens because git will likely rename after a
                # git rm and git add, so we need to check for the old binary
                logger.info(f'Checking for old binaries in {dst.relative_to(WRAPPER_ROOT)}')
                old_lib_path = dst / self.old_lib_filename
                if old_lib_path.exists():
                    logger.info(f'Removing old binary {old_lib_path.relative_to(WRAPPER_ROOT)}')
                    if not self.dry_run:
                        old_lib_path.unlink()
            assert self.lib_filename is not None, 'Library filename is not set.'
            logger.info(f'Checking symlinks in {dst.relative_to(WRAPPER_ROOT)} for {self.lib_filename}')
            symlinks = [p for p in dst.glob('libndi.so*') if p.is_symlink()]
            lib_file = dst / self.lib_filename
            assert lib_file.exists(), f'Library file {lib_file} does not exist.'
            for symlink in symlinks:
                symlink_target = symlink.resolve()
                if symlink_target == lib_file.resolve():
                    continue
                logger.info(f'Relinking symlink {symlink.relative_to(WRAPPER_ROOT)} to {lib_file.relative_to(WRAPPER_ROOT)}')
                if self.dry_run:
                    continue
                symlink.unlink()
                symlink.symlink_to(lib_file.relative_to(symlink.parent))
                assert symlink.resolve() == lib_file.resolve()
                if self.git_enable:
                    run_git('add', symlink)


class MacFileHandler(FileHandler):
    LIB_SOURCES = Path('lib') / 'macOS' / 'libndi.dylib'
    LIB_DESTS = WRAPPER_ROOT / 'bin'
    DOC_SOURCES = Path('licenses') / 'libndi_licenses.txt'
    DOC_DESTS = WRAPPER_ROOT / 'bin'
    # HEADER_SOURCES = Path('include') / '*.h'
    # HEADER_DESTS = WRAPPER_ROOT / 'include'
    FILE_TYPES = ['lib', 'doc']

    def copy_file(self, src_path: Path, dst_path: Path, file_type: FileType) -> None:
        assert dst_path.exists(), f'Destination path {dst_path} does not exist.'
        return super().copy_file(src_path, dst_path, file_type)


def undo_working_copy(lib_version: str|None) -> None:
    wrapper_dir = WRAPPER_ROOT.relative_to(HERE) / '*'
    logger.info(f'Undoing working copy in {wrapper_dir}...')
    subprocess.run(shlex.split(f'git restore --staged {wrapper_dir}'), check=True)
    subprocess.run(shlex.split(f'git restore {wrapper_dir}'), check=True)
    subprocess.run(shlex.split(f'git restore --staged libndi_licenses.txt'), check=True)
    subprocess.run(shlex.split(f'git restore libndi_licenses.txt'), check=True)

    if lib_version is not None:
        lib_filename = f'libndi.so.{lib_version}'
        for p in (WRAPPER_ROOT / 'bin').iterdir():
            if not p.is_dir():
                continue
            so_file = p / lib_filename
            if so_file.exists():
                logger.info(f'Removing old binary {so_file.relative_to(WRAPPER_ROOT)}')
                so_file.unlink()


@click.group()
def cli():
    pass

@cli.command()
@click.option(
    '--src',
    type=click.Path(path_type=Path),
    required=True,
    help='Source directory of the NDI SDK files.',
)
@click.option(
    '--platform',
    type=click.Choice(PlatformTypes, case_sensitive=False),
    required=True,
    help='Platform to copy files for.',
)
@click.option(
    '--dry-run',
    is_flag=True,
    help='Do not copy files, just print what would be done.',
)
@click.option(
    '--git',
    is_flag=True,
    help='Enable git commands to add copied files.',
)
def copy_files(src: Path, platform: PlatformType, dry_run: bool, git: bool) -> None:
    """Copy NDI SDK files to the wrapper directory."""
    src_dir = src.expanduser().resolve()
    if not src_dir.is_dir():
        raise ValueError(f'Source directory {src_dir} does not exist or is not a directory.')
    handler_cls = FileHandler.get_platform_cls(platform)
    file_handler = handler_cls(src_dir, git_enable=git, dry_run=dry_run)
    file_handler()

@cli.command()
@click.option(
    '--lib-version',
    type=str,
    required=False,
    help='Dotted version of the *current* NDI library, e.g. "6.1.1".',
)
def undo(lib_version: str|None) -> None:
    """Undo the working copy changes in the wrapper directory.

    This will unstage and restore all files in the wrapper directory.
    Any binaries with the specified version will be removed.
    """
    undo_working_copy(lib_version)



if __name__ == '__main__':
    cli()
