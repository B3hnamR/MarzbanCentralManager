"""Enhanced Base API client with advanced connection management."""

import asyncio
import httpx
from typing import Optional, Dict, Any
from urllib.parse import urljoin

from ..core.config import MarzbanConfig
from ..core.logger import get_logger
from ..core.exceptions import (
    APIError, AuthenticationError, AuthorizationError, 
    NotFoundError, ValidationError, ConnectionError
)
from ..core.connection_manager import connection_manager, RetryConfig, CircuitBreakerConfig
from ..core.token_manager import token_manager
from ..core.security import security_manager


class BaseAPIClient:
    """Enhanced base API client with advanced features."""
    
    def __init__(self, config: MarzbanConfig, service_name: str = "marzban"):
        self.config = config
        self.service_name = service_name
        self.logger = get_logger(f"api.{self.__class__.__name__}")
        self._initialized = False
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self._initialize()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.close()
    
    async def _initialize(self):
        """Initialize connection pool and token management."""
        if self._initialized:
            return
        
        try:
            # Create connection pool with advanced configuration
            retry_config = RetryConfig(
                max_attempts=3,
                base_delay=1.0,
                max_delay=30.0,
                exponential_base=2.0,
                jitter=True
            )
            
            circuit_config = CircuitBreakerConfig(
                failure_threshold=5,
                recovery_timeout=60,
                success_threshold=3
            )
            
            base_url = f"{self.config.base_url.rstrip('/')}"
            
            await connection_manager.create_pool(
                service_name=self.service_name,
                base_url=base_url,
                max_connections=10,
                timeout=self.config.timeout,
                verify_ssl=self.config.verify_ssl,
                retry_config=retry_config,
                circuit_config=circuit_config
            )
            
            self._initialized = True
            self.logger.debug(f"API client initialized for {self.service_name}")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize API client: {e}")
            raise
    
    async def close(self):
        """Close connections and cleanup."""
        if self._initialized:
            await connection_manager.close_pool(self.service_name)
            await token_manager.remove_token(self.service_name)
            self._initialized = False
            self.logger.debug(f"API client closed for {self.service_name}")
    
    def _build_url(self, endpoint: str) -> str:
        """Build full URL from endpoint."""
        base_url = self.config.base_url.rstrip('/')
        endpoint = endpoint.lstrip('/')
        return urljoin(f"{base_url}/", f"api/{endpoint}")
    
    def _get_headers(self, include_auth: bool = True) -> Dict[str, str]:
        """Get request headers."""
        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
        
        return headers
    
    async def _handle_response(self, response: httpx.Response) -> Dict[str, Any]:
        """Handle API response and raise appropriate exceptions."""
        try:
            data = response.json() if response.content else {}
        except Exception:
            data = {"detail": "Invalid JSON response"}
        
        if response.status_code == 200:
            return data
        elif response.status_code == 401:
            raise AuthenticationError(
                data.get("detail", "Authentication failed"),
                status_code=response.status_code,
                response_data=data
            )
        elif response.status_code == 403:
            raise AuthorizationError(
                data.get("detail", "Access forbidden"),
                status_code=response.status_code,
                response_data=data
            )
        elif response.status_code == 404:
            raise NotFoundError(
                data.get("detail", "Resource not found"),
                status_code=response.status_code,
                response_data=data
            )
        elif response.status_code == 409:
            raise ValidationError(
                data.get("detail", "Entity already exists"),
                status_code=response.status_code,
                response_data=data
            )
        elif response.status_code == 422:
            detail = data.get("detail", "Validation error")
            if isinstance(detail, list) and detail:
                # Extract validation error messages
                errors = []
                for error in detail:
                    if isinstance(error, dict):
                        field = " -> ".join(str(x) for x in error.get("loc", []))
                        msg = error.get("msg", "Invalid value")
                        errors.append(f"{field}: {msg}")
                detail = "; ".join(errors)
            
            raise ValidationError(
                detail,
                status_code=response.status_code,
                response_data=data
            )
        else:
            raise APIError(
                data.get("detail", f"API error: {response.status_code}"),
                status_code=response.status_code,
                response_data=data
            )
    
    async def _request(
        self,
        method: str,
        endpoint: str,
        data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
        include_auth: bool = True,
        use_retry: bool = True,
        use_circuit_breaker: bool = True
    ) -> Dict[str, Any]:
        """Make HTTP request with advanced connection management."""
        await self._initialize()
        
        # Get current token
        if include_auth:
            token = await token_manager.get_token(self.service_name, auto_refresh=True)
            if not token:
                # Try to authenticate
                token = await self._authenticate_and_store()
            
            if token:
                headers = self._get_headers_with_token(token)
            else:
                raise AuthenticationError("No valid token available")
        else:
            headers = self._get_headers(include_auth=False)
        
        # Build full URL
        url = f"/api/{endpoint.lstrip('/')}"
        
        try:
            self.logger.debug(f"{method} {url}")
            
            # Make request through connection manager
            response = await connection_manager.request(
                service_name=self.service_name,
                method=method,
                url=url,
                headers=headers,
                data=data,
                params=params,
                use_retry=use_retry,
                use_circuit_breaker=use_circuit_breaker
            )
            
            return await self._handle_response(response)
            
        except Exception as e:
            # Handle authentication errors
            if "401" in str(e) or "authentication" in str(e).lower():
                if include_auth:
                    self.logger.warning("Authentication failed, attempting to refresh token")
                    try:
                        token = await self._authenticate_and_store()
                        if token:
                            # Retry with new token
                            headers = self._get_headers_with_token(token)
                            response = await connection_manager.request(
                                service_name=self.service_name,
                                method=method,
                                url=url,
                                headers=headers,
                                data=data,
                                params=params,
                                use_retry=False,  # Don't retry again
                                use_circuit_breaker=use_circuit_breaker
                            )
                            return await self._handle_response(response)
                    except Exception as auth_error:
                        self.logger.error(f"Token refresh failed: {auth_error}")
                        raise AuthenticationError("Failed to refresh authentication")
            
            # Re-raise the original exception
            raise
    
    async def get(self, endpoint: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Make GET request."""
        return await self._request("GET", endpoint, params=params)
    
    async def post(self, endpoint: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Make POST request."""
        return await self._request("POST", endpoint, data=data)
    
    async def put(self, endpoint: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Make PUT request."""
        return await self._request("PUT", endpoint, data=data)
    
    async def delete(self, endpoint: str) -> Dict[str, Any]:
        """Make DELETE request."""
        return await self._request("DELETE", endpoint)
    
    def _get_headers_with_token(self, token: str) -> Dict[str, str]:
        """Get headers with authentication token."""
        return {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}"
        }
    
    async def _authenticate_and_store(self) -> Optional[str]:
        """Authenticate and store token with auto-refresh."""
        try:
            self.logger.info("Authenticating with Marzban API")
            
            auth_data = {
                "username": self.config.username,
                "password": self.config.password
            }
            
            # Make authentication request without retry/circuit breaker for initial auth
            response = await connection_manager.request(
                service_name=self.service_name,
                method="POST",
                url="/api/admin/token",
                headers=self._get_headers(include_auth=False),
                data=auth_data,
                use_retry=False,
                use_circuit_breaker=False
            )
            
            response_data = await self._handle_response(response)
            token = response_data.get("access_token")
            
            if not token:
                raise AuthenticationError("No access token in response")
            
            # Store token with auto-refresh callback
            await token_manager.store_token(
                service_name=self.service_name,
                token=token,
                refresh_callback=self._refresh_token_callback
            )
            
            self.logger.info("Authentication successful and token stored")
            return token
            
        except Exception as e:
            self.logger.error(f"Authentication failed: {e}")
            raise
    
    async def _refresh_token_callback(self) -> Optional[str]:
        """Callback for automatic token refresh."""
        try:
            self.logger.debug("Refreshing token via callback")
            
            auth_data = {
                "username": self.config.username,
                "password": self.config.password
            }
            
            response = await connection_manager.request(
                service_name=self.service_name,
                method="POST",
                url="/api/admin/token",
                headers=self._get_headers(include_auth=False),
                data=auth_data,
                use_retry=True,
                use_circuit_breaker=False
            )
            
            response_data = await self._handle_response(response)
            new_token = response_data.get("access_token")
            
            if new_token:
                self.logger.debug("Token refreshed successfully")
                return new_token
            else:
                self.logger.error("No access token in refresh response")
                return None
                
        except Exception as e:
            self.logger.error(f"Token refresh callback failed: {e}")
            return None
    
    async def authenticate(self) -> str:
        """Authenticate and get access token (legacy method)."""
        token = await self._authenticate_and_store()
        if not token:
            raise AuthenticationError("Authentication failed")
        return token
    
    async def test_connection(self) -> bool:
        """Test API connection."""
        try:
            await self._authenticate_and_store()
            return True
        except Exception as e:
            self.logger.error(f"Connection test failed: {e}")
            return False
    
    async def get_connection_stats(self) -> Optional[Dict[str, Any]]:
        """Get connection statistics."""
        return await connection_manager.get_pool_stats(self.service_name)
    
    async def get_token_info(self) -> Optional[Dict[str, Any]]:
        """Get token information."""
        token_info = token_manager.get_token_info(self.service_name)
        if token_info:
            return {
                "issued_at": token_info.issued_at.isoformat(),
                "expires_at": token_info.expires_at.isoformat(),
                "is_expired": token_info.is_expired,
                "needs_refresh": token_info.needs_refresh,
                "time_until_expiry": token_info.time_until_expiry
            }
        return None