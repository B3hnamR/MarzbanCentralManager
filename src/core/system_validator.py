"""Advanced system requirements validation and checking."""

import asyncio
import json
import re
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass
from enum import Enum

from .logger import get_logger
from .network_validator import TestResult, ValidationResult


@dataclass
class SystemRequirements:
    """System requirements specification."""
    min_cpu_cores: int = 1
    min_ram_gb: float = 1.0
    min_disk_gb: float = 10.0
    required_ports: List[int] = None
    required_services: List[str] = None
    supported_os: List[str] = None
    
    def __post_init__(self):
        if self.required_ports is None:
            self.required_ports = [62050, 62051]
        if self.required_services is None:
            self.required_services = ["docker"]
        if self.supported_os is None:
            self.supported_os = ["linux", "ubuntu", "debian", "centos", "rhel"]


@dataclass
class SystemInfo:
    """System information container."""
    os_name: str
    os_version: str
    cpu_cores: int
    ram_gb: float
    disk_gb: float
    architecture: str
    kernel_version: str
    uptime: str
    load_average: Optional[List[float]] = None


class SystemValidator:
    """Advanced system validation and requirements checking."""
    
    def __init__(self, ssh_client=None):
        self.logger = get_logger("system_validator")
        self.ssh_client = ssh_client
        self.requirements = SystemRequirements()
    
    async def validate_system_requirements(
        self, 
        host: str, 
        ssh_user: str, 
        ssh_port: int, 
        ssh_password: str,
        requirements: Optional[SystemRequirements] = None
    ) -> Dict[str, TestResult]:
        """Validate all system requirements."""
        if requirements:
            self.requirements = requirements
        
        results = {}
        
        try:
            # Get system information
            system_info = await self._get_system_info(host, ssh_user, ssh_port, ssh_password)
            
            if not system_info:
                return {
                    "system_info": TestResult(
                        name="system_info",
                        status=ValidationResult.FAIL,
                        message="Failed to retrieve system information",
                        suggestions=["Check SSH connectivity", "Verify credentials"]
                    )
                }
            
            # Run individual validation tests
            results["os_compatibility"] = self._validate_os_compatibility(system_info)
            results["cpu_requirements"] = self._validate_cpu_requirements(system_info)
            results["memory_requirements"] = self._validate_memory_requirements(system_info)
            results["disk_requirements"] = self._validate_disk_requirements(system_info)
            results["docker_status"] = await self._validate_docker_status(host, ssh_user, ssh_port, ssh_password)
            results["port_availability"] = await self._validate_port_availability(host, ssh_user, ssh_port, ssh_password)
            results["marzban_node_status"] = await self._check_marzban_node_installation(host, ssh_user, ssh_port, ssh_password)
            results["system_load"] = self._validate_system_load(system_info)
            
            # Add system info to results
            results["system_info"] = TestResult(
                name="system_info",
                status=ValidationResult.PASS,
                message="System information retrieved successfully",
                details=system_info.__dict__
            )
            
        except Exception as e:
            self.logger.error(f"System validation failed: {e}")
            results["validation_error"] = TestResult(
                name="validation_error",
                status=ValidationResult.FAIL,
                message=f"System validation error: {e}"
            )
        
        return results
    
    async def _get_system_info(
        self, 
        host: str, 
        ssh_user: str, 
        ssh_port: int, 
        ssh_password: str
    ) -> Optional[SystemInfo]:
        """Retrieve comprehensive system information via SSH."""
        try:
            commands = {
                "os_info": "cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -a",
                "cpu_info": "nproc && cat /proc/cpuinfo | grep 'model name' | head -1",
                "memory_info": "free -m | grep '^Mem:' | awk '{print $2}'",
                "disk_info": "df -h / | tail -1 | awk '{print $4}' | sed 's/G//'",
                "architecture": "uname -m",
                "kernel": "uname -r",
                "uptime": "uptime",
                "load_avg": "cat /proc/loadavg"
            }
            
            results = {}
            for cmd_name, command in commands.items():
                result = await self._execute_ssh_command(host, ssh_user, ssh_port, ssh_password, command)
                results[cmd_name] = result
            
            # Parse results
            return self._parse_system_info(results)
            
        except Exception as e:
            self.logger.error(f"Failed to get system info: {e}")
            return None
    
    async def _execute_ssh_command(
        self, 
        host: str, 
        ssh_user: str, 
        ssh_port: int, 
        ssh_password: str, 
        command: str
    ) -> str:
        """Execute SSH command and return output."""
        try:
            # Create SSH command
            ssh_cmd = [
                "sshpass", "-p", ssh_password,
                "ssh", "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=10",
                "-p", str(ssh_port),
                f"{ssh_user}@{host}",
                command
            ]
            
            # Execute command
            process = await asyncio.create_subprocess_exec(
                *ssh_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
            
            if process.returncode == 0:
                return stdout.decode().strip()
            else:
                self.logger.warning(f"SSH command failed: {stderr.decode()}")
                return ""
                
        except Exception as e:
            self.logger.error(f"SSH command execution failed: {e}")
            return ""
    
    def _parse_system_info(self, raw_data: Dict[str, str]) -> SystemInfo:
        """Parse raw system information into structured data."""
        try:
            # Parse OS information
            os_info = raw_data.get("os_info", "")
            os_name = "unknown"
            os_version = "unknown"
            
            if "ubuntu" in os_info.lower():
                os_name = "ubuntu"
                version_match = re.search(r'VERSION="([^"]+)"', os_info)
                if version_match:
                    os_version = version_match.group(1)
            elif "debian" in os_info.lower():
                os_name = "debian"
                version_match = re.search(r'VERSION="([^"]+)"', os_info)
                if version_match:
                    os_version = version_match.group(1)
            elif "centos" in os_info.lower():
                os_name = "centos"
                version_match = re.search(r'VERSION="([^"]+)"', os_info)
                if version_match:
                    os_version = version_match.group(1)
            
            # Parse CPU information
            cpu_cores = 1
            try:
                cpu_cores = int(raw_data.get("cpu_info", "1").split('\n')[0])
            except:
                pass
            
            # Parse memory information
            ram_gb = 1.0
            try:
                ram_mb = int(raw_data.get("memory_info", "1024"))
                ram_gb = ram_mb / 1024.0
            except:
                pass
            
            # Parse disk information
            disk_gb = 10.0
            try:
                disk_str = raw_data.get("disk_info", "10")
                disk_gb = float(re.sub(r'[^0-9.]', '', disk_str))
            except:
                pass
            
            # Parse load average
            load_average = None
            try:
                load_str = raw_data.get("load_avg", "")
                if load_str:
                    load_parts = load_str.split()[:3]
                    load_average = [float(x) for x in load_parts]
            except:
                pass
            
            return SystemInfo(
                os_name=os_name,
                os_version=os_version,
                cpu_cores=cpu_cores,
                ram_gb=ram_gb,
                disk_gb=disk_gb,
                architecture=raw_data.get("architecture", "unknown"),
                kernel_version=raw_data.get("kernel", "unknown"),
                uptime=raw_data.get("uptime", "unknown"),
                load_average=load_average
            )
            
        except Exception as e:
            self.logger.error(f"Failed to parse system info: {e}")
            return SystemInfo(
                os_name="unknown",
                os_version="unknown",
                cpu_cores=1,
                ram_gb=1.0,
                disk_gb=10.0,
                architecture="unknown",
                kernel_version="unknown",
                uptime="unknown"
            )
    
    def _validate_os_compatibility(self, system_info: SystemInfo) -> TestResult:
        """Validate operating system compatibility."""
        if system_info.os_name.lower() in self.requirements.supported_os:
            return TestResult(
                name="os_compatibility",
                status=ValidationResult.PASS,
                message=f"OS {system_info.os_name} {system_info.os_version} is supported",
                details={
                    "os_name": system_info.os_name,
                    "os_version": system_info.os_version,
                    "supported": True
                }
            )
        else:
            return TestResult(
                name="os_compatibility",
                status=ValidationResult.WARNING,
                message=f"OS {system_info.os_name} may not be fully supported",
                details={
                    "os_name": system_info.os_name,
                    "os_version": system_info.os_version,
                    "supported": False,
                    "supported_os": self.requirements.supported_os
                },
                suggestions=[
                    "Consider using Ubuntu 20.04+ or Debian 11+",
                    "Test thoroughly before production use",
                    "Check for compatibility issues"
                ]
            )
    
    def _validate_cpu_requirements(self, system_info: SystemInfo) -> TestResult:
        """Validate CPU requirements."""
        if system_info.cpu_cores >= self.requirements.min_cpu_cores:
            return TestResult(
                name="cpu_requirements",
                status=ValidationResult.PASS,
                message=f"CPU cores: {system_info.cpu_cores} (required: {self.requirements.min_cpu_cores})",
                details={
                    "cpu_cores": system_info.cpu_cores,
                    "required": self.requirements.min_cpu_cores,
                    "sufficient": True
                }
            )
        else:
            return TestResult(
                name="cpu_requirements",
                status=ValidationResult.FAIL,
                message=f"Insufficient CPU cores: {system_info.cpu_cores} (required: {self.requirements.min_cpu_cores})",
                details={
                    "cpu_cores": system_info.cpu_cores,
                    "required": self.requirements.min_cpu_cores,
                    "sufficient": False
                },
                suggestions=[
                    f"Upgrade to at least {self.requirements.min_cpu_cores} CPU cores",
                    "Consider using a more powerful server",
                    "Performance may be degraded"
                ]
            )
    
    def _validate_memory_requirements(self, system_info: SystemInfo) -> TestResult:
        """Validate memory requirements."""
        if system_info.ram_gb >= self.requirements.min_ram_gb:
            return TestResult(
                name="memory_requirements",
                status=ValidationResult.PASS,
                message=f"RAM: {system_info.ram_gb:.1f}GB (required: {self.requirements.min_ram_gb}GB)",
                details={
                    "ram_gb": system_info.ram_gb,
                    "required": self.requirements.min_ram_gb,
                    "sufficient": True
                }
            )
        else:
            return TestResult(
                name="memory_requirements",
                status=ValidationResult.FAIL,
                message=f"Insufficient RAM: {system_info.ram_gb:.1f}GB (required: {self.requirements.min_ram_gb}GB)",
                details={
                    "ram_gb": system_info.ram_gb,
                    "required": self.requirements.min_ram_gb,
                    "sufficient": False
                },
                suggestions=[
                    f"Upgrade to at least {self.requirements.min_ram_gb}GB RAM",
                    "Add swap space as temporary solution",
                    "Monitor memory usage closely"
                ]
            )
    
    def _validate_disk_requirements(self, system_info: SystemInfo) -> TestResult:
        """Validate disk space requirements."""
        if system_info.disk_gb >= self.requirements.min_disk_gb:
            return TestResult(
                name="disk_requirements",
                status=ValidationResult.PASS,
                message=f"Disk space: {system_info.disk_gb:.1f}GB (required: {self.requirements.min_disk_gb}GB)",
                details={
                    "disk_gb": system_info.disk_gb,
                    "required": self.requirements.min_disk_gb,
                    "sufficient": True
                }
            )
        else:
            return TestResult(
                name="disk_requirements",
                status=ValidationResult.FAIL,
                message=f"Insufficient disk space: {system_info.disk_gb:.1f}GB (required: {self.requirements.min_disk_gb}GB)",
                details={
                    "disk_gb": system_info.disk_gb,
                    "required": self.requirements.min_disk_gb,
                    "sufficient": False
                },
                suggestions=[
                    f"Free up at least {self.requirements.min_disk_gb}GB disk space",
                    "Clean up unnecessary files",
                    "Consider adding more storage"
                ]
            )
    
    def _validate_system_load(self, system_info: SystemInfo) -> TestResult:
        """Validate system load."""
        if not system_info.load_average:
            return TestResult(
                name="system_load",
                status=ValidationResult.SKIP,
                message="Load average information not available"
            )
        
        load_1min = system_info.load_average[0]
        load_threshold = system_info.cpu_cores * 0.8  # 80% of CPU cores
        
        if load_1min <= load_threshold:
            return TestResult(
                name="system_load",
                status=ValidationResult.PASS,
                message=f"System load is normal: {load_1min:.2f} (threshold: {load_threshold:.2f})",
                details={
                    "load_1min": load_1min,
                    "load_5min": system_info.load_average[1],
                    "load_15min": system_info.load_average[2],
                    "cpu_cores": system_info.cpu_cores,
                    "threshold": load_threshold
                }
            )
        else:
            return TestResult(
                name="system_load",
                status=ValidationResult.WARNING,
                message=f"High system load: {load_1min:.2f} (threshold: {load_threshold:.2f})",
                details={
                    "load_1min": load_1min,
                    "load_5min": system_info.load_average[1],
                    "load_15min": system_info.load_average[2],
                    "cpu_cores": system_info.cpu_cores,
                    "threshold": load_threshold
                },
                suggestions=[
                    "Check for resource-intensive processes",
                    "Consider upgrading hardware",
                    "Monitor system performance"
                ]
            )
    
    async def _validate_docker_status(
        self, 
        host: str, 
        ssh_user: str, 
        ssh_port: int, 
        ssh_password: str
    ) -> TestResult:
        """Validate Docker installation and status."""
        try:
            # Check Docker installation
            docker_version = await self._execute_ssh_command(
                host, ssh_user, ssh_port, ssh_password, 
                "docker --version 2>/dev/null"
            )
            
            if not docker_version:
                return TestResult(
                    name="docker_status",
                    status=ValidationResult.FAIL,
                    message="Docker is not installed",
                    suggestions=[
                        "Install Docker using: curl -fsSL https://get.docker.com | sh",
                        "Add user to docker group: sudo usermod -aG docker $USER",
                        "Start Docker service: sudo systemctl start docker"
                    ]
                )
            
            # Check Docker service status
            docker_status = await self._execute_ssh_command(
                host, ssh_user, ssh_port, ssh_password,
                "sudo systemctl is-active docker 2>/dev/null || service docker status 2>/dev/null"
            )
            
            # Check Docker permissions
            docker_ps = await self._execute_ssh_command(
                host, ssh_user, ssh_port, ssh_password,
                "docker ps 2>/dev/null"
            )
            
            details = {
                "version": docker_version,
                "service_status": docker_status,
                "permissions_ok": "CONTAINER ID" in docker_ps
            }
            
            if "active" in docker_status.lower() and details["permissions_ok"]:
                return TestResult(
                    name="docker_status",
                    status=ValidationResult.PASS,
                    message=f"Docker is running: {docker_version}",
                    details=details
                )
            else:
                suggestions = []
                if "active" not in docker_status.lower():
                    suggestions.append("Start Docker service: sudo systemctl start docker")
                if not details["permissions_ok"]:
                    suggestions.append("Add user to docker group: sudo usermod -aG docker $USER")
                    suggestions.append("Logout and login again to apply group changes")
                
                return TestResult(
                    name="docker_status",
                    status=ValidationResult.FAIL,
                    message="Docker is installed but not properly configured",
                    details=details,
                    suggestions=suggestions
                )
                
        except Exception as e:
            return TestResult(
                name="docker_status",
                status=ValidationResult.FAIL,
                message=f"Docker validation failed: {e}",
                suggestions=["Check SSH connectivity", "Verify Docker installation"]
            )
    
    async def _validate_port_availability(
        self, 
        host: str, 
        ssh_user: str, 
        ssh_port: int, 
        ssh_password: str
    ) -> TestResult:
        """Validate required ports availability."""
        try:
            busy_ports = []
            available_ports = []
            
            for port in self.requirements.required_ports:
                # Check if port is in use
                port_check = await self._execute_ssh_command(
                    host, ssh_user, ssh_port, ssh_password,
                    f"netstat -tuln | grep :{port} || ss -tuln | grep :{port}"
                )
                
                if port_check:
                    busy_ports.append(port)
                else:
                    available_ports.append(port)
            
            if not busy_ports:
                return TestResult(
                    name="port_availability",
                    status=ValidationResult.PASS,
                    message=f"All required ports are available: {self.requirements.required_ports}",
                    details={
                        "available_ports": available_ports,
                        "busy_ports": busy_ports,
                        "required_ports": self.requirements.required_ports
                    }
                )
            else:
                return TestResult(
                    name="port_availability",
                    status=ValidationResult.FAIL,
                    message=f"Some required ports are busy: {busy_ports}",
                    details={
                        "available_ports": available_ports,
                        "busy_ports": busy_ports,
                        "required_ports": self.requirements.required_ports
                    },
                    suggestions=[
                        f"Stop services using ports: {busy_ports}",
                        "Use different ports for Marzban Node",
                        "Check firewall configuration"
                    ]
                )
                
        except Exception as e:
            return TestResult(
                name="port_availability",
                status=ValidationResult.FAIL,
                message=f"Port availability check failed: {e}"
            )
    
    async def _check_marzban_node_installation(
        self, 
        host: str, 
        ssh_user: str, 
        ssh_port: int, 
        ssh_password: str
    ) -> TestResult:
        """Check if Marzban Node is already installed."""
        try:
            # Check for Marzban Node directory
            node_dir = await self._execute_ssh_command(
                host, ssh_user, ssh_port, ssh_password,
                "ls -la /opt/marzban-node 2>/dev/null || ls -la ~/Marzban-node 2>/dev/null"
            )
            
            # Check for running Marzban Node containers
            node_container = await self._execute_ssh_command(
                host, ssh_user, ssh_port, ssh_password,
                "docker ps | grep marzban-node 2>/dev/null"
            )
            
            # Check for Marzban Node service
            node_service = await self._execute_ssh_command(
                host, ssh_user, ssh_port, ssh_password,
                "systemctl is-active marzban-node 2>/dev/null"
            )
            
            installation_status = {
                "directory_exists": bool(node_dir),
                "container_running": bool(node_container),
                "service_active": "active" in node_service.lower(),
                "details": {
                    "directory": node_dir,
                    "container": node_container,
                    "service": node_service
                }
            }
            
            if installation_status["directory_exists"] or installation_status["container_running"]:
                return TestResult(
                    name="marzban_node_status",
                    status=ValidationResult.WARNING,
                    message="Marzban Node appears to be already installed",
                    details=installation_status,
                    suggestions=[
                        "This node may already be configured",
                        "Check if it's registered in another panel",
                        "Consider importing instead of creating new"
                    ]
                )
            else:
                return TestResult(
                    name="marzban_node_status",
                    status=ValidationResult.PASS,
                    message="No existing Marzban Node installation found",
                    details=installation_status
                )
                
        except Exception as e:
            return TestResult(
                name="marzban_node_status",
                status=ValidationResult.SKIP,
                message=f"Could not check Marzban Node status: {e}"
            )