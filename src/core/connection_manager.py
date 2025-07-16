"""Advanced connection management with pooling and retry logic."""

import asyncio
import time
import random
from typing import Optional, Dict, Any, List
from dataclasses import dataclass
from enum import Enum
import httpx

from .logger import get_logger
from .token_manager import token_manager


class CircuitState(Enum):
    """Circuit breaker states."""
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


@dataclass
class RetryConfig:
    """Retry configuration."""
    max_attempts: int = 3
    base_delay: float = 1.0
    max_delay: float = 60.0
    exponential_base: float = 2.0
    jitter: bool = True


@dataclass
class CircuitBreakerConfig:
    """Circuit breaker configuration."""
    failure_threshold: int = 5
    recovery_timeout: int = 60
    success_threshold: int = 3


@dataclass
class ConnectionStats:
    """Connection statistics."""
    total_requests: int = 0
    successful_requests: int = 0
    failed_requests: int = 0
    total_response_time: float = 0.0
    last_request_time: Optional[float] = None
    
    @property
    def success_rate(self) -> float:
        """Calculate success rate."""
        if self.total_requests == 0:
            return 0.0
        return self.successful_requests / self.total_requests
    
    @property
    def average_response_time(self) -> float:
        """Calculate average response time."""
        if self.successful_requests == 0:
            return 0.0
        return self.total_response_time / self.successful_requests


class CircuitBreaker:
    """Circuit breaker implementation."""
    
    def __init__(self, config: CircuitBreakerConfig):
        self.config = config
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.success_count = 0
        self.last_failure_time = 0
        self.logger = get_logger("circuit_breaker")
    
    async def call(self, func, *args, **kwargs):
        """Execute function with circuit breaker protection."""
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time > self.config.recovery_timeout:
                self.state = CircuitState.HALF_OPEN
                self.success_count = 0
                self.logger.info("Circuit breaker moved to HALF_OPEN state")
            else:
                raise Exception("Circuit breaker is OPEN")
        
        try:
            result = await func(*args, **kwargs)
            await self._on_success()
            return result
        except Exception as e:
            await self._on_failure()
            raise
    
    async def _on_success(self):
        """Handle successful request."""
        if self.state == CircuitState.HALF_OPEN:
            self.success_count += 1
            if self.success_count >= self.config.success_threshold:
                self.state = CircuitState.CLOSED
                self.failure_count = 0
                self.logger.info("Circuit breaker moved to CLOSED state")
        else:
            self.failure_count = 0
    
    async def _on_failure(self):
        """Handle failed request."""
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.state == CircuitState.HALF_OPEN:
            self.state = CircuitState.OPEN
            self.logger.warning("Circuit breaker moved to OPEN state from HALF_OPEN")
        elif self.failure_count >= self.config.failure_threshold:
            self.state = CircuitState.OPEN
            self.logger.warning(f"Circuit breaker OPENED after {self.failure_count} failures")


class ConnectionPool:
    """HTTP connection pool with advanced features."""
    
    def __init__(
        self,
        base_url: str,
        max_connections: int = 10,
        max_keepalive_connections: int = 5,
        keepalive_expiry: int = 30,
        timeout: int = 30,
        verify_ssl: bool = True
    ):
        self.base_url = base_url.rstrip('/')
        self.logger = get_logger("connection_pool")
        
        # Connection limits
        limits = httpx.Limits(
            max_connections=max_connections,
            max_keepalive_connections=max_keepalive_connections,
            keepalive_expiry=keepalive_expiry
        )
        
        # Timeout configuration
        timeout_config = httpx.Timeout(
            connect=timeout,
            read=timeout,
            write=timeout,
            pool=timeout
        )
        
        # Create client
        self._client = httpx.AsyncClient(
            base_url=self.base_url,
            limits=limits,
            timeout=timeout_config,
            verify=verify_ssl,
            follow_redirects=True
        )
        
        # Statistics and monitoring
        self.stats = ConnectionStats()
        self._lock = asyncio.Lock()
    
    async def request(
        self,
        method: str,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None
    ) -> httpx.Response:
        """Make HTTP request with connection pooling."""
        start_time = time.time()
        
        try:
            async with self._lock:
                self.stats.total_requests += 1
                self.stats.last_request_time = start_time
            
            response = await self._client.request(
                method=method,
                url=url,
                headers=headers,
                json=data,
                params=params
            )
            
            # Update success statistics
            response_time = time.time() - start_time
            async with self._lock:
                self.stats.successful_requests += 1
                self.stats.total_response_time += response_time
            
            self.logger.debug(f"{method} {url} - {response.status_code} ({response_time:.3f}s)")
            return response
            
        except Exception as e:
            # Update failure statistics
            async with self._lock:
                self.stats.failed_requests += 1
            
            self.logger.error(f"{method} {url} failed: {e}")
            raise
    
    async def close(self):
        """Close connection pool."""
        await self._client.aclose()
        self.logger.debug("Connection pool closed")
    
    def get_stats(self) -> Dict[str, Any]:
        """Get connection statistics."""
        return {
            "total_requests": self.stats.total_requests,
            "successful_requests": self.stats.successful_requests,
            "failed_requests": self.stats.failed_requests,
            "success_rate": self.stats.success_rate,
            "average_response_time": self.stats.average_response_time,
            "last_request_time": self.stats.last_request_time
        }


class RetryManager:
    """Advanced retry manager with exponential backoff."""
    
    def __init__(self, config: RetryConfig):
        self.config = config
        self.logger = get_logger("retry_manager")
    
    async def execute_with_retry(self, func, *args, **kwargs):
        """Execute function with retry logic."""
        last_exception = None
        
        for attempt in range(self.config.max_attempts):
            try:
                result = await func(*args, **kwargs)
                if attempt > 0:
                    self.logger.info(f"Operation succeeded on attempt {attempt + 1}")
                return result
                
            except Exception as e:
                last_exception = e
                
                if attempt < self.config.max_attempts - 1:
                    delay = self._calculate_delay(attempt)
                    self.logger.warning(
                        f"Attempt {attempt + 1} failed: {e}. Retrying in {delay:.2f}s"
                    )
                    await asyncio.sleep(delay)
                else:
                    self.logger.error(f"All {self.config.max_attempts} attempts failed")
        
        raise last_exception
    
    def _calculate_delay(self, attempt: int) -> float:
        """Calculate delay for next retry."""
        delay = self.config.base_delay * (self.config.exponential_base ** attempt)
        delay = min(delay, self.config.max_delay)
        
        if self.config.jitter:
            # Add random jitter (±25%)
            jitter = delay * 0.25 * (2 * random.random() - 1)
            delay += jitter
        
        return max(0, delay)


class ConnectionManager:
    """Advanced connection manager with pooling, retry, and circuit breaker."""
    
    def __init__(self):
        self.logger = get_logger("connection_manager")
        self._pools: Dict[str, ConnectionPool] = {}
        self._circuit_breakers: Dict[str, CircuitBreaker] = {}
        self._retry_managers: Dict[str, RetryManager] = {}
        self._lock = asyncio.Lock()
    
    async def create_pool(
        self,
        service_name: str,
        base_url: str,
        max_connections: int = 10,
        timeout: int = 30,
        verify_ssl: bool = True,
        retry_config: Optional[RetryConfig] = None,
        circuit_config: Optional[CircuitBreakerConfig] = None
    ) -> bool:
        """Create connection pool for service."""
        try:
            async with self._lock:
                # Create connection pool
                pool = ConnectionPool(
                    base_url=base_url,
                    max_connections=max_connections,
                    timeout=timeout,
                    verify_ssl=verify_ssl
                )
                
                self._pools[service_name] = pool
                
                # Create retry manager
                retry_config = retry_config or RetryConfig()
                self._retry_managers[service_name] = RetryManager(retry_config)
                
                # Create circuit breaker
                circuit_config = circuit_config or CircuitBreakerConfig()
                self._circuit_breakers[service_name] = CircuitBreaker(circuit_config)
                
                self.logger.info(f"Connection pool created for {service_name}")
                return True
                
        except Exception as e:
            self.logger.error(f"Failed to create pool for {service_name}: {e}")
            return False
    
    async def request(
        self,
        service_name: str,
        method: str,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        data: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, Any]] = None,
        use_retry: bool = True,
        use_circuit_breaker: bool = True
    ) -> httpx.Response:
        """Make HTTP request with all advanced features."""
        if service_name not in self._pools:
            raise ValueError(f"No connection pool found for {service_name}")
        
        pool = self._pools[service_name]
        retry_manager = self._retry_managers[service_name]
        circuit_breaker = self._circuit_breakers[service_name]
        
        async def _make_request():
            return await pool.request(method, url, headers, data, params)
        
        # Apply circuit breaker if enabled
        if use_circuit_breaker:
            async def _circuit_protected_request():
                return await circuit_breaker.call(_make_request)
            request_func = _circuit_protected_request
        else:
            request_func = _make_request
        
        # Apply retry if enabled
        if use_retry:
            return await retry_manager.execute_with_retry(request_func)
        else:
            return await request_func()
    
    async def get_pool_stats(self, service_name: str) -> Optional[Dict[str, Any]]:
        """Get statistics for connection pool."""
        if service_name not in self._pools:
            return None
        
        pool = self._pools[service_name]
        circuit_breaker = self._circuit_breakers[service_name]
        
        stats = pool.get_stats()
        stats.update({
            "circuit_breaker_state": circuit_breaker.state.value,
            "circuit_breaker_failures": circuit_breaker.failure_count
        })
        
        return stats
    
    async def close_pool(self, service_name: str):
        """Close connection pool for service."""
        async with self._lock:
            if service_name in self._pools:
                await self._pools[service_name].close()
                del self._pools[service_name]
                del self._retry_managers[service_name]
                del self._circuit_breakers[service_name]
                
                self.logger.info(f"Connection pool closed for {service_name}")
    
    async def close_all_pools(self):
        """Close all connection pools."""
        async with self._lock:
            for service_name in list(self._pools.keys()):
                await self._pools[service_name].close()
            
            self._pools.clear()
            self._retry_managers.clear()
            self._circuit_breakers.clear()
            
            self.logger.info("All connection pools closed")
    
    def list_pools(self) -> List[str]:
        """List all active connection pools."""
        return list(self._pools.keys())


# Global connection manager instance
connection_manager = ConnectionManager()