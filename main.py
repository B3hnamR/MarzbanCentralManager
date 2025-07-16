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
    """Start interactive mode."""
    display_header("Marzban Central Manager - Interactive Mode")
    
    if not config_manager.is_marzban_configured():
        error_message("Marzban panel is not configured!")
        if confirm_action("Would you like to configure it now?"):
            ctx = click.get_current_context()
            ctx.invoke(setup)
        else:
            return
    
    while True:
        click.echo("\n" + "="*50)
        click.echo("MAIN MENU")
        click.echo("="*50)
        click.echo("1. Node Management")
        click.echo("2. User Management (Coming Soon)")
        click.echo("3. System Monitoring (Coming Soon)")
        click.echo("4. Configuration")
        click.echo("5. Exit")
        click.echo("="*50)
        
        choice = click.prompt("Choose an option", type=int)
        
        if choice == 1:
            node_menu()
        elif choice == 2:
            info_message("User management features coming soon!")
        elif choice == 3:
            info_message("System monitoring features coming soon!")
        elif choice == 4:
            config_menu()
        elif choice == 5:
            info_message("Goodbye!")
            break
        else:
            error_message("Invalid choice!")


def node_menu():
    """Node management interactive menu."""
    while True:
        click.echo("\n" + "="*50)
        click.echo("NODE MANAGEMENT")
        click.echo("="*50)
        click.echo("1. List all nodes")
        click.echo("2. Show node details")
        click.echo("3. Add new node")
        click.echo("4. Update node")
        click.echo("5. Delete node")
        click.echo("6. Reconnect node")
        click.echo("7. Node status summary")
        click.echo("8. Usage statistics")
        click.echo("9. Back to main menu")
        click.echo("="*50)
        
        choice = click.prompt("Choose an option", type=int)
        
        if choice == 1:
            ctx = click.get_current_context()
            ctx.invoke(node.commands['list'])
        elif choice == 2:
            node_id = click.prompt("Enter node ID", type=int)
            ctx = click.get_current_context()
            ctx.invoke(node.commands['show'], node_id=node_id)
        elif choice == 3:
            name = click.prompt("Node name")
            address = click.prompt("Node IP address")
            port = click.prompt("Node port", default=62050, type=int)
            api_port = click.prompt("API port", default=62051, type=int)
            usage_coefficient = click.prompt("Usage coefficient", default=1.0, type=float)
            
            ctx = click.get_current_context()
            ctx.invoke(node.commands['add'], 
                      name=name, address=address, port=port, 
                      api_port=api_port, usage_coefficient=usage_coefficient,
                      add_as_host=True, wait=True)
        elif choice == 4:
            node_id = click.prompt("Enter node ID to update", type=int)
            info_message("Leave fields empty to keep current values")
            
            name = click.prompt("New name", default="", show_default=False) or None
            address = click.prompt("New address", default="", show_default=False) or None
            
            ctx = click.get_current_context()
            ctx.invoke(node.commands['update'], 
                      node_id=node_id, name=name, address=address)
        elif choice == 5:
            node_id = click.prompt("Enter node ID to delete", type=int)
            ctx = click.get_current_context()
            ctx.invoke(node.commands['delete'], node_id=node_id, force=False)
        elif choice == 6:
            node_id = click.prompt("Enter node ID to reconnect", type=int)
            ctx = click.get_current_context()
            ctx.invoke(node.commands['reconnect'], node_id=node_id, wait=True)
        elif choice == 7:
            ctx = click.get_current_context()
            ctx.invoke(node.commands['status'])
        elif choice == 8:
            days = click.prompt("Number of days", default=30, type=int)
            ctx = click.get_current_context()
            ctx.invoke(node.commands['usage'], days=days)
        elif choice == 9:
            break
        else:
            error_message("Invalid choice!")


def config_menu():
    """Configuration interactive menu."""
    while True:
        click.echo("\n" + "="*50)
        click.echo("CONFIGURATION")
        click.echo("="*50)
        click.echo("1. Setup Marzban connection")
        click.echo("2. Show current configuration")
        click.echo("3. Test connection")
        click.echo("4. Back to main menu")
        click.echo("="*50)
        
        choice = click.prompt("Choose an option", type=int)
        
        if choice == 1:
            ctx = click.get_current_context()
            ctx.invoke(setup)
        elif choice == 2:
            ctx = click.get_current_context()
            ctx.invoke(show)
        elif choice == 3:
            ctx = click.get_current_context()
            ctx.invoke(test)
        elif choice == 4:
            break
        else:
            error_message("Invalid choice!")


# Add command groups
cli.add_command(node)


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