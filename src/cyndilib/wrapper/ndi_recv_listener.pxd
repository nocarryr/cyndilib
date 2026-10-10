# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

from .ndi_structs cimport NDIlib_listener_event


cdef extern from "Processing.NDI.RecvListener.h" nogil:

    # // The type instance for a receiver listener.
    cdef struct NDIlib_recv_listener_instance_type:
        pass
    ctypedef NDIlib_recv_listener_instance_type* NDIlib_recv_listener_instance_t

    cdef struct NDIlib_recv_listener_create_t:
        # // The URL address of the NDI Discovery Server to connect to. If NULL, then the default NDI discovery
        # // server will be used. If there is no discovery server available, then the receiver listener will not
        # // be able to be instantiated and the create function will return NULL. The format of this field is
        # // expected to be the hostname or IP address, optionally followed by a colon and a port number. If the
        # // port number is not specified, then port 5959 will be used. For example,
        # //     127.0.0.1:5959
        # //       or
        # //     127.0.0.1
        # //       or
        # //     hostname:5959
        # // If this field is a comma-separated list, then only the first address will be used.
        const char* p_url_address

    # // Create an instance of the receiver listener. This will return NULL if it fails to create the listener.
    NDIlib_recv_listener_instance_t NDIlib_recv_listener_create(const NDIlib_recv_listener_create_t* p_create_settings)
    # Note: this is an overloaded definition adding the `p_create_settings` parameter. If not specified, it will be NULL.
    NDIlib_recv_listener_instance_t NDIlib_recv_listener_create()

    # // Destroy an instance of the receiver listener.
    void NDIlib_recv_listener_destroy(NDIlib_recv_listener_instance_t p_instance)

    # // Returns true if the receiver listener is actively connected to the configured NDI Discovery Server.
    bint NDIlib_recv_listener_is_connected(NDIlib_recv_listener_instance_t p_instance)

    # // Retrieve the URL address of the NDI Discovery Server that the receiver listener is connected to. This can
    # // return NULL if the instance pointer is invalid.
    const char* NDIlib_recv_listener_get_server_url(NDIlib_recv_listener_instance_t p_instance)

    # // The types of streams that a receiver can receive from the source it's connected to.
    cdef enum NDIlib_receiver_type_e:
        NDIlib_receiver_type_none
        NDIlib_receiver_type_metadata
        NDIlib_receiver_type_video
        NDIlib_receiver_type_audio

        # // Make sure this is a 32-bit enumeration.
        NDIlib_receiver_type_max


    # // The types of commands that a receiver can process.
    cdef enum NDIlib_receiver_command_e:
        NDIlib_receiver_command_none

        # // A receiver can be told to connect to a specific source.
        NDIlib_receiver_command_connect

        # // Make sure this is a 32-bit enumeration.
        NDIlib_receiver_command_max

    # // Describes a receiver that has been discovered.
    cdef struct NDIlib_receiver_t:
        # // The unique identifier for the receiver on the network.
        const char* p_uuid

        # // The human-readable name of the receiver.
        const char* p_name

        # // The unique identifier for the input group that the receiver belongs to.
        const char* p_input_uuid

        # // The human-readable name of the input group that the receiver belongs to.
        const char* p_input_name

        # // The known IP address of the receiver.
        const char* p_address

        # // An array of streams that the receiver is set to receive. The last entry in this list will be
        # // NDIlib_receiver_type_none.
        NDIlib_receiver_type_e* p_streams

        # // How many elements are in the p_streams array, excluding the NDIlib_receiver_type_none entry.
        uint32_t num_streams

        # // An array of commands that the receiver can process. The last entry in this list will be
        # // NDIlib_receiver_command_none.
        NDIlib_receiver_command_e* p_commands

        # // How many elements are in the p_commands array, excluding the NDIlib_receiver_command_none entry.
        uint32_t num_commands

        # // Are we currently subscribed for receiver events?
        bint events_subscribed


    # // Retrieves the current list of advertised receivers. The memory for the returned structure is only valid
    # // until the next call or when destroy is called. For a given NDIlib_recv_listener_instance_t, do not call
    # // NDIlib_recv_listener_get_receivers asynchronously.
    const NDIlib_receiver_t* NDIlib_recv_listener_get_receivers(NDIlib_recv_listener_instance_t p_instance, uint32_t* p_num_receivers)

    # // This will allow you to wait until the number of online receivers has changed.
    bint NDIlib_recv_listener_wait_for_receivers(NDIlib_recv_listener_instance_t p_instance, uint32_t timeout_in_ms)

    # // This will subscribe this listener instance to begin receiving events from the specified receiver.
    void NDIlib_recv_listener_subscribe_events(NDIlib_recv_listener_instance_t p_instance, const char* p_receiver_uuid)

    # // This will unsubscribe this listener instance from receiving events from the specified receiver.
    void NDIlib_recv_listener_unsubscribe_events(NDIlib_recv_listener_instance_t p_instance, const char* p_receiver_uuid)

    # // For backwards compatibility.
    ctypedef NDIlib_listener_event NDIlib_recv_listener_event

    # // Returns a list of the currently pending events for the listener. The events are returned in the order that
    # // they were received. The timeout value is the amount of time in milliseconds that the function will wait
    # // for events to be received. If the timeout is 0, then the function will return immediately with any events
    # // that are currently pending. If the timeout is -1, then the function will wait indefinitely for events to
    # // be received. The function will return NULL if no events were received within the timeout period. The
    # // returned events should be freed using NDIlib_recv_listener_free_events().
    const NDIlib_recv_listener_event* NDIlib_recv_listener_get_events(NDIlib_recv_listener_instance_t p_instance, uint32_t* p_num_events, uint32_t timeout_in_ms)

    # // Frees the memory allocated for the events returned by NDIlib_recv_listener_get_events().
    void NDIlib_recv_listener_free_events(NDIlib_recv_listener_instance_t p_instance, const NDIlib_recv_listener_event* p_events)

    # // Trigger the "connect" command to be sent from the listener to the receiver. This will return false if the
    # // command could not be sent, receiver is unknown, or some other error occurred. If p_source_name is NULL,
    # // then this would indicate that the receiver should disconnect from its current source. Note that this
    # // should only be called for a receiver that has NDIlib_receiver_command_connect in its list of commands that
    # // it can respond to.
    bint NDIlib_recv_listener_send_connect(NDIlib_recv_listener_instance_t p_instance, const char* p_receiver_uuid, const char* p_source_name)
