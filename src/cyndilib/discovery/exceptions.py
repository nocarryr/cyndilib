
class DiscoveryServerNotFoundError(UserWarning):
    """Warning raised when the discovery server is not found
    """


class DiscoveryServerUnavailableError(UserWarning):
    """Warning raised when the built-in discovery server is unavailable for the
    current platform
    """
