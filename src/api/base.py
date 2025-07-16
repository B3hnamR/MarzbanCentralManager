"""Base API client for Marzban Central Manager."""

import httpx
import asyncio
from typing import Optional, Dict, Any, Union
from urllib.parse import urljoin

from ..core.config import MarzbanConfig
from ..core.logger import get_logger
from ..core.exceptions import (
    APIError, AuthenticationError, AuthorizationError, 
    NotFoundError, ValidationError, ConnectionError
)


class BaseAPIClient:
    """Base API client with common functionality."""
    
    def __init__(self, config: MarzbanConfig):
        self.config = config
        self.logger = get_logger(f"api.{self.__class__.__name__}")
        self._client: Optional[httpx.AsyncClient] = None
        self._token: Optional[str] = None
    
    async def __aenter__(self):
        """Async context manager entry."""
        await self._ensure_client()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.close()
    
    async def _ensure_client(self):
        """Ensure HTTP client is initialized."""
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(self.config.timeout),
                verify=self.config.verify_ssl,
                follow_redirects=True
            )
    
    async def close(self):
        """Close the HTTP client."""
        if self._client:
            await self._client.aclose()
            self._client = None
    
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
        
        if include_auth and self._token:
            headers["Authorization"] = f"Bearer {self._token}"
        
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
        retry_count: int = 0
    ) -> Dict[str, Any]:
        """Make HTTP request with error handling and retries."""
        await self._ensure_client()
        
        url = self._build_url(endpoint)
        headers = self._get_headers(include_auth)
        
        try:
            self.logger.debug(f"{method} {url}")
            
            if method.upper() == "GET":
                response = await self._client.get(url, headers=headers, params=params)
            elif method.upper() == "POST":
                response = await self._client.post(url, headers=headers, json=data, params=params)
            elif method.upper() == "PUT":
                response = await self._client.put(url, headers=headers, json=data, params=params)
            elif method.upper() == "DELETE":
                response = await self._client.delete(url, headers=headers, params=params)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")
            
            return await self._handle_response(response)
            
        except httpx.ConnectError as e:
            raise ConnectionError(f"Failed to connect to API: {e}")
        except httpx.TimeoutException as e:
            raise ConnectionError(f"API request timeout: {e}")
        except AuthenticationError as e:
            # Try to refresh token and retry once
            if retry_count == 0 and include_auth:
                self.logger.warning("Authentication failed, attempting to refresh token")
                await self.authenticate()
                return await self._request(method, endpoint, data, params, include_auth, retry_count + 1)
            raise
        except (APIError, ConnectionError):
            raise
        except Exception as e:
            raise APIError(f"Unexpected error: {e}")
    
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
    
    async def authenticate(self) -> str:
        """Authenticate and get access token."""
        self.logger.info("Authenticating with Marzban API")
        
        auth_data = {
            "username": self.config.username,
            "password": self.config.password
        }
        
        try:
            response = await self._request(
                "POST", 
                "admin/token", 
                data=auth_data, 
                include_auth=False
            )
            
            self._token = response.get("access_token")
            if not self._token:
                raise AuthenticationError("No access token in response")
            
            self.logger.info("Authentication successful")
            return self._token
            
        except Exception as e:
            self.logger.error(f"Authentication failed: {e}")
            raise
    
    async def test_connection(self) -> bool:
        """Test API connection."""
        try:
            await self.authenticate()
            return True
        except Exception as e:
            self.logger.error(f"Connection test failed: {e}")
            return False