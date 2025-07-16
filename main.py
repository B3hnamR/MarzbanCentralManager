#!/usr/bin/env python3
"""
Marzban Central Manager v4.0
Professional API-Based Management System

A comprehensive, API-driven management system for Marzban panel and nodes.
"""

import sys
import asyncio
import click
from pathlib import Path

# Add src to Python path
sys.path.insert(0, str(Path(__file__).parent / "src"))

from src.core.config import config_manager, MarzbanConfig
from src.core.logger import logger
from src.api.base import BaseAPIClient
from src.services.node_service import NodeService
from src.services.monitoring_service import MonitoringService
from src.services.discovery_service import DiscoveryService
# Import other services here as they are implemented
# from src.services.user_service import UserService
# from src.services.system_service import SystemService

from src.cli.commands.node import node
from src.cli.commands.monitor import monitor
from src.cli.commands.discover import discover
from src.cli.ui.display import (
    display_header, success_message, error_message, info_message,
    confirm_action, prompt_for_input
)


class AppContext:
    """
    A context object to hold application-wide instances like services.
    This avoids re-creating services for every command.
    """
    def __init__(self):
        self.config = config_manager.load_config()
        
        # Initialize services
        self.node_service = NodeService()
        self.monitoring_service = MonitoringService()
        self.discovery_service = DiscoveryService()
        # self.user_service = UserService() # Uncomment when implemented
        # self.system_service = SystemService() # Uncomment when implemented

    async def close_services(self):
        """Gracefully close all service connections."""
        await self.node_service.close()
        # Add other services' close methods here
        logger.debug("All services closed.")

@click.group()
@click.option('--debug', is_flag=True, help='Enable debug mode')
@click.option('--log-file', help='Log file path')
@click.pass_context
def cli(ctx, debug, log_file):
    """Marzban Central Manager - Professional API-Based Management System."""
    # Create and store the main context object
    ctx.obj = AppContext()

    # Override config with CLI options
    if debug:
        ctx.obj.config.debug = True
        ctx.obj.config.log_level = "DEBUG"
    
    if log_file:
        ctx.obj.config.log_file = log_file
    
    # Configure logger
    logger.configure(
        level=ctx.obj.config.log_level,
        log_file=ctx.obj.config.log_file,
        debug=ctx.obj.config.debug
    )
    
    # Register a finalizer to close services
    @ctx.call_on_close
    def cleanup():
        async def do_cleanup():
            if ctx.obj:
                await ctx.obj.close_services()
        asyncio.run(do_cleanup())


@cli.group()
def config():
    """Configuration management commands."""
    pass


@config.command()
@click.pass_context
def setup(ctx):
    """Setup Marzban panel connection."""
    display_header("Marzban Panel Configuration")
    info_message("Please provide your Marzban panel connection details:")
    
    current_config = ctx.obj.config
    
    base_url = prompt_for_input(
        "Panel URL (e.g., https://panel.example.com:8000)",
        default=current_config.marzban.base_url if current_config.marzban else None
    )
    username = prompt_for_input(
        "Admin Username",
        default=current_config.marzban.username if current_config.marzban else None
    )
    password = prompt_for_input("Admin Password", hide_input=True)
    
    async def test_connection():
        test_config = MarzbanConfig(base_url=base_url, username=username, password=password)
        async with BaseAPIClient(test_config) as client:
            return await client.test_connection()
    
    info_message("Testing connection...")
    
    try:
        if asyncio.run(test_connection()):
            success_message("Connection test successful!")
            config_manager.update_marzban_config(base_url, username, password)
            success_message("Configuration saved successfully!")
        else:
            error_message("Connection test failed!")
            if confirm_action("Save configuration anyway?"):
                config_manager.update_marzban_config(base_url, username, password)
                info_message("Configuration saved (connection test failed)")
            else:
                info_message("Configuration not saved")
    except Exception as e:
        error_message(f"Connection test error: {e}")
        if confirm_action("Save configuration anyway?"):
            config_manager.update_marzban_config(base_url, username, password)
            info_message("Configuration saved (connection test failed)")


@config.command()
@click.pass_context
def show(ctx):
    """Show current configuration."""
    config = ctx.obj.config
    display_header("Current Configuration")
    
    click.echo(f"Debug Mode: {config.debug}")
    click.echo(f"Log Level: {config.log_level}")
    click.echo(f"Log File: {config.log_file or 'Console only'}")
    
    if config.marzban and config.marzban.base_url:
        click.echo(f"
Marzban Panel:")
        click.echo(f"  URL: {config.marzban.base_url}")
        click.echo(f"  Username: {config.marzban.username}")
        click.echo(f"  Password: {'*' * len(config.marzban.password) if config.marzban.password else 'Not set'}")
    else:
        click.echo(f"
Marzban Panel: Not configured")

@config.command()
def test():
    """Test Marzban panel connection."""
    if not config_manager.is_marzban_configured():
        error_message("Marzban panel is not configured!")
        info_message("Run 'python main.py config setup' to configure the connection.")
        return
    
    async def do_test():
        config = config_manager.load_config()
        async with BaseAPIClient(config.marzban) as client:
            return await client.test_connection()

    info_message("Testing Marzban panel connection...")
    try:
        if asyncio.run(do_test()):
            success_message("Connection test successful!")
        else:
            error_message("Connection test failed!")
    except Exception as e:
        error_message(f"Connection test error: {e}")

@cli.command()
def interactive():
    """Start interactive mode with professional menu system."""
    from src.cli.ui.menus import start_interactive_menu
    
    try:
        asyncio.run(start_interactive_menu())
    except KeyboardInterrupt:
        info_message("
👋 Goodbye! Thanks for using Marzban Central Manager")
    except Exception as e:
        error_message(f"Interactive mode error: {e}")

# Add command groups
cli.add_command(node)
cli.add_command(monitor)
cli.add_command(discover)

@cli.command()
def version():
    """Show version information."""
    click.echo("Marzban Central Manager v4.0")

if __name__ == '__main__':
    try:
        cli(obj={})
    except KeyboardInterrupt:
        info_message("
Operation cancelled by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}", exc_info=True)
        error_message(f"Unexpected error: {e}")
        sys.exit(1)
