"""Custom exceptions for Marzban Central Manager."""


class MarzbanManagerException(Exception):
    """Base exception for Marzban Manager."""
    pass


class ConfigurationError(MarzbanManagerException):
    """Raised when there's a configuration error."""
    pass


class APIError(MarzbanManagerException):
    """Base class for API-related errors."""
    
    def __init__(self, message: str, status_code: int = None, response_data: dict = None):
        super().__init__(message)
        self.status_code = status_code
        self.response_data = response_data


class AuthenticationError(APIError):
    """Raised when authentication fails."""
    pass


class AuthorizationError(APIError):
    """Raised when user doesn't have permission."""
    pass


class NotFoundError(APIError):
    """Raised when resource is not found."""
    pass


class ValidationError(APIError):
    """Raised when request validation fails."""
    pass


class ConnectionError(APIError):
    """Raised when connection to API fails."""
    pass


class NodeError(MarzbanManagerException):
    """Base class for node-related errors."""
    pass


class NodeNotFoundError(NodeError):
    """Raised when node is not found."""
    pass


class NodeConnectionError(NodeError):
    """Raised when node connection fails."""
    pass


class NodeAlreadyExistsError(NodeError):
    """Raised when trying to add a node that already exists."""
    pass