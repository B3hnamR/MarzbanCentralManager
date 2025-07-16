"""CLI commands for real-time monitoring."""

import asyncio
import click
from datetime import datetime

from ...services.monitoring_service import monitoring_service
from ...cli.ui.enhanced_display import ProgressBar, ProgressConfig, ProgressStyle
from ...core.utils import format_duration
from ..utils import coro
from ..ui.display import success_message, error_message, info_message


@click.group()
def monitor():
    """Real-time monitoring commands."""
    pass


@monitor.command()
@click.option('--interval', '-i', default=30, help='Monitoring interval in seconds')
@click.option('--duration', '-d', default=0, help='Monitoring duration in seconds (0 = infinite)')
@click.option('--alerts-only', is_flag=True, help='Show only alerts')
@coro
async def start(interval: int, duration: int, alerts_only: bool):
    """Start real-time monitoring."""
    info_message("🔍 Starting real-time monitoring...")
    
    monitoring_service.set_monitoring_interval(interval)
    
    update_count = 0
    start_time = datetime.now()
    
    async def update_callback(data):
        nonlocal update_count
        update_count += 1
        
        if not alerts_only:
            click.clear()
            click.echo("=" * 80)
            click.echo(f"🔍 REAL-TIME MONITORING (Update #{update_count})")
            click.echo(f"Started: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
            click.echo(f"Interval: {interval}s | Duration: {format_duration(duration) if duration else 'Infinite'}")
            click.echo("=" * 80)
            
            system_metrics = data.get('system_metrics', {})
            click.echo(f"
📊 SYSTEM OVERVIEW:")
            # ... (display logic remains the same)

        alerts = await monitoring_service.get_alerts()
        if alerts:
            # ... (display logic remains the same)
            pass

        if not alerts_only:
            click.echo(f"
Press Ctrl+C to stop monitoring...")

    monitoring_service.subscribe_to_updates(update_callback)
    
    try:
        await monitoring_service.start_monitoring()
        
        if duration > 0:
            await asyncio.sleep(duration)
            info_message(f"
⏰ Monitoring completed after {format_duration(duration)}")
        else:
            while True:
                await asyncio.sleep(1)
    
    except KeyboardInterrupt:
        info_message(f"
⏹️  Monitoring stopped by user")
    
    finally:
        monitoring_service.unsubscribe_from_updates(update_callback)
        await monitoring_service.stop_monitoring()


@monitor.command()
@coro
async def status():
    """Show current monitoring status."""
    if monitoring_service.is_monitoring:
        success_message("✅ Monitoring is active")
        metrics = await monitoring_service.get_current_metrics()
        # ... (display logic remains the same)
    else:
        error_message("❌ Monitoring is not active")
        info_message("Use 'monitor start' to begin monitoring")


@monitor.command()
@coro
async def stop():
    """Stop monitoring."""
    if monitoring_service.is_monitoring:
        await monitoring_service.stop_monitoring()
        success_message("⏹️  Monitoring stopped")
    else:
        error_message("❌ Monitoring is not running")


@monitor.command()
@click.argument('node_id', type=int)
@click.option('--limit', '-l', default=20, help='Number of historical records to show')
@coro
async def history(node_id: int, limit: int):
    """Show historical metrics for a node."""
    info_message(f"📈 Historical metrics for Node {node_id}")
    try:
        history_data = await monitoring_service.get_node_history(node_id, limit)
        if not history_data:
            info_message("❌ No historical data found for this node")
            return
        # ... (display logic remains the same)
    except Exception as e:
        error_message(f"❌ Error retrieving history: {e}")


@monitor.command()
@coro
async def alerts():
    """Show current alerts."""
    info_message("🚨 Current Alerts")
    try:
        alerts = await monitoring_service.get_alerts()
        if not alerts:
            success_message("✅ No active alerts")
            return
        # ... (display logic remains the same)
    except Exception as e:
        error_message(f"❌ Error retrieving alerts: {e}")


@monitor.command()
@coro
async def summary():
    """Show monitoring summary."""
    info_message("📊 Monitoring Summary")
    try:
        summary = await monitoring_service.get_health_summary()
        # ... (display logic remains the same)
    except Exception as e:
        error_message(f"❌ Error retrieving summary: {e}")


@monitor.command()
@coro
async def force_update():
    """Force immediate metrics update."""
    info_message("🔄 Forcing metrics update...")
    try:
        await monitoring_service.force_update()
        success_message("✅ Metrics updated successfully")
        summary = await monitoring_service.get_health_summary()
        # ... (display logic remains the same)
    except Exception as e:
        error_message(f"❌ Error updating metrics: {e}")
