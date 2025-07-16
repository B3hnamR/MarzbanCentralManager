"""Utility functions for Marzban Central Manager."""

import re
import ipaddress
from typing import Union, Optional
from datetime import datetime, timezone


def is_valid_ip(ip: str) -> bool:
    """Check if string is a valid IP address."""
    try:
        ipaddress.ip_address(ip)
        return True
    except ValueError:
        return False


def is_valid_port(port: Union[str, int]) -> bool:
    """Check if port number is valid."""
    try:
        port_num = int(port)
        return 1 <= port_num <= 65535
    except (ValueError, TypeError):
        return False


def is_valid_domain(domain: str) -> bool:
    """Check if string is a valid domain name."""
    if not domain or len(domain) > 253:
        return False
    
    # Remove trailing dot if present
    if domain.endswith('.'):
        domain = domain[:-1]
    
    # Check each label
    labels = domain.split('.')
    if len(labels) < 2:
        return False
    
    for label in labels:
        if not label or len(label) > 63:
            return False
        if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$', label):
            return False
    
    return True


def is_valid_url(url: str) -> bool:
    """Check if string is a valid URL."""
    url_pattern = re.compile(
        r'^https?://'  # http:// or https://
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'  # domain...
        r'localhost|'  # localhost...
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # ...or ip
        r'(?::\d+)?'  # optional port
        r'(?:/?|[/?]\S+)$', re.IGNORECASE)
    return url_pattern.match(url) is not None


def format_bytes(bytes_value: int) -> str:
    """Format bytes to human readable format."""
    if bytes_value == 0:
        return "0 B"
    
    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
    unit_index = 0
    size = float(bytes_value)
    
    while size >= 1024 and unit_index < len(units) - 1:
        size /= 1024
        unit_index += 1
    
    if unit_index == 0:
        return f"{int(size)} {units[unit_index]}"
    else:
        return f"{size:.2f} {units[unit_index]}"


def format_duration(seconds: int) -> str:
    """Format seconds to human readable duration."""
    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        minutes = seconds // 60
        remaining_seconds = seconds % 60
        if remaining_seconds == 0:
            return f"{minutes}m"
        return f"{minutes}m {remaining_seconds}s"
    elif seconds < 86400:
        hours = seconds // 3600
        remaining_minutes = (seconds % 3600) // 60
        if remaining_minutes == 0:
            return f"{hours}h"
        return f"{hours}h {remaining_minutes}m"
    else:
        days = seconds // 86400
        remaining_hours = (seconds % 86400) // 3600
        if remaining_hours == 0:
            return f"{days}d"
        return f"{days}d {remaining_hours}h"


def get_current_timestamp() -> str:
    """Get current timestamp in ISO format."""
    return datetime.now(timezone.utc).isoformat()


def parse_timestamp(timestamp_str: str) -> Optional[datetime]:
    """Parse timestamp string to datetime object."""
    try:
        return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
    except (ValueError, AttributeError):
        return None


def truncate_string(text: str, max_length: int, suffix: str = "...") -> str:
    """Truncate string to maximum length."""
    if len(text) <= max_length:
        return text
    return text[:max_length - len(suffix)] + suffix


def sanitize_filename(filename: str) -> str:
    """Sanitize filename by removing invalid characters."""
    # Remove invalid characters
    sanitized = re.sub(r'[<>:"/\\|?*]', '_', filename)
    
    # Remove leading/trailing spaces and dots
    sanitized = sanitized.strip(' .')
    
    # Ensure it's not empty
    if not sanitized:
        sanitized = "unnamed"
    
    return sanitized


def mask_sensitive_data(data: str, mask_char: str = "*", visible_chars: int = 4) -> str:
    """Mask sensitive data showing only first and last few characters."""
    if not data or len(data) <= visible_chars * 2:
        return mask_char * len(data) if data else ""
    
    visible_start = data[:visible_chars]
    visible_end = data[-visible_chars:]
    masked_middle = mask_char * (len(data) - visible_chars * 2)
    
    return f"{visible_start}{masked_middle}{visible_end}"


def validate_node_name(name: str) -> bool:
    """Validate node name format."""
    if not name or len(name) < 2 or len(name) > 50:
        return False
    
    # Allow alphanumeric, spaces, hyphens, underscores
    return re.match(r'^[a-zA-Z0-9\s\-_]+$', name) is not None


def clean_url(url: str) -> str:
    """Clean and normalize URL."""
    url = url.strip()
    
    # Remove trailing slash
    if url.endswith('/'):
        url = url[:-1]
    
    return url


def is_port_open(host: str, port: int, timeout: int = 5) -> bool:
    """Check if a port is open on a host."""
    import socket
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (socket.timeout, socket.error):
        return False


def resolve_hostname(hostname: str) -> Optional[str]:
    """Resolve hostname to IP address."""
    import socket
    try:
        return socket.gethostbyname(hostname)
    except socket.gaierror:
        return None


def extract_host_port(address: str) -> tuple[str, Optional[int]]:
    """Extract host and port from address string."""
    if ':' in address:
        parts = address.rsplit(':', 1)
        try:
            port = int(parts[1])
            return parts[0], port
        except ValueError:
            return address, None
    return address, None


def calculate_success_rate(passed: int, total: int) -> float:
    """Calculate success rate percentage."""
    if total == 0:
        return 0.0
    return (passed / total) * 100


def generate_random_port(start: int = 10000, end: int = 65000) -> int:
    """Generate a random port number in the specified range."""
    import random
    return random.randint(start, end)


def is_private_ip(ip: str) -> bool:
    """Check if IP address is private."""
    try:
        ip_obj = ipaddress.ip_address(ip)
        return ip_obj.is_private
    except ValueError:
        return False


def normalize_node_name(name: str) -> str:
    """Normalize node name by removing extra spaces and invalid characters."""
    if not name:
        return ""
    
    # Remove extra spaces and normalize
    normalized = re.sub(r'\s+', ' ', name.strip())
    
    # Replace invalid characters with underscores
    normalized = re.sub(r'[^\w\s\-]', '_', normalized)
    
    return normalized


def validate_ssh_credentials(username: str, password: str) -> dict:
    """Validate SSH credentials format."""
    issues = []
    
    if not username or len(username.strip()) == 0:
        issues.append("Username is required")
    elif len(username) > 32:
        issues.append("Username is too long (max 32 characters)")
    elif not re.match(r'^[a-zA-Z0-9._-]+$', username):
        issues.append("Username contains invalid characters")
    
    if not password:
        issues.append("Password is required")
    elif len(password) < 6:
        issues.append("Password is too short (min 6 characters)")
    
    return {
        "valid": len(issues) == 0,
        "issues": issues
    }


def format_network_speed(bytes_per_second: float) -> str:
    """Format network speed to human readable format."""
    # Convert to bits per second
    bits_per_second = bytes_per_second * 8
    
    units = ["bps", "Kbps", "Mbps", "Gbps"]
    unit_index = 0
    speed = float(bits_per_second)
    
    while speed >= 1000 and unit_index < len(units) - 1:
        speed /= 1000
        unit_index += 1
    
    return f"{speed:.1f} {units[unit_index]}"


def parse_version_string(version: str) -> tuple[int, int, int]:
    """Parse version string to tuple of integers."""
    try:
        # Remove 'v' prefix if present
        version = version.lstrip('v')
        
        # Split by dots and convert to integers
        parts = version.split('.')
        major = int(parts[0]) if len(parts) > 0 else 0
        minor = int(parts[1]) if len(parts) > 1 else 0
        patch = int(parts[2]) if len(parts) > 2 else 0
        
        return (major, minor, patch)
    except (ValueError, IndexError):
        return (0, 0, 0)


def compare_versions(version1: str, version2: str) -> int:
    """Compare two version strings. Returns -1, 0, or 1."""
    v1 = parse_version_string(version1)
    v2 = parse_version_string(version2)
    
    if v1 < v2:
        return -1
    elif v1 > v2:
        return 1
    else:
        return 0