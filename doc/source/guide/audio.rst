Audio in |NDI|
==============

.. _guide_audio_dynamic_range:

Dynamic Range
-------------

When sending or receiving audio in |NDI|, it's important to understand the dynamic
range that the library works with.

Audio samples are passed as 32-bit floating point values, but they are not necessarily
:term:`normalized <normalized audio>` to +/- 1.0.  Instead, a sine wave at 2.0 :term:`peak-to-peak`
is considered to be at +4 :term:`dBu`.


The following table explains the relationship between the different scales:

.. list-table:: Audio Reference Scales
  :header-rows: 1

  * - dBu
    - dBVU
    - dBFS (SMPTE)
    - dBFS (EBU)
    - NDI Amplitude
  * - +24 dB
    - +20 dB
    - 0 dB
    -
    - 10.0
  * - +18 dB
    - +14 dB
    - -6 dB
    - 0 dB
    - :math:`10 ^{14/20} \approx 5.01`
  * - +4 dB
    - 0 dB
    - -20 dB
    - -14 dB
    - 1.0
  * - -16 dB
    - -20 dB
    - -40 dB
    - -34 dB
    - 0.1


.. seealso::

  `NDI Audio Frames`_ for more information on audio frames in |NDI|.


Why It Matters
^^^^^^^^^^^^^^

That same waveform (amplitude of +/- 1.0) will be -20 :term:`dBFS` (SMPTE) and -14 :term:`dBFS` (EBU).

We can then see that, in the SMPTE scale:

.. math::

  0\text{ dBFS} = +24\text{ dBu} = +20\text {dBVU}

giving the amplitude :math:`A_{fs}` as:

.. math::

  A_{fs} = 10 ^{20/20} = 10.0


If you simply pass a wavefile in 32-bit float format into |NDI|, it will be 20 dB lower than expected.
Conversely, if you are receiving audio from |NDI|, the audio will be 20 dB higher than expected (ouch)!


How to Handle It
^^^^^^^^^^^^^^^^

Starting with ``cyndilib v0.0.8``, scaling audio samples to/from |NDI| can be done automatically by the
:class:`~cyndilib.audio_frame.AudioFrame`, but its :attr:`reference level <cyndilib.audio_frame.AudioFrame.reference_level>`
must be set appropriately.

By default, it is set to :attr:`~cyndilib.audio_reference.AudioReference.dBVU` so no scaling is done to
maintain backwards-compatibility [#]_.

To send or receive :term:`normalized audio`, set the reference level to :attr:`~cyndilib.audio_reference.AudioReference.dBFS_smpte`.

>>> from cyndilib import AudioReference, AudioSendFrame, AudioFrameSync
>>> send_frame = AudioSendFrame()
>>> send_frame.reference_level = AudioReference.dBFS_smpte
>>> # Now send_frame can be filled with normalized audio samples
>>> # and they will be scaled up by 20 dB (10x amplitude) when sent.


>>> recv_frame = AudioFrameSync()
>>> recv_frame.reference_level = AudioReference.dBFS_smpte
>>> # Now recv_frame will provide normalized audio samples
>>> # by scaling down the received samples by 20 dB (0.1x amplitude).



.. _NDI Audio Frames: https://docs.ndi.video/all/developing-with-ndi/sdk/frame-types#audio-frames-ndilib_audio_frame_v3_t


.. [#] The amplitude of 0 dBVU is equal to 1.0 in |NDI|, so no scaling is required.
