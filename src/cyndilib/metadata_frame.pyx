from libc.string cimport strcpy
# cimport lxml.includes.etreepublic as cetree
# cdef object etree
# from lxml import etree
# cetree.import_lxml__etree()

# import xml.etree.ElementTree as ET
import re


cdef object DOC_PATTERN = re.compile(r'<(?P<tag>\w+)(?P<attrs>[\w\s,",=]+)/>')
cdef object ATTR_PATTERN = re.compile(r'(\s+(?P<name>\w+)="(?P<value>\w+)")')


def parse_xml(str xml):
    cdef object m = DOC_PATTERN.match(xml)
    if m is None:
        return None, None
    cdef str tag = m['tag'], attr_str = m['attrs']
    cdef dict attrs = {}, d

    # cdef str key, value

    for m in ATTR_PATTERN.finditer(attr_str):
        print(f'm: {m!r}')
        d = m.groupdict()
        key = d['name']
        if key is None:
            continue
        value = d['value']
        if value is None:
            continue
        attrs[key] = value
    return tag, attrs


cdef class MetadataFrame:
    def __cinit__(self, *args, **kwargs):
        self.ptr = metadata_frame_create()

    def __init__(self, *args, **kwargs):
        self.tag = None
        self.attrs = {}

    def __dealloc__(self):
        cdef NDIlib_metadata_frame_t* p = self.ptr
        self.ptr = NULL
        if p is not NULL:
            metadata_frame_destroy(p)

    def get_tag(self):
        return self.tag

    def set_tag(self, str tag):
        self.tag = tag

    def get(self, str tag):
        return self.attrs.get(tag)

    def __getitem__(self, str key):
        return self.attrs[key]

    cdef char* _get_data(self) nogil:
        return self.ptr.p_data
    cdef void _set_data(self, char* data) nogil:
        self.ptr.p_data = data

    def get_timecode(self):
        return self._get_timecode()
    cdef int64_t _get_timecode(self) nogil:
        return self.ptr.timecode
    cdef void _set_timecode(self, int64_t value) nogil:
        self.ptr.timecode = value


cdef class MetadataRecvFrame(MetadataFrame):
    cdef bint can_receive(self) nogil except *:
        return True
    cdef void _prepare_incoming(self, NDIlib_recv_instance_t recv_ptr) except *:
        self.tag = None
        self.attrs.clear()
    cdef void _process_incoming(self, NDIlib_recv_instance_t recv_ptr) except *:
        cdef str data_str = self.ptr.p_data.decode('UTF-8')
        if len(data_str):
            tag, attrs = parse_xml(data_str)
            if tag is not None:
                self.tag = tag
                self.attrs = attrs

        NDIlib_recv_free_metadata(recv_ptr, self.ptr)

def test():
    import time
    cdef NDIlib_recv_instance_t recv_ptr = NULL
    cdef MetadataRecvFrame mf = MetadataRecvFrame()
    cdef bytes xml_b = b'<ndi_tally_echo on_program="true" on_preview="false"/>'
    cdef char* xml_c = xml_b
    # cdef char* xml_str = xml_b
    mf.ptr.p_data = <char*>mem_alloc(sizeof(char) * len(xml_b))
    cdef char** ptr1 = &xml_c
    cdef char** ptr2 = &(mf.ptr.p_data)
    print('copy')
    time.sleep(.1)
    strcpy(ptr2[0], ptr1[0])
    print('copied')
    time.sleep(.1)
    # mf.ptr.p_data = xml_b
    # mf.ptr.length = len(xml_b)
    # try:
    print('parsing')
    time.sleep(.1)
    # cdef cpp_string tag_name_c

    # tag_name_c = _parse_metadata(mf.ptr.p_data, &(mf.attrib_map))
    # mf.tag_name = tag_name_c
    mf._process_incoming(recv_ptr)
    print('parsed')
    time.sleep(.1)
    print(mf.tag)
    print(mf.attrs)
    # cdef dict attrs = mf.attribs()
    # print(attrs)
    # print(mf.get_tag())
    time.sleep(.1)
    assert mf.tag == 'ndi_tally_echo'
    assert mf['on_program'] == 'true'
    assert mf.get('on_preview') == 'false'
    # finally:
    #     mf.ptr.p_data = NULL
