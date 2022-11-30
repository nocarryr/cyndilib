cyndilib
########

A Python wrapper for `Newtek NDI®`_ written in `Cython`_


Description
***********

NDI® allows video and audio to be reliably sent and received over IP with
minimal latency and very high quality. For more information see https://ndi.tv/.

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
    - https://pypi.org/projects/cyndilib


Installation
************

Installation via ``pip`` is supported using pre-built platform wheels::

    pip install cyndilib

All of the necessary headers and Cython files are included in the distribution.
This will allow for development of applications directly using
``cimport`` directives.


Building
========

For Windows, the `NDI® SDK`_ will need to be downloaded and installed before
building. MacOS and most Linux shouldn't require this.

Clone or download the repository::

    git clone https://github.com/nocarryr/cyndilib.git
    cd cyndilib


If `pipenv <https://pipenv.pypa.io/en/latest/>`_ is installed on your system,
the provided Pipfile may be used::

    pipenv install --dev


If encountering errors, try compiling the extensions manually using::

    python setup.py build_ext --inplace


This should display more useful error messages.


Usage
*****

Documentation can be found at https://cyndilib.readthedocs.io.
Since this project is still in its early stages of development however,
a look at the example code and tests in the repository might be more useful.


License
*******

cyndilib is licensed under the MIT license. See included `LICENSE`_ file.

NDI® is a registered trademark of NewTek, Inc. Its associated license
information can be found in `libndi_licenses.rst`_.


⚠ Distribution Considerations ⚠
===============================

Before distributing or including this in your own projects it is **important**
that you have read and understand the "Licensing" section included in the
`NDI® SDK`_ Documentation.

There are specific requirements listed for branding, trademark use and URLs to
be displayed, etc. To the best of my knowledge this project is following the
guidelines and corrections will be made if discovered otherwise.

Liability for derivative works, etc falls under the responsibility of their authors.



.. _Newtek NDI®: https://ndi.tv/
.. _NDI® SDK: https://ndi.tv/sdk/
.. _Cython: https://cython.org
.. _PyPI: https://pypi.org/
.. _LICENSE: license.rst
.. _libndi_licenses.rst: libndi_licenses.rst
