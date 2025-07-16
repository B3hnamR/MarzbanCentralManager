"""Real-time monitoring service for nodes and system health."""

import asyncio
import time
import psutil
from typing import Dict, List, Optional, Callable, Any
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from enum import Enum

from ..core.logger import get_logger
from ..core.cache_manager import cache_manager
from ..models.node import Node, NodeStatus
from .node_service import NodeService


class HealthStatus(Enum):
    """Health status levels."""
    HEALTHY = "healthy"
    WARNING = "warning"
    CRITICAL = "critical"
    UNKNOWN = "unknown"


@dataclass
class NodeMetrics:
    """Real-time node metrics."""
    node_id: int
    node_name: str
    status: NodeStatus
    response_time: Optional[float] = None
    cpu_usage: Optional[float] = None
    memory_usage: Optional[float] = None
    disk_usage: Optional[float] = None
    network_in: Optional[int] = None
    network_out: Optional[int] = None
    uptime: Optional[int] = None
    last_seen: Optional[datetime] = None
    health_status: HealthStatus = HealthStatus.UNKNOWN
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        data = asdict(self)
        data['status'] = self.status.value
        data['health_status'] = self.health_status.value
        data['last_seen'] = self.last_seen.isoformat() if self.last_seen else None
        return data
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'NodeMetrics':
        """Create from dictionary."""
        data = data.copy()
        data['status'] = NodeStatus(data['status'])
        data['health_status'] = HealthStatus(data['health_status'])
        data['last_seen'] = datetime.fromisoformat(data['last_seen']) if data['last_seen'] else None
        return cls(**data)


@dataclass
class SystemMetrics:
    """System-wide metrics."""
    total_nodes: int = 0
    healthy_nodes: int = 0
    warning_nodes: int = 0
    critical_nodes: int = 0
    offline_nodes: int = 0
    total_cpu_usage: float = 0.0
    total_memory_usage: float = 0.0
    total_disk_usage: float = 0.0
    total_network_in: int = 0
    total_network_out: int = 0
    last_updated: Optional[datetime] = None
    
    @property
    def health_percentage(self) -> float:
        """Calculate overall health percentage."""
        if self.total_nodes == 0:
            return 0.0
        return (self.healthy_nodes / self.total_nodes) * 100


class MonitoringService:
    """Real-time monitoring service for nodes and system health."""
    
    def __init__(self):
        self.logger = get_logger("monitoring_service")
        self.node_service = NodeService()
        self.is_monitoring = False
        self.monitoring_interval = 30  # seconds
        self.monitoring_task: Optional[asyncio.Task] = None
        self.subscribers: List[Callable] = []
        
        # Metrics storage
        self.node_metrics: Dict[int, NodeMetrics] = {}
        self.system_metrics = SystemMetrics()
        
        # Performance tracking
        self.metrics_history: Dict[int, List[NodeMetrics]] = {}
        self.max_history_size = 100  # Keep last 100 measurements per node
    
    def subscribe_to_updates(self, callback: Callable[[Dict[str, Any]], None]):
        """Subscribe to real-time updates."""
        self.subscribers.append(callback)
        self.logger.info(f"Added subscriber: {callback.__name__}")
    
    def unsubscribe_from_updates(self, callback: Callable):
        """Unsubscribe from real-time updates."""
        if callback in self.subscribers:
            self.subscribers.remove(callback)
            self.logger.info(f"Removed subscriber: {callback.__name__}")
    
    async def _notify_subscribers(self, update_data: Dict[str, Any]):
        """Notify all subscribers of updates."""
        for callback in self.subscribers:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(update_data)
                else:
                    callback(update_data)
            except Exception as e:
                self.logger.error(f"Error notifying subscriber {callback.__name__}: {e}")
    
    async def start_monitoring(self):
        """Start real-time monitoring."""
        if self.is_monitoring:
            self.logger.warning("Monitoring is already running")
            return
        
        self.is_monitoring = True
        self.monitoring_task = asyncio.create_task(self._monitoring_loop())
        self.logger.info("Real-time monitoring started")
    
    async def stop_monitoring(self):
        """Stop real-time monitoring."""
        if not self.is_monitoring:
            return
        
        self.is_monitoring = False
        
        if self.monitoring_task:
            self.monitoring_task.cancel()
            try:
                await self.monitoring_task
            except asyncio.CancelledError:
                pass
        
        self.logger.info("Real-time monitoring stopped")
    
    async def _monitoring_loop(self):
        """Main monitoring loop."""
        self.logger.info(f"Starting monitoring loop (interval: {self.monitoring_interval}s)")
        
        while self.is_monitoring:
            try:
                start_time = time.time()
                
                # Collect metrics
                await self._collect_node_metrics()
                await self._update_system_metrics()
                
                # Cache metrics
                await self._cache_metrics()
                
                # Notify subscribers
                await self._notify_subscribers({
                    "type": "metrics_update",
                    "node_metrics": {node_id: metrics.to_dict() for node_id, metrics in self.node_metrics.items()},
                    "system_metrics": asdict(self.system_metrics),
                    "timestamp": datetime.now().isoformat()
                })
                
                # Calculate sleep time
                elapsed = time.time() - start_time
                sleep_time = max(0, self.monitoring_interval - elapsed)
                
                if sleep_time > 0:
                    await asyncio.sleep(sleep_time)
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in monitoring loop: {e}")
                await asyncio.sleep(5)  # Short delay before retry
    
    async def _collect_node_metrics(self):
        """Collect metrics for all nodes."""
        try:
            nodes = await self.node_service.list_nodes(use_cache=False)
            
            for node in nodes:
                try:
                    metrics = await self._collect_single_node_metrics(node)
                    self.node_metrics[node.id] = metrics
                    
                    # Store in history
                    if node.id not in self.metrics_history:
                        self.metrics_history[node.id] = []
                    
                    self.metrics_history[node.id].append(metrics)
                    
                    # Limit history size
                    if len(self.metrics_history[node.id]) > self.max_history_size:
                        self.metrics_history[node.id] = self.metrics_history[node.id][-self.max_history_size:]
                
                except Exception as e:
                    self.logger.error(f"Failed to collect metrics for node {node.id}: {e}")
                    
                    # Create error metrics
                    error_metrics = NodeMetrics(
                        node_id=node.id,
                        node_name=node.name,
                        status=NodeStatus.ERROR,
                        health_status=HealthStatus.CRITICAL,
                        last_seen=datetime.now()
                    )
                    self.node_metrics[node.id] = error_metrics
        
        except Exception as e:
            self.logger.error(f"Failed to collect node metrics: {e}")
    
    async def _collect_single_node_metrics(self, node: Node) -> NodeMetrics:
        """Collect metrics for a single node."""
        start_time = time.time()
        
        # Basic metrics from node object
        metrics = NodeMetrics(
            node_id=node.id,
            node_name=node.name,
            status=node.status,
            last_seen=datetime.now()
        )
        
        try:
            # Test response time
            from ..core.network_validator import NetworkValidator
            validator = NetworkValidator()
            
            connectivity_result = await validator.validate_connectivity(node.address, node.port)
            if connectivity_result.status.value == "pass":
                metrics.response_time = connectivity_result.duration * 1000  # Convert to ms
            
            # Determine health status
            metrics.health_status = self._calculate_health_status(node, metrics)
            
        except Exception as e:
            self.logger.warning(f"Failed to collect detailed metrics for node {node.id}: {e}")
            metrics.health_status = HealthStatus.WARNING
        
        return metrics
    
    def _calculate_health_status(self, node: Node, metrics: NodeMetrics) -> HealthStatus:
        """Calculate health status based on node state and metrics."""
        if node.status == NodeStatus.CONNECTED:
            if metrics.response_time and metrics.response_time < 100:  # < 100ms
                return HealthStatus.HEALTHY
            elif metrics.response_time and metrics.response_time < 500:  # < 500ms
                return HealthStatus.WARNING
            else:
                return HealthStatus.CRITICAL
        elif node.status == NodeStatus.CONNECTING:
            return HealthStatus.WARNING
        elif node.status in [NodeStatus.DISCONNECTED, NodeStatus.ERROR]:
            return HealthStatus.CRITICAL
        elif node.status == NodeStatus.DISABLED:
            return HealthStatus.UNKNOWN
        else:
            return HealthStatus.WARNING
    
    async def _update_system_metrics(self):
        """Update system-wide metrics."""
        self.system_metrics.total_nodes = len(self.node_metrics)
        self.system_metrics.healthy_nodes = sum(1 for m in self.node_metrics.values() if m.health_status == HealthStatus.HEALTHY)
        self.system_metrics.warning_nodes = sum(1 for m in self.node_metrics.values() if m.health_status == HealthStatus.WARNING)
        self.system_metrics.critical_nodes = sum(1 for m in self.node_metrics.values() if m.health_status == HealthStatus.CRITICAL)
        self.system_metrics.offline_nodes = sum(1 for m in self.node_metrics.values() if m.status in [NodeStatus.DISCONNECTED, NodeStatus.ERROR])
        self.system_metrics.last_updated = datetime.now()
        
        # Calculate totals
        total_response_time = sum(m.response_time for m in self.node_metrics.values() if m.response_time)
        active_nodes = sum(1 for m in self.node_metrics.values() if m.response_time)
        
        if active_nodes > 0:
            avg_response_time = total_response_time / active_nodes
            # Use response time as a proxy for system load
            self.system_metrics.total_cpu_usage = min(100, avg_response_time / 10)  # Rough estimation
    
    async def _cache_metrics(self):
        """Cache current metrics."""
        try:
            # Cache node metrics
            node_metrics_data = {node_id: metrics.to_dict() for node_id, metrics in self.node_metrics.items()}
            await cache_manager.set("monitoring:node_metrics", node_metrics_data, ttl=60, tags=["monitoring"])
            
            # Cache system metrics
            await cache_manager.set("monitoring:system_metrics", asdict(self.system_metrics), ttl=60, tags=["monitoring"])
            
        except Exception as e:
            self.logger.error(f"Failed to cache metrics: {e}")
    
    async def get_current_metrics(self) -> Dict[str, Any]:
        """Get current metrics."""
        return {
            "node_metrics": {node_id: metrics.to_dict() for node_id, metrics in self.node_metrics.items()},
            "system_metrics": asdict(self.system_metrics),
            "timestamp": datetime.now().isoformat()
        }
    
    async def get_node_metrics(self, node_id: int) -> Optional[NodeMetrics]:
        """Get metrics for specific node."""
        return self.node_metrics.get(node_id)
    
    async def get_node_history(self, node_id: int, limit: int = 50) -> List[NodeMetrics]:
        """Get historical metrics for a node."""
        history = self.metrics_history.get(node_id, [])
        return history[-limit:] if limit else history
    
    async def get_health_summary(self) -> Dict[str, Any]:
        """Get health summary."""
        return {
            "total_nodes": self.system_metrics.total_nodes,
            "healthy": self.system_metrics.healthy_nodes,
            "warning": self.system_metrics.warning_nodes,
            "critical": self.system_metrics.critical_nodes,
            "offline": self.system_metrics.offline_nodes,
            "health_percentage": self.system_metrics.health_percentage,
            "last_updated": self.system_metrics.last_updated.isoformat() if self.system_metrics.last_updated else None
        }
    
    async def get_alerts(self) -> List[Dict[str, Any]]:
        """Get current alerts based on metrics."""
        alerts = []
        
        for node_id, metrics in self.node_metrics.items():
            if metrics.health_status == HealthStatus.CRITICAL:
                alerts.append({
                    "type": "critical",
                    "node_id": node_id,
                    "node_name": metrics.node_name,
                    "message": f"Node {metrics.node_name} is in critical state",
                    "status": metrics.status.value,
                    "timestamp": datetime.now().isoformat()
                })
            elif metrics.health_status == HealthStatus.WARNING:
                alerts.append({
                    "type": "warning",
                    "node_id": node_id,
                    "node_name": metrics.node_name,
                    "message": f"Node {metrics.node_name} has performance issues",
                    "response_time": metrics.response_time,
                    "timestamp": datetime.now().isoformat()
                })
        
        # System-level alerts
        if self.system_metrics.health_percentage < 50:
            alerts.append({
                "type": "critical",
                "message": f"System health is critical: {self.system_metrics.health_percentage:.1f}%",
                "healthy_nodes": self.system_metrics.healthy_nodes,
                "total_nodes": self.system_metrics.total_nodes,
                "timestamp": datetime.now().isoformat()
            })
        elif self.system_metrics.health_percentage < 80:
            alerts.append({
                "type": "warning",
                "message": f"System health is degraded: {self.system_metrics.health_percentage:.1f}%",
                "healthy_nodes": self.system_metrics.healthy_nodes,
                "total_nodes": self.system_metrics.total_nodes,
                "timestamp": datetime.now().isoformat()
            })
        
        return alerts
    
    def set_monitoring_interval(self, interval: int):
        """Set monitoring interval in seconds."""
        self.monitoring_interval = max(10, interval)  # Minimum 10 seconds
        self.logger.info(f"Monitoring interval set to {self.monitoring_interval} seconds")
    
    async def force_update(self):
        """Force immediate metrics update."""
        if self.is_monitoring:
            await self._collect_node_metrics()
            await self._update_system_metrics()
            await self._cache_metrics()
            
            await self._notify_subscribers({
                "type": "forced_update",
                "node_metrics": {node_id: metrics.to_dict() for node_id, metrics in self.node_metrics.items()},
                "system_metrics": asdict(self.system_metrics),
                "timestamp": datetime.now().isoformat()
            })
    
    async def close(self):
        """Close monitoring service."""
        await self.stop_monitoring()
        await self.node_service.close()
        self.logger.info("Monitoring service closed")


# Global monitoring service instance
monitoring_service = MonitoringService()