"""Advanced network validation and testing system."""

import asyncio
import socket
import ssl
import time
import subprocess
import platform
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
from enum import Enum
import httpx

from .logger import get_logger


class ValidationResult(Enum):
    """Validation result status."""
    PASS = "pass"
    FAIL = "fail"
    WARNING = "warning"
    SKIP = "skip"


@dataclass
class TestResult:
    """Individual test result."""
    name: str
    status: ValidationResult
    message: str
    details: Optional[Dict[str, Any]] = None
    duration: float = 0.0
    suggestions: Optional[List[str]] = None


@dataclass
class NetworkMetrics:
    """Network performance metrics."""
    latency_ms: float
    packet_loss: float
    bandwidth_mbps: Optional[float] = None
    jitter_ms: Optional[float] = None
    connection_time_ms: Optional[float] = None


class NetworkValidator:
    """Advanced network validation and testing."""
    
    def __init__(self):
        self.logger = get_logger("network_validator")
        self.timeout = 10
        self.ping_count = 4
    
    async def validate_connectivity(
        self, 
        host: str, 
        port: int, 
        protocol: str = "tcp"
    ) -> TestResult:
        """Test basic network connectivity."""
        start_time = time.time()
        
        try:
            if protocol.lower() == "tcp":
                result = await self._test_tcp_connection(host, port)
            elif protocol.lower() == "udp":
                result = await self._test_udp_connection(host, port)
            else:
                return TestResult(
                    name="connectivity",
                    status=ValidationResult.FAIL,
                    message=f"Unsupported protocol: {protocol}",
                    duration=time.time() - start_time
                )
            
            duration = time.time() - start_time
            
            if result["success"]:
                return TestResult(
                    name="connectivity",
                    status=ValidationResult.PASS,
                    message=f"Successfully connected to {host}:{port}",
                    details=result,
                    duration=duration
                )
            else:
                return TestResult(
                    name="connectivity",
                    status=ValidationResult.FAIL,
                    message=f"Failed to connect to {host}:{port}: {result.get('error', 'Unknown error')}",
                    details=result,
                    duration=duration,
                    suggestions=[
                        "Check if the host is reachable",
                        "Verify the port is open",
                        "Check firewall settings",
                        "Ensure the service is running"
                    ]
                )
                
        except Exception as e:
            return TestResult(
                name="connectivity",
                status=ValidationResult.FAIL,
                message=f"Connection test failed: {e}",
                duration=time.time() - start_time,
                suggestions=["Check network configuration", "Verify host and port"]
            )
    
    async def _test_tcp_connection(self, host: str, port: int) -> Dict[str, Any]:
        """Test TCP connection."""
        try:
            start_time = time.time()
            
            # Create connection
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(host, port),
                timeout=self.timeout
            )
            
            connection_time = (time.time() - start_time) * 1000
            
            # Close connection
            writer.close()
            await writer.wait_closed()
            
            return {
                "success": True,
                "connection_time_ms": connection_time,
                "protocol": "tcp"
            }
            
        except asyncio.TimeoutError:
            return {
                "success": False,
                "error": "Connection timeout",
                "protocol": "tcp"
            }
        except ConnectionRefusedError:
            return {
                "success": False,
                "error": "Connection refused",
                "protocol": "tcp"
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "protocol": "tcp"
            }
    
    async def _test_udp_connection(self, host: str, port: int) -> Dict[str, Any]:
        """Test UDP connection."""
        try:
            # UDP is connectionless, so we just try to create a socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(self.timeout)
            
            try:
                # Try to send a small packet
                sock.sendto(b"test", (host, port))
                return {
                    "success": True,
                    "protocol": "udp",
                    "note": "UDP test - no response expected"
                }
            finally:
                sock.close()
                
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "protocol": "udp"
            }
    
    async def test_ping(self, host: str) -> TestResult:
        """Test ping connectivity and measure latency."""
        start_time = time.time()
        
        try:
            # Determine ping command based on OS
            if platform.system().lower() == "windows":
                cmd = ["ping", "-n", str(self.ping_count), host]
            else:
                cmd = ["ping", "-c", str(self.ping_count), host]
            
            # Execute ping command
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=self.timeout + 5
            )
            
            duration = time.time() - start_time
            
            if process.returncode == 0:
                # Parse ping results
                metrics = self._parse_ping_output(stdout.decode())
                
                return TestResult(
                    name="ping",
                    status=ValidationResult.PASS,
                    message=f"Ping successful - Avg latency: {metrics.latency_ms:.1f}ms, Loss: {metrics.packet_loss:.1f}%",
                    details={
                        "latency_ms": metrics.latency_ms,
                        "packet_loss": metrics.packet_loss,
                        "jitter_ms": metrics.jitter_ms
                    },
                    duration=duration
                )
            else:
                error_msg = stderr.decode().strip() or "Ping failed"
                return TestResult(
                    name="ping",
                    status=ValidationResult.FAIL,
                    message=f"Ping failed: {error_msg}",
                    duration=duration,
                    suggestions=[
                        "Check if host is reachable",
                        "Verify network connectivity",
                        "Check DNS resolution"
                    ]
                )
                
        except asyncio.TimeoutError:
            return TestResult(
                name="ping",
                status=ValidationResult.FAIL,
                message="Ping test timed out",
                duration=time.time() - start_time,
                suggestions=["Check network connectivity", "Host may be unreachable"]
            )
        except Exception as e:
            return TestResult(
                name="ping",
                status=ValidationResult.FAIL,
                message=f"Ping test error: {e}",
                duration=time.time() - start_time
            )
    
    def _parse_ping_output(self, output: str) -> NetworkMetrics:
        """Parse ping command output to extract metrics."""
        lines = output.split('\n')
        latencies = []
        packet_loss = 0.0
        
        try:
            for line in lines:
                # Extract latency from ping responses
                if "time=" in line:
                    time_part = line.split("time=")[1].split()[0]
                    if "ms" in time_part:
                        latency = float(time_part.replace("ms", ""))
                        latencies.append(latency)
                
                # Extract packet loss
                if "packet loss" in line or "lost" in line:
                    import re
                    loss_match = re.search(r'(\d+(?:\.\d+)?)%', line)
                    if loss_match:
                        packet_loss = float(loss_match.group(1))
            
            if latencies:
                avg_latency = sum(latencies) / len(latencies)
                jitter = max(latencies) - min(latencies) if len(latencies) > 1 else 0.0
            else:
                avg_latency = 0.0
                jitter = 0.0
            
            return NetworkMetrics(
                latency_ms=avg_latency,
                packet_loss=packet_loss,
                jitter_ms=jitter
            )
            
        except Exception as e:
            self.logger.warning(f"Failed to parse ping output: {e}")
            return NetworkMetrics(latency_ms=0.0, packet_loss=100.0)
    
    async def test_ssl_certificate(self, host: str, port: int = 443) -> TestResult:
        """Test SSL certificate validity."""
        start_time = time.time()
        
        try:
            # Create SSL context
            context = ssl.create_default_context()
            
            # Connect and get certificate
            with socket.create_connection((host, port), timeout=self.timeout) as sock:
                with context.wrap_socket(sock, server_hostname=host) as ssock:
                    cert = ssock.getpeercert()
                    cipher = ssock.cipher()
            
            duration = time.time() - start_time
            
            # Analyze certificate
            cert_info = self._analyze_certificate(cert)
            
            if cert_info["valid"]:
                return TestResult(
                    name="ssl_certificate",
                    status=ValidationResult.PASS,
                    message=f"SSL certificate is valid (expires: {cert_info['expires']})",
                    details={
                        "certificate": cert_info,
                        "cipher": cipher,
                        "connection_time_ms": duration * 1000
                    },
                    duration=duration
                )
            else:
                return TestResult(
                    name="ssl_certificate",
                    status=ValidationResult.WARNING,
                    message=f"SSL certificate issues: {cert_info['issues']}",
                    details=cert_info,
                    duration=duration,
                    suggestions=[
                        "Check certificate expiration",
                        "Verify certificate chain",
                        "Update SSL certificate"
                    ]
                )
                
        except ssl.SSLError as e:
            return TestResult(
                name="ssl_certificate",
                status=ValidationResult.FAIL,
                message=f"SSL error: {e}",
                duration=time.time() - start_time,
                suggestions=[
                    "Check SSL configuration",
                    "Verify certificate installation",
                    "Check certificate chain"
                ]
            )
        except Exception as e:
            return TestResult(
                name="ssl_certificate",
                status=ValidationResult.FAIL,
                message=f"SSL test failed: {e}",
                duration=time.time() - start_time
            )
    
    def _analyze_certificate(self, cert: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze SSL certificate for validity and issues."""
        import datetime
        
        issues = []
        
        try:
            # Check expiration
            not_after = cert.get('notAfter')
            if not_after:
                expiry_date = datetime.datetime.strptime(not_after, '%b %d %H:%M:%S %Y %Z')
                days_until_expiry = (expiry_date - datetime.datetime.now()).days
                
                if days_until_expiry < 0:
                    issues.append("Certificate has expired")
                elif days_until_expiry < 30:
                    issues.append(f"Certificate expires in {days_until_expiry} days")
            
            # Check subject
            subject = dict(x[0] for x in cert.get('subject', []))
            issuer = dict(x[0] for x in cert.get('issuer', []))
            
            return {
                "valid": len(issues) == 0,
                "issues": issues,
                "subject": subject,
                "issuer": issuer,
                "expires": not_after,
                "serial_number": cert.get('serialNumber'),
                "version": cert.get('version')
            }
            
        except Exception as e:
            return {
                "valid": False,
                "issues": [f"Certificate analysis failed: {e}"],
                "raw_cert": cert
            }
    
    async def test_http_response(
        self, 
        url: str, 
        expected_status: int = 200,
        timeout: int = None
    ) -> TestResult:
        """Test HTTP response and measure performance."""
        start_time = time.time()
        timeout = timeout or self.timeout
        
        try:
            async with httpx.AsyncClient(timeout=timeout, verify=False) as client:
                response = await client.get(url)
                
                duration = time.time() - start_time
                
                # Analyze response
                analysis = {
                    "status_code": response.status_code,
                    "response_time_ms": duration * 1000,
                    "content_length": len(response.content),
                    "headers": dict(response.headers),
                    "encoding": response.encoding
                }
                
                if response.status_code == expected_status:
                    return TestResult(
                        name="http_response",
                        status=ValidationResult.PASS,
                        message=f"HTTP response OK ({response.status_code}) - {duration*1000:.1f}ms",
                        details=analysis,
                        duration=duration
                    )
                else:
                    return TestResult(
                        name="http_response",
                        status=ValidationResult.WARNING,
                        message=f"Unexpected status code: {response.status_code} (expected {expected_status})",
                        details=analysis,
                        duration=duration,
                        suggestions=[
                            "Check service configuration",
                            "Verify endpoint availability",
                            "Check authentication requirements"
                        ]
                    )
                    
        except httpx.TimeoutException:
            return TestResult(
                name="http_response",
                status=ValidationResult.FAIL,
                message="HTTP request timed out",
                duration=time.time() - start_time,
                suggestions=["Check service availability", "Increase timeout", "Check network connectivity"]
            )
        except Exception as e:
            return TestResult(
                name="http_response",
                status=ValidationResult.FAIL,
                message=f"HTTP test failed: {e}",
                duration=time.time() - start_time
            )
    
    async def test_bandwidth(self, host: str, port: int, duration: int = 5) -> TestResult:
        """Test network bandwidth (simplified test)."""
        start_time = time.time()
        
        try:
            # Simple bandwidth test by downloading data
            test_data = b"0" * 1024  # 1KB test packet
            total_bytes = 0
            test_start = time.time()
            
            while time.time() - test_start < duration:
                try:
                    reader, writer = await asyncio.wait_for(
                        asyncio.open_connection(host, port),
                        timeout=2
                    )
                    
                    writer.write(test_data)
                    await writer.drain()
                    
                    data = await reader.read(1024)
                    total_bytes += len(data)
                    
                    writer.close()
                    await writer.wait_closed()
                    
                except Exception:
                    break
                
                await asyncio.sleep(0.1)
            
            test_duration = time.time() - test_start
            bandwidth_mbps = (total_bytes * 8) / (test_duration * 1024 * 1024)
            
            return TestResult(
                name="bandwidth",
                status=ValidationResult.PASS,
                message=f"Estimated bandwidth: {bandwidth_mbps:.2f} Mbps",
                details={
                    "bandwidth_mbps": bandwidth_mbps,
                    "total_bytes": total_bytes,
                    "test_duration": test_duration
                },
                duration=time.time() - start_time
            )
            
        except Exception as e:
            return TestResult(
                name="bandwidth",
                status=ValidationResult.SKIP,
                message=f"Bandwidth test skipped: {e}",
                duration=time.time() - start_time
            )
    
    async def comprehensive_network_test(
        self, 
        host: str, 
        ports: List[int],
        include_ssl: bool = True,
        include_http: bool = True
    ) -> Dict[str, TestResult]:
        """Run comprehensive network tests."""
        results = {}
        
        # Basic connectivity tests
        self.logger.info(f"Starting comprehensive network test for {host}")
        
        # Ping test
        results["ping"] = await self.test_ping(host)
        
        # Port connectivity tests
        for port in ports:
            test_name = f"port_{port}"
            results[test_name] = await self.validate_connectivity(host, port)
        
        # SSL test (if requested and port 443 is in the list)
        if include_ssl and 443 in ports:
            results["ssl"] = await self.test_ssl_certificate(host, 443)
        
        # HTTP test (if requested)
        if include_http:
            if 80 in ports:
                results["http"] = await self.test_http_response(f"http://{host}")
            if 443 in ports:
                results["https"] = await self.test_http_response(f"https://{host}")
        
        # Bandwidth test (using first available port)
        if ports:
            results["bandwidth"] = await self.test_bandwidth(host, ports[0])
        
        return results