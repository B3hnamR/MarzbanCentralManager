"""Display utilities for CLI interface."""

import click
from typing import List, Dict, Any
from tabulate import tabulate

from ...models.node import Node, NodeUsage
from ...core.utils import format_bytes, truncate_string


def success_message(message: str):
    """Display success message."""
    click.echo(click.style(f"✅ {message}", fg='green'))


def error_message(message: str):
    """Display error message."""
    click.echo(click.style(f"❌ {message}", fg='red'))


def warning_message(message: str):
    """Display warning message."""
    click.echo(click.style(f"⚠️  {message}", fg='yellow'))


def info_message(message: str):
    """Display info message."""
    click.echo(click.style(f"ℹ️  {message}", fg='blue'))


def display_nodes_table(nodes: List[Node]):
    """Display nodes in a table format."""
    if not nodes:
        info_message("No nodes found")
        return
    
    headers = ["ID", "Name", "Address", "Port", "API Port", "Status", "Version", "Coefficient"]
    rows = []
    
    for node in nodes:
        rows.append([
            node.id,
            truncate_string(node.name, 20),
            node.address,
            node.port,
            node.api_port,
            node.display_status,
            node.xray_version or "N/A",
            f"{node.usage_coefficient:.1f}"
        ])
    
    click.echo("\n" + "="*80)
    click.echo(f"NODES ({len(nodes)} total)")
    click.echo("="*80)
    click.echo(tabulate(rows, headers=headers, tablefmt="grid"))
    click.echo("="*80)


def display_node_details(node: Node):
    """Display detailed information about a node."""
    click.echo("\n" + "="*50)
    click.echo("NODE DETAILS")
    click.echo("="*50)
    click.echo(f"ID: {node.id}")
    click.echo(f"Name: {node.name}")
    click.echo(f"Address: {node.address}")
    click.echo(f"Port: {node.port}")
    click.echo(f"API Port: {node.api_port}")
    click.echo(f"Status: {node.display_status}")
    click.echo(f"Usage Coefficient: {node.usage_coefficient}")
    click.echo(f"Xray Version: {node.xray_version or 'N/A'}")
    
    if node.message:
        click.echo(f"Message: {node.message}")
    
    click.echo("="*50)


def display_usage_table(usage_stats: List[NodeUsage], days: int):
    """Display usage statistics in a table format."""
    if not usage_stats:
        info_message(f"No usage data found for the last {days} days")
        return
    
    headers = ["Node ID", "Node Name", "Uplink", "Downlink", "Total"]
    rows = []
    
    total_uplink = 0
    total_downlink = 0
    
    for usage in usage_stats:
        rows.append([
            usage.node_id,
            truncate_string(usage.node_name, 25),
            usage.formatted_uplink,
            usage.formatted_downlink,
            usage.formatted_total
        ])
        
        total_uplink += usage.uplink
        total_downlink += usage.downlink
    
    # Add total row
    rows.append([
        "TOTAL",
        f"{len(usage_stats)} nodes",
        format_bytes(total_uplink),
        format_bytes(total_downlink),
        format_bytes(total_uplink + total_downlink)
    ])
    
    click.echo("\n" + "="*80)
    click.echo(f"NODE USAGE STATISTICS (Last {days} days)")
    click.echo("="*80)
    click.echo(tabulate(rows, headers=headers, tablefmt="grid"))
    click.echo("="*80)


def display_status_summary(summary: Dict[str, int]):
    """Display node status summary."""
    total = summary.get("total", 0)
    connected = summary.get("connected", 0)
    connecting = summary.get("connecting", 0)
    disconnected = summary.get("disconnected", 0)
    disabled = summary.get("disabled", 0)
    error = summary.get("error", 0)
    
    click.echo("\n" + "="*50)
    click.echo("NODE STATUS SUMMARY")
    click.echo("="*50)
    click.echo(f"Total Nodes: {total}")
    click.echo(f"🟢 Connected: {connected}")
    click.echo(f"🟡 Connecting: {connecting}")
    click.echo(f"🔴 Disconnected: {disconnected}")
    click.echo(f"⚫ Disabled: {disabled}")
    click.echo(f"❌ Error: {error}")
    
    if total > 0:
        health_percentage = (connected / total) * 100
        click.echo(f"\nHealth: {health_percentage:.1f}%")
        
        if health_percentage >= 90:
            click.echo(click.style("Status: Excellent", fg='green'))
        elif health_percentage >= 70:
            click.echo(click.style("Status: Good", fg='yellow'))
        else:
            click.echo(click.style("Status: Needs Attention", fg='red'))
    
    click.echo("="*50)


def display_progress_bar(current: int, total: int, description: str = ""):
    """Display a simple progress bar."""
    if total == 0:
        return
    
    percentage = (current / total) * 100
    bar_length = 30
    filled_length = int(bar_length * current // total)
    
    bar = '█' * filled_length + '-' * (bar_length - filled_length)
    
    click.echo(f"\r{description} |{bar}| {percentage:.1f}% ({current}/{total})", nl=False)
    
    if current == total:
        click.echo()  # New line when complete


def confirm_action(message: str, default: bool = False) -> bool:
    """Confirm an action with the user."""
    return click.confirm(message, default=default)


def prompt_for_input(message: str, default: str = None, hide_input: bool = False) -> str:
    """Prompt user for input."""
    return click.prompt(message, default=default, hide_input=hide_input)


def display_header(title: str, width: int = 60):
    """Display a formatted header."""
    click.echo("\n" + "="*width)
    click.echo(title.center(width))
    click.echo("="*width)


def display_separator(width: int = 60):
    """Display a separator line."""
    click.echo("-" * width)


def display_key_value_pairs(data: Dict[str, Any], title: str = None):
    """Display key-value pairs in a formatted way."""
    if title:
        display_header(title)
    
    max_key_length = max(len(str(key)) for key in data.keys()) if data else 0
    
    for key, value in data.items():
        key_str = str(key).ljust(max_key_length)
        click.echo(f"{key_str}: {value}")
    
    if title:
        click.echo("="*60)


def display_list_items(items: List[str], title: str = None, numbered: bool = True):
    """Display a list of items."""
    if title:
        display_header(title)
    
    for i, item in enumerate(items, 1):
        if numbered:
            click.echo(f"{i:2d}. {item}")
        else:
            click.echo(f"   • {item}")
    
    if title:
        click.echo("="*60)


def clear_screen():
    """Clear the terminal screen."""
    click.clear()


def pause(message: str = "Press any key to continue..."):
    """Pause execution and wait for user input."""
    click.pause(message)