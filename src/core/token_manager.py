"""Advanced token management system for Marzban Central Manager."""

import asyncio
import time
import jwt
from typing import Optional, Dict, Any, Callable
from datetime import datetime, timedelta
from dataclasses import dataclass

from .logger import get_logger
from .security import security_manager


@dataclass
class TokenInfo:
    """Token information container."""
    token: str
    expires_at: datetime
    issued_at: datetime
    refresh_threshold: int = 300  # Refresh 5 minutes before expiry
    
    @property
    def is_expired(self) -> bool:
        """Check if token is expired."""
        return datetime.now() >= self.expires_at
    
    @property
    def needs_refresh(self) -> bool:
        """Check if token needs refresh."""
        refresh_time = self.expires_at - timedelta(seconds=self.refresh_threshold)
        return datetime.now() >= refresh_time
    
    @property
    def time_until_expiry(self) -> int:
        """Get seconds until token expires."""
        delta = self.expires_at - datetime.now()
        return max(0, int(delta.total_seconds()))


class TokenManager:
    """Advanced token management with auto-refresh and caching."""
    
    def __init__(self):
        self.logger = get_logger("token_manager")
        self._tokens: Dict[str, TokenInfo] = {}
        self._refresh_callbacks: Dict[str, Callable] = {}
        self._refresh_tasks: Dict[str, asyncio.Task] = {}
        self._lock = asyncio.Lock()
    
    def _decode_token_payload(self, token: str) -> Optional[Dict[str, Any]]:
        """Decode JWT token payload without verification."""
        try:
            # Decode without verification to get expiry info
            payload = jwt.decode(token, options={"verify_signature": False})
            return payload
        except Exception as e:
            self.logger.warning(f"Failed to decode token payload: {e}")
            return None
    
    def _calculate_expiry(self, token: str) -> datetime:
        """Calculate token expiry time."""
        payload = self._decode_token_payload(token)
        
        if payload and 'exp' in payload:
            # Use JWT expiry time
            return datetime.fromtimestamp(payload['exp'])
        else:
            # Default expiry (24 hours from now)
            return datetime.now() + timedelta(hours=24)
    
    async def store_token(
        self, 
        service_name: str, 
        token: str, 
        refresh_callback: Optional[Callable] = None
    ) -> bool:
        """Store token with automatic refresh capability."""
        try:
            async with self._lock:
                expires_at = self._calculate_expiry(token)
                issued_at = datetime.now()
                
                token_info = TokenInfo(
                    token=token,
                    expires_at=expires_at,
                    issued_at=issued_at
                )
                
                self._tokens[service_name] = token_info
                
                if refresh_callback:
                    self._refresh_callbacks[service_name] = refresh_callback
                    # Start auto-refresh task
                    await self._start_refresh_task(service_name)
                
                self.logger.info(f"Token stored for {service_name}, expires at {expires_at}")
                return True
                
        except Exception as e:
            self.logger.error(f"Failed to store token for {service_name}: {e}")
            return False
    
    async def get_token(self, service_name: str, auto_refresh: bool = True) -> Optional[str]:
        """Get valid token, with automatic refresh if needed."""
        try:
            async with self._lock:
                if service_name not in self._tokens:
                    self.logger.warning(f"No token found for {service_name}")
                    return None
                
                token_info = self._tokens[service_name]
                
                # Check if token is expired
                if token_info.is_expired:
                    self.logger.warning(f"Token for {service_name} is expired")
                    
                    if auto_refresh and service_name in self._refresh_callbacks:
                        self.logger.info(f"Attempting to refresh expired token for {service_name}")
                        if await self._refresh_token(service_name):
                            return self._tokens[service_name].token
                    
                    return None
                
                # Check if token needs refresh
                if auto_refresh and token_info.needs_refresh and service_name in self._refresh_callbacks:
                    self.logger.info(f"Token for {service_name} needs refresh")
                    # Refresh in background, return current token
                    asyncio.create_task(self._refresh_token(service_name))
                
                return token_info.token
                
        except Exception as e:
            self.logger.error(f"Failed to get token for {service_name}: {e}")
            return None
    
    async def _refresh_token(self, service_name: str) -> bool:
        """Refresh token using callback."""
        try:
            if service_name not in self._refresh_callbacks:
                self.logger.error(f"No refresh callback for {service_name}")
                return False
            
            refresh_callback = self._refresh_callbacks[service_name]
            
            self.logger.info(f"Refreshing token for {service_name}")
            new_token = await refresh_callback()
            
            if new_token:
                # Update token info
                expires_at = self._calculate_expiry(new_token)
                issued_at = datetime.now()
                
                self._tokens[service_name] = TokenInfo(
                    token=new_token,
                    expires_at=expires_at,
                    issued_at=issued_at
                )
                
                self.logger.info(f"Token refreshed for {service_name}")
                return True
            else:
                self.logger.error(f"Failed to refresh token for {service_name}")
                return False
                
        except Exception as e:
            self.logger.error(f"Token refresh failed for {service_name}: {e}")
            return False
    
    async def _start_refresh_task(self, service_name: str):
        """Start background refresh task."""
        # Cancel existing task if any
        if service_name in self._refresh_tasks:
            self._refresh_tasks[service_name].cancel()
        
        # Start new refresh task
        task = asyncio.create_task(self._refresh_loop(service_name))
        self._refresh_tasks[service_name] = task
    
    async def _refresh_loop(self, service_name: str):
        """Background loop for token refresh."""
        try:
            while service_name in self._tokens:
                token_info = self._tokens[service_name]
                
                # Calculate sleep time until refresh is needed
                sleep_time = max(60, token_info.time_until_expiry - token_info.refresh_threshold)
                
                await asyncio.sleep(sleep_time)
                
                # Check if token still needs refresh
                if service_name in self._tokens and self._tokens[service_name].needs_refresh:
                    await self._refresh_token(service_name)
                
        except asyncio.CancelledError:
            self.logger.debug(f"Refresh loop cancelled for {service_name}")
        except Exception as e:
            self.logger.error(f"Refresh loop error for {service_name}: {e}")
    
    async def remove_token(self, service_name: str):
        """Remove token and stop refresh task."""
        async with self._lock:
            if service_name in self._tokens:
                del self._tokens[service_name]
            
            if service_name in self._refresh_callbacks:
                del self._refresh_callbacks[service_name]
            
            if service_name in self._refresh_tasks:
                self._refresh_tasks[service_name].cancel()
                del self._refresh_tasks[service_name]
            
            self.logger.info(f"Token removed for {service_name}")
    
    def get_token_info(self, service_name: str) -> Optional[TokenInfo]:
        """Get token information."""
        return self._tokens.get(service_name)
    
    def list_tokens(self) -> Dict[str, Dict[str, Any]]:
        """List all stored tokens with their status."""
        result = {}
        
        for service_name, token_info in self._tokens.items():
            result[service_name] = {
                "issued_at": token_info.issued_at.isoformat(),
                "expires_at": token_info.expires_at.isoformat(),
                "is_expired": token_info.is_expired,
                "needs_refresh": token_info.needs_refresh,
                "time_until_expiry": token_info.time_until_expiry,
                "has_refresh_callback": service_name in self._refresh_callbacks
            }
        
        return result
    
    async def cleanup(self):
        """Cleanup all tokens and tasks."""
        async with self._lock:
            # Cancel all refresh tasks
            for task in self._refresh_tasks.values():
                task.cancel()
            
            # Wait for tasks to complete
            if self._refresh_tasks:
                await asyncio.gather(*self._refresh_tasks.values(), return_exceptions=True)
            
            # Clear all data
            self._tokens.clear()
            self._refresh_callbacks.clear()
            self._refresh_tasks.clear()
            
            self.logger.info("Token manager cleanup completed")


# Global token manager instance
token_manager = TokenManager()