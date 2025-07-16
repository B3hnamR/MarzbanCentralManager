"""Interactive menu system for Marzban Central Manager."""

import asyncio
import os
import sys
from typing import Dict, List, Callable, Optional, Any
from datetime import datetime

from ...core.config import config_manager
from ...core.logger import get_logger
from ...core.exceptions import ConfigurationError
from ...services.node_service import NodeService
from .display import (
    display_header, success_message, error_message, info_message, warning_message,
    confirm_action, prompt_for_input, clear_screen, pause, display_separator,
    display_key_value_pairs, display_nodes_table, display_node_details,
    display_status_summary, display_usage_table
)


class MenuSystem:
    """Professional interactive menu system."""
    
    def __init__(self):
        self.logger = get_logger("menu")
        self.running = True
        self.current_menu = "main"
        self.menu_history = []
        
        # Services
        self.node_service = NodeService()
        
        # Menu definitions
        self.menus = self._define_menus()
    
    def _define_menus(self) -> Dict[str, Dict]:
        """Define all menu structures."""
        return {
            "main": {
                "title": "🚀 Marzban Central Manager v4.0",
                "subtitle": "Professional API-Based Management System",
                "options": [
                    {"key": "1", "title": "🔧 Node Management", "action": self._goto_node_menu},
                    {"key": "2", "title": "👥 User Management", "action": self._coming_soon, "disabled": True},
                    {"key": "3", "title": "🛡️  Admin Management", "action": self._coming_soon, "disabled": True},
                    {"key": "4", "title": "📋 Template Management", "action": self._coming_soon, "disabled": True},
                    {"key": "5", "title": "🖥️  System Management", "action": self._coming_soon, "disabled": True},
                    {"key": "6", "title": "📱 Subscription Tools", "action": self._coming_soon, "disabled": True},
                    {"key": "7", "title": "⚙️  Configuration", "action": self._goto_config_menu},
                    {"key": "8", "title": "📊 System Status", "action": self._show_system_status},
                    {"key": "9", "title": "📋 About & Help", "action": self._show_about},
                    {"key": "0", "title": "🚪 Exit", "action": self._exit_application},
                ]
            },
            "node": {
                "title": "🔧 Node Management",
                "subtitle": "Manage your Marzban nodes",
                "options": [
                    {"key": "1", "title": "📋 List All Nodes", "action": self._node_list},
                    {"key": "2", "title": "👁️  Show Node Details", "action": self._node_show},
                    {"key": "3", "title": "➕ Add New Node", "action": self._node_add},
                    {"key": "4", "title": "✏️  Update Node", "action": self._node_update},
                    {"key": "5", "title": "🗑️  Delete Node", "action": self._node_delete},
                    {"key": "6", "title": "🔄 Reconnect Node", "action": self._node_reconnect},
                    {"key": "7", "title": "✅ Enable Node", "action": self._node_enable},
                    {"key": "8", "title": "❌ Disable Node", "action": self._node_disable},
                    {"key": "9", "title": "📊 Node Status Summary", "action": self._node_status},
                    {"key": "10", "title": "📈 Usage Statistics", "action": self._node_usage},
                    {"key": "11", "title": "💚 Healthy Nodes", "action": self._node_healthy},
                    {"key": "12", "title": "💔 Unhealthy Nodes", "action": self._node_unhealthy},
                    {"key": "13", "title": "⚙️  Node Settings", "action": self._node_settings},
                    {"key": "0", "title": "🔙 Back to Main Menu", "action": self._goto_main_menu},
                ]
            },
            "config": {
                "title": "⚙️  Configuration Management",
                "subtitle": "Configure system settings",
                "options": [
                    {"key": "1", "title": "🔧 Setup Marzban Connection", "action": self._config_setup},
                    {"key": "2", "title": "👁️  Show Current Configuration", "action": self._config_show},
                    {"key": "3", "title": "🔍 Test Connection", "action": self._config_test},
                    {"key": "4", "title": "📝 Edit Log Settings", "action": self._config_logging},
                    {"key": "5", "title": "🔄 Reset Configuration", "action": self._config_reset},
                    {"key": "0", "title": "🔙 Back to Main Menu", "action": self._goto_main_menu},
                ]
            }
        }
    
    async def start(self):
        """Start the interactive menu system."""
        self.logger.info("Starting interactive menu system")
        
        # Check initial configuration
        if not await self._check_initial_setup():
            return
        
        try:
            while self.running:
                await self._display_current_menu()
                choice = await self._get_user_choice()
                await self._handle_choice(choice)
                
        except KeyboardInterrupt:
            info_message("\n\n👋 Goodbye! Thanks for using Marzban Central Manager")
        except Exception as e:
            error_message(f"Unexpected error: {e}")
            self.logger.error(f"Menu system error: {e}")
        finally:
            await self._cleanup()
    
    async def _check_initial_setup(self) -> bool:
        """Check if initial setup is required."""
        if not config_manager.is_marzban_configured():
            clear_screen()
            display_header("🚀 Welcome to Marzban Central Manager!")
            
            warning_message("Marzban panel connection is not configured.")
            info_message("Let's set it up first...")
            
            if confirm_action("Would you like to configure it now?", default=True):
                await self._config_setup()
                return True
            else:
                error_message("Configuration is required to use this application.")
                return False
        
        return True
    
    async def _display_current_menu(self):
        """Display the current menu."""
        clear_screen()
        
        menu = self.menus[self.current_menu]
        
        # Header
        display_header(menu["title"], width=80)
        if "subtitle" in menu:
            print(f"{'📍 ' + menu['subtitle']:^80}")
            display_separator(80)
        
        # Show current time and status
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        config_status = "✅ Configured" if config_manager.is_marzban_configured() else "❌ Not Configured"
        
        print(f"🕒 Time: {current_time}  |  🔧 API: {config_status}")
        display_separator(80)
        
        # Menu options
        print()
        for option in menu["options"]:
            if option.get("disabled", False):
                print(f"  {option['key']:>2}. {option['title']} (Coming Soon)")
            else:
                print(f"  {option['key']:>2}. {option['title']}")
        
        print()
        display_separator(80)
    
    async def _get_user_choice(self) -> str:
        """Get user choice with validation."""
        while True:
            try:
                choice = prompt_for_input("👉 Choose an option").strip()
                
                # Validate choice
                menu = self.menus[self.current_menu]
                valid_keys = [opt["key"] for opt in menu["options"] if not opt.get("disabled", False)]
                
                if choice in valid_keys:
                    return choice
                else:
                    error_message(f"Invalid choice '{choice}'. Please try again.")
                    
            except (EOFError, KeyboardInterrupt):
                raise
            except Exception as e:
                error_message(f"Input error: {e}")
    
    async def _handle_choice(self, choice: str):
        """Handle user choice."""
        menu = self.menus[self.current_menu]
        
        for option in menu["options"]:
            if option["key"] == choice and not option.get("disabled", False):
                try:
                    await option["action"]()
                except Exception as e:
                    error_message(f"Error executing action: {e}")
                    self.logger.error(f"Menu action error: {e}")
                    pause()
                break
    
    # Navigation methods
    def _goto_main_menu(self):
        """Go to main menu."""
        self.current_menu = "main"
    
    def _goto_node_menu(self):
        """Go to node management menu."""
        self.current_menu = "node"
    
    def _goto_config_menu(self):
        """Go to configuration menu."""
        self.current_menu = "config"
    
    # Node management methods
    async def _node_list(self):
        """List all nodes."""
        try:
            info_message("Fetching nodes...")
            nodes = await self.node_service.list_nodes()
            
            clear_screen()
            display_header("📋 All Nodes")
            display_nodes_table(nodes)
            
        except Exception as e:
            error_message(f"Failed to fetch nodes: {e}")
        
        pause()
    
    async def _node_show(self):
        """Show node details."""
        try:
            node_id = int(prompt_for_input("Enter Node ID"))
            
            info_message(f"Fetching node {node_id}...")
            node = await self.node_service.get_node(node_id)
            
            clear_screen()
            display_node_details(node)
            
        except ValueError:
            error_message("Invalid node ID. Please enter a number.")
        except Exception as e:
            error_message(f"Failed to fetch node: {e}")
        
        pause()
    
    async def _node_add(self):
        """Add new node."""
        try:
            clear_screen()
            display_header("➕ Add New Node")
            
            name = prompt_for_input("Node Name")
            address = prompt_for_input("Node IP Address")
            port = int(prompt_for_input("Node Port", default="62050"))
            api_port = int(prompt_for_input("API Port", default="62051"))
            usage_coefficient = float(prompt_for_input("Usage Coefficient", default="1.0"))
            
            add_as_host = confirm_action("Add as new host?", default=True)
            
            info_message(f"Creating node '{name}'...")
            
            node = await self.node_service.create_node(
                name=name,
                address=address,
                port=port,
                api_port=api_port,
                usage_coefficient=usage_coefficient,
                add_as_new_host=add_as_host
            )
            
            success_message(f"Node '{name}' created successfully!")
            display_node_details(node)
            
            if confirm_action("Wait for node to connect?", default=True):
                info_message("Waiting for node to connect...")
                connected = await self.node_service.wait_for_node_connection(node.id, timeout=60)
                
                if connected:
                    success_message("Node connected successfully!")
                else:
                    warning_message("Node failed to connect within timeout")
            
        except ValueError as e:
            error_message(f"Invalid input: {e}")
        except Exception as e:
            error_message(f"Failed to create node: {e}")
        
        pause()
    
    async def _node_update(self):
        """Update node."""
        try:
            node_id = int(prompt_for_input("Enter Node ID to update"))
            
            # Get current node
            current_node = await self.node_service.get_node(node_id)
            
            clear_screen()
            display_header(f"✏️  Update Node {node_id}")
            display_node_details(current_node)
            
            info_message("Leave fields empty to keep current values")
            
            name = prompt_for_input("New name", default="") or None
            address = prompt_for_input("New address", default="") or None
            port_str = prompt_for_input("New port", default="")
            port = int(port_str) if port_str else None
            
            if name or address or port:
                info_message(f"Updating node {node_id}...")
                
                updated_node = await self.node_service.update_node(
                    node_id=node_id,
                    name=name,
                    address=address,
                    port=port
                )
                
                success_message(f"Node {node_id} updated successfully!")
                display_node_details(updated_node)
            else:
                info_message("No changes made.")
            
        except ValueError:
            error_message("Invalid input.")
        except Exception as e:
            error_message(f"Failed to update node: {e}")
        
        pause()
    
    async def _node_delete(self):
        """Delete node."""
        try:
            node_id = int(prompt_for_input("Enter Node ID to delete"))
            
            # Get node details
            node = await self.node_service.get_node(node_id)
            
            clear_screen()
            display_header("🗑️  Delete Node")
            display_node_details(node)
            
            warning_message("This action cannot be undone!")
            
            if confirm_action(f"Are you sure you want to delete node {node_id} ({node.name})?"):
                info_message(f"Deleting node {node_id}...")
                await self.node_service.delete_node(node_id)
                success_message(f"Node {node_id} ({node.name}) deleted successfully!")
            else:
                info_message("Deletion cancelled.")
            
        except ValueError:
            error_message("Invalid node ID.")
        except Exception as e:
            error_message(f"Failed to delete node: {e}")
        
        pause()
    
    async def _node_reconnect(self):
        """Reconnect node."""
        try:
            node_id = int(prompt_for_input("Enter Node ID to reconnect"))
            
            info_message(f"Reconnecting node {node_id}...")
            await self.node_service.reconnect_node(node_id)
            success_message(f"Reconnection triggered for node {node_id}")
            
            if confirm_action("Wait for node to connect?", default=True):
                info_message("Waiting for node to connect...")
                connected = await self.node_service.wait_for_node_connection(node_id, timeout=60)
                
                if connected:
                    success_message("Node reconnected successfully!")
                else:
                    warning_message("Node failed to reconnect within timeout")
            
        except ValueError:
            error_message("Invalid node ID.")
        except Exception as e:
            error_message(f"Failed to reconnect node: {e}")
        
        pause()
    
    async def _node_enable(self):
        """Enable node."""
        try:
            node_id = int(prompt_for_input("Enter Node ID to enable"))
            
            info_message(f"Enabling node {node_id}...")
            node = await self.node_service.enable_node(node_id)
            success_message(f"Node {node_id} enabled successfully!")
            display_node_details(node)
            
        except ValueError:
            error_message("Invalid node ID.")
        except Exception as e:
            error_message(f"Failed to enable node: {e}")
        
        pause()
    
    async def _node_disable(self):
        """Disable node."""
        try:
            node_id = int(prompt_for_input("Enter Node ID to disable"))
            
            info_message(f"Disabling node {node_id}...")
            node = await self.node_service.disable_node(node_id)
            success_message(f"Node {node_id} disabled successfully!")
            display_node_details(node)
            
        except ValueError:
            error_message("Invalid node ID.")
        except Exception as e:
            error_message(f"Failed to disable node: {e}")
        
        pause()
    
    async def _node_status(self):
        """Show node status summary."""
        try:
            info_message("Fetching node status summary...")
            summary = await self.node_service.get_node_status_summary()
            
            clear_screen()
            display_status_summary(summary)
            
        except Exception as e:
            error_message(f"Failed to get status summary: {e}")
        
        pause()
    
    async def _node_usage(self):
        """Show usage statistics."""
        try:
            days = int(prompt_for_input("Number of days to look back", default="30"))
            
            info_message(f"Fetching usage statistics for last {days} days...")
            
            from datetime import datetime, timedelta
            end_date = datetime.now()
            start_date = end_date - timedelta(days=days)
            
            usage_stats = await self.node_service.get_node_usage(start_date, end_date)
            
            clear_screen()
            display_usage_table(usage_stats, days)
            
        except ValueError:
            error_message("Invalid number of days.")
        except Exception as e:
            error_message(f"Failed to get usage statistics: {e}")
        
        pause()
    
    async def _node_healthy(self):
        """Show healthy nodes."""
        try:
            info_message("Fetching healthy nodes...")
            nodes = await self.node_service.get_healthy_nodes()
            
            clear_screen()
            display_header("💚 Healthy Nodes")
            
            if nodes:
                display_nodes_table(nodes)
                success_message(f"Found {len(nodes)} healthy nodes")
            else:
                warning_message("No healthy nodes found")
            
        except Exception as e:
            error_message(f"Failed to get healthy nodes: {e}")
        
        pause()
    
    async def _node_unhealthy(self):
        """Show unhealthy nodes."""
        try:
            info_message("Fetching unhealthy nodes...")
            nodes = await self.node_service.get_unhealthy_nodes()
            
            clear_screen()
            display_header("💔 Unhealthy Nodes")
            
            if nodes:
                display_nodes_table(nodes)
                warning_message(f"Found {len(nodes)} unhealthy nodes")
            else:
                success_message("All nodes are healthy!")
            
        except Exception as e:
            error_message(f"Failed to get unhealthy nodes: {e}")
        
        pause()
    
    async def _node_settings(self):
        """Show node settings."""
        try:
            info_message("Fetching node settings...")
            settings = await self.node_service.get_node_settings()
            
            clear_screen()
            display_header("⚙️  Node Settings")
            
            settings_data = {
                "Minimum Node Version": settings.min_node_version,
                "Certificate Length": f"{len(settings.certificate)} characters"
            }
            
            display_key_value_pairs(settings_data)
            
            if confirm_action("Show full certificate?"):
                print("\n📜 TLS Certificate:")
                display_separator(80)
                print(settings.certificate)
                display_separator(80)
            
        except Exception as e:
            error_message(f"Failed to get node settings: {e}")
        
        pause()
    
    # Configuration methods
    async def _config_setup(self):
        """Setup Marzban configuration."""
        try:
            clear_screen()
            display_header("🔧 Marzban Panel Configuration")
            
            info_message("Please provide your Marzban panel connection details:")
            
            # Get current config
            current_config = config_manager.load_config()
            
            base_url = prompt_for_input(
                "Panel URL (e.g., https://panel.example.com:8000)",
                default=current_config.marzban.base_url if current_config.marzban else ""
            )
            
            username = prompt_for_input(
                "Admin Username",
                default=current_config.marzban.username if current_config.marzban else ""
            )
            
            password = prompt_for_input("Admin Password", hide_input=True)
            
            # Test connection
            info_message("Testing connection...")
            
            from ...api.base import BaseAPIClient
            from ...core.config import MarzbanConfig
            
            test_config = MarzbanConfig(
                base_url=base_url,
                username=username,
                password=password
            )
            
            async with BaseAPIClient(test_config) as client:
                if await client.test_connection():
                    success_message("Connection test successful!")
                    
                    # Save configuration
                    config_manager.update_marzban_config(base_url, username, password)
                    success_message("Configuration saved successfully!")
                    
                else:
                    error_message("Connection test failed!")
                    if confirm_action("Save configuration anyway?"):
                        config_manager.update_marzban_config(base_url, username, password)
                        warning_message("Configuration saved (connection test failed)")
            
        except Exception as e:
            error_message(f"Configuration setup failed: {e}")
        
        pause()
    
    async def _config_show(self):
        """Show current configuration."""
        try:
            config = config_manager.load_config()
            
            clear_screen()
            display_header("👁️  Current Configuration")
            
            config_data = {
                "Debug Mode": str(config.debug),
                "Log Level": config.log_level,
                "Log File": config.log_file or "Console only"
            }
            
            if config.marzban:
                config_data.update({
                    "Panel URL": config.marzban.base_url,
                    "Username": config.marzban.username,
                    "Password": "*" * len(config.marzban.password) if config.marzban.password else "Not set",
                    "Timeout": f"{config.marzban.timeout}s",
                    "Verify SSL": str(config.marzban.verify_ssl)
                })
            else:
                config_data["Marzban Panel"] = "Not configured"
            
            display_key_value_pairs(config_data)
            
        except Exception as e:
            error_message(f"Failed to show configuration: {e}")
        
        pause()
    
    async def _config_test(self):
        """Test Marzban connection."""
        try:
            if not config_manager.is_marzban_configured():
                error_message("Marzban panel is not configured!")
                if confirm_action("Would you like to configure it now?"):
                    await self._config_setup()
                return
            
            info_message("Testing Marzban panel connection...")
            
            from ...api.base import BaseAPIClient
            
            config = config_manager.load_config()
            async with BaseAPIClient(config.marzban) as client:
                if await client.test_connection():
                    success_message("Connection test successful!")
                else:
                    error_message("Connection test failed!")
            
        except Exception as e:
            error_message(f"Connection test error: {e}")
        
        pause()
    
    async def _config_logging(self):
        """Configure logging settings."""
        info_message("Logging configuration feature coming soon!")
        pause()
    
    async def _config_reset(self):
        """Reset configuration."""
        warning_message("This will reset all configuration settings!")
        
        if confirm_action("Are you sure you want to reset configuration?"):
            try:
                # Create default config
                from ...core.config import AppConfig
                default_config = AppConfig()
                config_manager.save_config(default_config)
                
                success_message("Configuration reset successfully!")
                warning_message("You will need to reconfigure Marzban connection.")
                
            except Exception as e:
                error_message(f"Failed to reset configuration: {e}")
        else:
            info_message("Configuration reset cancelled.")
        
        pause()
    
    # System methods
    async def _show_system_status(self):
        """Show system status."""
        try:
            clear_screen()
            display_header("📊 System Status")
            
            # Basic system info
            status_data = {
                "Application": "Marzban Central Manager v4.0",
                "Python Version": sys.version.split()[0],
                "Platform": sys.platform,
                "Current Time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "Configuration": "✅ OK" if config_manager.is_marzban_configured() else "❌ Not configured"
            }
            
            # Try to get node count
            try:
                nodes = await self.node_service.list_nodes()
                status_data["Total Nodes"] = str(len(nodes))
                
                summary = await self.node_service.get_node_status_summary()
                status_data["Connected Nodes"] = str(summary.get("connected", 0))
                status_data["Disconnected Nodes"] = str(summary.get("disconnected", 0))
                
            except Exception:
                status_data["Node Status"] = "Unable to fetch"
            
            display_key_value_pairs(status_data)
            
        except Exception as e:
            error_message(f"Failed to get system status: {e}")
        
        pause()
    
    def _show_about(self):
        """Show about information."""
        clear_screen()
        display_header("📋 About Marzban Central Manager")
        
        about_text = """
🚀 Marzban Central Manager v4.0
Professional API-Based Management System

📝 Description:
A comprehensive, API-driven management system for Marzban panel and nodes.
Built with modern Python technologies and professional architecture.

👨‍💻 Author: B3hnamR
📧 Email: behnamrjd@gmail.com
🌐 GitHub: https://github.com/B3hnamR

🛠️  Technology Stack:
• Python 3.8+ with asyncio
• httpx for HTTP requests
• Click for CLI interface
• PyYAML for configuration
• Professional logging system

✨ Features:
• Complete Node Management
• API-based operations
• Interactive menu system
• Professional logging
• Error handling & recovery
• Async operations support

📜 License: MIT License
        """
        
        print(about_text)
        pause()
    
    def _coming_soon(self):
        """Show coming soon message."""
        info_message("This feature is coming soon! 🚧")
        info_message("Stay tuned for updates...")
        pause()
    
    def _exit_application(self):
        """Exit the application."""
        info_message("👋 Thank you for using Marzban Central Manager!")
        self.running = False
    
    async def _cleanup(self):
        """Cleanup resources."""
        try:
            await self.node_service.close()
            self.logger.info("Menu system cleanup completed")
        except Exception as e:
            self.logger.error(f"Cleanup error: {e}")


async def start_interactive_menu():
    """Start the interactive menu system."""
    menu_system = MenuSystem()
    await menu_system.start()