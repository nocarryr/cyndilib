:mod:`cyndilib.receiver`
===========================

.. currentmodule:: cyndilib.receiver

.. automodule:: cyndilib.receiver


Receiver
--------

.. autoclass:: Receiver
    :members:


RecvThread
----------

.. autoclass:: RecvThread
    :members:


ReceiveFrameType
----------------

.. class:: ReceiveFrameType(enum.IntFlag)

    Frame type flags used to receive specific frame types and indicate results.
    Members and be combined using bit-wise operators.

    .. attribute:: nothing

        Indicate nothing can or has been received

    .. attribute:: recv_video

        Indicate video frames can or have been received

    .. attribute:: recv_audio

        Indicate video frames can or have been received

    .. attribute:: recv_metadata

        Indicate metadata frames can or have been received

    .. attribute:: recv_status_change

        Indicate a status change has occurred (results only)

    .. attribute:: recv_error

        Indicate an error occurred (results only)

    .. attribute:: recv_buffers_full

        Indicates a :class:`VideoRecvFrame` or :class:`AudioRecvFrame` buffer
        was full when trying to read (results only)

    .. attribute:: recv_all

        A combination of :attr:`recv_video`, :attr:`recv_audio` and
        :attr:`recv_metadata`
