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
