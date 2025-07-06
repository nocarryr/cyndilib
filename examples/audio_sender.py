from __future__ import annotations
from typing import NamedTuple, Generator
from fractions import Fraction
import time

import numpy as np
import click

from cyndilib.wrapper.ndi_structs import FourCC
from cyndilib.video_frame import VideoSendFrame
from cyndilib.audio_frame import AudioSendFrame
from cyndilib.sender import Sender


FloatArray2D = np.ndarray[tuple[int, int], np.dtype[np.float32]]
FloatArray3D = np.ndarray[tuple[int, int, int], np.dtype[np.float32]]



class Options(NamedTuple):
    """Options set through the cli
    """
    xres: int                           #: Horizontal resolution
    yres: int                           #: Vertical resolution
    fps: int                            #: Frame rate
    sine_freq: float = 1000.0           #: Frequency of the sine wave
    sine_vol_dBVU: float = -20          #: Volume of the sine wave in dBVU
    sample_rate: int = 48000            #: Sample rate of the audio
    audio_channels: int = 2             #: Number of audio channels
    num_frames: int|None = None         #: Number of frames to send, or None for infinite
    sender_name: str = 'audio_sender'   #: NDI name for the sender



def build_blank_frame(xres: int, yres: int):
    """Build an array of black pixels in UYVY422 format."""
    cw, ch = xres >> 1, yres
    num_bytes = xres * yres + (cw * ch * 2)
    data = np.zeros(num_bytes, dtype=np.uint8)
    data[1::2] = 16   # Y channel
    data[0::2] = 128  # U/V channels
    return data


def gen_sine_wave(
    sample_rate: int,
    num_channels: int,
    center_freq: float,
    num_samples: int,
    amplitude: float = 1.0,
    t_offset: float = 0.0,
):
    """Build a sine wave signal.
    """
    t = np.arange(num_samples) / sample_rate
    t += t_offset
    sig = amplitude * np.sin(2 * np.pi * center_freq * t)
    sig = np.reshape(sig, (1, num_samples))
    if num_channels > 1:
        sig = np.repeat(sig, num_channels, axis=0)
    assert sig.shape == (num_channels, num_samples)
    return sig.astype(np.float32)



class Signal:
    """Signal helper

    Allows for iteration over samples of a sine wave signal aligned with the
    frame rate.
    """
    def __init__(self, opts: Options) -> None:
        self.opts = opts
        self.amplitude = 10 ** (opts.sine_vol_dBVU / 20.0)
        self.samples_per_frame = opts.sample_rate // opts.fps
        one_sample = Fraction(1, opts.sample_rate)
        fc = 1 / Fraction(opts.sine_freq)
        self.samples_per_cycle = fc / one_sample
        self.cycles_per_frame = self.samples_per_frame / self.samples_per_cycle
        self.frame_count = 0

    @property
    def time_offset(self) -> float:
        """Time offset in seconds for the current frame."""
        return self.frame_count / self.opts.fps

    def __iter__(self) -> Generator[FloatArray2D, None, None]:
        while True:
            sig = gen_sine_wave(
                sample_rate=self.opts.sample_rate,
                num_channels=self.opts.audio_channels,
                center_freq=self.opts.sine_freq,
                amplitude=self.amplitude,
                num_samples=self.samples_per_frame,
                t_offset=self.time_offset,
            )
            assert sig.shape == (self.opts.audio_channels, self.samples_per_frame)
            yield sig
            self.frame_count += 1



def send(opts: Options) -> None:
    """Send a sine wave audio signal as an NDI stream."""

    sig_generator = Signal(opts)

    sender = Sender(opts.sender_name)

    # Build a VideoSendFrame and set its resolution and frame rate
    # to match the options argument.
    vf = VideoSendFrame()
    vf.set_resolution(opts.xres, opts.yres)
    vf.set_frame_rate(Fraction(opts.fps))
    vf.set_fourcc(FourCC.UYVY)

    # Build an AudioSendFrame and set its sample rate and number of channels
    af = AudioSendFrame()
    af.sample_rate = opts.sample_rate
    af.num_channels = opts.audio_channels

    # Set `max_num_samples` to the number of samples per frame
    af.set_max_num_samples(sig_generator.samples_per_frame)

    # Add the video and audio frames to the sender
    sender.set_video_frame(vf)
    sender.set_audio_frame(af)

    # Build data for a blank video frame
    vid_data = build_blank_frame(opts.xres, opts.yres)

    start_time = time.monotonic()
    num_frames_sent = 0

    with sender:
        for samples in sig_generator:
            if opts.num_frames is not None:
                if num_frames_sent >= opts.num_frames:
                    break

            # Write the video and audio data to the sender
            # Note that we don't have to wait in between frames,
            # as the sender will handle the timing for us.
            sender.write_video_and_audio(
                video_data=vid_data,
                audio_data=samples,
            )

            num_frames_sent += 1
            now = time.monotonic()
            elapsed = now - start_time
            click.echo(f'\rFrames: {num_frames_sent:04d}\tDuration: {elapsed:.3f}s', nl=False)



@click.command()
@click.option('--xres', type=int, default=640, show_default=True)
@click.option('--yres', type=int, default=480, show_default=True)
@click.option('--fps', type=int, default=30, show_default=True)
@click.option('-f', '--sine-freq', type=float, default=1000.0, show_default=True)
@click.option('-s', '--sine-vol', type=float, default=-20.0, show_default=True)
@click.option('--sample-rate', type=int, default=48000, show_default=True)
@click.option('--audio-channels', type=int, default=2, show_default=True)
@click.option(
    '-n', '--num-frames', type=int, default=None, show_default=True,
    help='Number of frames to send, or None for infinite',
)
@click.option(
    '--sender-name', type=str, default='audio_sender', show_default=True,
    help='NDI name for the sender',
)
def main(
    xres: int,
    yres: int,
    fps: int,
    sine_freq: float,
    sine_vol: float,
    sample_rate: int,
    audio_channels: int,
    num_frames: int | None,
    sender_name: str,
) -> None:
    """Send a sine wave audio signal as an NDI stream."""
    opts = Options(
        xres=xres,
        yres=yres,
        fps=fps,
        sine_freq=sine_freq,
        sine_vol_dBVU=sine_vol,
        sample_rate=sample_rate,
        audio_channels=audio_channels,
        num_frames=num_frames,
        sender_name=sender_name,
    )
    try:
        send(opts)
    finally:
        click.echo('')


if __name__ == '__main__':
    main()
