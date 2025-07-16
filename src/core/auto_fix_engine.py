"""Auto-fix engine for resolving common node setup issues."""

import asyncio
import random
from typing import Dict, List, Optional, Any, Callable
from dataclasses import dataclass
from enum import Enum

from .logger import get_logger
from .network_validator import TestResult, ValidationResult
from .system_validator import SystemValidator


class FixAction(Enum):
    """Types of fix actions."""
    INSTALL_PACKAGE = "install_package"
    START_SERVICE = "start_service"
    CONFIGURE_FIREWALL = "configure_firewall"
    CREATE_USER = "create_user"
    SET_PERMISSIONS = "set_permissions"
    MODIFY_CONFIG = "modify_config"
    DOWNLOAD_FILE = "download_file"
    RUN_COMMAND = "run_command"


@dataclass
class FixStep:
    """Individual fix step."""
    action: FixAction
    description: str
    command: str
    verify_command: Optional[str] = None
    rollback_command: Optional[str] = None
    risk_level: str = "low"  # low, medium, high
    requires_sudo: bool = False
    timeout: int = 60


@dataclass
class FixPlan:
    """Complete fix plan for an issue."""
    issue_name: str
    description: str
    steps: List[FixStep]
    estimated_time: int  # seconds
    risk_level: str = "low"
    prerequisites: List[str] = None
    
    def __post_init__(self):
        if self.prerequisites is None:
            self.prerequisites = []


class AutoFixEngine:
    """Engine for automatically fixing common node setup issues."""
    
    def __init__(self):
        self.logger = get_logger("auto_fix_engine")
        self.fix_plans = self._initialize_fix_plans()
        self.system_validator = SystemValidator()
    
    def _initialize_fix_plans(self) -> Dict[str, FixPlan]:
        """Initialize predefined fix plans."""
        return {
            "docker_not_installed": FixPlan(
                issue_name="docker_not_installed",
                description="Install Docker and configure it properly",
                estimated_time=180,
                risk_level="medium",
                steps=[
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Update package index",
                        command="apt-get update",
                        requires_sudo=True,
                        timeout=60
                    ),
                    FixStep(
                        action=FixAction.INSTALL_PACKAGE,
                        description="Install required packages",
                        command="apt-get install -y curl ca-certificates gnupg lsb-release",
                        requires_sudo=True,
                        timeout=120
                    ),
                    FixStep(
                        action=FixAction.DOWNLOAD_FILE,
                        description="Download Docker installation script",
                        command="curl -fsSL https://get.docker.com -o get-docker.sh",
                        verify_command="test -f get-docker.sh",
                        timeout=30
                    ),
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Install Docker",
                        command="sh get-docker.sh",
                        verify_command="docker --version",
                        requires_sudo=True,
                        timeout=300
                    ),
                    FixStep(
                        action=FixAction.START_SERVICE,
                        description="Start Docker service",
                        command="systemctl start docker && systemctl enable docker",
                        verify_command="systemctl is-active docker",
                        requires_sudo=True,
                        timeout=30
                    )
                ]
            ),
            
            "docker_permissions": FixPlan(
                issue_name="docker_permissions",
                description="Fix Docker permissions for current user",
                estimated_time=30,
                risk_level="low",
                steps=[
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Add user to docker group",
                        command="usermod -aG docker $USER",
                        requires_sudo=True,
                        timeout=10
                    ),
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Apply group changes",
                        command="newgrp docker",
                        timeout=10
                    )
                ]
            ),
            
            "ports_busy": FixPlan(
                issue_name="ports_busy",
                description="Find and suggest alternative ports",
                estimated_time=60,
                risk_level="low",
                steps=[
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Find available ports",
                        command="python3 -c \"import socket; s=socket.socket(); s.bind(('', 0)); print(s.getsockname()[1]); s.close()\"",
                        timeout=10
                    )
                ]
            ),
            
            "firewall_blocking": FixPlan(
                issue_name="firewall_blocking",
                description="Configure firewall to allow required ports",
                estimated_time=60,
                risk_level="medium",
                steps=[
                    FixStep(
                        action=FixAction.CONFIGURE_FIREWALL,
                        description="Allow port 62050 (Marzban Node)",
                        command="ufw allow 62050/tcp",
                        verify_command="ufw status | grep 62050",
                        requires_sudo=True,
                        timeout=10
                    ),
                    FixStep(
                        action=FixAction.CONFIGURE_FIREWALL,
                        description="Allow port 62051 (Marzban Node API)",
                        command="ufw allow 62051/tcp",
                        verify_command="ufw status | grep 62051",
                        requires_sudo=True,
                        timeout=10
                    )
                ]
            ),
            
            "insufficient_resources": FixPlan(
                issue_name="insufficient_resources",
                description="Optimize system resources",
                estimated_time=120,
                risk_level="medium",
                steps=[
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Clean package cache",
                        command="apt-get clean && apt-get autoremove -y",
                        requires_sudo=True,
                        timeout=60
                    ),
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Create swap file (1GB)",
                        command="fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile",
                        verify_command="swapon --show | grep /swapfile",
                        requires_sudo=True,
                        timeout=60
                    )
                ]
            ),
            
            "marzban_node_install": FixPlan(
                issue_name="marzban_node_install",
                description="Install Marzban Node",
                estimated_time=300,
                risk_level="medium",
                prerequisites=["docker_installed"],
                steps=[
                    FixStep(
                        action=FixAction.RUN_COMMAND,
                        description="Create Marzban Node directory",
                        command="mkdir -p /opt/marzban-node",
                        requires_sudo=True,
                        timeout=10
                    ),
                    FixStep(
                        action=FixAction.DOWNLOAD_FILE,
                        description="Download Marzban Node",
                        command="cd /opt/marzban-node && git clone https://github.com/Gozargah/Marzban-node .",
                        verify_command="test -f /opt/marzban-node/docker-compose.yml",
                        requires_sudo=True,
                        timeout=120
                    ),
                    FixStep(
                        action=FixAction.MODIFY_CONFIG,
                        description="Configure Marzban Node",
                        command="cd /opt/marzban-node && cp .env.example .env",
                        requires_sudo=True,
                        timeout=10
                    )
                ]
            )
        }
    
    async def analyze_issues(self, validation_results: Dict[str, TestResult]) -> Dict[str, List[str]]:
        """Analyze validation results and identify fixable issues."""
        issues = {}
        
        for test_name, result in validation_results.items():
            if result.status == ValidationResult.FAIL:
                fixable_issues = self._identify_fixable_issues(test_name, result)
                if fixable_issues:
                    issues[test_name] = fixable_issues
        
        return issues
    
    def _identify_fixable_issues(self, test_name: str, result: TestResult) -> List[str]:
        """Identify which issues can be automatically fixed."""
        fixable = []
        
        # Docker-related issues
        if "docker" in test_name.lower():
            if "not installed" in result.message.lower():
                fixable.append("docker_not_installed")
            elif "permission" in result.message.lower() or "group" in result.message.lower():
                fixable.append("docker_permissions")
        
        # Port-related issues
        if "port" in test_name.lower() and "busy" in result.message.lower():
            fixable.append("ports_busy")
        
        # Firewall issues
        if "connection" in test_name.lower() and "refused" in result.message.lower():
            fixable.append("firewall_blocking")
        
        # Resource issues
        if any(keyword in test_name.lower() for keyword in ["cpu", "memory", "disk"]):
            if "insufficient" in result.message.lower():
                fixable.append("insufficient_resources")
        
        # Marzban Node installation
        if "marzban" in test_name.lower() and "not found" in result.message.lower():
            fixable.append("marzban_node_install")
        
        return fixable
    
    async def create_fix_plan(self, issues: List[str]) -> Optional[FixPlan]:
        """Create a comprehensive fix plan for multiple issues."""
        if not issues:
            return None
        
        # Sort issues by dependency and risk
        sorted_issues = self._sort_issues_by_priority(issues)
        
        combined_steps = []
        total_time = 0
        max_risk = "low"
        all_prerequisites = set()
        
        for issue in sorted_issues:
            if issue in self.fix_plans:
                plan = self.fix_plans[issue]
                combined_steps.extend(plan.steps)
                total_time += plan.estimated_time
                
                if plan.risk_level == "high" or (plan.risk_level == "medium" and max_risk == "low"):
                    max_risk = plan.risk_level
                
                all_prerequisites.update(plan.prerequisites)
        
        return FixPlan(
            issue_name="combined_fix",
            description=f"Fix multiple issues: {', '.join(sorted_issues)}",
            steps=combined_steps,
            estimated_time=total_time,
            risk_level=max_risk,
            prerequisites=list(all_prerequisites)
        )
    
    def _sort_issues_by_priority(self, issues: List[str]) -> List[str]:
        """Sort issues by fix priority (dependencies first)."""
        priority_order = [
            "docker_not_installed",
            "docker_permissions", 
            "firewall_blocking",
            "ports_busy",
            "insufficient_resources",
            "marzban_node_install"
        ]
        
        sorted_issues = []
        for priority_issue in priority_order:
            if priority_issue in issues:
                sorted_issues.append(priority_issue)
        
        # Add any remaining issues
        for issue in issues:
            if issue not in sorted_issues:
                sorted_issues.append(issue)
        
        return sorted_issues
    
    async def execute_fix_plan(
        self,
        plan: FixPlan,
        host: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str,
        progress_callback: Optional[Callable] = None,
        dry_run: bool = False
    ) -> Dict[str, Any]:
        """Execute a fix plan."""
        self.logger.info(f"Executing fix plan: {plan.description}")
        
        results = {
            "success": False,
            "completed_steps": 0,
            "total_steps": len(plan.steps),
            "step_results": [],
            "error": None,
            "rollback_performed": False
        }
        
        if dry_run:
            self.logger.info("DRY RUN MODE - No actual changes will be made")
            return await self._simulate_fix_execution(plan, results)
        
        completed_steps = []
        
        try:
            for i, step in enumerate(plan.steps):
                if progress_callback:
                    await progress_callback(i, len(plan.steps), step.description)
                
                self.logger.info(f"Executing step {i+1}/{len(plan.steps)}: {step.description}")
                
                step_result = await self._execute_fix_step(
                    step, host, ssh_user, ssh_port, ssh_password
                )
                
                results["step_results"].append(step_result)
                
                if step_result["success"]:
                    completed_steps.append(step)
                    results["completed_steps"] += 1
                    self.logger.info(f"Step completed successfully: {step.description}")
                else:
                    self.logger.error(f"Step failed: {step.description} - {step_result['error']}")
                    
                    # Attempt rollback
                    if completed_steps:
                        self.logger.info("Attempting rollback of completed steps")
                        await self._rollback_steps(completed_steps, host, ssh_user, ssh_port, ssh_password)
                        results["rollback_performed"] = True
                    
                    results["error"] = step_result["error"]
                    return results
            
            results["success"] = True
            self.logger.info("Fix plan executed successfully")
            
        except Exception as e:
            self.logger.error(f"Fix plan execution failed: {e}")
            results["error"] = str(e)
            
            # Attempt rollback
            if completed_steps:
                await self._rollback_steps(completed_steps, host, ssh_user, ssh_port, ssh_password)
                results["rollback_performed"] = True
        
        return results
    
    async def _execute_fix_step(
        self,
        step: FixStep,
        host: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str
    ) -> Dict[str, Any]:
        """Execute a single fix step."""
        try:
            # Prepare command
            command = step.command
            if step.requires_sudo and not command.startswith("sudo"):
                command = f"sudo {command}"
            
            # Execute command
            output = await self._execute_ssh_command(
                host, ssh_user, ssh_port, ssh_password, command, step.timeout
            )
            
            # Verify if verification command is provided
            if step.verify_command:
                verify_output = await self._execute_ssh_command(
                    host, ssh_user, ssh_port, ssh_password, step.verify_command, 10
                )
                
                if not verify_output:
                    return {
                        "success": False,
                        "error": "Verification failed",
                        "output": output,
                        "verify_output": verify_output
                    }
            
            return {
                "success": True,
                "output": output,
                "verify_output": step.verify_command and verify_output or None
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "output": None
            }
    
    async def _execute_ssh_command(
        self,
        host: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str,
        command: str,
        timeout: int = 30
    ) -> str:
        """Execute SSH command."""
        try:
            ssh_cmd = [
                "sshpass", "-p", ssh_password,
                "ssh", "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=10",
                "-p", str(ssh_port),
                f"{ssh_user}@{host}",
                command
            ]
            
            process = await asyncio.create_subprocess_exec(
                *ssh_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
            
            if process.returncode == 0:
                return stdout.decode().strip()
            else:
                raise Exception(f"Command failed: {stderr.decode()}")
                
        except Exception as e:
            raise Exception(f"SSH execution failed: {e}")
    
    async def _rollback_steps(
        self,
        completed_steps: List[FixStep],
        host: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str
    ):
        """Rollback completed steps in reverse order."""
        self.logger.info("Starting rollback process")
        
        for step in reversed(completed_steps):
            if step.rollback_command:
                try:
                    self.logger.info(f"Rolling back: {step.description}")
                    await self._execute_ssh_command(
                        host, ssh_user, ssh_port, ssh_password, 
                        step.rollback_command, step.timeout
                    )
                except Exception as e:
                    self.logger.error(f"Rollback failed for step '{step.description}': {e}")
    
    async def _simulate_fix_execution(self, plan: FixPlan, results: Dict[str, Any]) -> Dict[str, Any]:
        """Simulate fix execution for dry run."""
        self.logger.info("Simulating fix execution (dry run)")
        
        for i, step in enumerate(plan.steps):
            await asyncio.sleep(0.1)  # Simulate execution time
            
            step_result = {
                "success": True,
                "output": f"[DRY RUN] Would execute: {step.command}",
                "verify_output": f"[DRY RUN] Would verify: {step.verify_command}" if step.verify_command else None
            }
            
            results["step_results"].append(step_result)
            results["completed_steps"] += 1
        
        results["success"] = True
        return results
    
    def get_available_fixes(self) -> Dict[str, str]:
        """Get list of available automatic fixes."""
        return {
            name: plan.description 
            for name, plan in self.fix_plans.items()
        }
    
    def estimate_fix_time(self, issues: List[str]) -> int:
        """Estimate total time needed to fix issues."""
        total_time = 0
        for issue in issues:
            if issue in self.fix_plans:
                total_time += self.fix_plans[issue].estimated_time
        return total_time
    
    def assess_fix_risk(self, issues: List[str]) -> str:
        """Assess overall risk level of fixing issues."""
        risk_levels = []
        for issue in issues:
            if issue in self.fix_plans:
                risk_levels.append(self.fix_plans[issue].risk_level)
        
        if "high" in risk_levels:
            return "high"
        elif "medium" in risk_levels:
            return "medium"
        else:
            return "low"
    
    async def suggest_alternative_ports(
        self,
        host: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str,
        count: int = 2
    ) -> List[int]:
        """Suggest alternative available ports."""
        suggested_ports = []
        
        try:
            for _ in range(count):
                # Find random available port
                port_cmd = "python3 -c \"import socket; s=socket.socket(); s.bind(('', 0)); print(s.getsockname()[1]); s.close()\""
                port_output = await self._execute_ssh_command(
                    host, ssh_user, ssh_port, ssh_password, port_cmd
                )
                
                if port_output.isdigit():
                    suggested_ports.append(int(port_output))
                    
        except Exception as e:
            self.logger.error(f"Failed to suggest alternative ports: {e}")
            # Fallback to random ports in safe range
            suggested_ports = [random.randint(10000, 65000) for _ in range(count)]
        
        return suggested_ports