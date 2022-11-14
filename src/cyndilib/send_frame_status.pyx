

cdef void frame_status_set_send_id(SendFrame_status_ft* ptr, Py_intptr_t send_id) nogil except *:
    cdef SendFrame_status_ft* _ptr = ptr
    while True:
        if send_id == NULL_ID and _ptr.id == _ptr.next_send_id:
            _ptr.send_ready = False
        _ptr.next_send_id = send_id

        if _ptr.id == send_id:
            _ptr.send_ready = True
            _ptr.write_available = False
        if _ptr.next is NULL:
            break
        _ptr = _ptr.next
    _ptr = ptr
    while True:
        if send_id == NULL_ID and _ptr.id == _ptr.next_send_id:
            _ptr.send_ready = False
        _ptr.next_send_id = send_id
        if _ptr.id == send_id:
            _ptr.send_ready = True
            _ptr.write_available = False
        if _ptr.prev is NULL:
            break
        _ptr = _ptr.prev

cdef void frame_status_clear_write(SendFrame_status_ft* ptr, Py_intptr_t send_id) nogil except *:
    cdef SendFrame_status_ft* _ptr = ptr
    while True:
        if _ptr.id == send_id:
            _ptr.send_ready = False
        elif not _ptr.send_ready:
            _ptr.write_available = True
        _ptr.next_send_id = NULL_ID
        if _ptr.next is NULL:
            break
        _ptr = _ptr.next
    _ptr = ptr
    while True:
        if _ptr.id == send_id:
            _ptr.send_ready = False
        elif not _ptr.send_ready:
            _ptr.write_available = True
        _ptr.next_send_id = NULL_ID
        if _ptr.prev is NULL:
            break
        _ptr = _ptr.prev

cdef SendFrame_status_ft* frame_status_get_writer(SendFrame_status_ft* ptr) nogil except *:
    cdef SendFrame_status_ft* _ptr = ptr
    while True:
        if _ptr.write_available and not _ptr.send_ready:
            return _ptr
        if _ptr.next is NULL:
            break
        _ptr = _ptr.next
    while True:
        if _ptr.write_available and not _ptr.send_ready:
            return _ptr
        if _ptr.prev is NULL:
            break
        _ptr = _ptr.prev
    return NULL

cdef SendFrame_status_ft* frame_status_get_sender(SendFrame_status_ft* ptr) nogil except *:
    cdef SendFrame_status_ft* _ptr = ptr
    while True:
        if _ptr.id == _ptr.next_send_id:
            return _ptr
        if _ptr.next is NULL:
            break
        _ptr = _ptr.next
    _ptr = ptr
    while True:
        if _ptr.id == _ptr.next_send_id:
            return _ptr
        if _ptr.prev is NULL:
            break
        _ptr = _ptr.prev
    return NULL
