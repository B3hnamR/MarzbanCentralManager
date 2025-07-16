"""Auto-discovery service for finding nodes in the network."""

import asyncio
import socket
import ipaddress
import subprocess
from typing import List, Dict, Optional, Any, Callable, Tuple
from dataclasses import dataclass
from datetime import datetime
from enum import Enum

from ..core.logger import get_logger
from ..core.network_validator import NetworkValidator
from ..core.utils import is_valid_ip, is_port_open


class DiscoveryMethod(Enum):
    """Discovery methods."""
    PING_SWEEP = "ping_sweep"
    PORT_SCAN = "port_scan"
    ARP_SCAN = "arp_scan"
    NMAP_SCAN = "nmap_scan"
    MANUAL_RANGE = "manual_range"


@dataclass
class DiscoveredNode:
    """Discovered node information."""
    ip_address: str
    hostname: Optional[str] = None
    open_ports: List[int] = None
    response_time: Optional[float] = None
    mac_address: Optional[str] = None
    os_info: Optional[str] = None
    marzban_node_detected: bool = False
    marzban_version: Optional[str] = None
    discovery_method: Optional[DiscoveryMethod] = None
    discovered_at: Optional[datetime] = None
    confidence_score: float = 0.0
    
    def __post_init__(self):
        if self.open_ports is None:
            self.open_ports = []
        if self.discovered_at is None:
            self.discovered_at = datetime.now()
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "ip_address": self.ip_address,
            "hostname": self.hostname,
            "open_ports": self.open_ports,
            "response_time": self.response_time,
            "mac_address": self.mac_address,
            "os_info": self.os_info,
            "marzban_node_detected": self.marzban_node_detected,
            "marzban_version": self.marzban_version,
            "discovery_method": self.discovery_method.value if self.discovery_method else None,
            "discovered_at": self.discovered_at.isoformat() if self.discovered_at else None,
            "confidence_score": self.confidence_score
        }


@dataclass
class DiscoveryConfig:
    """Discovery configuration."""
    methods: List[DiscoveryMethod] = None
    target_ports: List[int] = None
    timeout: int = 5
    max_concurrent: int = 50
    include_localhost: bool = False
    deep_scan: bool = False
    
    def __post_init__(self):
        if self.methods is None:
            self.methods = [DiscoveryMethod.PING_SWEEP, DiscoveryMethod.PORT_SCAN]
        if self.target_ports is None:
            self.target_ports = [62050, 62051, 22, 80, 443, 8080, 8443]


class DiscoveryService:
    """Auto-discovery service for finding nodes in the network."""
    
    def __init__(self):
        self.logger = get_logger("discovery_service")
        self.network_validator = NetworkValidator()
        self.is_scanning = False
        self.discovered_nodes: Dict[str, DiscoveredNode] = {}
        
        # Common Marzban node ports
        self.marzban_ports = [62050, 62051, 8000, 8080, 8443]
        
        # Known Marzban node indicators
        self.marzban_indicators = [
            "marzban",
            "xray",
            "v2ray",
            "trojan",
            "shadowsocks"
        ]
    
    async def discover_network_range(
        self,
        network_range: str,
        config: Optional[DiscoveryConfig] = None,
        progress_callback: Optional[Callable] = None
    ) -> List[DiscoveredNode]:
        """Discover nodes in a network range."""
        config = config or DiscoveryConfig()
        
        try:
            # Parse network range
            network = ipaddress.ip_network(network_range, strict=False)
            hosts = list(network.hosts())
            
            if not config.include_localhost:
                # Filter out localhost addresses
                hosts = [host for host in hosts if not host.is_loopback]
            
            self.logger.info(f"Starting discovery scan for {len(hosts)} hosts in {network_range}")
            
            self.is_scanning = True
            discovered = []
            
            # Process hosts in batches to control concurrency
            batch_size = config.max_concurrent
            
            for i in range(0, len(hosts), batch_size):
                if not self.is_scanning:
                    break
                
                batch = hosts[i:i + batch_size]
                
                if progress_callback:
                    await progress_callback(i, len(hosts), f"Scanning batch {i//batch_size + 1}")
                
                # Scan batch concurrently
                tasks = [self._scan_host(str(host), config) for host in batch]
                batch_results = await asyncio.gather(*tasks, return_exceptions=True)
                
                # Process results
                for result in batch_results:
                    if isinstance(result, DiscoveredNode) and result.ip_address:
                        discovered.append(result)
                        self.discovered_nodes[result.ip_address] = result
            
            self.is_scanning = False
            
            if progress_callback:
                await progress_callback(len(hosts), len(hosts), f"Discovery completed: {len(discovered)} nodes found")
            
            self.logger.info(f"Discovery completed: {len(discovered)} nodes found")
            return discovered
            
        except Exception as e:
            self.is_scanning = False
            self.logger.error(f"Discovery failed: {e}")
            raise
    
    async def _scan_host(self, ip_address: str, config: DiscoveryConfig) -> Optional[DiscoveredNode]:
        """Scan a single host."""
        try:
            node = DiscoveredNode(ip_address=ip_address)
            
            # Ping test
            if DiscoveryMethod.PING_SWEEP in config.methods:
                ping_result = await self._ping_host(ip_address, config.timeout)
                if not ping_result["alive"]:
                    return None  # Host is not reachable
                
                node.response_time = ping_result.get("response_time")
                node.discovery_method = DiscoveryMethod.PING_SWEEP
            
            # Port scan
            if DiscoveryMethod.PORT_SCAN in config.methods:
                open_ports = await self._scan_ports(ip_address, config.target_ports, config.timeout)
                node.open_ports = open_ports
                
                if open_ports:
                    node.discovery_method = DiscoveryMethod.PORT_SCAN
            
            # Hostname resolution
            try:
                hostname = socket.gethostbyaddr(ip_address)[0]
                node.hostname = hostname
            except:
                pass
            
            # Deep scan if enabled
            if config.deep_scan:
                await self._deep_scan_host(node, config)
            
            # Check for Marzban node indicators
            await self._detect_marzban_node(node)
            
            # Calculate confidence score
            node.confidence_score = self._calculate_confidence_score(node)
            
            return node
            
        except Exception as e:
            self.logger.debug(f"Failed to scan host {ip_address}: {e}")
            return None
    
    async def _ping_host(self, ip_address: str, timeout: int) -> Dict[str, Any]:
        """Ping a host to check if it's alive."""
        try:
            ping_result = await self.network_validator.test_ping(ip_address)
            
            if ping_result.status.value == "pass":
                return {
                    "alive": True,
                    "response_time": ping_result.details.get("latency_ms") if ping_result.details else None
                }
            else:
                return {"alive": False}
                
        except Exception as e:
            self.logger.debug(f"Ping failed for {ip_address}: {e}")
            return {"alive": False}
    
    async def _scan_ports(self, ip_address: str, ports: List[int], timeout: int) -> List[int]:
        """Scan ports on a host."""
        open_ports = []
        
        try:
            # Create tasks for concurrent port scanning
            tasks = [self._check_port(ip_address, port, timeout) for port in ports]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            for port, result in zip(ports, results):
                if result is True:
                    open_ports.append(port)
            
        except Exception as e:
            self.logger.debug(f"Port scan failed for {ip_address}: {e}")
        
        return open_ports
    
    async def _check_port(self, ip_address: str, port: int, timeout: int) -> bool:
        """Check if a specific port is open."""
        try:
            future = asyncio.open_connection(ip_address, port)
            reader, writer = await asyncio.wait_for(future, timeout=timeout)
            writer.close()
            await writer.wait_closed()
            return True
        except:
            return False
    
    async def _deep_scan_host(self, node: DiscoveredNode, config: DiscoveryConfig):
        """Perform deep scan on a host."""
        try:
            # Try to get more information about open ports
            for port in node.open_ports:
                try:
                    # Try to connect and get banner
                    banner = await self._get_service_banner(node.ip_address, port, config.timeout)
                    if banner:
                        # Analyze banner for service information
                        if any(indicator in banner.lower() for indicator in self.marzban_indicators):
                            node.marzban_node_detected = True
                            
                            # Try to extract version
                            version = self._extract_version_from_banner(banner)
                            if version:
                                node.marzban_version = version
                
                except Exception as e:
                    self.logger.debug(f"Banner grab failed for {node.ip_address}:{port}: {e}")
            
            # Try HTTP requests on web ports
            web_ports = [port for port in node.open_ports if port in [80, 443, 8000, 8080, 8443]]
            for port in web_ports:
                try:
                    url = f"{'https' if port in [443, 8443] else 'http'}://{node.ip_address}:{port}"
                    http_result = await self.network_validator.test_http_response(url, timeout=config.timeout)
                    
                    if http_result.status.value == "pass" and http_result.details:
                        headers = http_result.details.get("headers", {})
                        
                        # Check for Marzban-specific headers or content
                        server_header = headers.get("server", "").lower()
                        if any(indicator in server_header for indicator in self.marzban_indicators):
                            node.marzban_node_detected = True
                
                except Exception as e:
                    self.logger.debug(f"HTTP check failed for {node.ip_address}:{port}: {e}")
        
        except Exception as e:
            self.logger.debug(f"Deep scan failed for {node.ip_address}: {e}")
    
    async def _get_service_banner(self, ip_address: str, port: int, timeout: int) -> Optional[str]:
        """Get service banner from a port."""
        try:
            future = asyncio.open_connection(ip_address, port)
            reader, writer = await asyncio.wait_for(future, timeout=timeout)
            
            # Try to read banner
            banner_data = await asyncio.wait_for(reader.read(1024), timeout=2)
            banner = banner_data.decode('utf-8', errors='ignore').strip()
            
            writer.close()
            await writer.wait_closed()
            
            return banner if banner else None
            
        except Exception:
            return None
    
    def _extract_version_from_banner(self, banner: str) -> Optional[str]:
        """Extract version information from service banner."""
        import re
        
        # Common version patterns
        version_patterns = [
            r'marzban[/\s]+v?(\d+\.\d+\.\d+)',
            r'xray[/\s]+v?(\d+\.\d+\.\d+)',
            r'v2ray[/\s]+v?(\d+\.\d+\.\d+)',
            r'version[/\s]+v?(\d+\.\d+\.\d+)',
        ]
        
        for pattern in version_patterns:
            match = re.search(pattern, banner.lower())
            if match:
                return match.group(1)
        
        return None
    
    async def _detect_marzban_node(self, node: DiscoveredNode):
        """Detect if a node is running Marzban."""
        # Check for common Marzban ports
        marzban_ports_found = [port for port in node.open_ports if port in self.marzban_ports]
        
        if marzban_ports_found:
            node.marzban_node_detected = True
            
            # Try to get more specific information
            for port in marzban_ports_found:
                try:
                    # Test connectivity to Marzban API port
                    if port in [62051, 8000]:
                        connectivity = await self.network_validator.validate_connectivity(node.ip_address, port)
                        if connectivity.status.value == "pass":
                            node.marzban_node_detected = True
                            break
                
                except Exception:
                    continue
    
    def _calculate_confidence_score(self, node: DiscoveredNode) -> float:
        """Calculate confidence score for discovered node."""
        score = 0.0
        
        # Base score for being reachable
        if node.response_time is not None:
            score += 20.0
        
        # Score for open ports
        if node.open_ports:
            score += min(30.0, len(node.open_ports) * 5.0)
        
        # Score for Marzban-specific ports
        marzban_ports_found = [port for port in node.open_ports if port in self.marzban_ports]
        if marzban_ports_found:
            score += 30.0
        
        # Score for Marzban detection
        if node.marzban_node_detected:
            score += 40.0
        
        # Score for version detection
        if node.marzban_version:
            score += 10.0
        
        # Score for hostname
        if node.hostname:
            score += 5.0
        
        # Bonus for good response time
        if node.response_time and node.response_time < 50:
            score += 5.0
        
        return min(100.0, score)
    
    async def discover_local_network(
        self,
        config: Optional[DiscoveryConfig] = None,
        progress_callback: Optional[Callable] = None
    ) -> List[DiscoveredNode]:
        """Discover nodes in the local network."""
        try:
            # Get local network ranges
            local_networks = await self._get_local_networks()
            
            all_discovered = []
            
            for network in local_networks:
                self.logger.info(f"Scanning local network: {network}")
                
                discovered = await self.discover_network_range(
                    network,
                    config,
                    progress_callback
                )
                
                all_discovered.extend(discovered)
            
            return all_discovered
            
        except Exception as e:
            self.logger.error(f"Local network discovery failed: {e}")
            raise
    
    async def _get_local_networks(self) -> List[str]:
        """Get local network ranges."""
        networks = []
        
        try:
            import netifaces
            
            # Get all network interfaces
            for interface in netifaces.interfaces():
                try:
                    addresses = netifaces.ifaddresses(interface)
                    
                    # Get IPv4 addresses
                    if netifaces.AF_INET in addresses:
                        for addr_info in addresses[netifaces.AF_INET]:
                            ip = addr_info.get('addr')
                            netmask = addr_info.get('netmask')
                            
                            if ip and netmask and not ip.startswith('127.'):
                                # Calculate network
                                network = ipaddress.IPv4Network(f"{ip}/{netmask}", strict=False)
                                networks.append(str(network))
                
                except Exception as e:
                    self.logger.debug(f"Failed to process interface {interface}: {e}")
        
        except ImportError:
            # Fallback method without netifaces
            self.logger.warning("netifaces not available, using fallback method")
            
            # Common private network ranges
            common_networks = [
                "192.168.1.0/24",
                "192.168.0.0/24",
                "10.0.0.0/24",
                "172.16.0.0/24"
            ]
            
            # Try to detect which one is in use
            for network in common_networks:
                try:
                    # Test if gateway is reachable
                    gateway_ip = str(list(ipaddress.ip_network(network).hosts())[0])
                    ping_result = await self._ping_host(gateway_ip, 2)
                    
                    if ping_result["alive"]:
                        networks.append(network)
                        break
                
                except Exception:
                    continue
        
        return networks
    
    async def discover_ip_range(
        self,
        start_ip: str,
        end_ip: str,
        config: Optional[DiscoveryConfig] = None,
        progress_callback: Optional[Callable] = None
    ) -> List[DiscoveredNode]:
        """Discover nodes in an IP range."""
        try:
            start_addr = ipaddress.ip_address(start_ip)
            end_addr = ipaddress.ip_address(end_ip)
            
            if start_addr > end_addr:
                raise ValueError("Start IP must be less than or equal to end IP")
            
            # Generate IP list
            current = start_addr
            ips = []
            
            while current <= end_addr:
                ips.append(str(current))
                current += 1
            
            self.logger.info(f"Scanning IP range: {start_ip} - {end_ip} ({len(ips)} addresses)")
            
            config = config or DiscoveryConfig()
            discovered = []
            
            # Process IPs in batches
            batch_size = config.max_concurrent
            
            for i in range(0, len(ips), batch_size):
                if not self.is_scanning:
                    break
                
                batch = ips[i:i + batch_size]
                
                if progress_callback:
                    await progress_callback(i, len(ips), f"Scanning batch {i//batch_size + 1}")
                
                # Scan batch concurrently
                tasks = [self._scan_host(ip, config) for ip in batch]
                batch_results = await asyncio.gather(*tasks, return_exceptions=True)
                
                # Process results
                for result in batch_results:
                    if isinstance(result, DiscoveredNode) and result.ip_address:
                        discovered.append(result)
                        self.discovered_nodes[result.ip_address] = result
            
            if progress_callback:
                await progress_callback(len(ips), len(ips), f"Range scan completed: {len(discovered)} nodes found")
            
            self.logger.info(f"IP range scan completed: {len(discovered)} nodes found")
            return discovered
            
        except Exception as e:
            self.logger.error(f"IP range discovery failed: {e}")
            raise
    
    def stop_discovery(self):
        """Stop ongoing discovery."""
        self.is_scanning = False
        self.logger.info("Discovery scan stopped")
    
    def get_discovered_nodes(self) -> List[DiscoveredNode]:
        """Get all discovered nodes."""
        return list(self.discovered_nodes.values())
    
    def get_marzban_candidates(self) -> List[DiscoveredNode]:
        """Get nodes that are likely Marzban nodes."""
        return [node for node in self.discovered_nodes.values() if node.marzban_node_detected or node.confidence_score >= 70]
    
    def clear_discovered_nodes(self):
        """Clear discovered nodes cache."""
        self.discovered_nodes.clear()
        self.logger.info("Discovered nodes cache cleared")
    
    async def validate_discovered_node(self, node: DiscoveredNode) -> Dict[str, Any]:
        """Validate a discovered node for Marzban compatibility."""
        validation_result = {
            "valid": False,
            "issues": [],
            "recommendations": [],
            "confidence": node.confidence_score
        }
        
        try:
            # Check if required ports are open
            required_ports = [62050, 62051]  # Marzban node ports
            missing_ports = [port for port in required_ports if port not in node.open_ports]
            
            if missing_ports:
                validation_result["issues"].append(f"Missing required ports: {missing_ports}")
                validation_result["recommendations"].append("Ensure Marzban node is running and ports are open")
            
            # Check connectivity
            if 62050 in node.open_ports:
                connectivity = await self.network_validator.validate_connectivity(node.ip_address, 62050)
                if connectivity.status.value != "pass":
                    validation_result["issues"].append("Cannot connect to Marzban node port")
                    validation_result["recommendations"].append("Check firewall and node configuration")
            
            # Check response time
            if node.response_time and node.response_time > 1000:  # > 1 second
                validation_result["issues"].append(f"High response time: {node.response_time:.1f}ms")
                validation_result["recommendations"].append("Check network connectivity and node performance")
            
            # Determine if valid
            validation_result["valid"] = len(validation_result["issues"]) == 0 and node.confidence_score >= 50
            
        except Exception as e:
            validation_result["issues"].append(f"Validation error: {e}")
        
        return validation_result


# Global discovery service instance
discovery_service = DiscoveryService()