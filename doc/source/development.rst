Development
***********

.. highlight:: bash


Building from Source
====================

First clone or download the repository::

    git clone https://github.com/nocarryr/cyndilib.git
    cd cyndilib


Build Dependencies
------------------

The build dependencies can be installed with::

    pip install setuptools cython numpy



Compilation
-----------


A common pattern for developing cython projects is to build the extension modules
in-place (next to the source files themselves)::

    python setup.py build_ext --inplace

Then install in "editable" mode::

    pip install -e .


Options
^^^^^^^

There are a few options to aid in development and most are available as arguments
to the setup script.


:``--annotate``: produces an HTML file for each cython module giving insight into
    some of the internals and the Python overhead for each source line.  See the
    cython `compiler options`_ for more details.
:``--use-profile``: will compile with profiling enabled (as well as other necessary
    compiler directives) for use with ``cProfile``. This is not enabled by default
    as there is a lot of overhead added to each function call making things significantly
    slower.  See cython's `profiling documentation`_ for more details.
:``-j`` / ``--parallel``: sets the number of parallel build jobs for compilation


.. _build-extensions:

Build Command
^^^^^^^^^^^^^

A typical invocation during development would then be::

    python setup.py build_ext --inplace --annotate -j 12


Where the ``-j 12`` is the number of CPU cores to use.



Testing
=======


Test dependencies can be installed with::

    pip install pytest pytest-doctestplus psutil



Test Compilation
----------------

Some of the tests depend on Cython modules which must first be compiled with the
included build script::

    ./build_tests.py

or::

    python build_tests.py


This may need to be run again after making changes to any of the Cython
declaration modules (``.pxd`` files) in the project.


Invocation
----------

A full test run can be done by calling ``py.test`` without any arguments.
This will run all tests in the ``./tests/`` directory::

    py.test


Note that after making changes to the source code, the modules must be
:ref:`recompiled <build-extensions>` as well as the tests.


There are also a few code examples in the documentation in `doctest`_
format.  These can be tested with::

    py.test doc/



Documentation
=============

This project uses `Sphinx`_ for its documentation.
The dependencies can be installed with::

    pip install -r doc/requirements.txt


Since the `autodoc`_ extension is used, the modules must be
:ref:`compiled <build-extensions>` before building the docs::

    python setup.py build_ext --inplace -j 12
    cd doc
    make html


.. note::

    Sometimes changes aren't detected after recompiling, so a call to
    ``make clean`` may be required




.. _compiler options: https://cython.readthedocs.io/en/latest/src/userguide/source_files_and_compilation.html#compiler-options
.. _profiling documentation: https://cython.readthedocs.io/en/latest/src/tutorial/profiling_tutorial.html
.. _doctest: https://docs.python.org/3/library/doctest.html
.. _pytest: https://docs.pytest.org/
.. _Sphinx: https://www.sphinx-doc.org/
.. _autodoc: https://www.sphinx-doc.org/en/master/usage/extensions/autodoc.html
