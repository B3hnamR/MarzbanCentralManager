"""Node management CLI commands."""

import asyncio
import click
from typing import Optional
from datetime import datetime, timedelta

from ...services.node_service import NodeService
from ...models.node import NodeStatus
from ...core.logger import get_logger
from ...core.exceptions import (
    NodeError, NodeNotFoundError, NodeAlreadyExistsError,
    ConfigurationError
)
from ..ui.display import (
    display_nodes_table, display_node_details, display_usage_table,
    display_status_summary, success_message, error_message, info_message
)


@click.group()
def node():
    """Node management commands."""
    pass


@node.command()
@click.option('--format', 'output_format', default='table', 
              type=click.Choice(['table', 'json']), 
              help='Output format')
def list(output_format):
    """List all nodes."""
    async def _list_nodes():
        service = NodeService()
        try:
            nodes = await service.list_nodes()
            
            if output_format == 'json':
                import json
                nodes_data = [node.to_dict() for node in nodes]
                click.echo(json.dumps(nodes_data, indent=2))
            else:
                display_nodes_table(nodes)
                
        except ConfigurationError as e:
            error_message(f"Configuration error: {e}")
            click.echo("\nPlease run 'python main.py config setup' to configure Marzban connection.")
        except NodeError as e:
            error_message(f"Failed to list nodes: {e}")
        finally:
            await service.close()
    
    asyncio.run(_list_nodes())


@node.command()
@click.argument('node_id', type=int)
@click.option('--format', 'output_format', default='details', 
              type=click.Choice(['details', 'json']), 
              help='Output format')
def show(node_id, output_format):
    """Show details of a specific node."""
    async def _show_node():
        service = NodeService()
        try:
            node = await service.get_node(node_id)
            
            if output_format == 'json':
                import json
                click.echo(json.dumps(node.to_dict(), indent=2))
            else:
                display_node_details(node)
                
        except NodeNotFoundError as e:
            error_message(f"Node not found: {e}")
        except NodeError as e:
            error_message(f"Failed to get node: {e}")
        finally:
            await service.close()
    
    asyncio.run(_show_node())


@node.command()
@click.option('--name', required=True, help='Node name')
@click.option('--address', required=True, help='Node IP address')
@click.option('--port', default=62050, help='Node port (default: 62050)')
@click.option('--api-port', default=62051, help='Node API port (default: 62051)')
@click.option('--usage-coefficient', default=1.0, help='Usage coefficient (default: 1.0)')
@click.option('--add-as-host/--no-add-as-host', default=True, 
              help='Add as new host (default: True)')
@click.option('--wait/--no-wait', default=True, 
              help='Wait for node to connect (default: True)')
def add(name, address, port, api_port, usage_coefficient, add_as_host, wait):
    """Add a new node."""
    async def _add_node():
        service = NodeService()
        try:
            info_message(f"Creating node: {name} ({address})")
            
            node = await service.create_node(
                name=name,
                address=address,
                port=port,
                api_port=api_port,
                usage_coefficient=usage_coefficient,
                add_as_new_host=add_as_host
            )
            
            success_message(f"Node created successfully!")
            display_node_details(node)
            
            if wait and node.status != NodeStatus.CONNECTED:
                info_message("Waiting for node to connect...")
                connected = await service.wait_for_node_connection(node.id, timeout=60)
                
                if connected:
                    success_message("Node connected successfully!")
                else:
                    error_message("Node failed to connect within timeout")
                    
        except NodeAlreadyExistsError as e:
            error_message(f"Node already exists: {e}")
        except NodeError as e:
            error_message(f"Failed to create node: {e}")
        finally:
            await service.close()
    
    asyncio.run(_add_node())


@node.command()
@click.argument('node_id', type=int)
@click.option('--name', help='New node name')
@click.option('--address', help='New node IP address')
@click.option('--port', type=int, help='New node port')
@click.option('--api-port', type=int, help='New node API port')
@click.option('--usage-coefficient', type=float, help='New usage coefficient')
@click.option('--status', type=click.Choice(['connected', 'connecting', 'disconnected', 'disabled']),
              help='New node status')
def update(node_id, name, address, port, api_port, usage_coefficient, status):
    """Update an existing node."""
    async def _update_node():
        service = NodeService()
        try:
            # Convert status string to enum if provided
            status_enum = None
            if status:
                status_enum = NodeStatus(status)
            
            info_message(f"Updating node {node_id}")
            
            node = await service.update_node(
                node_id=node_id,
                name=name,
                address=address,
                port=port,
                api_port=api_port,
                usage_coefficient=usage_coefficient,
                status=status_enum
            )
            
            success_message(f"Node {node_id} updated successfully!")
            display_node_details(node)
            
        except NodeNotFoundError as e:
            error_message(f"Node not found: {e}")
        except NodeError as e:
            error_message(f"Failed to update node: {e}")
        finally:
            await service.close()
    
    asyncio.run(_update_node())


@node.command()
@click.argument('node_id', type=int)
@click.option('--force', is_flag=True, help='Force deletion without confirmation')
def delete(node_id, force):
    """Delete a node."""
    async def _delete_node():
        service = NodeService()
        try:
            # Get node details first
            node = await service.get_node(node_id)
            
            if not force:
                click.echo(f"\nNode to delete:")
                display_node_details(node)
                
                if not click.confirm(f"\nAre you sure you want to delete node {node_id} ({node.name})?"):
                    info_message("Deletion cancelled")
                    return
            
            info_message(f"Deleting node {node_id}")
            await service.delete_node(node_id)
            success_message(f"Node {node_id} ({node.name}) deleted successfully!")
            
        except NodeNotFoundError as e:
            error_message(f"Node not found: {e}")
        except NodeError as e:
            error_message(f"Failed to delete node: {e}")
        finally:
            await service.close()
    
    asyncio.run(_delete_node())


@node.command()
@click.argument('node_id', type=int)
@click.option('--wait/--no-wait', default=True, 
              help='Wait for node to connect (default: True)')
def reconnect(node_id, wait):
    """Reconnect a node."""
    async def _reconnect_node():
        service = NodeService()
        try:
            info_message(f"Reconnecting node {node_id}")
            await service.reconnect_node(node_id)
            success_message(f"Reconnection triggered for node {node_id}")
            
            if wait:
                info_message("Waiting for node to connect...")
                connected = await service.wait_for_node_connection(node_id, timeout=60)
                
                if connected:
                    success_message("Node reconnected successfully!")
                else:
                    error_message("Node failed to reconnect within timeout")
                    
        except NodeNotFoundError as e:
            error_message(f"Node not found: {e}")
        except NodeError as e:
            error_message(f"Failed to reconnect node: {e}")
        finally:
            await service.close()
    
    asyncio.run(_reconnect_node())


@node.command()
@click.argument('node_id', type=int)
def enable(node_id):
    """Enable a disabled node."""
    async def _enable_node():
        service = NodeService()
        try:
            info_message(f"Enabling node {node_id}")
            node = await service.enable_node(node_id)
            success_message(f"Node {node_id} enabled successfully!")
            display_node_details(node)
            
        except NodeNotFoundError as e:
            error_message(f"Node not found: {e}")
        except NodeError as e:
            error_message(f"Failed to enable node: {e}")
        finally:
            await service.close()
    
    asyncio.run(_enable_node())


@node.command()
@click.argument('node_id', type=int)
def disable(node_id):
    """Disable a node."""
    async def _disable_node():
        service = NodeService()
        try:
            info_message(f"Disabling node {node_id}")
            node = await service.disable_node(node_id)
            success_message(f"Node {node_id} disabled successfully!")
            display_node_details(node)
            
        except NodeNotFoundError as e:
            error_message(f"Node not found: {e}")
        except NodeError as e:
            error_message(f"Failed to disable node: {e}")
        finally:
            await service.close()
    
    asyncio.run(_disable_node())


@node.command()
def status():
    """Show node status summary."""
    async def _show_status():
        service = NodeService()
        try:
            summary = await service.get_node_status_summary()
            display_status_summary(summary)
            
        except NodeError as e:
            error_message(f"Failed to get status summary: {e}")
        finally:
            await service.close()
    
    asyncio.run(_show_status())


@node.command()
@click.option('--days', default=30, help='Number of days to look back (default: 30)')
@click.option('--format', 'output_format', default='table', 
              type=click.Choice(['table', 'json']), 
              help='Output format')
def usage(days, output_format):
    """Show node usage statistics."""
    async def _show_usage():
        service = NodeService()
        try:
            end_date = datetime.now()
            start_date = end_date - timedelta(days=days)
            
            info_message(f"Fetching usage statistics for last {days} days")
            usage_stats = await service.get_node_usage(start_date, end_date)
            
            if output_format == 'json':
                import json
                usage_data = [usage.to_dict() for usage in usage_stats]
                click.echo(json.dumps(usage_data, indent=2))
            else:
                display_usage_table(usage_stats, days)
                
        except NodeError as e:
            error_message(f"Failed to get usage statistics: {e}")
        finally:
            await service.close()
    
    asyncio.run(_show_usage())


@node.command()
def healthy():
    """List healthy nodes."""
    async def _list_healthy():
        service = NodeService()
        try:
            nodes = await service.get_healthy_nodes()
            
            if nodes:
                success_message(f"Found {len(nodes)} healthy nodes:")
                display_nodes_table(nodes)
            else:
                info_message("No healthy nodes found")
                
        except NodeError as e:
            error_message(f"Failed to get healthy nodes: {e}")
        finally:
            await service.close()
    
    asyncio.run(_list_healthy())


@node.command()
def unhealthy():
    """List unhealthy nodes."""
    async def _list_unhealthy():
        service = NodeService()
        try:
            nodes = await service.get_unhealthy_nodes()
            
            if nodes:
                error_message(f"Found {len(nodes)} unhealthy nodes:")
                display_nodes_table(nodes)
            else:
                success_message("All nodes are healthy!")
                
        except NodeError as e:
            error_message(f"Failed to get unhealthy nodes: {e}")
        finally:
            await service.close()
    
    asyncio.run(_list_unhealthy())


@node.command()
def settings():
    """Show node settings."""
    async def _show_settings():
        service = NodeService()
        try:
            settings = await service.get_node_settings()
            
            click.echo("\n" + "="*50)
            click.echo("NODE SETTINGS")
            click.echo("="*50)
            click.echo(f"Minimum Node Version: {settings.min_node_version}")
            click.echo(f"Certificate Length: {len(settings.certificate)} characters")
            click.echo("="*50)
            
            if click.confirm("Show full certificate?"):
                click.echo("\nTLS Certificate:")
                click.echo("-" * 50)
                click.echo(settings.certificate)
                
        except NodeError as e:
            error_message(f"Failed to get node settings: {e}")
        finally:
            await service.close()
    
    asyncio.run(_show_settings())