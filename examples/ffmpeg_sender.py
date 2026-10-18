from __future__ import annotations

from typing import NamedTuple, Literal, Generator, Any, cast, get_args
from typing_extensions import Self
import enum
import io
import subprocess
import shlex
from fractions import Fraction
from contextlib import contextmanager

import numpy as np

import click

from cyndilib import (
    Sender,
    VideoSendFrame,
    AudioSendFrame,
    FourCC,
    AudioReference,
)

TestSource = Literal[
    'testsrc2', 'yuvtestsrc', 'rgbtestsrc', 'smptebars', 'smptehdbars',
    'zoneplate', 'colorspectrum',
]

FF_CMD = '{ffmpeg} -f lavfi -i {source}=size={xres}x{yres}:rate={fps} \
    -pix_fmt {pix_fmt.name} -f rawvideo pipe: '



class PixFmt(enum.Enum):
    """Maps ffmpeg's ``pix_fmt`` names to their corresponding
    :class:`FourCC <cyndilib.wrapper.ndi_structs.FourCC>` types
    """
    uyvy422 = FourCC.UYVY   #: uyvy422
    nv12 = FourCC.NV12      #: nv12
    rgba = FourCC.RGBA      #: rgba
    rgb0 = FourCC.RGBX      #: rgb0
    bgra = FourCC.BGRA      #: bgra
    bgr0 = FourCC.BGRX      #: bgr0
    p216be = FourCC.P216    #: p216be
    yuv420p = FourCC.I420   #: yuv420p (i420)

    @classmethod
    def from_str(cls, name: str) -> Self:
        return cls.__members__[name]


class Options(NamedTuple):
    """Options set through the cli
    """
    source: TestSource                  #: Source to use for the test pattern
    pix_fmt: PixFmt                     #: Pixel format to send
    xres: int                           #: Horizontal resolution
    yres: int                           #: Vertical resolution
    fps: str                            #: Frame rate
    sender_name: str = 'ffmpeg_sender'  #: NDI name for the sender
    sine_freq: float = 1000.0           #: Frequency of the sine wave
    sine_vol_dB: float = -20            #: Volume of the sine wave in dBVU
    sample_rate: int = 48000            #: Sample rate of the audio
    audio_channels: int = 2             #: Number of audio channels
    audio_reference: AudioReference = AudioReference.dBVU #: Audio reference level
    ffmpeg: str = 'ffmpeg'              #: Name/Path of the "ffmpeg" executable


def parse_frame_rate(fr: str) -> Fraction:
    """Helper for NTSC frame rates (29.97, 59.94)
    """
    if '/' in fr:
        n, d = [int(s) for s in fr.split('/')]
    elif '.' in fr:
        n = round(float(fr)) * 1000
        d = 1001
    else:
        n = int(fr)
        d = 1
    return Fraction(n, d)

class Signal:
    """Signal helper

    Allows for iteration over samples of a sine wave signal aligned with the
    frame rate.
    """
    def __init__(self, opts: Options) -> None:
        self.fps = parse_frame_rate(opts.fps)
        self.opts = opts
        self.amplitude = 10 ** (opts.sine_vol_dB / 20.0)
        spf = opts.sample_rate / self.fps
        if spf % 1 == 0:
            samples_per_frame = [int(spf)]
            max_samples_per_frame = int(spf)
        else:
            assert opts.sample_rate == 48000
            if self.fps == Fraction(30000, 1001):
                # These sample counts will align with the frame rate every 5 frames.
                samples_per_frame = [
                    1602, 1601, 1602, 1601, 1602,
                ]
            elif self.fps == Fraction(60000, 1001):
                # These sample counts will align with the frame rate every 5 frames.
                samples_per_frame = [
                    801, 801, 801, 800, 801,
                ]
            total_samples = sum(samples_per_frame)
            assert total_samples == spf * len(samples_per_frame)
            max_samples_per_frame = max(samples_per_frame)
        self.samples_per_frame = samples_per_frame
        self.max_samples_per_frame = max_samples_per_frame

        one_sample = Fraction(1, opts.sample_rate)
        fc = 1 / Fraction(opts.sine_freq)
        self.samples_per_cycle = fc / one_sample
        self.cycles_per_frame = [spf / self.samples_per_cycle for spf in samples_per_frame]
        self.total_samples = 0

    @property
    def time_offset(self) -> float:
        """Time offset in seconds for the current frame."""
        return self.total_samples / self.opts.sample_rate

    def __iter__(self):
        while True:
            for spf in self.samples_per_frame:
                sig = gen_sine_wave(
                    sample_rate=self.opts.sample_rate,
                    num_channels=self.opts.audio_channels,
                    center_freq=self.opts.sine_freq,
                    amplitude=self.amplitude,
                    num_samples=spf,
                    t_offset=self.time_offset,
                )
                assert sig.shape == (self.opts.audio_channels, spf)
                yield sig
                self.total_samples += spf


def gen_sine_wave(
    sample_rate: int,
    num_channels: int,
    center_freq: float,
    num_samples: int,
    amplitude: float = 1.0,
    t_offset: float = 0.0,
):
    """Build a sine wave signal
    """
    t = np.arange(num_samples) / sample_rate
    t += t_offset
    sig = amplitude * np.sin(2 * np.pi * center_freq * t)
    sig = np.reshape(sig, (1, num_samples))
    if num_channels > 1:
        sig = np.repeat(sig, num_channels, axis=0)
    assert sig.shape == (num_channels, num_samples)
    return sig.astype(np.float32)


@contextmanager
def ffmpeg_proc(opts: Options) -> Generator[subprocess.Popen[bytes], Any, None]:
    """Context manager for the ffmpeg subprocess generating frames
    """
    ff_cmd = FF_CMD.format(**opts._asdict())
    ff_proc = subprocess.Popen(shlex.split(ff_cmd), stdout=subprocess.PIPE)
    try:
        ff_proc.poll()
        if ff_proc.returncode is None:
            yield ff_proc
    finally:
        ff_proc.kill()


def send(opts: Options) -> None:
    """Send frames generated by ffmpeg's ``testsrc2`` as an |NDI| stream

    The raw frames generated by ffmpeg are sent to a pipe and read from its
    :attr:`~subprocess.Popen.stdout`.  The data is then fed directly to
    :meth:`cyndilib.sender.Sender.write_video_async` using an
    intermediate :class:`memoryview`
    """
    sender = Sender(
        opts.sender_name,
        discovery={
            'enabled': True,
        },
    )

    # Build a VideoSendFrame and set its resolution and frame rate
    # to match the options argument
    vf = VideoSendFrame()
    vf.set_resolution(opts.xres, opts.yres)
    fr = parse_frame_rate(opts.fps)
    vf.set_frame_rate(fr)
    vf.set_fourcc(opts.pix_fmt.value)

    sig_generator = Signal(opts)
    sample_iter = iter(sig_generator)

    # Build an AudioSendFrame and set its properties to match the options argument
    af = AudioSendFrame()
    af.sample_rate = opts.sample_rate
    af.num_channels = opts.audio_channels
    af.reference_level = opts.audio_reference

    # Set `max_num_samples` to the number of samples per frame
    af.set_max_num_samples(sig_generator.max_samples_per_frame)

    # Add the VideoSendFrame and AudioSendFrame to the sender
    sender.set_video_frame(vf)
    sender.set_audio_frame(af)

    # Pre-allocate a bytearray to hold frame data and create a view of it
    # So we can buffer into it from ffmpeg then pass directly to the sender
    frame_size_bytes = vf.get_data_size()
    ba = bytearray(frame_size_bytes)
    mv = memoryview(ba)

    i = 0
    frame_sent = False

    with sender:
        with ffmpeg_proc(opts) as ff_proc:
            stdout = cast(io.BytesIO, ff_proc.stdout)
            while True:
                i += 1
                if ff_proc.returncode is not None:
                    break
                # Read from the ffmpeg process into a view of the bytearray
                num_read = stdout.readinto(mv)

                # The first few reads might be empty, ignore
                if num_read == 0:
                    if frame_sent:
                        # If we've sent a frame and there's no output,
                        # ffmpeg has likely quit without setting returncode
                        break
                    elif i > 1000:
                        # Check for ffmpeg startup errors
                        print('Timeout waiting for ffmpeg to produce output')
                        break
                    continue
                frame_sent = True

                # Pass the memoryview of the video frame data directly to the sender
                # (using the buffer protocol)
                sender.write_video_async(mv)


                # Generate the next audio frame's worth of samples and write to the sender.
                # Since the video was sent asynchronously,
                # the sender will handle syncing the audio and video frames.
                samples = next(sample_iter)
                sender.write_audio(samples)

                if i % 10 == 0:
                    ff_proc.poll()



@click.command()
@click.option(
    '--source',
    type=click.Choice(
        choices=[m for m in get_args(TestSource)],
    ),
    default='testsrc2',
    show_default=True,
    help='Name of the ffmpeg test source to use',
)
@click.option(
    '--pix-fmt',
    type=click.Choice(choices=[m.name for m in PixFmt]),
    default=PixFmt.uyvy422.name,
    show_default=True,
    show_choices=True,
)
@click.option('-x', '--x-res', type=int, default=1920, show_default=True)
@click.option('-y', '--y-res', type=int, default=1080, show_default=True)
@click.option('--fps', type=str, default='30', show_default=True)
@click.option(
    '-n', '--sender-name',
    type=str,
    default='ffmpeg_sender',
    show_default=True,
    help='NDI name for the sender',
)
@click.option('-f', '--sine-freq', type=float, default=1000.0, show_default=True)
@click.option(
    '-s', '--sine-vol', type=float, default=-20.0, show_default=True,
    help='Volume of the sine wave in dB (unit depends on audio reference)',
)
@click.option(
    '--audio-reference',
    type=click.Choice([m.name for m in AudioReference]),
    default=AudioReference.dBVU.name,
    show_default=True,
    help='Audio reference level',
)
@click.option('--sample-rate', type=int, default=48000, show_default=True)
@click.option('--audio-channels', type=int, default=2, show_default=True)
@click.option(
    '--ffmpeg',
    type=str,
    default='ffmpeg',
    show_default=True,
    help='Name/Path of the "ffmpeg" executable',
)
def main(
    source: TestSource,
    pix_fmt: str,
    x_res: int,
    y_res: int,
    fps: str,
    sender_name: str,
    sine_freq: float,
    sine_vol: float,
    audio_reference: str,
    sample_rate: int,
    audio_channels: int,
    ffmpeg: str
):
    opts = Options(
        source=source,
        pix_fmt=PixFmt.from_str(pix_fmt),
        xres=x_res,
        yres=y_res,
        fps=fps,
        sine_freq=sine_freq,
        sine_vol_dB=sine_vol,
        audio_reference=AudioReference[audio_reference],
        sample_rate=sample_rate,
        audio_channels=audio_channels,
        sender_name=sender_name,
        ffmpeg=ffmpeg,
    )
    send(opts)


if __name__ == '__main__':
    main()
