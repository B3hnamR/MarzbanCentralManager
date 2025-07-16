"""Node management CLI commands."""

import json
import click
from datetime import datetime, timedelta

from ...models.node import NodeStatus
from ...core.exceptions import NodeError, NodeNotFoundError, NodeAlreadyExistsError, ConfigurationError
from ..ui.display import (
    display_nodes_table, display_node_details, display_usage_table,
    display_status_summary, success_message, error_message, info_message
)
from ..utils import coro


@click.group()
def node():
    """Node management commands."""
    pass


@node.command("list")
@click.option('--format', 'output_format', default='table', type=click.Choice(['table', 'json']), help='Output format')
@click.pass_context
@coro
async def list_nodes(ctx, output_format):
    """List all nodes."""
    node_service = ctx.obj.node_service
    try:
        nodes = await node_service.list_nodes()
        if output_format == 'json':
            nodes_data = [node.to_dict() for node in nodes]
            click.echo(json.dumps(nodes_data, indent=2))
        else:
            display_nodes_table(nodes)
    except ConfigurationError as e:
        error_message(f"Configuration error: {e}")
        click.echo("
Please run 'python main.py config setup' to configure Marzban connection.")
    except NodeError as e:
        error_message(f"Failed to list nodes: {e}")


@node.command("show")
@click.argument('node_id', type=int)
@click.option('--format', 'output_format', default='details', type=click.Choice(['details', 'json']), help='Output format')
@click.pass_context
@coro
async def show_node(ctx, node_id, output_format):
    """Show details of a specific node."""
    node_service = ctx.obj.node_service
    try:
        node = await node_service.get_node(node_id)
        if output_format == 'json':
            click.echo(json.dumps(node.to_dict(), indent=2))
        else:
            display_node_details(node)
    except NodeNotFoundError as e:
        error_message(f"Node not found: {e}")
    except NodeError as e:
        error_message(f"Failed to get node: {e}")


@node.command("add")
@click.option('--name', required=True, help='Node name')
@click.option('--address', required=True, help='Node IP address')
@click.option('--port', default=62050, help='Node port (default: 62050)')
@click.option('--api-port', default=62051, help='Node API port (default: 62051)')
@click.option('--usage-coefficient', default=1.0, help='Usage coefficient (default: 1.0)')
@click.option('--add-as-host/--no-add-as-host', default=True, help='Add as new host (default: True)')
@click.option('--wait/--no-wait', default=True, help='Wait for node to connect (default: True)')
@click.pass_context
@coro
async def add_node(ctx, name, address, port, api_port, usage_coefficient, add_as_host, wait):
    """Add a new node."""
    node_service = ctx.obj.node_service
    try:
        info_message(f"Creating node: {name} ({address})")
        node = await node_service.create_node(
            name=name, address=address, port=port, api_port=api_port,
            usage_coefficient=usage_coefficient, add_as_new_host=add_as_host
        )
        success_message(f"Node created successfully!")
        display_node_details(node)
        if wait and node.status != NodeStatus.CONNECTED:
            info_message("Waiting for node to connect...")
            connected = await node_service.wait_for_node_connection(node.id, timeout=60)
            if connected:
                success_message("Node connected successfully!")
            else:
                error_message("Node failed to connect within timeout")
    except NodeAlreadyExistsError as e:
        error_message(f"Node already exists: {e}")
    except NodeError as e:
        error_message(f"Failed to create node: {e}")


@node.command("update")
@click.argument('node_id', type=int)
@click.option('--name', help='New node name')
@click.option('--address', help='New node IP address')
@click.option('--port', type=int, help='New node port')
@click.option('--api-port', type=int, help='New node API port')
@click.option('--usage-coefficient', type=float, help='New usage coefficient')
@click.option('--status', type=click.Choice(['connected', 'connecting', 'disconnected', 'disabled']), help='New node status')
@click.pass_context
@coro
async def update_node(ctx, node_id, name, address, port, api_port, usage_coefficient, status):
    """Update an existing node."""
    node_service = ctx.obj.node_service
    try:
        status_enum = NodeStatus(status) if status else None
        info_message(f"Updating node {node_id}")
        node = await node_service.update_node(
            node_id=node_id, name=name, address=address, port=port,
            api_port=api_port, usage_coefficient=usage_coefficient, status=status_enum
        )
        success_message(f"Node {node_id} updated successfully!")
        display_node_details(node)
    except NodeNotFoundError as e:
        error_message(f"Node not found: {e}")
    except NodeError as e:
        error_message(f"Failed to update node: {e}")


@node.command("delete")
@click.argument('node_id', type=int)
@click.option('--force', is_flag=True, help='Force deletion without confirmation')
@click.pass_context
@coro
async def delete_node(ctx, node_id, force):
    """Delete a node."""
    node_service = ctx.obj.node_service
    try:
        node = await node_service.get_node(node_id)
        if not force:
            click.echo(f"
Node to delete:")
            display_node_details(node)
            if not click.confirm(f"
Are you sure you want to delete node {node_id} ({node.name})?"):
                info_message("Deletion cancelled")
                return
        info_message(f"Deleting node {node_id}")
        await node_service.delete_node(node_id)
        success_message(f"Node {node_id} ({node.name}) deleted successfully!")
    except NodeNotFoundError as e:
        error_message(f"Node not found: {e}")
    except NodeError as e:
        error_message(f"Failed to delete node: {e}")


@node.command("reconnect")
@click.argument('node_id', type=int)
@click.option('--wait/--no-wait', default=True, help='Wait for node to connect (default: True)')
@click.pass_context
@coro
async def reconnect_node(ctx, node_id, wait):
    """Reconnect a node."""
    node_service = ctx.obj.node_service
    try:
        info_message(f"Reconnecting node {node_id}")
        await node_service.reconnect_node(node_id)
        success_message(f"Reconnection triggered for node {node_id}")
        if wait:
            info_message("Waiting for node to connect...")
            connected = await node_service.wait_for_node_connection(node_id, timeout=60)
            if connected:
                success_message("Node reconnected successfully!")
            else:
                error_message("Node failed to reconnect within timeout")
    except NodeNotFoundError as e:
        error_message(f"Node not found: {e}")
    except NodeError as e:
        error_message(f"Failed to reconnect node: {e}")


@node.command("enable")
@click.argument('node_id', type=int)
@click.pass_context
@coro
async def enable_node(ctx, node_id):
    """Enable a disabled node."""
    node_service = ctx.obj.node_service
    try:
        info_message(f"Enabling node {node_id}")
        node = await node_service.enable_node(node_id)
        success_message(f"Node {node_id} enabled successfully!")
        display_node_details(node)
    except NodeNotFoundError as e:
        error_message(f"Node not found: {e}")
    except NodeError as e:
        error_message(f"Failed to enable node: {e}")


@node.command("disable")
@click.argument('node_id', type=int)
@click.pass_context
@coro
async def disable_node(ctx, node_id):
    """Disable a node."""
    node_service = ctx.obj.node_service
    try:
        info_message(f"Disabling node {node_id}")
        node = await node_service.disable_node(node_id)
        success_message(f"Node {node_id} disabled successfully!")
        display_node_details(node)
    except NodeNotFoundError as e:
        error_message(f"Node not found: {e}")
    except NodeError as e:
        error_message(f"Failed to disable node: {e}")


@node.command("status")
@click.pass_context
@coro
async def status_summary(ctx):
    """Show node status summary."""
    node_service = ctx.obj.node_service
    try:
        summary = await node_service.get_node_status_summary()
        display_status_summary(summary)
    except NodeError as e:
        error_message(f"Failed to get status summary: {e}")


@node.command("usage")
@click.option('--days', default=30, help='Number of days to look back (default: 30)')
@click.option('--format', 'output_format', default='table', type=click.Choice(['table', 'json']), help='Output format')
@click.pass_context
@coro
async def usage_stats(ctx, days, output_format):
    """Show node usage statistics."""
    node_service = ctx.obj.node_service
    try:
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)
        info_message(f"Fetching usage statistics for last {days} days")
        usage_stats = await node_service.get_node_usage(start_date, end_date)
        if output_format == 'json':
            usage_data = [usage.to_dict() for usage in usage_stats]
            click.echo(json.dumps(usage_data, indent=2))
        else:
            display_usage_table(usage_stats, days)
    except NodeError as e:
        error_message(f"Failed to get usage statistics: {e}")

@node.command("healthy")
@click.pass_context
@coro
async def healthy_nodes(ctx):
    """List healthy nodes."""
    node_service = ctx.obj.node_service
    try:
        nodes = await node_service.get_healthy_nodes()
        if nodes:
            success_message(f"Found {len(nodes)} healthy nodes:")
            display_nodes_table(nodes)
        else:
            info_message("No healthy nodes found")
    except NodeError as e:
        error_message(f"Failed to get healthy nodes: {e}")


@node.command("unhealthy")
@click.pass_context
@coro
async def unhealthy_nodes(ctx):
    """List unhealthy nodes."""
    node_service = ctx.obj.node_service
    try:
        nodes = await node_service.get_unhealthy_nodes()
        if nodes:
            error_message(f"Found {len(nodes)} unhealthy nodes:")
            display_nodes_table(nodes)
        else:
            success_message("All nodes are healthy!")
    except NodeError as e:
        error_message(f"Failed to get unhealthy nodes: {e}")


@node.command("settings")
@click.pass_context
@coro
async def node_settings(ctx):
    """Show node settings."""
    node_service = ctx.obj.node_service
    try:
        settings = await node_service.get_node_settings()
        click.echo("
" + "="*50)
        click.echo("NODE SETTINGS")
        click.echo("="*50)
        click.echo(f"Minimum Node Version: {settings.min_node_version}")
        click.echo(f"Certificate Length: {len(settings.certificate)} characters")
        click.echo("="*50)
        if click.confirm("Show full certificate?"):
            click.echo("
TLS Certificate:")
            click.echo("-" * 50)
            click.echo(settings.certificate)
    except NodeError as e:
        error_message(f"Failed to get node settings: {e}")
