:mod:`cyndilib.wrapper.ndi_recv`
================================

.. currentmodule:: cyndilib.wrapper.ndi_recv

.. automodule:: cyndilib.wrapper.ndi_recv


RecvBandwidth
-------------

.. class:: RecvBandwidth(enum.Enum)

    Specifies the bandwidth to use when receiving

    .. attribute:: metadata_only

    .. attribute:: audio_only

    .. attribute:: lowest

    .. attribute:: highest


RecvColorFormat
---------------

.. class:: RecvColorFormat(enum.Enum)

    Specifies the desired color format to use when receiving

    .. attribute:: BGRX_BGRA

        Delivers :attr:`~.ndi_structs.FourCC.BGRA` if an alpha channel is present,
        otherwise :attr:`~.ndi_structs.FourCC.BGRA`

    .. attribute:: UYVY_BGRA

        Delivers :attr:`~.ndi_structs.FourCC.BGRA` if an alpha channel is present,
        otherwise :attr:`~.ndi_structs.FourCC.UYVY`

    .. attribute:: RGBX_RGBA

        Delivers :attr:`~.ndi_structs.FourCC.RGBA` if an alpha channel is present,
        otherwise :attr:`~.ndi_structs.FourCC.RGBX`

    .. attribute:: UYVY_RGBA

        Delivers :attr:`~.ndi_structs.FourCC.RGBA` if an alpha channel is present,
        otherwise :attr:`~.ndi_structs.FourCC.UYVY`

    .. attribute:: fastest

        This format will try to decode the video using the fastest available color format for the incoming
        video signal. This format follows the following guidelines, although different platforms might
        vary slightly based on their capabilities and specific performance profiles. In general if you want
        the best performance this mode should be used.

        When using this format, you should consider than allow_video_fields is true, and individual fields
        will always be delivered.

        For most video sources on most platforms, this will follow the following conventions.

        No alpha channel
            :attr:`~.ndi_structs.FourCC.UYVY`

        Alpha channel
            :attr:`~.ndi_structs.FourCC.UYVA`

    .. attribute:: best

        This format will try to provide the video in the format that is the closest to native for the incoming
        codec yielding the highest quality. Specifically, this allows for receiving on 16bpp color from many
        sources.

        When using this format, you should consider than allow_video_fields is true, and individual fields
        will always be delivered.

        For most video sources on most platforms, this will follow the following conventions

        No alpha channel
            :attr:`~.ndi_structs.FourCC.P216`, or :attr:`~.ndi_structs.FourCC.UYVY`

        Alpha channel
            :attr:`~.ndi_structs.FourCC.PA16` or :attr:`~.ndi_structs.FourCC.UYVA`
