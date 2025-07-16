"""CLI commands for auto-discovery of nodes."""

import asyncio
import click
from typing import Optional
from tabulate import tabulate

from ...services.discovery_service import discovery_service, DiscoveryConfig, DiscoveryMethod
from ...services.node_service import NodeService
from ...cli.ui.enhanced_display import ProgressBar, ProgressConfig, ProgressStyle
from ...core.utils import is_valid_ip


@click.group()
def discover():
    """Auto-discovery commands for finding nodes."""
    pass


@discover.command()
@click.option('--network', '-n', help='Network range (e.g., 192.168.1.0/24)')
@click.option('--timeout', '-t', default=5, help='Connection timeout in seconds')
@click.option('--max-concurrent', '-c', default=50, help='Maximum concurrent scans')
@click.option('--deep-scan', is_flag=True, help='Perform deep scan for more details')
@click.option('--ports', '-p', help='Comma-separated list of ports to scan')
async def network(network: Optional[str], timeout: int, max_concurrent: int, deep_scan: bool, ports: Optional[str]):
    """Discover nodes in a network range."""
    
    if not network:
        # Auto-discover local networks
        click.echo("🔍 Auto-discovering local networks...")
        
        try:
            config = DiscoveryConfig(
                timeout=timeout,
                max_concurrent=max_concurrent,
                deep_scan=deep_scan
            )
            
            if ports:
                config.target_ports = [int(p.strip()) for p in ports.split(',')]
            
            # Progress tracking
            progress = ProgressBar(100, ProgressConfig(style=ProgressStyle.BAR, show_eta=True))
            
            async def progress_callback(current, total, message):
                if total > 0:
                    percentage = int((current / total) * 100)
                    progress.set_progress(percentage, message)
            
            discovered = await discovery_service.discover_local_network(config, progress_callback)
            progress.finish("Discovery completed!")
            
        except Exception as e:
            click.echo(f"❌ Auto-discovery failed: {e}")
            return
    
    else:
        # Scan specified network
        click.echo(f"🔍 Scanning network: {network}")
        
        try:
            config = DiscoveryConfig(
                timeout=timeout,
                max_concurrent=max_concurrent,
                deep_scan=deep_scan
            )
            
            if ports:
                config.target_ports = [int(p.strip()) for p in ports.split(',')]
            
            # Progress tracking
            progress = ProgressBar(100, ProgressConfig(style=ProgressStyle.BAR, show_eta=True))
            
            async def progress_callback(current, total, message):
                if total > 0:
                    percentage = int((current / total) * 100)
                    progress.set_progress(percentage, message)
            
            discovered = await discovery_service.discover_network_range(network, config, progress_callback)
            progress.finish("Network scan completed!")
            
        except Exception as e:
            click.echo(f"❌ Network scan failed: {e}")
            return
    
    # Display results
    if discovered:
        click.echo(f"\n✅ Found {len(discovered)} nodes:")
        _display_discovered_nodes(discovered)
        
        # Show Marzban candidates
        marzban_candidates = [node for node in discovered if node.marzban_node_detected or node.confidence_score >= 70]
        if marzban_candidates:
            click.echo(f"\n🎯 Potential Marzban nodes ({len(marzban_candidates)}):")
            _display_discovered_nodes(marzban_candidates, highlight_marzban=True)
    else:
        click.echo("❌ No nodes found in the specified network")


@discover.command()
@click.argument('start_ip')
@click.argument('end_ip')
@click.option('--timeout', '-t', default=5, help='Connection timeout in seconds')
@click.option('--max-concurrent', '-c', default=50, help='Maximum concurrent scans')
@click.option('--deep-scan', is_flag=True, help='Perform deep scan for more details')
@click.option('--ports', '-p', help='Comma-separated list of ports to scan')
async def range(start_ip: str, end_ip: str, timeout: int, max_concurrent: int, deep_scan: bool, ports: Optional[str]):
    """Discover nodes in an IP range."""
    
    # Validate IP addresses
    if not is_valid_ip(start_ip):
        click.echo(f"❌ Invalid start IP address: {start_ip}")
        return
    
    if not is_valid_ip(end_ip):
        click.echo(f"❌ Invalid end IP address: {end_ip}")
        return
    
    click.echo(f"🔍 Scanning IP range: {start_ip} - {end_ip}")
    
    try:
        config = DiscoveryConfig(
            timeout=timeout,
            max_concurrent=max_concurrent,
            deep_scan=deep_scan
        )
        
        if ports:
            config.target_ports = [int(p.strip()) for p in ports.split(',')]
        
        # Progress tracking
        progress = ProgressBar(100, ProgressConfig(style=ProgressStyle.BAR, show_eta=True))
        
        async def progress_callback(current, total, message):
            if total > 0:
                percentage = int((current / total) * 100)
                progress.set_progress(percentage, message)
        
        discovered = await discovery_service.discover_ip_range(start_ip, end_ip, config, progress_callback)
        progress.finish("IP range scan completed!")
        
        # Display results
        if discovered:
            click.echo(f"\n✅ Found {len(discovered)} nodes:")
            _display_discovered_nodes(discovered)
            
            # Show Marzban candidates
            marzban_candidates = [node for node in discovered if node.marzban_node_detected or node.confidence_score >= 70]
            if marzban_candidates:
                click.echo(f"\n🎯 Potential Marzban nodes ({len(marzban_candidates)}):")
                _display_discovered_nodes(marzban_candidates, highlight_marzban=True)
        else:
            click.echo("❌ No nodes found in the specified range")
    
    except Exception as e:
        click.echo(f"❌ IP range scan failed: {e}")


@discover.command()
async def list():
    """List all discovered nodes."""
    discovered = discovery_service.get_discovered_nodes()
    
    if not discovered:
        click.echo("❌ No discovered nodes found")
        click.echo("Use 'discover network' or 'discover range' to find nodes")
        return
    
    click.echo(f"📋 Discovered Nodes ({len(discovered)}):")
    _display_discovered_nodes(discovered)


@discover.command()
async def candidates():
    """Show Marzban node candidates."""
    candidates = discovery_service.get_marzban_candidates()
    
    if not candidates:
        click.echo("❌ No Marzban node candidates found")
        click.echo("Use 'discover network --deep-scan' to find potential nodes")
        return
    
    click.echo(f"🎯 Marzban Node Candidates ({len(candidates)}):")
    _display_discovered_nodes(candidates, highlight_marzban=True)
    
    # Show validation results
    click.echo(f"\n🔍 Validation Results:")
    click.echo("-" * 80)
    
    for candidate in candidates:
        click.echo(f"\n📍 {candidate.ip_address} ({candidate.hostname or 'Unknown hostname'})")
        
        try:
            validation = await discovery_service.validate_discovered_node(candidate)
            
            if validation["valid"]:
                click.echo(click.style("  ✅ Valid Marzban node", fg='green'))
            else:
                click.echo(click.style("  ❌ Validation failed", fg='red'))
            
            if validation["issues"]:
                click.echo("  Issues:")
                for issue in validation["issues"]:
                    click.echo(f"    • {issue}")
            
            if validation["recommendations"]:
                click.echo("  Recommendations:")
                for rec in validation["recommendations"]:
                    click.echo(f"    • {rec}")
            
            click.echo(f"  Confidence: {validation['confidence']:.1f}%")
        
        except Exception as e:
            click.echo(f"  ❌ Validation error: {e}")


@discover.command()
@click.argument('ip_address')
async def validate(ip_address: str):
    """Validate a specific IP as a potential Marzban node."""
    
    if not is_valid_ip(ip_address):
        click.echo(f"❌ Invalid IP address: {ip_address}")
        return
    
    click.echo(f"🔍 Validating {ip_address} as Marzban node...")
    
    # Check if already discovered
    discovered = discovery_service.get_discovered_nodes()
    node = next((n for n in discovered if n.ip_address == ip_address), None)
    
    if not node:
        # Perform quick scan
        click.echo("📡 Node not in cache, performing quick scan...")
        
        config = DiscoveryConfig(deep_scan=True, timeout=10)
        
        try:
            # Scan single host
            from ...services.discovery_service import DiscoveredNode
            
            # Create a temporary discovered node for validation
            node = DiscoveredNode(ip_address=ip_address)
            
            # Quick port scan
            from ...core.utils import is_port_open
            
            common_ports = [62050, 62051, 22, 80, 443, 8080]
            open_ports = []
            
            for port in common_ports:
                if await asyncio.get_event_loop().run_in_executor(None, is_port_open, ip_address, port, 3):
                    open_ports.append(port)
            
            node.open_ports = open_ports
            
            # Check for Marzban indicators
            marzban_ports = [62050, 62051]
            node.marzban_node_detected = any(port in open_ports for port in marzban_ports)
            
        except Exception as e:
            click.echo(f"❌ Quick scan failed: {e}")
            return
    
    # Validate the node
    try:
        validation = await discovery_service.validate_discovered_node(node)
        
        click.echo(f"\n📊 Validation Results for {ip_address}:")
        click.echo("-" * 50)
        
        if validation["valid"]:
            click.echo(click.style("✅ Valid Marzban node", fg='green', bold=True))
        else:
            click.echo(click.style("❌ Not a valid Marzban node", fg='red', bold=True))
        
        click.echo(f"Confidence Score: {validation['confidence']:.1f}%")
        
        if node.open_ports:
            click.echo(f"Open Ports: {', '.join(map(str, node.open_ports))}")
        
        if node.marzban_node_detected:
            click.echo(click.style("🎯 Marzban node detected!", fg='green'))
        
        if validation["issues"]:
            click.echo(f"\n❌ Issues ({len(validation['issues'])}):")
            for issue in validation["issues"]:
                click.echo(f"  • {issue}")
        
        if validation["recommendations"]:
            click.echo(f"\n💡 Recommendations ({len(validation['recommendations'])}):")
            for rec in validation["recommendations"]:
                click.echo(f"  • {rec}")
        
        # Suggest adding to nodes
        if validation["valid"]:
            click.echo(f"\n💡 This node can be added to your Marzban Central Manager:")
            click.echo(f"   mcm nodes add --name 'Discovered Node' --address {ip_address}")
    
    except Exception as e:
        click.echo(f"❌ Validation failed: {e}")


@discover.command()
@click.argument('ip_address')
@click.option('--name', '-n', prompt=True, help='Name for the new node')
@click.option('--port', '-p', default=62050, help='Node port')
@click.option('--api-port', '-a', default=62051, help='API port')
async def add(ip_address: str, name: str, port: int, api_port: int):
    """Add a discovered node to the node list."""
    
    if not is_valid_ip(ip_address):
        click.echo(f"❌ Invalid IP address: {ip_address}")
        return
    
    # Validate the node first
    click.echo(f"🔍 Validating {ip_address} before adding...")
    
    discovered = discovery_service.get_discovered_nodes()
    node = next((n for n in discovered if n.ip_address == ip_address), None)
    
    if node:
        validation = await discovery_service.validate_discovered_node(node)
        
        if not validation["valid"]:
            click.echo(f"❌ Node validation failed:")
            for issue in validation["issues"]:
                click.echo(f"  • {issue}")
            
            if not click.confirm("Do you want to add this node anyway?"):
                return
    
    # Add the node
    try:
        node_service = NodeService()
        
        click.echo(f"➕ Adding node: {name} ({ip_address})")
        
        new_node = await node_service.create_node(
            name=name,
            address=ip_address,
            port=port,
            api_port=api_port
        )
        
        click.echo(click.style(f"✅ Node added successfully!", fg='green'))
        click.echo(f"Node ID: {new_node.id}")
        click.echo(f"Name: {new_node.name}")
        click.echo(f"Address: {new_node.address}:{new_node.port}")
        click.echo(f"Status: {new_node.status.value}")
        
        await node_service.close()
    
    except Exception as e:
        click.echo(f"❌ Failed to add node: {e}")


@discover.command()
async def clear():
    """Clear discovered nodes cache."""
    if click.confirm("Are you sure you want to clear all discovered nodes?"):
        discovery_service.clear_discovered_nodes()
        click.echo("✅ Discovered nodes cache cleared")
    else:
        click.echo("❌ Operation cancelled")


@discover.command()
async def stop():
    """Stop ongoing discovery scan."""
    discovery_service.stop_discovery()
    click.echo("⏹️  Discovery scan stopped")


def _display_discovered_nodes(nodes, highlight_marzban=False):
    """Display discovered nodes in a table."""
    if not nodes:
        return
    
    # Prepare table data
    headers = ["IP Address", "Hostname", "Open Ports", "Response", "Marzban", "Confidence", "Method"]
    table_data = []
    
    for node in nodes:
        # Format open ports
        ports_str = ", ".join(map(str, node.open_ports[:5]))  # Show first 5 ports
        if len(node.open_ports) > 5:
            ports_str += f" (+{len(node.open_ports) - 5})"
        
        # Format response time
        response_str = f"{node.response_time:.1f}ms" if node.response_time else "N/A"
        
        # Marzban detection
        marzban_str = "✅" if node.marzban_node_detected else "❌"
        
        # Confidence score
        confidence_str = f"{node.confidence_score:.1f}%"
        
        # Discovery method
        method_str = node.discovery_method.value if node.discovery_method else "N/A"
        
        row = [
            node.ip_address,
            node.hostname or "Unknown",
            ports_str or "None",
            response_str,
            marzban_str,
            confidence_str,
            method_str
        ]
        
        table_data.append(row)
    
    # Sort by confidence score (descending)
    table_data.sort(key=lambda x: float(x[5].replace('%', '')), reverse=True)
    
    # Display table
    click.echo(tabulate(table_data, headers=headers, tablefmt="grid"))
    
    if highlight_marzban:
        click.echo(f"\n💡 Tip: Use 'discover validate <ip>' to get detailed validation")
        click.echo(f"💡 Tip: Use 'discover add <ip>' to add a node to your list")


# Add the discover group to the main CLI
if __name__ == '__main__':
    discover()