# cython: language_level=3
# distutils: language = c++

from .ndi_send cimport NDIlib_send_instance_t

cdef extern from "Processing.NDI.SendAdvertiser.h" nogil:
    # // The type instance for a sender advertiser.
    cdef struct NDIlib_send_advertiser_instance_type:
        pass
    ctypedef NDIlib_send_advertiser_instance_type* NDIlib_send_advertiser_instance_t

    cdef struct NDIlib_send_advertiser_create_t:
        # // The URL address of the NDI Discovery Server to connect to. If NULL, then the default NDI discovery
        # // server will be used. If there is no discovery server available, then the sender advertiser will not
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

    # // Create an instance of the sender advertiser. This will return NULL if it fails to create the advertiser.
    NDIlib_send_advertiser_instance_t NDIlib_send_advertiser_create(const NDIlib_send_advertiser_create_t* p_create_settings)
    # Note: this is an overloaded definition adding the `p_create_settings` parameter. If not specified, it will be NULL.
    NDIlib_send_advertiser_instance_t NDIlib_send_advertiser_create()

    # // Destroy an instance of the sender advertiser.
    void NDIlib_send_advertiser_destroy(NDIlib_send_advertiser_instance_t p_instance)

    # // Add the sender to the list of senders that are being advertised. Returns false if the receiver has been
    # // previously registered.
    bint NDIlib_send_advertiser_add_sender(
        NDIlib_send_advertiser_instance_t p_instance,
        NDIlib_send_instance_t p_sender,
        bint allow_monitoring
    )

    # // Remove the sender from the list of senders that are being advertised. Returns false if the sender was not
    # // previously registered.
    bint NDIlib_send_advertiser_del_sender(
        NDIlib_send_advertiser_instance_t p_instance,
        NDIlib_send_instance_t p_sender
    )
