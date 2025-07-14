# How these files were created

The audio reference files in this directory were generated using the
[Test Patterns] generator from [NDI Tools] as the source and captured
using the [ndi-record] utility included in the SDK.
It was intentional to not include `cyndilib` in this process.

- The sine generator in [Test Patterns] was then set to each of its available
  options and the `dBu` and `dBVU` levels were noted for each run of `ndi-record`.
- The audio was then extracted from each `.mov` file using `ffmpeg -i foo.mov -c:a pcm_f32le foo.wav`
- The metadata within `index.json` was taken from parsing the `stdout` from `ndi-record`
  with the exception of the "extra_metadata" field (which was entered manually for each recording).
- Due their size (and issues with the stdlib's `wave` module), the 32-bit (float) wav files were then
  read using [soundfile](https://pypi.org/project/soundfile/) as numpy arrays and saved using `np.savez_compressed`.
  This also avoided adding an extra dependency for tests.

[NDI Tools]: https://ndi.video/tools/
[Test Patterns]: https://ndi.video/tools/test-patterns/
[ndi-record]: https://docs.ndi.video/all/developing-with-ndi/sdk/command-line-tools#recording
