"""Unit tests for NodeService."""

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock

from src.services.node_service import NodeService
from src.models.node import Node, NodeStatus
from src.core.exceptions import NodeNotFoundError, NodeAlreadyExistsError


class TestNodeService:
    """Test cases for NodeService."""
    
    @pytest.fixture
    def mock_api(self):
        """Mock API client."""
        api = AsyncMock()
        return api
    
    @pytest.fixture
    def node_service(self, mock_api):
        """NodeService instance with mocked API."""
        service = NodeService()
        service._api = mock_api
        return service
    
    @pytest.fixture
    def sample_node(self):
        """Sample node data."""
        return Node(
            id=1,
            name="Test Node",
            address="192.168.1.1",
            port=62050,
            api_port=62051,
            usage_coefficient=1.0,
            status=NodeStatus.CONNECTED,
            xray_version="1.8.1"
        )
    
    @pytest.mark.asyncio
    async def test_list_nodes(self, node_service, mock_api, sample_node):
        """Test listing nodes."""
        mock_api.list_nodes.return_value = [sample_node]
        
        nodes = await node_service.list_nodes()
        
        assert len(nodes) == 1
        assert nodes[0].name == "Test Node"
        mock_api.list_nodes.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_get_node(self, node_service, mock_api, sample_node):
        """Test getting specific node."""
        mock_api.get_node.return_value = sample_node
        
        node = await node_service.get_node(1)
        
        assert node.id == 1
        assert node.name == "Test Node"
        mock_api.get_node.assert_called_once_with(1)
    
    @pytest.mark.asyncio
    async def test_get_node_not_found(self, node_service, mock_api):
        """Test getting non-existent node."""
        mock_api.get_node.side_effect = Exception("Node not found")
        
        with pytest.raises(NodeNotFoundError):
            await node_service.get_node(999)
    
    @pytest.mark.asyncio
    async def test_create_node(self, node_service, mock_api, sample_node):
        """Test creating new node."""
        mock_api.find_node_by_name.return_value = None
        mock_api.find_node_by_address.return_value = None
        mock_api.create_node.return_value = sample_node
        
        node = await node_service.create_node(
            name="Test Node",
            address="192.168.1.1"
        )
        
        assert node.name == "Test Node"
        assert node.address == "192.168.1.1"
        mock_api.create_node.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_create_node_already_exists(self, node_service, mock_api, sample_node):
        """Test creating node that already exists."""
        mock_api.find_node_by_name.return_value = sample_node
        
        with pytest.raises(NodeAlreadyExistsError):
            await node_service.create_node(
                name="Test Node",
                address="192.168.1.1"
            )
    
    @pytest.mark.asyncio
    async def test_delete_node(self, node_service, mock_api, sample_node):
        """Test deleting node."""
        mock_api.get_node.return_value = sample_node
        mock_api.delete_node.return_value = True
        
        result = await node_service.delete_node(1)
        
        assert result is True
        mock_api.delete_node.assert_called_once_with(1)
    
    @pytest.mark.asyncio
    async def test_reconnect_node(self, node_service, mock_api, sample_node):
        """Test reconnecting node."""
        mock_api.get_node.return_value = sample_node
        mock_api.reconnect_node.return_value = True
        
        result = await node_service.reconnect_node(1)
        
        assert result is True
        mock_api.reconnect_node.assert_called_once_with(1)