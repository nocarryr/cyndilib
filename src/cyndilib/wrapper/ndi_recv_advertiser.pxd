# cython: language_level=3
# distutils: language = c++

from .ndi_recv cimport NDIlib_recv_instance_t

cdef extern from "Processing.NDI.RecvAdvertiser.h" nogil:

    # // The type instance for a receiver advertiser.
    cdef struct NDIlib_recv_advertiser_instance_type:
        pass
    ctypedef NDIlib_recv_advertiser_instance_type* NDIlib_recv_advertiser_instance_t

    cdef struct NDIlib_recv_advertiser_create_t:
    # // The URL address of the NDI Discovery Server to connect to. If NULL, then the default NDI discovery
	# // server will be used. If there is no discovery server available, then the receiver advertiser will not
	# // be able to be instantiated and the create function will return NULL. The format of this field is
	# // expected to be the hostname or IP address, optionally followed by a colon and a port number. If the
	# // port number is not specified, then port 5959 will be used. For example,
	# //     127.0.0.1:5959
	# //       or
	# //     127.0.0.1
	# //       or
	# //     hostname:5959
	# // This field can also specify multiple addresses separated by commas for redundancy support.
        const char* p_url_address


    # // Create an instance of the receiver advertiser. This will return NULL if it fails to create the advertiser.
    NDIlib_recv_advertiser_instance_t NDIlib_recv_advertiser_create()
    # Note: this is an overloaded definition adding the `p_create_settings` parameter. If not specified, it will be NULL.
    NDIlib_recv_advertiser_instance_t NDIlib_recv_advertiser_create(const NDIlib_recv_advertiser_create_t* p_create_settings)

    # // Destroy an instance of the receiver advertiser.
    void NDIlib_recv_advertiser_destroy(NDIlib_recv_advertiser_instance_t p_instance)

    # // Add the receiver to the list of receivers that are being advertised. Returns false if the receiver has
    # // been previously registered.
    bint NDIlib_recv_advertiser_add_receiver(
        NDIlib_recv_advertiser_instance_t p_instance,
        NDIlib_recv_instance_t p_receiver,
        bint allow_controlling, bint allow_monitoring
    )
    # Note: this is an overloaded definition adding the `p_input_group_name` parameter. If not specified, it will be NULL.
    bint NDIlib_recv_advertiser_add_receiver(
        NDIlib_recv_advertiser_instance_t p_instance,
        NDIlib_recv_instance_t p_receiver,
        bint allow_controlling, bint allow_monitoring,
        const char* p_input_group_name
    )

    # // Remove the receiver from the list of receivers that are being advertised. Returns false if the receiver
    # // was not previously registered.
    bint NDIlib_recv_advertiser_del_receiver(
        NDIlib_recv_advertiser_instance_t p_instance,
        NDIlib_recv_instance_t p_receiver
    )
