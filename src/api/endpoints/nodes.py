"""Node management API endpoints."""

from typing import List, Optional, Dict, Any
from datetime import datetime

from ..base import BaseAPIClient
from ...models.node import Node, NodeCreate, NodeUpdate, NodeUsage, NodeSettings
from ...core.logger import get_logger
from ...core.constants import APIEndpoints


class NodesAPI(BaseAPIClient):
    """API client for node management operations."""

    def __init__(self, config):
        super().__init__(config)
        self.logger = get_logger("api.nodes")

    async def get_node_settings(self) -> NodeSettings:
        """Get node settings including TLS certificate."""
        self.logger.debug("Fetching node settings")
        response = await self.get(str(APIEndpoints.NODE_SETTINGS))
        return NodeSettings.from_dict(response)

    async def list_nodes(self) -> List[Node]:
        """Get list of all nodes."""
        self.logger.debug("Fetching all nodes")
        response = await self.get(str(APIEndpoints.NODES))
        return [Node.from_dict(node_data) for node_data in response]

    async def get_node(self, node_id: int) -> Node:
        """Get specific node by ID."""
        self.logger.debug(f"Fetching node {node_id}")
        response = await self.get(f"{APIEndpoints.NODES}/{node_id}")
        return Node.from_dict(response)

    async def create_node(self, node_data: NodeCreate) -> Node:
        """Create a new node."""
        self.logger.info(f"Creating node: {node_data.name}")
        response = await self.post(str(APIEndpoints.NODES), node_data.to_dict())
        created_node = Node.from_dict(response)
        self.logger.info(f"Node created successfully with ID: {created_node.id}")
        return created_node

    async def update_node(self, node_id: int, node_data: NodeUpdate) -> Node:
        """Update an existing node."""
        self.logger.info(f"Updating node {node_id}")
        response = await self.put(f"{APIEndpoints.NODES}/{node_id}", node_data.to_dict())
        updated_node = Node.from_dict(response)
        self.logger.info(f"Node {node_id} updated successfully")
        return updated_node

    async def delete_node(self, node_id: int) -> bool:
        """Delete a node."""
        self.logger.info(f"Deleting node {node_id}")
        await self.delete(f"{APIEndpoints.NODES}/{node_id}")
        self.logger.info(f"Node {node_id} deleted successfully")
        return True

    async def reconnect_node(self, node_id: int) -> bool:
        """Trigger reconnection for a node."""
        self.logger.info(f"Reconnecting node {node_id}")
        await self.post(f"{APIEndpoints.NODES}/{node_id}/reconnect")
        self.logger.info(f"Reconnection triggered for node {node_id}")
        return True

    async def get_nodes_usage(
        self,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[NodeUsage]:
        """Get usage statistics for nodes."""
        self.logger.debug("Fetching nodes usage statistics")

        params = {}
        if start_date:
            params["start"] = start_date.isoformat()
        if end_date:
            params["end"] = end_date.isoformat()

        response = await self.get(f"{APIEndpoints.NODES}/usage", params=params)

        # Handle both response formats
        if isinstance(response, dict) and "usages" in response:
            usage_data = response["usages"]
        else:
            usage_data = response

        return [NodeUsage.from_dict(usage) for usage in usage_data]

    async def find_node_by_name(self, name: str) -> Optional[Node]:
        """Find node by name."""
        nodes = await self.list_nodes()
        for node in nodes:
            if node.name == name:
                return node
        return None

    async def find_node_by_address(self, address: str) -> Optional[Node]:
        """Find node by address."""
        nodes = await self.list_nodes()
        for node in nodes:
            if node.address == address:
                return node
        return None

    async def get_node_status_summary(self) -> Dict[str, int]:
        """Get summary of node statuses."""
        nodes = await self.list_nodes()

        summary = {
            "total": len(nodes),
            "connected": 0,
            "connecting": 0,
            "disconnected": 0,
            "disabled": 0,
            "error": 0
        }

        for node in nodes:
            if node.status in summary:
                summary[node.status] += 1
            else:
                summary["error"] += 1

        return summary

    async def get_healthy_nodes(self) -> List[Node]:
        """Get list of healthy (connected) nodes."""
        nodes = await self.list_nodes()
        return [node for node in nodes if node.status == "connected"]

    async def get_unhealthy_nodes(self) -> List[Node]:
        """Get list of unhealthy nodes."""
        nodes = await self.list_nodes()
        return [node for node in nodes if node.status != "connected"]
