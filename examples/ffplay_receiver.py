from __future__ import annotations

from typing import NamedTuple, TYPE_CHECKING
from typing_extensions import Self
import enum
import time
import subprocess
import shlex

import click

from cyndilib.wrapper.ndi_structs import FourCC
from cyndilib.wrapper.ndi_recv import RecvColorFormat, RecvBandwidth
from cyndilib.video_frame import VideoFrameSync
from cyndilib.receiver import Receiver
from cyndilib.finder import Finder
if TYPE_CHECKING:
    from cyndilib.finder import Source


FF_PLAY = '{ffplay} -video_size {xres}x{yres} -pixel_format {pix_fmt} -f rawvideo -i pipe:'
"""ffplay command line format"""


pix_fmts = {
    FourCC.UYVY: 'uyvy422',
    FourCC.NV12: 'nv12',
    FourCC.RGBA: 'rgba',
    FourCC.BGRA: 'bgra',
    FourCC.RGBX: 'rgba',
    FourCC.BGRX: 'bgra',
}
"""Mapping of :class:`FourCC <cyndilib.wrapper.ndi_structs.FourCC>` types to
ffmpeg's ``pix_fmt`` definitions
"""


class RecvFmt(enum.Enum):
    """Pixel format to receive (mapped to values of
    :class:`cyndilib.wrapper.ndi_recv.RecvColorFormat`)
    """
    uyvy = RecvColorFormat.UYVY_RGBA    #: UYVY (RGBA if alpha is present)
    rgb = RecvColorFormat.RGBX_RGBA     #: RGB / RGBA
    bgr = RecvColorFormat.BGRX_BGRA     #: BGR / BGRA

    @classmethod
    def from_str(cls, name: str) -> Self:
        return cls.__members__[name]


class Bandwidth(enum.Enum):
    """Receive bandwidth
    """
    lowest = RecvBandwidth.lowest       #: Lowest
    highest = RecvBandwidth.highest     #: Highest

    @classmethod
    def from_str(cls, name: str) -> Self:
        return cls.__members__[name]


class Options(NamedTuple):
    """Options set through the cli
    """
    sender_name: str = 'ffmpeg_sender'
    """The name of the |NDI| source to connect to"""

    recv_fmt: RecvFmt = RecvFmt.uyvy
    """Receive pixel format"""

    recv_bandwidth: Bandwidth = Bandwidth.highest
    """Receive bandwidth"""

    ffplay: str = 'ffplay'
    """Name/Path of the ``ffplay`` executable"""


def get_source(finder: Finder, name: str) -> Source:
    """Use the Finder to search for an NDI source by name using either its
    full name or its :attr:`~cyndilib.finder.Source.stream_name`
    """
    click.echo('waiting for ndi sources...')
    finder.wait_for_sources(10)
    for source in finder:
        if source.name == name or source.stream_name == name:
            return source
    raise Exception(f'source not found. {finder.get_source_names()=}')


def wait_for_first_frame(receiver: Receiver) -> None:
    """The first few frames contain no data. Capture frames until the first
    non-empty one
    """
    vf = receiver.frame_sync.video_frame
    assert vf is not None
    frame_rate = vf.get_frame_rate()
    wait_time = float(1 / frame_rate)
    click.echo('waiting for frame...')
    while receiver.is_connected():
        receiver.frame_sync.capture_video()
        resolution = vf.get_resolution()
        if min(resolution) > 0 and vf.get_data_size() > 0:
            click.echo('have frame')
            return
        time.sleep(wait_time)


def play(options: Options) -> None:
    """Create the :class:`~cyndilib.receiver.Receiver` and send the frames to
    ``ffplay``
    """
    # Get the NDI source and keep the Finder open until exit
    with Finder() as finder:
        source = get_source(finder, options.sender_name)

        # Build the receiver and video frame
        receiver = Receiver(
            color_format=options.recv_fmt.value,
            bandwidth=options.recv_bandwidth.value,
        )
        vf = VideoFrameSync()
        frame_sync = receiver.frame_sync
        frame_sync.set_video_frame(vf)

        # Set the receiver source and wait for it to connect
        receiver.set_source(source)
        click.echo(f'connecting to "{source.name}"...')
        i = 0
        while not receiver.is_connected():
            if i > 30:
                raise Exception('timeout waiting for connection')
            time.sleep(.5)
            i += 1
        click.echo('connected')

        proc: subprocess.Popen|None = None

        try:
            wait_for_first_frame(receiver)
            # At this point we should have received a frame, so the pixel format,
            # resolution and frame rate should be populated.
            fourcc = vf.get_fourcc()
            frame_rate = vf.get_frame_rate()
            wait_time = float(1 / frame_rate)
            xres, yres = vf.get_resolution()

            cmd_str = FF_PLAY.format(
                xres=xres,
                yres=yres,
                pix_fmt=pix_fmts[fourcc],
                ffplay=options.ffplay,
            )
            click.echo(f'{cmd_str=}')
            proc = subprocess.Popen(shlex.split(cmd_str), stdin=subprocess.PIPE)
            assert proc.stdin is not None

            # Since we already have a frame with data, write it to ffplay
            # Note that the frame object itself is directly used as the data source
            # (since `VideoFrameSync` supports the buffer protocol)
            proc.stdin.write(vf)

            while receiver.is_connected():
                # Not the best timing method, but we're using `FrameSync` to
                # capture frames, so it'll correct things for us (within reason).
                time.sleep(wait_time)
                receiver.frame_sync.capture_video()
                proc.poll()
                if proc.returncode is not None:
                    break
                proc.stdin.write(vf)

        finally:
            if proc is not None:
                proc.kill()


@click.command()
@click.option(
    '-s', '--sender-name',
    type=str,
    default='ffmpeg_sender',
    show_default=True,
    help='The NDI source name to connect to',
)
@click.option(
    '-f', '--recv-fmt',
    type=click.Choice(choices=[m.name for m in RecvFmt]),
    default='uyvy',
    show_default=True,
    show_choices=True,
    help='Pixel format'
)
@click.option(
    '-b', '--recv-bandwidth',
    type=click.Choice(choices=[m.name for m in Bandwidth]),
    default='highest',
    show_default=True,
    show_choices=True,
)
@click.option(
    '--ffplay',
    type=str,
    default='ffplay',
    show_default=True,
    help='Name/Path of the "ffplay" executable',
)
def main(sender_name: str, recv_fmt: str, recv_bandwidth: str, ffplay: str):
    options = Options(
        sender_name=sender_name,
        recv_fmt=RecvFmt.from_str(recv_fmt),
        recv_bandwidth=Bandwidth.from_str(recv_bandwidth),
        ffplay=ffplay,
    )
    play(options)


if __name__ == '__main__':
    main()
