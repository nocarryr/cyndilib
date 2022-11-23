cyndilib
########

A Python wrapper for `Newtek NDI®`_ written in `Cython`_


Description
***********

NDI® allows video and audio to be reliably sent and received over IP with
minimal latency and very high quality. For more information about NDI®, see:

https://ndi.tv/

This project aims to wrap most functionality of the `NDI® SDK`_ for use in
Python. Due to the real-time nature of audio and video, nearly all of this
library is written in `Cython`_ for performance purposes. By design, "cyndilib"
may be used within other Cython code.


Installation
************

This project is not yet published on `PyPI <https://pypi.org/>`_, but it is planned to be very soon.
For now, building from source is the only method available. In the future,
this will be::

    pip install cyndilib


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

Documentation is not yet built for this project, but will be soon. For now,
take a look at the example code and tests.


License
*******

cyndilib is licensed under the MIT license. See included `LICENSE`_ file.

NDI® is a registered trademark of NewTek, Inc. Its associated license
information can be found in `libndi_licenses.rst`_.

Also visit https://ndi.tv/ for details.



.. _Newtek NDI®: https://ndi.tv/
.. _NDI® SDK: https://ndi.tv/sdk/
.. _Cython: https://cython.org
.. _PyPI: https://pypi.org/
.. _LICENSE: license.rst
.. _libndi_licenses.rst: libndi_licenses.rst
