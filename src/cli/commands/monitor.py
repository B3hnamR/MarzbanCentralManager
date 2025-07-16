"""CLI commands for real-time monitoring."""

import asyncio
import click
from typing import Optional
from datetime import datetime

from ...services.monitoring_service import monitoring_service
from ...cli.ui.enhanced_display import ProgressBar, ProgressConfig, ProgressStyle
from ...core.utils import format_duration


@click.group()
def monitor():
    """Real-time monitoring commands."""
    pass


@monitor.command()
@click.option('--interval', '-i', default=30, help='Monitoring interval in seconds')
@click.option('--duration', '-d', default=0, help='Monitoring duration in seconds (0 = infinite)')
@click.option('--alerts-only', is_flag=True, help='Show only alerts')
async def start(interval: int, duration: int, alerts_only: bool):
    """Start real-time monitoring."""
    click.echo("🔍 Starting real-time monitoring...")
    
    # Set monitoring interval
    monitoring_service.set_monitoring_interval(interval)
    
    # Subscribe to updates
    update_count = 0
    start_time = datetime.now()
    
    async def update_callback(data):
        nonlocal update_count
        update_count += 1
        
        if not alerts_only:
            # Clear screen and show current status
            click.clear()
            click.echo("=" * 80)
            click.echo(f"🔍 REAL-TIME MONITORING (Update #{update_count})")
            click.echo(f"Started: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
            click.echo(f"Interval: {interval}s | Duration: {format_duration(duration) if duration else 'Infinite'}")
            click.echo("=" * 80)
            
            # Show system metrics
            system_metrics = data.get('system_metrics', {})
            click.echo(f"\n📊 SYSTEM OVERVIEW:")
            click.echo(f"Total Nodes: {system_metrics.get('total_nodes', 0)}")
            click.echo(f"Healthy: {system_metrics.get('healthy_nodes', 0)} | "
                      f"Warning: {system_metrics.get('warning_nodes', 0)} | "
                      f"Critical: {system_metrics.get('critical_nodes', 0)} | "
                      f"Offline: {system_metrics.get('offline_nodes', 0)}")
            
            health_pct = system_metrics.get('health_percentage', 0)
            if health_pct >= 80:
                health_color = 'green'
            elif health_pct >= 60:
                health_color = 'yellow'
            else:
                health_color = 'red'
            
            click.echo(f"Health: {click.style(f'{health_pct:.1f}%', fg=health_color)}")
            
            # Show node metrics
            node_metrics = data.get('node_metrics', {})
            if node_metrics:
                click.echo(f"\n🖥️  NODE STATUS:")
                click.echo("-" * 80)
                
                for node_id, metrics in node_metrics.items():
                    status = metrics.get('status', 'unknown')
                    health = metrics.get('health_status', 'unknown')
                    response_time = metrics.get('response_time')
                    
                    # Color coding
                    if health == 'healthy':
                        health_color = 'green'
                    elif health == 'warning':
                        health_color = 'yellow'
                    elif health == 'critical':
                        health_color = 'red'
                    else:
                        health_color = 'white'
                    
                    response_str = f"{response_time:.1f}ms" if response_time else "N/A"
                    
                    click.echo(f"{metrics.get('node_name', f'Node {node_id}'):20} | "
                              f"Status: {status:12} | "
                              f"Health: {click.style(health, fg=health_color):15} | "
                              f"Response: {response_str}")
        
        # Always show alerts
        alerts = await monitoring_service.get_alerts()
        if alerts:
            if not alerts_only:
                click.echo(f"\n🚨 ALERTS ({len(alerts)}):")
                click.echo("-" * 80)
            
            for alert in alerts:
                alert_type = alert.get('type', 'info')
                message = alert.get('message', 'Unknown alert')
                
                if alert_type == 'critical':
                    click.echo(click.style(f"🔴 CRITICAL: {message}", fg='red', bold=True))
                elif alert_type == 'warning':
                    click.echo(click.style(f"🟡 WARNING: {message}", fg='yellow'))
                else:
                    click.echo(f"ℹ️  INFO: {message}")
        elif alerts_only:
            click.echo("✅ No alerts at this time")
        
        if not alerts_only:
            click.echo(f"\nPress Ctrl+C to stop monitoring...")
    
    # Subscribe to monitoring updates
    monitoring_service.subscribe_to_updates(update_callback)
    
    try:
        # Start monitoring
        await monitoring_service.start_monitoring()
        
        # Wait for specified duration or until interrupted
        if duration > 0:
            await asyncio.sleep(duration)
            click.echo(f"\n⏰ Monitoring completed after {format_duration(duration)}")
        else:
            # Wait indefinitely
            while True:
                await asyncio.sleep(1)
    
    except KeyboardInterrupt:
        click.echo(f"\n⏹️  Monitoring stopped by user")
    
    finally:
        # Cleanup
        monitoring_service.unsubscribe_from_updates(update_callback)
        await monitoring_service.stop_monitoring()


@monitor.command()
async def status():
    """Show current monitoring status."""
    if monitoring_service.is_monitoring:
        click.echo("✅ Monitoring is active")
        
        # Get current metrics
        metrics = await monitoring_service.get_current_metrics()
        system_metrics = metrics.get('system_metrics', {})
        
        click.echo(f"\n📊 Current Status:")
        click.echo(f"Total Nodes: {system_metrics.get('total_nodes', 0)}")
        click.echo(f"Healthy: {system_metrics.get('healthy_nodes', 0)}")
        click.echo(f"Warning: {system_metrics.get('warning_nodes', 0)}")
        click.echo(f"Critical: {system_metrics.get('critical_nodes', 0)}")
        click.echo(f"Offline: {system_metrics.get('offline_nodes', 0)}")
        
        health_pct = system_metrics.get('health_percentage', 0)
        click.echo(f"Overall Health: {health_pct:.1f}%")
        
        last_updated = system_metrics.get('last_updated')
        if last_updated:
            click.echo(f"Last Updated: {last_updated}")
        
        # Show alerts
        alerts = await monitoring_service.get_alerts()
        if alerts:
            click.echo(f"\n🚨 Active Alerts: {len(alerts)}")
            for alert in alerts[:5]:  # Show first 5 alerts
                alert_type = alert.get('type', 'info')
                message = alert.get('message', 'Unknown alert')
                
                if alert_type == 'critical':
                    click.echo(click.style(f"  🔴 {message}", fg='red'))
                elif alert_type == 'warning':
                    click.echo(click.style(f"  🟡 {message}", fg='yellow'))
        else:
            click.echo("\n✅ No active alerts")
    
    else:
        click.echo("❌ Monitoring is not active")
        click.echo("Use 'monitor start' to begin monitoring")


@monitor.command()
async def stop():
    """Stop monitoring."""
    if monitoring_service.is_monitoring:
        await monitoring_service.stop_monitoring()
        click.echo("⏹️  Monitoring stopped")
    else:
        click.echo("❌ Monitoring is not running")


@monitor.command()
@click.argument('node_id', type=int)
@click.option('--limit', '-l', default=20, help='Number of historical records to show')
async def history(node_id: int, limit: int):
    """Show historical metrics for a node."""
    click.echo(f"📈 Historical metrics for Node {node_id}")
    
    try:
        history_data = await monitoring_service.get_node_history(node_id, limit)
        
        if not history_data:
            click.echo("❌ No historical data found for this node")
            return
        
        click.echo(f"\nShowing last {len(history_data)} records:")
        click.echo("-" * 80)
        click.echo(f"{'Timestamp':20} | {'Status':12} | {'Health':10} | {'Response':10}")
        click.echo("-" * 80)
        
        for record in history_data[-limit:]:
            timestamp = record.last_seen.strftime('%H:%M:%S') if record.last_seen else 'N/A'
            status = record.status.value
            health = record.health_status.value
            response = f"{record.response_time:.1f}ms" if record.response_time else "N/A"
            
            # Color coding for health
            if health == 'healthy':
                health_colored = click.style(health, fg='green')
            elif health == 'warning':
                health_colored = click.style(health, fg='yellow')
            elif health == 'critical':
                health_colored = click.style(health, fg='red')
            else:
                health_colored = health
            
            click.echo(f"{timestamp:20} | {status:12} | {health_colored:20} | {response:10}")
    
    except Exception as e:
        click.echo(f"❌ Error retrieving history: {e}")


@monitor.command()
async def alerts():
    """Show current alerts."""
    click.echo("🚨 Current Alerts")
    
    try:
        alerts = await monitoring_service.get_alerts()
        
        if not alerts:
            click.echo("✅ No active alerts")
            return
        
        click.echo(f"\nFound {len(alerts)} alerts:")
        click.echo("-" * 80)
        
        for i, alert in enumerate(alerts, 1):
            alert_type = alert.get('type', 'info')
            message = alert.get('message', 'Unknown alert')
            timestamp = alert.get('timestamp', '')
            
            if alert_type == 'critical':
                type_colored = click.style('CRITICAL', fg='red', bold=True)
            elif alert_type == 'warning':
                type_colored = click.style('WARNING', fg='yellow')
            else:
                type_colored = click.style('INFO', fg='blue')
            
            click.echo(f"{i:2}. {type_colored} - {message}")
            
            if timestamp:
                click.echo(f"    Time: {timestamp}")
            
            # Show additional details
            if 'node_name' in alert:
                click.echo(f"    Node: {alert['node_name']}")
            
            if 'response_time' in alert:
                click.echo(f"    Response Time: {alert['response_time']:.1f}ms")
            
            click.echo()
    
    except Exception as e:
        click.echo(f"❌ Error retrieving alerts: {e}")


@monitor.command()
async def summary():
    """Show monitoring summary."""
    click.echo("📊 Monitoring Summary")
    
    try:
        summary = await monitoring_service.get_health_summary()
        
        click.echo(f"\n🖥️  Node Overview:")
        click.echo(f"Total Nodes: {summary.get('total_nodes', 0)}")
        click.echo(f"Healthy: {click.style(str(summary.get('healthy', 0)), fg='green')}")
        click.echo(f"Warning: {click.style(str(summary.get('warning', 0)), fg='yellow')}")
        click.echo(f"Critical: {click.style(str(summary.get('critical', 0)), fg='red')}")
        click.echo(f"Offline: {summary.get('offline', 0)}")
        
        health_pct = summary.get('health_percentage', 0)
        if health_pct >= 80:
            health_color = 'green'
        elif health_pct >= 60:
            health_color = 'yellow'
        else:
            health_color = 'red'
        
        click.echo(f"\n📈 Overall Health: {click.style(f'{health_pct:.1f}%', fg=health_color)}")
        
        last_updated = summary.get('last_updated')
        if last_updated:
            click.echo(f"Last Updated: {last_updated}")
        
        # Show alerts count
        alerts = await monitoring_service.get_alerts()
        alert_count = len(alerts)
        
        if alert_count > 0:
            critical_count = sum(1 for a in alerts if a.get('type') == 'critical')
            warning_count = sum(1 for a in alerts if a.get('type') == 'warning')
            
            click.echo(f"\n🚨 Active Alerts: {alert_count}")
            if critical_count > 0:
                click.echo(f"  Critical: {click.style(str(critical_count), fg='red')}")
            if warning_count > 0:
                click.echo(f"  Warning: {click.style(str(warning_count), fg='yellow')}")
        else:
            click.echo(f"\n✅ No active alerts")
    
    except Exception as e:
        click.echo(f"❌ Error retrieving summary: {e}")


@monitor.command()
async def force_update():
    """Force immediate metrics update."""
    click.echo("🔄 Forcing metrics update...")
    
    try:
        await monitoring_service.force_update()
        click.echo("✅ Metrics updated successfully")
        
        # Show updated summary
        summary = await monitoring_service.get_health_summary()
        click.echo(f"\n📊 Updated Status:")
        click.echo(f"Total Nodes: {summary.get('total_nodes', 0)}")
        click.echo(f"Health: {summary.get('health_percentage', 0):.1f}%")
        
    except Exception as e:
        click.echo(f"❌ Error updating metrics: {e}")


# Add the monitor group to the main CLI
if __name__ == '__main__':
    monitor()