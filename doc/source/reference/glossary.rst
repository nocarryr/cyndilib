Glossary
========

.. glossary::

    ndi-timecode
        Per-frame timecode in :term:`ndi-time` which is not used by the
        |NDI| library but is passed through for applications
        to interpret/display as needed.

    ndi-timestamp
        Per-frame timestamp in :term:`ndi-time` filled in by the |NDI| library
        using a high-precision clock. This is used to ensure accuracy in
        stream synchronization across the network.

    ndi-time
        Time since the :term:`UNIX epoch` in 100-nanosecond increments as
        a signed 64-bit integer. Conversion to seconds would be
        :math:`T_s = T_n*10^{-6}` and conversion from seconds would be
        :math:`T_n = T_s*10^{6}`.

    UNIX epoch
        The point at which time starts: January 1, 1970 00:00:00 (UTC) on all
        platforms

    uint8
        Unsigned 8-bit integer

    uint16
        Unsigned 16-bit integer

    line stride
        The number of bytes needed for one horizontal line of a video frame

    peak-to-peak
        The difference between the maximum positive and maximum negative amplitudes
        of a waveform.

        A waveform that ranges from -1.0 to +1.0 has a peak-to-peak value of 2.0.

    normalized audio
        Audio samples that are within the range of -1.0 to +1.0 (2.0 :term:`peak-to-peak`).


    dBFS
        Decibels relative to full scale. 0 dBFS is the maximum possible digital level.
        All digital audio levels are negative numbers in `dBFS`_.

        The alignment levels for this scale are:

        * SMPTE
            * :math:`-20\text{ dBFS} = 0\text{ dBVU} = +4\text{ dBu}`
        * EBU
            * :math:`-14\text{ dBFS} = -4\text{ dBVU} = 0\text{ dBu}`

    dBVU
        Decibels relative to 1.0 volts RMS. Its amplitude is calculated as:

        .. math::

            dBVU = 20 * log_{10}(V_{RMS})

        where :math:`V_{RMS}` is the RMS voltage of the signal.

        This is also known as a `Volume Unit`_ (VU) and its alignment level is 0 dBVU.

    dBu
        Decibels relative to 0.775 volts RMS. Its amplitude is calculated as:

        .. math::

            dBu = 20 * log_{10}(V_{RMS}/0.775)

        where :math:`V_{RMS}` is the RMS voltage of the signal.

        The alignment level for this scale is :math:`+4\text{ dBu} = 0\text{ dBVU}`.



.. _dBFS: https://en.m.wikipedia.org/wiki/DBFS
.. _Volume Unit: https://en.m.wikipedia.org/wiki/VU_meter
