"""
This module defines constants used throughout the application,
including API endpoints and other configuration values.
"""
from enum import Enum


class APIEndpoints(str, Enum):
    """
    Enumeration for Marzban API endpoints to avoid hardcoded strings.
    """
    TOKEN = "/api/admin/token"

    NODES = "/api/nodes"
    NODE_USAGE = "/api/node/{node_id}/usage"

    USERS = "/api/users"
    USER = "/api/user/{username}"
    USER_USAGE = "/api/user/{username}/usage"
    USER_SUBSCRIPTION_INFO = "/api/user/{username}/subscription"
    USER_RESET = "/api/user/{username}/reset"

    ADMINS = "/api/admins"
    ADMIN = "/api/admin/{username}"

    USER_TEMPLATES = "/api/user_templates"
    USER_TEMPLATE = "/api/user_template/{id}"

    SYSTEM = "/api/system"
    SYSTEM_STATS = "/api/system/stats"

    SUBSCRIPTION = "/api/subscription"
    SUBSCRIPTION_USER = "/api/sub/{sub_code}/user"
    SUBSCRIPTION_INFO = "/api/sub/{sub_code}"


    def __str__(self) -> str:
        return self.value

