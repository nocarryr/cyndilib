Glossary
========

.. glossary::

    ndi-timecode
        Per-frame timecode in :term:`ndi-time` which is not used by the
        |NDI| library but is passed through for applications
        to interpret/display as needed.

    ndi-timestamp
        Per-frame timestamp in :term:`ndi-time` filled in by the |NDI| library
        using a high-precision clock. This is used to ensure accuracy in
        stream synchronization across the network.

    ndi-time
        Time since the :term:`UNIX epoch` in 100-nanosecond increments as
        a signed 64-bit integer. Conversion to seconds would be
        :math:`T_s = T_n*10^{-6}` and conversion from seconds would be
        :math:`T_n = T_s*10^{6}`.

    UNIX epoch
        The point at which time starts: January 1, 1970 00:00:00 (UTC) on all
        platforms

    uint8
        Unsigned 8-bit integer

    uint16
        Unsigned 16-bit integer

    line stride
        The number of bytes needed for one horizontal line of a video frame

    peak-to-peak
        The difference between the maximum positive and maximum negative amplitudes
        of a waveform.

        A waveform that ranges from -1.0 to +1.0 has a peak-to-peak value of 2.0.

    normalized audio
        Audio samples that are within the range of -1.0 to +1.0 (2.0 :term:`peak-to-peak`).


    dBFS
        Decibels relative to full scale. 0 dBFS is the maximum possible digital level.
        All digital audio levels are negative numbers in `dBFS`_.

        The alignment levels for this scale are:

        * SMPTE
            * :math:`-20\text{ dBFS} = 0\text{ dBVU} = +4\text{ dBu}`
        * EBU
            * :math:`-18\text{ dBFS} = -4\text{ dBVU} = 0\text{ dBu}`

    dBVU
        Decibels relative to 1.0 volts RMS. Its amplitude is calculated as:

        .. math::

            dBVU = 20 * log_{10}(V_{RMS})

        where :math:`V_{RMS}` is the RMS voltage of the signal.

        This is also known as a `Volume Unit`_ (VU) and its alignment level is 0 dBVU.

    dBu
        Decibels relative to 0.775 volts RMS. Its amplitude is calculated as:

        .. math::

            dBu = 20 * log_{10}(V_{RMS}/0.775)

        where :math:`V_{RMS}` is the RMS voltage of the signal.

        The `dBu`_ alignment level is :math:`+4\text{ dBu} = 0\text{ dBVU}`.


    Discovery Server
        A command-line application available for Windows, macOS, and Linux.
        It allows you to replace mDNS-based automatic discovery with a centralized
        registry of |NDI| sources.

        More information can be found in the `Discovery Server`_,
        `Receive Discovery Monitor and Control`_ and
        `Send Discovery and Advertiser`_ documentation.

    Send Advertiser
        Provides the API for advertising |NDI| senders within the :term:`Discovery Server`,
        ensuring they can be discovered by other systems.

        More information can be found in the `Send Advertiser API`_ documentation.

    Send Listener
        Offers the API for retrieving a list of advertised senders,
        enabling the monitoring of sender events.

        More information can be found in the `Send Listener API`_ documentation.

    Receive Advertiser
        Provides the API for advertising |NDI| receivers within the :term:`Discovery Server`,
        ensuring they can be discovered by other systems.

        More information can be found in the `Receive Advertiser API`_ documentation.

    Receive Listener
        Offers the API for retrieving a list of advertised receivers,
        enabling the monitoring of receiver events and the control of the sources connected to those receivers.
        These APIs provide a powerful method for discovering, monitoring, and controlling receivers
        in real time. The |NDI| Receiver Advertiser API and |NDI| Receiver Listener API are both included
        as part of the Standard SDK.

        More information can be found in the `Receive Listener API`_ documentation.

    NDI Configuration
        The |NDI| configuration settings are stored in JSON files as described in the
        `NDI Configuration File`_ documentation. The location of these files varies per platform and is
        described in the |NDI| `Platform Documentation`_.

        For Windows, the |NDI| Tools Bundle includes “Access Manager”, a user interface for configuring
        most of the settings.  They are also stored in ``C:\ProgramData\NDI\ndi-config.v1.json``.

        For macOS and Linux, the configuration settings are stored in ``$HOME/.ndi/ndi-config.v1.json``.

    Discovery Configuration

        To use the |NDI| :term:`Discovery Server`, it will most likely be necessary to configure IP addresses for
        the servers on the network.  This can be done by setting the following in the :term:`NDI Configuration`

        .. code-block:: json

            {
              "ndi": {
                "networks": {
                  "ips": "",
                  "discovery": "<discovery-server-ips>"
                }
              }
            }

        Multiple discovery servers can be specified by separating their IP addresses with commas.

        More information can be found in the `Discovery Server`_ documentation.



.. _dBu: https://en.m.wikipedia.org/wiki/Decibel#Voltage
.. _dBFS: https://en.m.wikipedia.org/wiki/DBFS
.. _Volume Unit: https://en.m.wikipedia.org/wiki/VU_meter
.. _Discovery Server: https://docs.ndi.video/all/getting-started/white-paper/discovery-and-registration/discovery-server
.. _Send Discovery and Advertiser: https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-sender-discovery-and-monitor
.. _Receive Discovery Monitor and Control: https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-recv-discovery-monitor-and-control
.. _Receive Advertiser API: https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-recv-discovery-monitor-and-control#ndi-recv-a-dvertiser
.. _Receive Listener API: https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-recv-discovery-monitor-and-control#ndi-recv-listener
.. _Send Advertiser API: https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-sender-discovery-and-monitor/ndi-sender-advertiser
.. _Send Listener API: https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-sender-discovery-and-monitor/ndi-sender-listener
.. _NDI Configuration File: https://docs.ndi.video/all/developing-with-ndi/sdk/configuration-files
.. _Platform Documentation: https://docs.ndi.video/all/developing-with-ndi/sdk/platform-considerations
