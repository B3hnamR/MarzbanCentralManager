"""Bulk operations service for managing multiple nodes simultaneously."""

import asyncio
import json
from typing import List, Dict, Any, Optional, Callable, Union
from dataclasses import dataclass, asdict
from datetime import datetime
from enum import Enum

from ..core.logger import get_logger
from ..core.offline_manager import offline_manager, OperationType
from ..models.node import Node, NodeStatus
from .node_service import NodeService


class BulkOperationStatus(Enum):
    """Status of bulk operations."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    PARTIAL = "partial"


@dataclass
class BulkOperationResult:
    """Result of a bulk operation."""
    operation_id: str
    operation_type: str
    total_items: int
    successful_items: int
    failed_items: int
    status: BulkOperationStatus
    start_time: datetime
    end_time: Optional[datetime] = None
    errors: List[str] = None
    details: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.errors is None:
            self.errors = []
        if self.details is None:
            self.details = {}
    
    @property
    def success_rate(self) -> float:
        """Calculate success rate percentage."""
        if self.total_items == 0:
            return 0.0
        return (self.successful_items / self.total_items) * 100
    
    @property
    def duration(self) -> float:
        """Calculate operation duration in seconds."""
        if not self.end_time:
            return (datetime.now() - self.start_time).total_seconds()
        return (self.end_time - self.start_time).total_seconds()


@dataclass
class NodeTemplate:
    """Template for node configuration."""
    name: str
    description: str
    port: int = 62050
    api_port: int = 62051
    usage_coefficient: float = 1.0
    add_as_new_host: bool = True
    tags: List[str] = None
    custom_config: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.tags is None:
            self.tags = []
        if self.custom_config is None:
            self.custom_config = {}
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'NodeTemplate':
        """Create from dictionary."""
        return cls(**data)


class BulkOperationsService:
    """Service for managing bulk operations on nodes."""
    
    def __init__(self):
        self.logger = get_logger("bulk_operations")
        self.node_service = NodeService()
        self.active_operations: Dict[str, BulkOperationResult] = {}
        self.templates: Dict[str, NodeTemplate] = {}
        
        # Load predefined templates
        self._load_default_templates()
    
    def _load_default_templates(self):
        """Load default node templates."""
        default_templates = {
            "standard": NodeTemplate(
                name="Standard Node",
                description="Standard configuration for most nodes",
                port=62050,
                api_port=62051,
                usage_coefficient=1.0,
                tags=["standard"]
            ),
            "high_performance": NodeTemplate(
                name="High Performance Node",
                description="Optimized for high traffic",
                port=62050,
                api_port=62051,
                usage_coefficient=1.5,
                tags=["high-performance", "premium"]
            ),
            "backup": NodeTemplate(
                name="Backup Node",
                description="Backup node configuration",
                port=62052,
                api_port=62053,
                usage_coefficient=0.5,
                tags=["backup", "secondary"]
            ),
            "development": NodeTemplate(
                name="Development Node",
                description="For development and testing",
                port=62054,
                api_port=62055,
                usage_coefficient=0.1,
                tags=["development", "testing"]
            )
        }
        
        self.templates.update(default_templates)
        self.logger.info(f"Loaded {len(default_templates)} default templates")
    
    async def bulk_create_nodes(
        self,
        node_configs: List[Dict[str, Any]],
        template_name: Optional[str] = None,
        progress_callback: Optional[Callable] = None
    ) -> BulkOperationResult:
        """Create multiple nodes in bulk."""
        import uuid
        
        operation_id = str(uuid.uuid4())
        operation = BulkOperationResult(
            operation_id=operation_id,
            operation_type="bulk_create",
            total_items=len(node_configs),
            successful_items=0,
            failed_items=0,
            status=BulkOperationStatus.RUNNING,
            start_time=datetime.now()
        )
        
        self.active_operations[operation_id] = operation
        
        try:
            self.logger.info(f"Starting bulk create operation: {operation_id}")
            
            # Apply template if specified
            if template_name and template_name in self.templates:
                template = self.templates[template_name]
                for config in node_configs:
                    # Merge template with config (config takes precedence)
                    template_dict = template.to_dict()
                    template_dict.update(config)
                    config.clear()
                    config.update(template_dict)
            
            # Process each node
            for i, config in enumerate(node_configs):
                try:
                    if progress_callback:
                        await progress_callback(i, len(node_configs), f"Creating node: {config.get('name', f'Node {i+1}')}")
                    
                    # Validate required fields
                    if not all(key in config for key in ['name', 'address']):
                        raise ValueError("Missing required fields: name, address")
                    
                    # Create node
                    node = await self.node_service.create_node(
                        name=config['name'],
                        address=config['address'],
                        port=config.get('port', 62050),
                        api_port=config.get('api_port', 62051),
                        usage_coefficient=config.get('usage_coefficient', 1.0),
                        add_as_new_host=config.get('add_as_new_host', True)
                    )
                    
                    operation.successful_items += 1
                    operation.details[f"node_{i}"] = {
                        "status": "success",
                        "node_id": node.id,
                        "name": node.name
                    }
                    
                    self.logger.debug(f"Created node: {node.name} (ID: {node.id})")
                    
                except Exception as e:
                    operation.failed_items += 1
                    error_msg = f"Failed to create node {config.get('name', f'Node {i+1}')}: {e}"
                    operation.errors.append(error_msg)
                    operation.details[f"node_{i}"] = {
                        "status": "failed",
                        "error": str(e)
                    }
                    
                    self.logger.error(error_msg)
                
                # Small delay to avoid overwhelming the API
                await asyncio.sleep(0.1)
            
            # Determine final status
            if operation.failed_items == 0:
                operation.status = BulkOperationStatus.COMPLETED
            elif operation.successful_items == 0:
                operation.status = BulkOperationStatus.FAILED
            else:
                operation.status = BulkOperationStatus.PARTIAL
            
            operation.end_time = datetime.now()
            
            self.logger.info(f"Bulk create completed: {operation.successful_items}/{operation.total_items} successful")
            
            if progress_callback:
                await progress_callback(len(node_configs), len(node_configs), "Bulk create completed")
            
            return operation
            
        except Exception as e:
            operation.status = BulkOperationStatus.FAILED
            operation.end_time = datetime.now()
            operation.errors.append(f"Bulk operation failed: {e}")
            
            self.logger.error(f"Bulk create operation failed: {e}")
            return operation
    
    async def bulk_update_nodes(
        self,
        node_ids: List[int],
        update_data: Dict[str, Any],
        progress_callback: Optional[Callable] = None
    ) -> BulkOperationResult:
        """Update multiple nodes in bulk."""
        import uuid
        
        operation_id = str(uuid.uuid4())
        operation = BulkOperationResult(
            operation_id=operation_id,
            operation_type="bulk_update",
            total_items=len(node_ids),
            successful_items=0,
            failed_items=0,
            status=BulkOperationStatus.RUNNING,
            start_time=datetime.now()
        )
        
        self.active_operations[operation_id] = operation
        
        try:
            self.logger.info(f"Starting bulk update operation: {operation_id}")
            
            for i, node_id in enumerate(node_ids):
                try:
                    if progress_callback:
                        await progress_callback(i, len(node_ids), f"Updating node: {node_id}")
                    
                    # Update node
                    node = await self.node_service.update_node(node_id, **update_data)
                    
                    operation.successful_items += 1
                    operation.details[f"node_{node_id}"] = {
                        "status": "success",
                        "node_id": node.id,
                        "name": node.name
                    }
                    
                    self.logger.debug(f"Updated node: {node.name} (ID: {node.id})")
                    
                except Exception as e:
                    operation.failed_items += 1
                    error_msg = f"Failed to update node {node_id}: {e}"
                    operation.errors.append(error_msg)
                    operation.details[f"node_{node_id}"] = {
                        "status": "failed",
                        "error": str(e)
                    }
                    
                    self.logger.error(error_msg)
                
                await asyncio.sleep(0.1)
            
            # Determine final status
            if operation.failed_items == 0:
                operation.status = BulkOperationStatus.COMPLETED
            elif operation.successful_items == 0:
                operation.status = BulkOperationStatus.FAILED
            else:
                operation.status = BulkOperationStatus.PARTIAL
            
            operation.end_time = datetime.now()
            
            self.logger.info(f"Bulk update completed: {operation.successful_items}/{operation.total_items} successful")
            
            return operation
            
        except Exception as e:
            operation.status = BulkOperationStatus.FAILED
            operation.end_time = datetime.now()
            operation.errors.append(f"Bulk operation failed: {e}")
            
            self.logger.error(f"Bulk update operation failed: {e}")
            return operation
    
    async def bulk_delete_nodes(
        self,
        node_ids: List[int],
        progress_callback: Optional[Callable] = None
    ) -> BulkOperationResult:
        """Delete multiple nodes in bulk."""
        import uuid
        
        operation_id = str(uuid.uuid4())
        operation = BulkOperationResult(
            operation_id=operation_id,
            operation_type="bulk_delete",
            total_items=len(node_ids),
            successful_items=0,
            failed_items=0,
            status=BulkOperationStatus.RUNNING,
            start_time=datetime.now()
        )
        
        self.active_operations[operation_id] = operation
        
        try:
            self.logger.info(f"Starting bulk delete operation: {operation_id}")
            
            for i, node_id in enumerate(node_ids):
                try:
                    if progress_callback:
                        await progress_callback(i, len(node_ids), f"Deleting node: {node_id}")
                    
                    # Get node info before deletion
                    node = await self.node_service.get_node(node_id)
                    node_name = node.name
                    
                    # Delete node
                    await self.node_service.delete_node(node_id)
                    
                    operation.successful_items += 1
                    operation.details[f"node_{node_id}"] = {
                        "status": "success",
                        "node_id": node_id,
                        "name": node_name
                    }
                    
                    self.logger.debug(f"Deleted node: {node_name} (ID: {node_id})")
                    
                except Exception as e:
                    operation.failed_items += 1
                    error_msg = f"Failed to delete node {node_id}: {e}"
                    operation.errors.append(error_msg)
                    operation.details[f"node_{node_id}"] = {
                        "status": "failed",
                        "error": str(e)
                    }
                    
                    self.logger.error(error_msg)
                
                await asyncio.sleep(0.1)
            
            # Determine final status
            if operation.failed_items == 0:
                operation.status = BulkOperationStatus.COMPLETED
            elif operation.successful_items == 0:
                operation.status = BulkOperationStatus.FAILED
            else:
                operation.status = BulkOperationStatus.PARTIAL
            
            operation.end_time = datetime.now()
            
            self.logger.info(f"Bulk delete completed: {operation.successful_items}/{operation.total_items} successful")
            
            return operation
            
        except Exception as e:
            operation.status = BulkOperationStatus.FAILED
            operation.end_time = datetime.now()
            operation.errors.append(f"Bulk operation failed: {e}")
            
            self.logger.error(f"Bulk delete operation failed: {e}")
            return operation
    
    async def bulk_reconnect_nodes(
        self,
        node_ids: List[int],
        progress_callback: Optional[Callable] = None
    ) -> BulkOperationResult:
        """Reconnect multiple nodes in bulk."""
        import uuid
        
        operation_id = str(uuid.uuid4())
        operation = BulkOperationResult(
            operation_id=operation_id,
            operation_type="bulk_reconnect",
            total_items=len(node_ids),
            successful_items=0,
            failed_items=0,
            status=BulkOperationStatus.RUNNING,
            start_time=datetime.now()
        )
        
        self.active_operations[operation_id] = operation
        
        try:
            self.logger.info(f"Starting bulk reconnect operation: {operation_id}")
            
            for i, node_id in enumerate(node_ids):
                try:
                    if progress_callback:
                        await progress_callback(i, len(node_ids), f"Reconnecting node: {node_id}")
                    
                    # Reconnect node
                    await self.node_service.reconnect_node(node_id)
                    
                    operation.successful_items += 1
                    operation.details[f"node_{node_id}"] = {
                        "status": "success",
                        "node_id": node_id
                    }
                    
                    self.logger.debug(f"Reconnected node: {node_id}")
                    
                except Exception as e:
                    operation.failed_items += 1
                    error_msg = f"Failed to reconnect node {node_id}: {e}"
                    operation.errors.append(error_msg)
                    operation.details[f"node_{node_id}"] = {
                        "status": "failed",
                        "error": str(e)
                    }
                    
                    self.logger.error(error_msg)
                
                await asyncio.sleep(0.5)  # Longer delay for reconnections
            
            # Determine final status
            if operation.failed_items == 0:
                operation.status = BulkOperationStatus.COMPLETED
            elif operation.successful_items == 0:
                operation.status = BulkOperationStatus.FAILED
            else:
                operation.status = BulkOperationStatus.PARTIAL
            
            operation.end_time = datetime.now()
            
            self.logger.info(f"Bulk reconnect completed: {operation.successful_items}/{operation.total_items} successful")
            
            return operation
            
        except Exception as e:
            operation.status = BulkOperationStatus.FAILED
            operation.end_time = datetime.now()
            operation.errors.append(f"Bulk operation failed: {e}")
            
            self.logger.error(f"Bulk reconnect operation failed: {e}")
            return operation
    
    async def bulk_change_status(
        self,
        node_ids: List[int],
        new_status: NodeStatus,
        progress_callback: Optional[Callable] = None
    ) -> BulkOperationResult:
        """Change status of multiple nodes in bulk."""
        import uuid
        
        operation_id = str(uuid.uuid4())
        operation = BulkOperationResult(
            operation_id=operation_id,
            operation_type="bulk_status_change",
            total_items=len(node_ids),
            successful_items=0,
            failed_items=0,
            status=BulkOperationStatus.RUNNING,
            start_time=datetime.now()
        )
        
        self.active_operations[operation_id] = operation
        
        try:
            self.logger.info(f"Starting bulk status change operation: {operation_id}")
            
            for i, node_id in enumerate(node_ids):
                try:
                    if progress_callback:
                        await progress_callback(i, len(node_ids), f"Changing status of node: {node_id}")
                    
                    # Change node status
                    if new_status == NodeStatus.DISABLED:
                        node = await self.node_service.disable_node(node_id)
                    elif new_status == NodeStatus.CONNECTED:
                        node = await self.node_service.enable_node(node_id)
                    else:
                        # Use update method for other statuses
                        node = await self.node_service.update_node(node_id, status=new_status)
                    
                    operation.successful_items += 1
                    operation.details[f"node_{node_id}"] = {
                        "status": "success",
                        "node_id": node.id,
                        "name": node.name,
                        "new_status": new_status.value
                    }
                    
                    self.logger.debug(f"Changed status of node {node.name} to {new_status.value}")
                    
                except Exception as e:
                    operation.failed_items += 1
                    error_msg = f"Failed to change status of node {node_id}: {e}"
                    operation.errors.append(error_msg)
                    operation.details[f"node_{node_id}"] = {
                        "status": "failed",
                        "error": str(e)
                    }
                    
                    self.logger.error(error_msg)
                
                await asyncio.sleep(0.1)
            
            # Determine final status
            if operation.failed_items == 0:
                operation.status = BulkOperationStatus.COMPLETED
            elif operation.successful_items == 0:
                operation.status = BulkOperationStatus.FAILED
            else:
                operation.status = BulkOperationStatus.PARTIAL
            
            operation.end_time = datetime.now()
            
            self.logger.info(f"Bulk status change completed: {operation.successful_items}/{operation.total_items} successful")
            
            return operation
            
        except Exception as e:
            operation.status = BulkOperationStatus.FAILED
            operation.end_time = datetime.now()
            operation.errors.append(f"Bulk operation failed: {e}")
            
            self.logger.error(f"Bulk status change operation failed: {e}")
            return operation
    
    # Template management methods
    def create_template(self, template_id: str, template: NodeTemplate):
        """Create a new node template."""
        self.templates[template_id] = template
        self.logger.info(f"Created template: {template_id}")
    
    def get_template(self, template_id: str) -> Optional[NodeTemplate]:
        """Get a node template by ID."""
        return self.templates.get(template_id)
    
    def list_templates(self) -> Dict[str, NodeTemplate]:
        """List all available templates."""
        return self.templates.copy()
    
    def delete_template(self, template_id: str) -> bool:
        """Delete a node template."""
        if template_id in self.templates:
            del self.templates[template_id]
            self.logger.info(f"Deleted template: {template_id}")
            return True
        return False
    
    def get_operation_result(self, operation_id: str) -> Optional[BulkOperationResult]:
        """Get result of a bulk operation."""
        return self.active_operations.get(operation_id)
    
    def list_active_operations(self) -> Dict[str, BulkOperationResult]:
        """List all active operations."""
        return self.active_operations.copy()
    
    def clear_completed_operations(self) -> int:
        """Clear completed operations from memory."""
        completed_ops = [
            op_id for op_id, op in self.active_operations.items()
            if op.status in [BulkOperationStatus.COMPLETED, BulkOperationStatus.FAILED, BulkOperationStatus.PARTIAL]
        ]
        
        for op_id in completed_ops:
            del self.active_operations[op_id]
        
        self.logger.info(f"Cleared {len(completed_ops)} completed operations")
        return len(completed_ops)
    
    async def close(self):
        """Close the bulk operations service."""
        await self.node_service.close()
        self.logger.info("Bulk operations service closed")