"""API Response models for Marzban Central Manager."""

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Union
from datetime import datetime


@dataclass
class APIResponse:
    """Base API response model."""
    
    success: bool
    data: Optional[Dict[str, Any]] = None
    message: Optional[str] = None
    status_code: Optional[int] = None
    timestamp: Optional[datetime] = None
    
    @classmethod
    def success_response(
        cls, 
        data: Optional[Dict[str, Any]] = None, 
        message: str = "Success"
    ) -> "APIResponse":
        """Create a success response."""
        return cls(
            success=True,
            data=data,
            message=message,
            status_code=200,
            timestamp=datetime.now()
        )
    
    @classmethod
    def error_response(
        cls, 
        message: str, 
        status_code: int = 500,
        data: Optional[Dict[str, Any]] = None
    ) -> "APIResponse":
        """Create an error response."""
        return cls(
            success=False,
            data=data,
            message=message,
            status_code=status_code,
            timestamp=datetime.now()
        )


@dataclass
class PaginatedResponse:
    """Paginated API response model."""
    
    items: List[Dict[str, Any]]
    total: int
    page: int
    per_page: int
    pages: int
    has_next: bool
    has_prev: bool
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PaginatedResponse":
        """Create from dictionary."""
        return cls(
            items=data.get("items", []),
            total=data.get("total", 0),
            page=data.get("page", 1),
            per_page=data.get("per_page", 10),
            pages=data.get("pages", 1),
            has_next=data.get("has_next", False),
            has_prev=data.get("has_prev", False)
        )


@dataclass
class StatusResponse:
    """Status response model."""
    
    status: str
    message: Optional[str] = None
    details: Optional[Dict[str, Any]] = None
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "StatusResponse":
        """Create from dictionary."""
        return cls(
            status=data.get("status", "unknown"),
            message=data.get("message"),
            details=data.get("details")
        )


@dataclass
class ErrorResponse:
    """Error response model."""
    
    error: str
    code: Optional[str] = None
    details: Optional[Dict[str, Any]] = None
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "ErrorResponse":
        """Create from dictionary."""
        return cls(
            error=data.get("error", "Unknown error"),
            code=data.get("code"),
            details=data.get("details")
        )


# Type aliases for common response types
NodeListResponse = List[Dict[str, Any]]
NodeResponse = Dict[str, Any]
StatsResponse = Dict[str, Union[str, int, float]]
HealthResponse = Dict[str, Any]