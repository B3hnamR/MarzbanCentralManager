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

from src.core.config import config_manager
from src.core.logger import logger
from src.cli.commands.node import node
from src.cli.commands.monitor import monitor
from src.cli.commands.discover import discover
from src.cli.ui.display import (
    display_header, success_message, error_message, info_message,
    confirm_action, prompt_for_input
)


@click.group()
@click.option('--debug', is_flag=True, help='Enable debug mode')
@click.option('--log-file', help='Log file path')
@click.pass_context
def cli(ctx, debug, log_file):
    """Marzban Central Manager - Professional API-Based Management System."""
    # Ensure context object exists
    ctx.ensure_object(dict)
    
    # Load configuration
    config = config_manager.load_config()
    
    # Override config with CLI options
    if debug:
        config.debug = True
        config.log_level = "DEBUG"
    
    if log_file:
        config.log_file = log_file
    
    # Configure logger
    logger.configure(
        level=config.log_level,
        log_file=config.log_file,
        debug=config.debug
    )
    
    # Store config in context
    ctx.obj['config'] = config


@cli.group()
def config():
    """Configuration management commands."""
    pass


@config.command()
def setup():
    """Setup Marzban panel connection."""
    display_header("Marzban Panel Configuration")
    
    info_message("Please provide your Marzban panel connection details:")
    
    # Get current config
    current_config = config_manager.load_config()
    
    # Prompt for configuration
    base_url = prompt_for_input(
        "Panel URL (e.g., https://panel.example.com:8000)",
        default=current_config.marzban.base_url if current_config.marzban else None
    )
    
    username = prompt_for_input(
        "Admin Username",
        default=current_config.marzban.username if current_config.marzban else None
    )
    
    password = prompt_for_input(
        "Admin Password",
        hide_input=True
    )
    
    # Test connection
    async def test_connection():
        from src.api.base import BaseAPIClient
        from src.core.config import MarzbanConfig
        
        test_config = MarzbanConfig(
            base_url=base_url,
            username=username,
            password=password
        )
        
        async with BaseAPIClient(test_config) as client:
            return await client.test_connection()
    
    info_message("Testing connection...")
    
    try:
        if asyncio.run(test_connection()):
            success_message("Connection test successful!")
            
            # Save configuration
            config_manager.update_marzban_config(base_url, username, password)
            success_message("Configuration saved successfully!")
            
        else:
            error_message("Connection test failed!")
            if not confirm_action("Save configuration anyway?"):
                info_message("Configuration not saved")
                return
            
            config_manager.update_marzban_config(base_url, username, password)
            info_message("Configuration saved (connection test failed)")
            
    except Exception as e:
        error_message(f"Connection test error: {e}")
        if confirm_action("Save configuration anyway?"):
            config_manager.update_marzban_config(base_url, username, password)
            info_message("Configuration saved (connection test failed)")


@config.command()
def show():
    """Show current configuration."""
    config = config_manager.load_config()
    
    display_header("Current Configuration")
    
    click.echo(f"Debug Mode: {config.debug}")
    click.echo(f"Log Level: {config.log_level}")
    click.echo(f"Log File: {config.log_file or 'Console only'}")
    
    if config.marzban:
        click.echo(f"\nMarzban Panel:")
        click.echo(f"  URL: {config.marzban.base_url}")
        click.echo(f"  Username: {config.marzban.username}")
        click.echo(f"  Password: {'*' * len(config.marzban.password) if config.marzban.password else 'Not set'}")
        click.echo(f"  Timeout: {config.marzban.timeout}s")
        click.echo(f"  Verify SSL: {config.marzban.verify_ssl}")
    else:
        click.echo(f"\nMarzban Panel: Not configured")
    
    if config.telegram_bot_token:
        click.echo(f"\nTelegram:")
        click.echo(f"  Bot Token: {'*' * 20}...{config.telegram_bot_token[-10:]}")
        click.echo(f"  Chat ID: {config.telegram_chat_id}")
    else:
        click.echo(f"\nTelegram: Not configured")


@config.command()
def test():
    """Test Marzban panel connection."""
    if not config_manager.is_marzban_configured():
        error_message("Marzban panel is not configured!")
        info_message("Run 'python main.py config setup' to configure the connection.")
        return
    
    async def test_connection():
        from src.api.base import BaseAPIClient
        
        config = config_manager.load_config()
        async with BaseAPIClient(config.marzban) as client:
            return await client.test_connection()
    
    info_message("Testing Marzban panel connection...")
    
    try:
        if asyncio.run(test_connection()):
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
        info_message("\n👋 Goodbye! Thanks for using Marzban Central Manager")
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
    click.echo("Professional API-Based Management System")
    click.echo("Author: B3hnamR")


if __name__ == '__main__':
    try:
        cli()
    except KeyboardInterrupt:
        info_message("\nOperation cancelled by user")
        sys.exit(1)
    except Exception as e:
        error_message(f"Unexpected error: {e}")
        sys.exit(1)