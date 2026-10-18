from __future__ import annotations
from typing import NamedTuple, TYPE_CHECKING
import time

import click
import numpy as np
import sounddevice as sd

from cyndilib import (
    AudioFrameSync,
    AudioReference,
    VideoFrameSync,
    Receiver,
    Finder,
)
if TYPE_CHECKING:
    from cyndilib.finder import Source



class Options(NamedTuple):
    """Options set through the cli
    """
    source_name: str = 'audio_sender'   #: NDI name for the source to receive from
    audio_channels: int = 2             #: Number of audio channels
    sample_rate: int = 48000            #: Sample rate of the audio
    audio_reference: AudioReference = AudioReference.dBVU
    """Audio reference level"""
    block_size: int = 1024              #: Block size for sounddevice output stream
    sender_name: str = 'audio_sender'   #: NDI name for the sender



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



def play(options: Options) -> None:
    """Receive audio from an NDI source using :class:`~cyndilib.audio_frame.AudioFrameSync`
    and play it using sounddevice.
    """

    # This is the number of samples we will capture in each chunk.
    # It's important to choose a chunk size that's larger than the number of
    # samples in a frame, otherwise the FrameSync won't have enough room to
    # buffer the incoming audio data.
    chunk_size = 6400

    receiver = Receiver(
        discovery={
            'enabled': True,
        }
    )

    # We're using a VideoFrameSync here even though we only care about the audio frames.
    # It's only needed so the FrameSync can manage timing for us.
    vf = VideoFrameSync()
    receiver.frame_sync.set_video_frame(vf)

    af = AudioFrameSync()
    af.num_channels = options.audio_channels
    af.sample_rate = options.sample_rate
    af.reference_level = options.audio_reference

    # Set `af.num_samples` to the number of samples we want to capture in each chunk.
    af.num_samples = chunk_size
    receiver.frame_sync.set_audio_frame(af)

    # We'll use this array to feed data to sounddevice. The shape will be (chunk_size, num_channels).
    write_samples = np.zeros((chunk_size, options.audio_channels), dtype=np.float32)

    # This is a transposed view of the same array to read data from the audio frame
    # (which has shape (num_channels, num_samples)).
    # We're doing this since sounddevice expects contiguous arrays.
    read_samples = write_samples.T

    with Finder() as finder:
        source = get_source(finder, options.source_name)

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
        click.echo('receiving audio... Press Ctrl-C to stop.')

        i = 0
        with sd.OutputStream(
            samplerate=options.sample_rate,
            channels=options.audio_channels,
            dtype='float32',
            blocksize=options.block_size,
        ) as stream:
            while receiver.is_connected():
                if i > 0:
                    # Simulate waiting for the next frame based on the frame rate.
                    time.sleep(float(1 / vf.get_frame_rate()))

                # Even though we aren't interested in the video frames,
                # we need to capture them so the FrameSync can advance and make the audio frames available.
                receiver.frame_sync.capture_video()

                samples_available = receiver.frame_sync.audio_samples_available()
                if samples_available < chunk_size:
                    continue

                # If there are enough samples available to fill our chunk size,
                # read them into our transposed read_samples array, which will feed into sounddevice.
                receiver.frame_sync.capture_audio(chunk_size)

                # Fill read_samples using the audio frame's buffer interface
                read_samples[:,:] = af

                # Now write the samples to sounddevice.
                # Since `write_samples` and `read_samples` are views of the same data,
                # this will write the audio data we just read from the frame.
                stream.write(write_samples)

                i += 1


@click.command()
@click.option(
    '-s', '--source-name',
    type=str,
    default='audio_sender',
    show_default=True,
    help='NDI source name to receive from',
)
@click.option('--audio-channels', type=int, default=2, show_default=True)
@click.option(
    '--sample-rate', type=int, default=48000, show_default=True)
@click.option(
    '--audio-reference',
    type=click.Choice([m.name for m in AudioReference]),
    default=AudioReference.dBVU.name,
    show_default=True,
    help='Audio reference level',
)
@click.option(
    '--block-size', type=int, default=1024, show_default=True,
    help='Block size for sounddevice output stream',
)
def main(
    source_name: str,
    audio_channels: int,
    sample_rate: int,
    audio_reference: str,
    block_size: int,
) -> None:
    options = Options(
        source_name=source_name,
        audio_channels=audio_channels,
        sample_rate=sample_rate,
        audio_reference=AudioReference[audio_reference],
        block_size=block_size,
    )
    play(options)


if __name__ == '__main__':
    main()
