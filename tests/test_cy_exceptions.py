import pytest

from _test_exceptions import raise_py_exc # type: ignore[missing-import]

@pytest.fixture(params=[
    Exception,
    RuntimeError,
    KeyError,
    IndexError,
    ValueError,
    TypeError,
    TypeError,
    MemoryError,
    ZeroDivisionError,
])
def exception_type(request):
    return request.param

def test_cy_exceptions(exception_type):
    msg = 'foobar!'
    with pytest.raises(exception_type, match=msg):
        raise_py_exc(exception_type, msg)
