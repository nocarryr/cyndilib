"""
Settings for :term:`Discovery Server` advertising

.. versionadded:: 0.1.4
"""
from typing import NotRequired, TypedDict


class ReceiveAdvertiserSettings(TypedDict):
    """:term:`Receive Advertiser` settings for the :class:`~.receiver.Receiver`
    """
    enabled: NotRequired[bool]
    """Whether the :term:`Receive Advertiser` should be enabled for the receiver.

    If enabled and the :term:`Discovery Server` cannot be found,
    a :class:`~.DiscoveryServerNotFoundError` warning will be raised.

    The default is ``False``.
    """
    use_default_url_address: NotRequired[bool]
    """Whether to use the default URL address for the :term:`Discovery Server`

    The default URL configuration is described in :term:`Discovery Configuration`.

    .. important::

        If False (and :attr:`enabled` is True), the :attr:`url_address` will be
        used for the :term:`Discovery Server` and **should be specified**.

    The default is ``True``.
    """
    url_address: NotRequired[str]
    """The URL address of the :term:`Discovery Server`

    This field is ignored if :attr:`use_default_url_address` is True.

    The default is the local loopback address (``'127.0.0.1'``) which would not
    allow discovery across the network.
    """
    allow_controlling: NotRequired[bool]
    """If True, allows controlling of the receiver through the :term:`Discovery Server`
    (if :attr:`enabled` is True).

    If enabled, the receiver can be controlled through the
    :term:`Receive Listener` API.

    The default is ``False``.
    """
    allow_monitoring: NotRequired[bool]
    """If True, allows monitoring of the receiver through the :term:`Discovery Server`
    (if :attr:`enabled` is True)

    The default is ``True``.
    """


class ReceiveAdvertiserSettingsFull(TypedDict):
    """Mirror of :class:`ReceiveAdvertiserSettings` with all fields required."""
    enabled: bool
    use_default_url_address: bool
    url_address: str
    allow_controlling: bool
    allow_monitoring: bool


RECEIVE_ADVERTISER_SETTINGS_DEFAULT = ReceiveAdvertiserSettingsFull(
    enabled=False,
    use_default_url_address=True,
    url_address='127.0.0.1',
    allow_controlling=False,
    allow_monitoring=True,
)
"""Default settings for the :term:`Receive Advertiser`"""


class SendAdvertiserSettings(TypedDict, total=False):
    """:term:`Send Advertiser` settings for the :class:`~.sender.Sender`
    """
    enabled: NotRequired[bool]
    """Whether the :term:`Send Advertiser` should be enabled for the sender.

    If enabled and the :term:`Discovery Server` cannot be found,
    a :class:`~.DiscoveryServerNotFoundError` warning will be raised.

    The default is ``False``.
    """
    use_default_url_address: NotRequired[bool]
    """Whether to use the default URL address for the :term:`Discovery Server`

    The default URL configuration is described in :term:`Discovery Configuration`.

    .. important::

        If False (and :attr:`enabled` is True), the :attr:`url_address` will be
        used for the :term:`Discovery Server` and **should be specified**.

    The default is ``True``.
    """
    url_address: NotRequired[str]
    """The URL address of the :term:`Discovery Server`

    This field is ignored if :attr:`use_default_url_address` is True.

    The default is the local loopback address (``'127.0.0.1'``) which would not
    allow discovery across the network.
    """
    allow_monitoring: NotRequired[bool]
    """If True, allows monitoring of the sender through the :term:`Discovery Server`
    (if :attr:`enabled` is True)

    The default is ``True``.
    """


class SendAdvertiserSettingsFull(TypedDict):
    """Mirror of :class:`SendAdvertiserSettings` with all fields required."""
    enabled: bool
    use_default_url_address: bool
    url_address: str
    allow_monitoring: bool


DEFAULT_SEND_ADVERTISER_SETTINGS = SendAdvertiserSettingsFull(
    enabled=False,
    use_default_url_address=True,
    url_address='127.0.0.1',
    allow_monitoring=True,
)
"""Default settings for the :term:`Send Advertiser`"""
