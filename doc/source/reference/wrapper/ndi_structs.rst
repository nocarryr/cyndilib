:mod:`cyndilib.wrapper.ndi_structs`
===================================

.. currentmodule:: cyndilib.wrapper.ndi_structs

.. automodule:: cyndilib.wrapper.ndi_structs


FrameType
---------

.. class:: FrameType(enum.Enum)

    Enum signifying |NDI| frame types

    .. attribute:: unknown

        Effectively means that the frame type is ``None``

    .. attribute:: video

        Specifies a :class:`~cyndilib.VideoFrame`

    .. attribute:: audio

        Specifies an :class:`~cyndilib.AudioFrame`

    .. attribute:: metadata

        Specifies a :class:`~cyndilib.MetadataFrame`

    .. attribute:: error

        Indicates an error occurred (when returned from an |NDI| function)


FrameFormat
-----------

.. class:: FrameFormat(enum.Enum)

    Enum specifying the field type of a video frame

    .. attribute:: progressive

        A progressive frame (non-fielded)

    .. attribute:: interleaved

        A fielded (interlaced) frame using field 0 for even lines and field 1
        for odd

    .. attribute:: field_0

        Indicates the current data contains the even field

    .. attribute:: field_1

        Indicates the current data contains the odd field


FourCC
------

.. class:: FourCC(enum.Enum)

    Enum specifying various `FourCC types`_ for video formats

    .. attribute:: UYVY

        Non-planar ``YCbCr`` format using ``4:2:2``. For every two pixels
        there are two ``Y`` samples and one of each color samples.

        The ordering for these is ``(U0, Y0, V0, Y1)`` where each component
        is :term:`uint8`.

        :term:`line stride`
            ``xres * sizeof(uint8_t) * 4``

        Size in bytes
            ``line_stride * yres``

    .. attribute:: UYVA

        Planar ``YCbCr + Alpha`` format using ``4:2:2:4``. The first plane
        is formatted as in :attr:`UYVY` and the second plane contains the alpha
        value for each pixel as :term:`uint8`.

        :term:`line stride`
            First Plane
                ``xres * sizeof(uint8_t) * 4``

            Second Plane
                ``xres * sizeof(uint8_t)``

        Size in bytes
            First plane
                ``xres * sizeof(uint8_t) * 4 * yres``

            Second plane
                ``xres * sizeof(uint8_t) * yres``

    .. attribute:: P216

        Semi-planar ``YCbCr`` format using ``4:2:2`` with 16bpp. The first
        plane contains the ``Y`` values with one :term:`uint16` sample for every
        pixel. The second plane contains the color samples as interleaved pairs
        within a single :term:`uint16` per pixel.

        The ordering for the second plane may be simpler to describe as
        ``(<uint8_t>U, <uint8_t>V)``.

        :term:`line stride`
            First plane (``Y``)
                ``xres * sizeof(uint16_t)``

            Second plane (``UV``)
                ``xres * sizeof(uint8_t) * 2`` (note this is the same as
                the first plane)

        Size in bytes (per plane)
            ``xres * sizeof(uint16_t) * yres``

    .. attribute:: PA16

        Semi-planar ``YCbCr + Alpha`` format using ``4:2:2:4``. The first
        two planes are formatted as described in :attr:`P216` and the third
        plane contains the alpha value for each pixel as :term:`uint16`.

        :term:`line stride` (per plane)
            ``xres * sizeof(uint16_t)``

        Size in bytes (per plane)
            ``xres * sizeof(uint16_t) * yres``

    .. attribute:: I420

        Planar ``YCbCr`` format using ``4:2:0`` video format with 8bpp.
        The first plane contains the ``Y`` values with one :term:`uint8` sample
        for every pixel. The second plane contains the ``Cb`` (``U``) samples and the
        third contains the ``Cr`` (``V``) values (also as :term:`uint8`).

        Since chroma subsampling is done both horizontallly and vertically,
        the ordering may be best described here:
        https://wiki.videolan.org/YUV#I420

        :term:`line stride`
            First plane
                ``xres * sizeof(uint8_t)``

            Second and third planes
                ``xres / 2 * sizeof(uint8_t)``

        Size in bytes
            First plane
                ``xres * sizeof(uint8_t) * yres``

            Second and third planes
                ``xres / 2 * sizeof(uint8_t) * yres / 2``


    .. attribute:: YV12

        Identical to :attr:`YV12`, except the order of the chroma pairs are
        reversed (hence the name "YV") making the plane order ``(Y, Cr, Cb)``
        or ``(Y, V, U)``.

    .. attribute:: NV12

        Planar ``YCbCr`` format using ``4:2:0`` with 8bpp. The first plane
        contains the ``Y`` samples as :term:`uint8` and the second contains
        the chroma pairs as interleaved :term:`uint8`.

        As with :attr:`I420` and :attr:`YV12`, the chroma subsampling is done
        within 2x2 groups of pixels and can be described here:
        https://wiki.videolan.org/YUV#NV12

        Instead of using separate (smaller) planes for the ``UV`` components,
        they are combined into a single plane with the same size as the ``Y``
        plane.

        :term:`line stride` (both planes)
            ``xres * sizeof(uint8_t)``

        Size in bytes (both planes)
            ``xres * sizeof(uint8_t) * yres``

    .. attribute:: RGBA

        Non-planar ``RGBA`` format using ``4:4:4:4``. For each pixel, the red,
        green, blue and alpha components are stored using one :term:`uint8`
        value for each (ordered as ``(R, G, B, A)``).

        :term:`line stride`
            ``xres * sizeof(uint8_t) * 4``

        Size in bytes
            ``xres * sizeof(uint8_t) * 4 * yres``

    .. attribute:: RGBX

        Like :attr:`RGBA` but with no alpha component. Values of ``255`` are
        inserted in its place.

    .. attribute:: BGRA

        Like :attr:`RGBA` except the components are ordered as ``(B, G, R, A)``

    .. attribute:: BGRX

        Like :attr:`BGRA` but with no alpha component



.. _FourCC types: https://en.wikipedia.org/wiki/FourCC
