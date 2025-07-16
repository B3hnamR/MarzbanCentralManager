"""Node data models."""

from dataclasses import dataclass
from typing import Optional, Dict, Any, Literal
from enum import Enum


class NodeStatus(str, Enum):
    """Node status enumeration."""
    CONNECTED = "connected"
    CONNECTING = "connecting"
    DISCONNECTED = "disconnected"
    DISABLED = "disabled"
    ERROR = "error"


@dataclass
class NodeSettings:
    """Node settings model."""
    min_node_version: str
    certificate: str
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'NodeSettings':
        """Create NodeSettings from dictionary."""
        return cls(
            min_node_version=data.get("min_node_version", ""),
            certificate=data.get("certificate", "")
        )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "min_node_version": self.min_node_version,
            "certificate": self.certificate
        }


@dataclass
class Node:
    """Node model."""
    id: int
    name: str
    address: str
    port: int
    api_port: int
    usage_coefficient: float
    status: NodeStatus
    xray_version: Optional[str] = None
    message: Optional[str] = None
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Node':
        """Create Node from dictionary."""
        return cls(
            id=data["id"],
            name=data["name"],
            address=data["address"],
            port=data["port"],
            api_port=data["api_port"],
            usage_coefficient=data["usage_coefficient"],
            status=NodeStatus(data.get("status", "disconnected")),
            xray_version=data.get("xray_version"),
            message=data.get("message")
        )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "name": self.name,
            "address": self.address,
            "port": self.port,
            "api_port": self.api_port,
            "usage_coefficient": self.usage_coefficient,
            "status": self.status.value,
            "xray_version": self.xray_version,
            "message": self.message
        }
    
    @property
    def is_healthy(self) -> bool:
        """Check if node is healthy."""
        return self.status == NodeStatus.CONNECTED
    
    @property
    def display_status(self) -> str:
        """Get display-friendly status."""
        status_map = {
            NodeStatus.CONNECTED: "🟢 Connected",
            NodeStatus.CONNECTING: "🟡 Connecting",
            NodeStatus.DISCONNECTED: "🔴 Disconnected",
            NodeStatus.DISABLED: "⚫ Disabled",
            NodeStatus.ERROR: "❌ Error"
        }
        return status_map.get(self.status, "❓ Unknown")


@dataclass
class NodeCreate:
    """Node creation model."""
    name: str
    address: str
    port: int = 62050
    api_port: int = 62051
    usage_coefficient: float = 1.0
    add_as_new_host: bool = True
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "name": self.name,
            "address": self.address,
            "port": self.port,
            "api_port": self.api_port,
            "usage_coefficient": self.usage_coefficient,
            "add_as_new_host": self.add_as_new_host
        }
    
    def validate(self) -> bool:
        """Validate node creation data."""
        from ..core.utils import is_valid_ip, is_valid_port, validate_node_name
        
        if not validate_node_name(self.name):
            raise ValueError("Invalid node name")
        
        if not is_valid_ip(self.address):
            raise ValueError("Invalid IP address")
        
        if not is_valid_port(self.port):
            raise ValueError("Invalid port number")
        
        if not is_valid_port(self.api_port):
            raise ValueError("Invalid API port number")
        
        if self.usage_coefficient <= 0:
            raise ValueError("Usage coefficient must be positive")
        
        return True


@dataclass
class NodeUpdate:
    """Node update model."""
    name: Optional[str] = None
    address: Optional[str] = None
    port: Optional[int] = None
    api_port: Optional[int] = None
    usage_coefficient: Optional[float] = None
    status: Optional[NodeStatus] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary, excluding None values."""
        data = {}
        
        if self.name is not None:
            data["name"] = self.name
        if self.address is not None:
            data["address"] = self.address
        if self.port is not None:
            data["port"] = self.port
        if self.api_port is not None:
            data["api_port"] = self.api_port
        if self.usage_coefficient is not None:
            data["usage_coefficient"] = self.usage_coefficient
        if self.status is not None:
            data["status"] = self.status.value
        
        return data
    
    def validate(self) -> bool:
        """Validate node update data."""
        from ..core.utils import is_valid_ip, is_valid_port, validate_node_name
        
        if self.name is not None and not validate_node_name(self.name):
            raise ValueError("Invalid node name")
        
        if self.address is not None and not is_valid_ip(self.address):
            raise ValueError("Invalid IP address")
        
        if self.port is not None and not is_valid_port(self.port):
            raise ValueError("Invalid port number")
        
        if self.api_port is not None and not is_valid_port(self.api_port):
            raise ValueError("Invalid API port number")
        
        if self.usage_coefficient is not None and self.usage_coefficient <= 0:
            raise ValueError("Usage coefficient must be positive")
        
        return True


@dataclass
class NodeUsage:
    """Node usage statistics model."""
    node_id: int
    node_name: str
    uplink: int
    downlink: int
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'NodeUsage':
        """Create NodeUsage from dictionary."""
        return cls(
            node_id=data["node_id"],
            node_name=data["node_name"],
            uplink=data["uplink"],
            downlink=data["downlink"]
        )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "node_id": self.node_id,
            "node_name": self.node_name,
            "uplink": self.uplink,
            "downlink": self.downlink
        }
    
    @property
    def total_usage(self) -> int:
        """Get total usage (uplink + downlink)."""
        return self.uplink + self.downlink
    
    @property
    def formatted_uplink(self) -> str:
        """Get formatted uplink."""
        from ..core.utils import format_bytes
        return format_bytes(self.uplink)
    
    @property
    def formatted_downlink(self) -> str:
        """Get formatted downlink."""
        from ..core.utils import format_bytes
        return format_bytes(self.downlink)
    
    @property
    def formatted_total(self) -> str:
        """Get formatted total usage."""
        from ..core.utils import format_bytes
        return format_bytes(self.total_usage)