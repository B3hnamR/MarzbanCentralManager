"""Node management service."""

import asyncio
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta

from ..api.endpoints.nodes import NodesAPI
from ..models.node import Node, NodeCreate, NodeUpdate, NodeUsage, NodeSettings, NodeStatus
from ..core.config import config_manager
from ..core.logger import get_logger
from ..core.exceptions import (
    NodeError, NodeNotFoundError, NodeConnectionError, 
    NodeAlreadyExistsError, ConfigurationError
)


class NodeService:
    """Service for managing nodes."""
    
    def __init__(self):
        self.logger = get_logger("service.node")
        self._api: Optional[NodesAPI] = None
    
    async def _get_api(self) -> NodesAPI:
        """Get API client instance."""
        if self._api is None:
            config = config_manager.load_config()
            if not config.marzban:
                raise ConfigurationError("Marzban configuration not found")
            
            self._api = NodesAPI(config.marzban)
            
            # Test connection
            if not await self._api.test_connection():
                raise NodeConnectionError("Failed to connect to Marzban API")
        
        return self._api
    
    async def close(self):
        """Close API connections."""
        if self._api:
            await self._api.close()
            self._api = None
    
    async def list_nodes(self) -> List[Node]:
        """Get list of all nodes."""
        self.logger.info("Fetching all nodes")
        api = await self._get_api()
        
        try:
            nodes = await api.list_nodes()
            self.logger.info(f"Found {len(nodes)} nodes")
            return nodes
        except Exception as e:
            self.logger.error(f"Failed to fetch nodes: {e}")
            raise NodeError(f"Failed to fetch nodes: {e}")
    
    async def get_node(self, node_id: int) -> Node:
        """Get specific node by ID."""
        self.logger.info(f"Fetching node {node_id}")
        api = await self._get_api()
        
        try:
            node = await api.get_node(node_id)
            self.logger.info(f"Found node: {node.name}")
            return node
        except Exception as e:
            self.logger.error(f"Failed to fetch node {node_id}: {e}")
            if "not found" in str(e).lower():
                raise NodeNotFoundError(f"Node {node_id} not found")
            raise NodeError(f"Failed to fetch node: {e}")
    
    async def create_node(
        self,
        name: str,
        address: str,
        port: int = 62050,
        api_port: int = 62051,
        usage_coefficient: float = 1.0,
        add_as_new_host: bool = True
    ) -> Node:
        """Create a new node."""
        self.logger.info(f"Creating node: {name} ({address})")
        api = await self._get_api()
        
        # Check if node with same name already exists
        existing_node = await api.find_node_by_name(name)
        if existing_node:
            raise NodeAlreadyExistsError(f"Node with name '{name}' already exists")
        
        # Check if node with same address already exists
        existing_node = await api.find_node_by_address(address)
        if existing_node:
            raise NodeAlreadyExistsError(f"Node with address '{address}' already exists")
        
        # Create node data
        node_data = NodeCreate(
            name=name,
            address=address,
            port=port,
            api_port=api_port,
            usage_coefficient=usage_coefficient,
            add_as_new_host=add_as_new_host
        )
        
        # Validate data
        try:
            node_data.validate()
        except ValueError as e:
            raise NodeError(f"Invalid node data: {e}")
        
        try:
            node = await api.create_node(node_data)
            self.logger.info(f"Node created successfully: {node.name} (ID: {node.id})")
            return node
        except Exception as e:
            self.logger.error(f"Failed to create node: {e}")
            if "already exists" in str(e).lower():
                raise NodeAlreadyExistsError(f"Node already exists: {e}")
            raise NodeError(f"Failed to create node: {e}")
    
    async def update_node(
        self,
        node_id: int,
        name: Optional[str] = None,
        address: Optional[str] = None,
        port: Optional[int] = None,
        api_port: Optional[int] = None,
        usage_coefficient: Optional[float] = None,
        status: Optional[NodeStatus] = None
    ) -> Node:
        """Update an existing node."""
        self.logger.info(f"Updating node {node_id}")
        api = await self._get_api()
        
        # Check if node exists
        try:
            existing_node = await api.get_node(node_id)
        except Exception:
            raise NodeNotFoundError(f"Node {node_id} not found")
        
        # Create update data
        update_data = NodeUpdate(
            name=name,
            address=address,
            port=port,
            api_port=api_port,
            usage_coefficient=usage_coefficient,
            status=status
        )
        
        # Validate data
        try:
            update_data.validate()
        except ValueError as e:
            raise NodeError(f"Invalid update data: {e}")
        
        try:
            node = await api.update_node(node_id, update_data)
            self.logger.info(f"Node {node_id} updated successfully")
            return node
        except Exception as e:
            self.logger.error(f"Failed to update node {node_id}: {e}")
            raise NodeError(f"Failed to update node: {e}")
    
    async def delete_node(self, node_id: int) -> bool:
        """Delete a node."""
        self.logger.info(f"Deleting node {node_id}")
        api = await self._get_api()
        
        # Check if node exists
        try:
            node = await api.get_node(node_id)
            node_name = node.name
        except Exception:
            raise NodeNotFoundError(f"Node {node_id} not found")
        
        try:
            await api.delete_node(node_id)
            self.logger.info(f"Node {node_id} ({node_name}) deleted successfully")
            return True
        except Exception as e:
            self.logger.error(f"Failed to delete node {node_id}: {e}")
            raise NodeError(f"Failed to delete node: {e}")
    
    async def reconnect_node(self, node_id: int) -> bool:
        """Reconnect a node."""
        self.logger.info(f"Reconnecting node {node_id}")
        api = await self._get_api()
        
        # Check if node exists
        try:
            node = await api.get_node(node_id)
            node_name = node.name
        except Exception:
            raise NodeNotFoundError(f"Node {node_id} not found")
        
        try:
            await api.reconnect_node(node_id)
            self.logger.info(f"Node {node_id} ({node_name}) reconnection triggered")
            return True
        except Exception as e:
            self.logger.error(f"Failed to reconnect node {node_id}: {e}")
            raise NodeError(f"Failed to reconnect node: {e}")
    
    async def get_node_usage(
        self,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[NodeUsage]:
        """Get usage statistics for all nodes."""
        self.logger.info("Fetching node usage statistics")
        api = await self._get_api()
        
        # Default to last 30 days if no dates provided
        if not start_date:
            start_date = datetime.now() - timedelta(days=30)
        if not end_date:
            end_date = datetime.now()
        
        try:
            usage_stats = await api.get_nodes_usage(start_date, end_date)
            self.logger.info(f"Retrieved usage stats for {len(usage_stats)} nodes")
            return usage_stats
        except Exception as e:
            self.logger.error(f"Failed to fetch usage statistics: {e}")
            raise NodeError(f"Failed to fetch usage statistics: {e}")
    
    async def get_node_settings(self) -> NodeSettings:
        """Get node settings including TLS certificate."""
        self.logger.info("Fetching node settings")
        api = await self._get_api()
        
        try:
            settings = await api.get_node_settings()
            self.logger.info("Node settings retrieved successfully")
            return settings
        except Exception as e:
            self.logger.error(f"Failed to fetch node settings: {e}")
            raise NodeError(f"Failed to fetch node settings: {e}")
    
    async def find_node_by_name(self, name: str) -> Optional[Node]:
        """Find node by name."""
        self.logger.debug(f"Searching for node by name: {name}")
        api = await self._get_api()
        
        try:
            return await api.find_node_by_name(name)
        except Exception as e:
            self.logger.error(f"Failed to search for node: {e}")
            raise NodeError(f"Failed to search for node: {e}")
    
    async def get_node_status_summary(self) -> Dict[str, int]:
        """Get summary of node statuses."""
        self.logger.info("Getting node status summary")
        api = await self._get_api()
        
        try:
            summary = await api.get_node_status_summary()
            self.logger.info(f"Status summary: {summary}")
            return summary
        except Exception as e:
            self.logger.error(f"Failed to get status summary: {e}")
            raise NodeError(f"Failed to get status summary: {e}")
    
    async def get_healthy_nodes(self) -> List[Node]:
        """Get list of healthy nodes."""
        self.logger.info("Fetching healthy nodes")
        api = await self._get_api()
        
        try:
            healthy_nodes = await api.get_healthy_nodes()
            self.logger.info(f"Found {len(healthy_nodes)} healthy nodes")
            return healthy_nodes
        except Exception as e:
            self.logger.error(f"Failed to fetch healthy nodes: {e}")
            raise NodeError(f"Failed to fetch healthy nodes: {e}")
    
    async def get_unhealthy_nodes(self) -> List[Node]:
        """Get list of unhealthy nodes."""
        self.logger.info("Fetching unhealthy nodes")
        api = await self._get_api()
        
        try:
            unhealthy_nodes = await api.get_unhealthy_nodes()
            self.logger.info(f"Found {len(unhealthy_nodes)} unhealthy nodes")
            return unhealthy_nodes
        except Exception as e:
            self.logger.error(f"Failed to fetch unhealthy nodes: {e}")
            raise NodeError(f"Failed to fetch unhealthy nodes: {e}")
    
    async def enable_node(self, node_id: int) -> Node:
        """Enable a disabled node."""
        return await self.update_node(node_id, status=NodeStatus.CONNECTING)
    
    async def disable_node(self, node_id: int) -> Node:
        """Disable a node."""
        return await self.update_node(node_id, status=NodeStatus.DISABLED)
    
    async def wait_for_node_connection(
        self, 
        node_id: int, 
        timeout: int = 60, 
        check_interval: int = 5
    ) -> bool:
        """Wait for node to connect."""
        self.logger.info(f"Waiting for node {node_id} to connect (timeout: {timeout}s)")
        
        start_time = datetime.now()
        while (datetime.now() - start_time).seconds < timeout:
            try:
                node = await self.get_node(node_id)
                if node.status == NodeStatus.CONNECTED:
                    self.logger.info(f"Node {node_id} connected successfully")
                    return True
                elif node.status == NodeStatus.ERROR:
                    self.logger.warning(f"Node {node_id} is in error state")
                    return False
                
                self.logger.debug(f"Node {node_id} status: {node.status}")
                await asyncio.sleep(check_interval)
                
            except Exception as e:
                self.logger.warning(f"Error checking node status: {e}")
                await asyncio.sleep(check_interval)
        
        self.logger.warning(f"Node {node_id} connection timeout")
        return False