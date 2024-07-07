Finder
######

.. currentmodule:: cyndilib.finder

The :class:`Finder` class allows discovery of |NDI| sources
on the network. Any discovered sources are then made available
as :class:`Source` instances.


.. testsetup::

    >>> fake_sender_name = getfixture('fake_sender')

.. autolink-concat:: on


General Usage
-------------


Open the :class:`Finder` and wait for it to find sources
with :meth:`Finder.wait_for_sources`

.. doctest::

    >>> from cyndilib.finder import Finder
    >>> finder = Finder()
    >>> finder.open()
    >>> changed = finder.wait_for_sources(timeout=5)
    >>> changed
    True


Get the names of any sources found on the network using
:meth:`Finder.get_source_names`

.. doctest::

    >>> source_names = finder.get_source_names()
    >>> source_names
    ['... (Example Video Source)']


You can also iterate the finder to get its :class:`Source`
objects

.. doctest::

    >>> [source for source in finder]
    [<Source: "... (Example Video Source)">]



Get the first :class:`Source` object and inspect its
:attr:`~Source.host_name` and :attr:`~Source.stream_name`

.. doctest::

    >>> source = finder.get_source(source_names[0])
    >>> source
    <Source: "... (Example Video Source)">
    >>> source.host_name
    '...'
    >>> source.stream_name
    'Example Video Source'


Note the host_name for this example shows as ``'...'``.
In reality, this will typically be the network hostname
of the source device (typically :func:`socket.gethostname`).

Always be sure to close the finder instance

.. doctest::

    >>> finder.close()


Alternatively, it may be used as a :term:`context manager`

.. doctest::

    >>> with Finder() as finder:
    ...     changed = finder.wait_for_sources(timeout=5)
    ...     [source for source in finder]
    [<Source: "... (Example Video Source)">]


Change Callback
---------------

A :attr:`~Finder.change_callback` can be provided which
will be called whenever the discovered sources changes.
The callback will be invoked with no arguments

.. doctest::

    >>> import time

    >>> finder = Finder()
    >>> def change_callback():
    ...     print(finder.get_source_names())
    >>> finder.set_change_callback(change_callback)

    >>> with finder:
    ...     time.sleep(5)
    ['... (Example Video Source)']
