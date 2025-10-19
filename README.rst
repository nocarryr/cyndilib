cyndilib
########

A Python wrapper for `NDI®`_ written in `Cython`_


Description
***********

NDI® allows video and audio to be reliably sent and received over IP with
minimal latency and very high quality. For more information see https://ndi.video.

This project aims to wrap most functionality of the `NDI® SDK`_ for use in
Python. Due to the real-time nature of audio and video, nearly all of this
library is written in `Cython`_ for performance purposes. By design, "cyndilib"
may be used within other Cython code.


Links
*****

.. list-table::

  * - Project Home
    - https://github.com/nocarryr/cyndilib
  * - Documentation
    - https://cyndilib.readthedocs.io
  * - PyPI
    - https://pypi.org/project/cyndilib


Installation
************


From PyPI
=========

This project is available on PyPI with pre-built wheels for most
platforms. Installing via `pip`_ would be the simplest method of
installation::

    pip install cyndilib

All of the necessary headers and Cython ``.pxd`` files will be included
in the distribution. This will allow for direct integration if using
Cython in your application using the ``cimport`` statement.
See the `Cython documentation <https://cython.readthedocs.io/en/latest/src/userguide/sharing_declarations.html>`_
for more details.


Building from Source
====================

This may be necessary if a pre-built wheel is not available for
your platform or Python version.

First clone or download the repository::

    git clone https://github.com/nocarryr/cyndilib.git
    cd cyndilib


The project can then be installed with::

    pip install .


All of the dependencies for building and installation should be automatically
detected and installed (assuming your system supports the `build metadata`_
specifications introduced `PEP 517`_).

.. note::

    The ``.`` in the above command implies that you are in the root directory
    of the cloned project.  For other uses, the path to the project root may
    be used instead.


Parallel Builds
^^^^^^^^^^^^^^^

There are quite a few sources to compile and by default, they will be compiled
one at a time.  There is currently not a direct way to tell pip to use multiple
threads when compiling.

An environment variable ``CYNDILIB_BUILD_PARALLEL`` may be used to work around
this however.  Its value can be either a specific number of threads to use
or ``"auto"`` to use all available cores::

    CYNDILIB_BUILD_PARALLEL=auto pip install .


Further Information
^^^^^^^^^^^^^^^^^^^

More information on compilation and development can be found on the
`development page <https://cyndilib.readthedocs.io/en/latest/development.html>`_
of the project documentation.


Extra
=====

External dependencies might be required for interacting with NDI. View the
official documentation on
'NDI SDK dependencies <https://docs.ndi.video/docs/sdk/platform-considerations>'.


Linux
-----

Linux requires Avahi, which provides network discovery for NDI devices.::

   libavahi-common.so.3
   libavahi-client.so.3


Ubuntu
^^^^^^

Avahi can be installed on Ubuntu by running:

.. code-block::

    sudo apt install avahi-daemon
    sudo systemctl enable --now avahi-daemon


Usage
*****

Documentation can be found at https://cyndilib.readthedocs.io.
Since this project is still in its early stages of development however,
a look at the example code and tests in the repository might be more useful.


License
*******

cyndilib is licensed under the MIT license. See included `LICENSE`_ file.

NDI® is a registered trademark of Vizrt NDI AB. Its associated license
information can be found in `libndi_licenses.txt`_.


⚠ Distribution Considerations ⚠
===============================

Before distributing or including this in your own projects it is **important**
that you have read and understand the "Licensing" section included in the
`NDI® SDK Documentation`_.

There are specific requirements listed for branding, trademark use and URLs to
be displayed, etc. To the best of my knowledge this project is following the
guidelines and corrections will be made if discovered otherwise.

Liability for derivative works, etc falls under the responsibility of their authors.



.. _NDI®: https://ndi.video
.. _NDI® SDK: https://ndi.video/for-developers/ndi-sdk/
.. _NDI® SDK Documentation: https://docs.ndi.video/docs
.. _Cython: https://cython.org
.. _PyPI: https://pypi.org/
.. _LICENSE: LICENSE
.. _libndi_licenses.txt: libndi_licenses.txt
.. _PEP 517: https://peps.python.org/pep-0517/
.. _build metadata: https://setuptools.pypa.io/en/latest/build_meta.html
.. _pip: https://pip.pypa.io/
