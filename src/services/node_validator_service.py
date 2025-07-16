"""Comprehensive node validation service."""

import asyncio
from typing import Dict, List, Optional, Any, Callable
from dataclasses import dataclass
from datetime import datetime

from ..core.logger import get_logger
from ..core.network_validator import NetworkValidator, TestResult, ValidationResult
from ..core.system_validator import SystemValidator, SystemRequirements
from ..core.auto_fix_engine import AutoFixEngine
from ..core.utils import is_valid_ip, is_valid_port, validate_node_name


@dataclass
class ValidationConfig:
    """Configuration for node validation."""
    # Network tests
    enable_ping_test: bool = True
    enable_port_test: bool = True
    enable_ssl_test: bool = False
    enable_http_test: bool = False
    enable_bandwidth_test: bool = False
    
    # System tests
    enable_system_requirements: bool = True
    enable_docker_check: bool = True
    enable_port_availability: bool = True
    enable_marzban_check: bool = True
    
    # Auto-fix options
    enable_auto_fix: bool = False
    auto_fix_risk_level: str = "low"  # low, medium, high
    
    # Timeouts
    network_timeout: int = 10
    ssh_timeout: int = 30
    total_timeout: int = 300


@dataclass
class ValidationReport:
    """Comprehensive validation report."""
    node_name: str
    node_ip: str
    node_port: int
    
    # Overall status
    overall_status: ValidationResult
    validation_time: float
    timestamp: datetime
    
    # Test results
    network_results: Dict[str, TestResult]
    system_results: Dict[str, TestResult]
    
    # Issues and fixes
    identified_issues: List[str]
    fixable_issues: List[str]
    fix_suggestions: List[str]
    
    # Auto-fix results (if applied)
    auto_fix_applied: bool = False
    auto_fix_results: Optional[Dict[str, Any]] = None
    
    # Recommendations
    recommendations: List[str] = None
    
    def __post_init__(self):
        if self.recommendations is None:
            self.recommendations = []
    
    @property
    def success_rate(self) -> float:
        """Calculate overall success rate."""
        all_results = {**self.network_results, **self.system_results}
        if not all_results:
            return 0.0
        
        passed = sum(1 for result in all_results.values() if result.status == ValidationResult.PASS)
        return (passed / len(all_results)) * 100
    
    @property
    def is_ready_for_deployment(self) -> bool:
        """Check if node is ready for deployment."""
        critical_tests = ["connectivity", "docker_status", "port_availability"]
        
        all_results = {**self.network_results, **self.system_results}
        
        for test_name in critical_tests:
            if test_name in all_results:
                if all_results[test_name].status == ValidationResult.FAIL:
                    return False
        
        return self.overall_status in [ValidationResult.PASS, ValidationResult.WARNING]


class NodeValidatorService:
    """Comprehensive node validation service."""
    
    def __init__(self):
        self.logger = get_logger("node_validator_service")
        self.network_validator = NetworkValidator()
        self.system_validator = SystemValidator()
        self.auto_fix_engine = AutoFixEngine()
    
    async def validate_node_comprehensive(
        self,
        node_name: str,
        node_ip: str,
        node_port: int,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str,
        config: Optional[ValidationConfig] = None,
        progress_callback: Optional[Callable] = None
    ) -> ValidationReport:
        """Perform comprehensive node validation."""
        start_time = datetime.now()
        config = config or ValidationConfig()
        
        self.logger.info(f"Starting comprehensive validation for node {node_name} ({node_ip})")
        
        # Initialize report
        report = ValidationReport(
            node_name=node_name,
            node_ip=node_ip,
            node_port=node_port,
            overall_status=ValidationResult.FAIL,
            validation_time=0.0,
            timestamp=start_time,
            network_results={},
            system_results={},
            identified_issues=[],
            fixable_issues=[],
            fix_suggestions=[]
        )
        
        try:
            # Phase 1: Basic input validation
            if progress_callback:
                await progress_callback(0, 100, "Validating input parameters")
            
            input_validation = await self._validate_input_parameters(
                node_name, node_ip, node_port, ssh_user, ssh_port
            )
            
            if not input_validation["valid"]:
                report.overall_status = ValidationResult.FAIL
                report.identified_issues.extend(input_validation["issues"])
                report.fix_suggestions.extend(input_validation["suggestions"])
                return report
            
            # Phase 2: Network validation
            if progress_callback:
                await progress_callback(10, 100, "Testing network connectivity")
            
            if config.enable_ping_test or config.enable_port_test:
                network_results = await self._run_network_tests(
                    node_ip, [node_port], config
                )
                report.network_results.update(network_results)
            
            # Phase 3: System validation
            if progress_callback:
                await progress_callback(40, 100, "Checking system requirements")
            
            if config.enable_system_requirements:
                system_results = await self._run_system_tests(
                    node_ip, ssh_user, ssh_port, ssh_password, config
                )
                report.system_results.update(system_results)
            
            # Phase 4: Issue analysis
            if progress_callback:
                await progress_callback(70, 100, "Analyzing issues")
            
            await self._analyze_validation_results(report)
            
            # Phase 5: Auto-fix (if enabled)
            if config.enable_auto_fix and report.fixable_issues:
                if progress_callback:
                    await progress_callback(80, 100, "Applying automatic fixes")
                
                await self._apply_auto_fixes(
                    report, node_ip, ssh_user, ssh_port, ssh_password, config
                )
            
            # Phase 6: Final assessment
            if progress_callback:
                await progress_callback(90, 100, "Generating recommendations")
            
            await self._generate_recommendations(report)
            
            # Calculate overall status
            report.overall_status = self._calculate_overall_status(report)
            
            if progress_callback:
                await progress_callback(100, 100, "Validation completed")
            
        except Exception as e:
            self.logger.error(f"Validation failed: {e}")
            report.overall_status = ValidationResult.FAIL
            report.identified_issues.append(f"Validation error: {e}")
        
        finally:
            report.validation_time = (datetime.now() - start_time).total_seconds()
            self.logger.info(f"Validation completed in {report.validation_time:.2f}s")
        
        return report
    
    async def _validate_input_parameters(
        self,
        node_name: str,
        node_ip: str,
        node_port: int,
        ssh_user: str,
        ssh_port: int
    ) -> Dict[str, Any]:
        """Validate input parameters."""
        issues = []
        suggestions = []
        
        # Validate node name
        if not validate_node_name(node_name):
            issues.append("Invalid node name format")
            suggestions.append("Use alphanumeric characters, spaces, hyphens, or underscores only")
        
        # Validate IP address
        if not is_valid_ip(node_ip):
            issues.append("Invalid IP address format")
            suggestions.append("Provide a valid IPv4 address")
        
        # Validate ports
        if not is_valid_port(node_port):
            issues.append("Invalid node port")
            suggestions.append("Use a port number between 1 and 65535")
        
        if not is_valid_port(ssh_port):
            issues.append("Invalid SSH port")
            suggestions.append("Use a valid SSH port number")
        
        # Validate SSH user
        if not ssh_user or len(ssh_user.strip()) == 0:
            issues.append("SSH username is required")
            suggestions.append("Provide a valid SSH username")
        
        return {
            "valid": len(issues) == 0,
            "issues": issues,
            "suggestions": suggestions
        }
    
    async def _run_network_tests(
        self,
        node_ip: str,
        ports: List[int],
        config: ValidationConfig
    ) -> Dict[str, TestResult]:
        """Run network connectivity tests."""
        results = {}
        
        try:
            # Set timeouts
            self.network_validator.timeout = config.network_timeout
            
            # Run comprehensive network test
            network_results = await self.network_validator.comprehensive_network_test(
                host=node_ip,
                ports=ports,
                include_ssl=config.enable_ssl_test,
                include_http=config.enable_http_test
            )
            
            results.update(network_results)
            
        except Exception as e:
            self.logger.error(f"Network tests failed: {e}")
            results["network_error"] = TestResult(
                name="network_error",
                status=ValidationResult.FAIL,
                message=f"Network testing failed: {e}"
            )
        
        return results
    
    async def _run_system_tests(
        self,
        node_ip: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str,
        config: ValidationConfig
    ) -> Dict[str, TestResult]:
        """Run system requirement tests."""
        results = {}
        
        try:
            # Define system requirements
            requirements = SystemRequirements(
                min_cpu_cores=1,
                min_ram_gb=1.0,
                min_disk_gb=10.0,
                required_ports=[62050, 62051],
                required_services=["docker"]
            )
            
            # Run system validation
            system_results = await self.system_validator.validate_system_requirements(
                host=node_ip,
                ssh_user=ssh_user,
                ssh_port=ssh_port,
                ssh_password=ssh_password,
                requirements=requirements
            )
            
            results.update(system_results)
            
        except Exception as e:
            self.logger.error(f"System tests failed: {e}")
            results["system_error"] = TestResult(
                name="system_error",
                status=ValidationResult.FAIL,
                message=f"System testing failed: {e}"
            )
        
        return results
    
    async def _analyze_validation_results(self, report: ValidationReport):
        """Analyze validation results and identify issues."""
        all_results = {**report.network_results, **report.system_results}
        
        # Identify failed tests
        for test_name, result in all_results.items():
            if result.status == ValidationResult.FAIL:
                report.identified_issues.append(f"{test_name}: {result.message}")
                
                # Add suggestions if available
                if result.suggestions:
                    report.fix_suggestions.extend(result.suggestions)
        
        # Analyze fixable issues
        fixable_issues = await self.auto_fix_engine.analyze_issues(all_results)
        for test_name, issues in fixable_issues.items():
            report.fixable_issues.extend(issues)
    
    async def _apply_auto_fixes(
        self,
        report: ValidationReport,
        node_ip: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str,
        config: ValidationConfig
    ):
        """Apply automatic fixes for identified issues."""
        if not report.fixable_issues:
            return
        
        try:
            # Filter issues by risk level
            allowed_issues = []
            for issue in report.fixable_issues:
                risk = self.auto_fix_engine.assess_fix_risk([issue])
                if self._is_risk_acceptable(risk, config.auto_fix_risk_level):
                    allowed_issues.append(issue)
            
            if not allowed_issues:
                self.logger.info("No auto-fixable issues within acceptable risk level")
                return
            
            # Create fix plan
            fix_plan = await self.auto_fix_engine.create_fix_plan(allowed_issues)
            if not fix_plan:
                return
            
            self.logger.info(f"Applying auto-fixes: {', '.join(allowed_issues)}")
            
            # Execute fix plan
            fix_results = await self.auto_fix_engine.execute_fix_plan(
                plan=fix_plan,
                host=node_ip,
                ssh_user=ssh_user,
                ssh_port=ssh_port,
                ssh_password=ssh_password,
                dry_run=False
            )
            
            report.auto_fix_applied = True
            report.auto_fix_results = fix_results
            
            if fix_results["success"]:
                self.logger.info("Auto-fixes applied successfully")
                
                # Re-run validation for fixed issues
                await self._revalidate_fixed_issues(
                    report, node_ip, ssh_user, ssh_port, ssh_password, allowed_issues
                )
            else:
                self.logger.error(f"Auto-fix failed: {fix_results.get('error')}")
                
        except Exception as e:
            self.logger.error(f"Auto-fix execution failed: {e}")
            report.auto_fix_results = {"success": False, "error": str(e)}
    
    def _is_risk_acceptable(self, risk_level: str, max_risk: str) -> bool:
        """Check if risk level is acceptable."""
        risk_order = ["low", "medium", "high"]
        return risk_order.index(risk_level) <= risk_order.index(max_risk)
    
    async def _revalidate_fixed_issues(
        self,
        report: ValidationReport,
        node_ip: str,
        ssh_user: str,
        ssh_port: int,
        ssh_password: str,
        fixed_issues: List[str]
    ):
        """Re-validate issues that were supposedly fixed."""
        try:
            # Re-run specific tests for fixed issues
            if "docker" in " ".join(fixed_issues):
                docker_result = await self.system_validator._validate_docker_status(
                    node_ip, ssh_user, ssh_port, ssh_password
                )
                report.system_results["docker_status"] = docker_result
            
            if "port" in " ".join(fixed_issues):
                port_result = await self.system_validator._validate_port_availability(
                    node_ip, ssh_user, ssh_port, ssh_password
                )
                report.system_results["port_availability"] = port_result
            
        except Exception as e:
            self.logger.error(f"Re-validation failed: {e}")
    
    async def _generate_recommendations(self, report: ValidationReport):
        """Generate recommendations based on validation results."""
        recommendations = []
        
        # Analyze success rate
        success_rate = report.success_rate
        
        if success_rate >= 90:
            recommendations.append("✅ Node is ready for deployment")
        elif success_rate >= 70:
            recommendations.append("⚠️ Node has minor issues but can be deployed with caution")
        else:
            recommendations.append("❌ Node requires fixes before deployment")
        
        # Specific recommendations based on failed tests
        all_results = {**report.network_results, **report.system_results}
        
        for test_name, result in all_results.items():
            if result.status == ValidationResult.FAIL:
                if "connectivity" in test_name:
                    recommendations.append("🌐 Check network connectivity and firewall settings")
                elif "docker" in test_name:
                    recommendations.append("🐳 Install and configure Docker properly")
                elif "port" in test_name:
                    recommendations.append("🔌 Ensure required ports are available")
                elif "memory" in test_name or "cpu" in test_name:
                    recommendations.append("💾 Upgrade server resources")
        
        # Auto-fix recommendations
        if report.fixable_issues and not report.auto_fix_applied:
            recommendations.append("🔧 Consider enabling auto-fix for automatic issue resolution")
        
        # Performance recommendations
        if "bandwidth" in report.network_results:
            bandwidth_result = report.network_results["bandwidth"]
            if bandwidth_result.details and bandwidth_result.details.get("bandwidth_mbps", 0) < 10:
                recommendations.append("📡 Consider upgrading network connection for better performance")
        
        report.recommendations = recommendations
    
    def _calculate_overall_status(self, report: ValidationReport) -> ValidationResult:
        """Calculate overall validation status."""
        all_results = {**report.network_results, **report.system_results}
        
        if not all_results:
            return ValidationResult.FAIL
        
        # Critical tests that must pass
        critical_tests = ["connectivity", "docker_status"]
        
        # Check critical tests
        for test_name in critical_tests:
            if test_name in all_results:
                if all_results[test_name].status == ValidationResult.FAIL:
                    return ValidationResult.FAIL
        
        # Count results
        fail_count = sum(1 for result in all_results.values() if result.status == ValidationResult.FAIL)
        warning_count = sum(1 for result in all_results.values() if result.status == ValidationResult.WARNING)
        
        if fail_count == 0:
            if warning_count == 0:
                return ValidationResult.PASS
            else:
                return ValidationResult.WARNING
        else:
            return ValidationResult.FAIL
    
    async def quick_connectivity_check(
        self,
        node_ip: str,
        node_port: int,
        timeout: int = 10
    ) -> TestResult:
        """Quick connectivity check for pre-validation."""
        self.network_validator.timeout = timeout
        return await self.network_validator.validate_connectivity(node_ip, node_port)
    
    async def validate_node_basic(
        self,
        node_name: str,
        node_ip: str,
        node_port: int
    ) -> Dict[str, TestResult]:
        """Basic node validation (network only)."""
        results = {}
        
        # Input validation
        if not validate_node_name(node_name):
            results["name_validation"] = TestResult(
                name="name_validation",
                status=ValidationResult.FAIL,
                message="Invalid node name format"
            )
        
        if not is_valid_ip(node_ip):
            results["ip_validation"] = TestResult(
                name="ip_validation",
                status=ValidationResult.FAIL,
                message="Invalid IP address format"
            )
        
        if not is_valid_port(node_port):
            results["port_validation"] = TestResult(
                name="port_validation",
                status=ValidationResult.FAIL,
                message="Invalid port number"
            )
        
        # Network connectivity
        if is_valid_ip(node_ip) and is_valid_port(node_port):
            results["connectivity"] = await self.quick_connectivity_check(node_ip, node_port)
        
        return results
    
    def get_validation_summary(self, report: ValidationReport) -> Dict[str, Any]:
        """Get a summary of validation results."""
        return {
            "node_name": report.node_name,
            "node_ip": report.node_ip,
            "overall_status": report.overall_status.value,
            "success_rate": report.success_rate,
            "validation_time": report.validation_time,
            "is_ready": report.is_ready_for_deployment,
            "total_tests": len(report.network_results) + len(report.system_results),
            "passed_tests": sum(
                1 for result in {**report.network_results, **report.system_results}.values()
                if result.status == ValidationResult.PASS
            ),
            "failed_tests": len(report.identified_issues),
            "fixable_issues": len(report.fixable_issues),
            "auto_fix_applied": report.auto_fix_applied,
            "recommendations_count": len(report.recommendations)
        }