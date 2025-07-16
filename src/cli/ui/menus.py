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
                    {"key": "2", "title": "📊 Live Monitoring", "action": self._goto_monitor_menu},
                    {"key": "3", "title": "🔍 Auto Discovery", "action": self._goto_discovery_menu},
                    {"key": "4", "title": "👥 User Management", "action": self._coming_soon, "disabled": True},
                    {"key": "5", "title": "🛡️  Admin Management", "action": self._coming_soon, "disabled": True},
                    {"key": "6", "title": "📋 Template Management", "action": self._coming_soon, "disabled": True},
                    {"key": "7", "title": "🖥️  System Management", "action": self._coming_soon, "disabled": True},
                    {"key": "8", "title": "📱 Subscription Tools", "action": self._coming_soon, "disabled": True},
                    {"key": "9", "title": "⚙️  Configuration", "action": self._goto_config_menu},
                    {"key": "10", "title": "📊 System Status", "action": self._show_system_status},
                    {"key": "11", "title": "📋 About & Help", "action": self._show_about},
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
            },
            "monitor": {
                "title": "📊 Live Monitoring",
                "subtitle": "Real-time node monitoring and health status",
                "options": [
                    {"key": "1", "title": "🚀 Start Live Monitoring", "action": self._monitor_start},
                    {"key": "2", "title": "📊 Current Status", "action": self._monitor_status},
                    {"key": "3", "title": "🚨 View Alerts", "action": self._monitor_alerts},
                    {"key": "4", "title": "📈 Health Summary", "action": self._monitor_health},
                    {"key": "5", "title": "📋 Node History", "action": self._monitor_history},
                    {"key": "6", "title": "🔄 Force Update", "action": self._monitor_update},
                    {"key": "7", "title": "⏹️  Stop Monitoring", "action": self._monitor_stop},
                    {"key": "0", "title": "🔙 Back to Main Menu", "action": self._goto_main_menu},
                ]
            },
            "discovery": {
                "title": "🔍 Auto Discovery",
                "subtitle": "Discover Marzban nodes in your network",
                "options": [
                    {"key": "1", "title": "🌐 Scan Local Network", "action": self._discovery_local},
                    {"key": "2", "title": "🎯 Scan Network Range", "action": self._discovery_range},
                    {"key": "3", "title": "📍 Scan IP Range", "action": self._discovery_ip_range},
                    {"key": "4", "title": "📋 List Discovered Nodes", "action": self._discovery_list},
                    {"key": "5", "title": "🎯 Marzban Candidates", "action": self._discovery_candidates},
                    {"key": "6", "title": "✅ Validate Node", "action": self._discovery_validate},
                    {"key": "7", "title": "�� Add Discovered Node", "action": self._discovery_add},
                    {"key": "8", "title": "🗑️  Clear Cache", "action": self._discovery_clear},
                    {"key": "9", "title": "⏹️  Stop Discovery", "action": self._discovery_stop},
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
    
    def _goto_monitor_menu(self):
        """Go to monitoring menu."""
        self.current_menu = "monitor"
    
    def _goto_discovery_menu(self):
        """Go to discovery menu."""
        self.current_menu = "discovery"
    
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
    
    # Monitoring methods
    async def _monitor_start(self):
        """Start live monitoring."""
        try:
            from ...services.monitoring_service import monitoring_service
            
            clear_screen()
            display_header("🚀 Starting Live Monitoring")
            
            if monitoring_service.is_monitoring:
                warning_message("Monitoring is already running!")
                pause()
                return
            
            interval = int(prompt_for_input("Monitoring interval (seconds)", default="30"))
            monitoring_service.set_monitoring_interval(interval)
            
            info_message("Starting monitoring service...")
            await monitoring_service.start_monitoring()
            
            success_message("Live monitoring started!")
            info_message(f"Monitoring interval: {interval} seconds")
            info_message("Press Ctrl+C to stop monitoring")
            
            # Simple monitoring display loop
            try:
                while monitoring_service.is_monitoring:
                    await asyncio.sleep(5)
                    
                    # Get current metrics
                    metrics = await monitoring_service.get_current_metrics()
                    system_metrics = metrics.get('system_metrics', {})
                    
                    clear_screen()
                    display_header("📊 Live Monitoring Dashboard")
                    
                    # Display system summary
                    summary_data = {
                        "Total Nodes": system_metrics.get('total_nodes', 0),
                        "Healthy Nodes": system_metrics.get('healthy_nodes', 0),
                        "Warning Nodes": system_metrics.get('warning_nodes', 0),
                        "Critical Nodes": system_metrics.get('critical_nodes', 0),
                        "Offline Nodes": system_metrics.get('offline_nodes', 0),
                        "Health Percentage": f"{system_metrics.get('health_percentage', 0):.1f}%",
                        "Last Updated": system_metrics.get('last_updated', 'Never')
                    }
                    
                    display_key_value_pairs(summary_data)
                    
                    # Show alerts
                    alerts = await monitoring_service.get_alerts()
                    if alerts:
                        print("\n🚨 Active Alerts:")
                        for alert in alerts[:5]:  # Show only first 5 alerts
                            alert_type = alert.get('type', 'info')
                            message = alert.get('message', 'No message')
                            if alert_type == 'critical':
                                print(f"  🔴 {message}")
                            elif alert_type == 'warning':
                                print(f"  🟡 {message}")
                            else:
                                print(f"  🔵 {message}")
                    
                    print(f"\n⏱️  Next update in {interval} seconds... (Press Ctrl+C to stop)")
                    
            except KeyboardInterrupt:
                info_message("\nStopping monitoring...")
                await monitoring_service.stop_monitoring()
                success_message("Monitoring stopped!")
            
        except Exception as e:
            error_message(f"Failed to start monitoring: {e}")
        
        pause()
    
    async def _monitor_status(self):
        """Show current monitoring status."""
        try:
            from ...services.monitoring_service import monitoring_service
            
            clear_screen()
            display_header("📊 Monitoring Status")
            
            if monitoring_service.is_monitoring:
                success_message("✅ Monitoring is active")
                
                # Get current metrics
                metrics = await monitoring_service.get_current_metrics()
                system_metrics = metrics.get('system_metrics', {})
                
                status_data = {
                    "Status": "Active",
                    "Monitoring Interval": f"{monitoring_service.monitoring_interval} seconds",
                    "Total Nodes": system_metrics.get('total_nodes', 0),
                    "Healthy Nodes": system_metrics.get('healthy_nodes', 0),
                    "Warning Nodes": system_metrics.get('warning_nodes', 0),
                    "Critical Nodes": system_metrics.get('critical_nodes', 0),
                    "Health Percentage": f"{system_metrics.get('health_percentage', 0):.1f}%",
                    "Last Updated": system_metrics.get('last_updated', 'Never')
                }
                
                display_key_value_pairs(status_data)
            else:
                warning_message("❌ Monitoring is not active")
                
                status_data = {
                    "Status": "Inactive",
                    "Monitoring Interval": f"{monitoring_service.monitoring_interval} seconds"
                }
                
                display_key_value_pairs(status_data)
            
        except Exception as e:
            error_message(f"Failed to get monitoring status: {e}")
        
        pause()
    
    async def _monitor_alerts(self):
        """View current alerts."""
        try:
            from ...services.monitoring_service import monitoring_service
            
            clear_screen()
            display_header("🚨 Current Alerts")
            
            alerts = await monitoring_service.get_alerts()
            
            if alerts:
                for i, alert in enumerate(alerts, 1):
                    alert_type = alert.get('type', 'info')
                    message = alert.get('message', 'No message')
                    timestamp = alert.get('timestamp', 'Unknown time')
                    
                    print(f"\n{i}. Alert Type: {alert_type.upper()}")
                    print(f"   Message: {message}")
                    print(f"   Time: {timestamp}")
                    
                    if 'node_id' in alert:
                        print(f"   Node ID: {alert['node_id']}")
                        print(f"   Node Name: {alert.get('node_name', 'Unknown')}")
                    
                    display_separator(60)
                
                success_message(f"Found {len(alerts)} active alerts")
            else:
                success_message("🎉 No active alerts! All systems are healthy.")
            
        except Exception as e:
            error_message(f"Failed to get alerts: {e}")
        
        pause()
    
    async def _monitor_health(self):
        """Show health summary."""
        try:
            from ...services.monitoring_service import monitoring_service
            
            clear_screen()
            display_header("📈 Health Summary")
            
            summary = await monitoring_service.get_health_summary()
            
            health_data = {
                "Total Nodes": summary.get('total_nodes', 0),
                "Healthy Nodes": f"{summary.get('healthy', 0)} 💚",
                "Warning Nodes": f"{summary.get('warning', 0)} 🟡",
                "Critical Nodes": f"{summary.get('critical', 0)} 🔴",
                "Offline Nodes": f"{summary.get('offline', 0)} ⚫",
                "Overall Health": f"{summary.get('health_percentage', 0):.1f}% 📊",
                "Last Updated": summary.get('last_updated', 'Never')
            }
            
            display_key_value_pairs(health_data)
            
            # Health status indicator
            health_percentage = summary.get('health_percentage', 0)
            if health_percentage >= 90:
                success_message("🎉 Excellent system health!")
            elif health_percentage >= 70:
                info_message("👍 Good system health")
            elif health_percentage >= 50:
                warning_message("⚠️  System health needs attention")
            else:
                error_message("🚨 Critical system health issues!")
            
        except Exception as e:
            error_message(f"Failed to get health summary: {e}")
        
        pause()
    
    async def _monitor_history(self):
        """Show node history."""
        try:
            from ...services.monitoring_service import monitoring_service
            
            node_id = int(prompt_for_input("Enter Node ID for history"))
            limit = int(prompt_for_input("Number of records to show", default="20"))
            
            clear_screen()
            display_header(f"📋 Node {node_id} History")
            
            history = await monitoring_service.get_node_history(node_id, limit)
            
            if history:
                print(f"{'Time':<20} {'Status':<12} {'Health':<10} {'Response (ms)':<15}")
                display_separator(60)
                
                for record in history:
                    timestamp = record.last_seen.strftime("%Y-%m-%d %H:%M:%S") if record.last_seen else "Unknown"
                    status = record.status.value
                    health = record.health_status.value
                    response = f"{record.response_time:.1f}" if record.response_time else "N/A"
                    
                    print(f"{timestamp:<20} {status:<12} {health:<10} {response:<15}")
                
                success_message(f"Showing {len(history)} historical records")
            else:
                warning_message("No historical data found for this node")
            
        except ValueError:
            error_message("Invalid input. Please enter valid numbers.")
        except Exception as e:
            error_message(f"Failed to get node history: {e}")
        
        pause()
    
    async def _monitor_update(self):
        """Force metrics update."""
        try:
            from ...services.monitoring_service import monitoring_service
            
            info_message("Forcing metrics update...")
            await monitoring_service.force_update()
            success_message("✅ Metrics updated successfully!")
            
            # Show updated summary
            summary = await monitoring_service.get_health_summary()
            
            print(f"\n📊 Updated Status:")
            print(f"Total Nodes: {summary.get('total_nodes', 0)}")
            print(f"Health: {summary.get('health_percentage', 0):.1f}%")
            print(f"Updated: {summary.get('last_updated', 'Never')}")
            
        except Exception as e:
            error_message(f"Failed to update metrics: {e}")
        
        pause()
    
    async def _monitor_stop(self):
        """Stop monitoring."""
        try:
            from ...services.monitoring_service import monitoring_service
            
            if monitoring_service.is_monitoring:
                info_message("Stopping monitoring service...")
                await monitoring_service.stop_monitoring()
                success_message("⏹️  Monitoring stopped successfully!")
            else:
                warning_message("Monitoring is not currently running")
            
        except Exception as e:
            error_message(f"Failed to stop monitoring: {e}")
        
        pause()
    
    # Discovery methods
    async def _discovery_local(self):
        """Scan local network for nodes."""
        try:
            from ...services.discovery_service import discovery_service, DiscoveryConfig
            
            clear_screen()
            display_header("🌐 Local Network Discovery")
            
            # Configure discovery
            timeout = int(prompt_for_input("Scan timeout (seconds)", default="5"))
            deep_scan = confirm_action("Enable deep scan?", default=False)
            
            config = DiscoveryConfig(
                timeout=timeout,
                deep_scan=deep_scan
            )
            
            info_message("Starting local network discovery...")
            info_message("This may take several minutes depending on your network size.")
            
            # Progress callback
            async def progress_callback(current, total, message):
                print(f"\r🔍 Progress: {current}/{total} - {message}", end="", flush=True)
            
            discovered = await discovery_service.discover_local_network(config, progress_callback)
            
            clear_screen()
            display_header("🌐 Local Network Discovery Results")
            
            if discovered:
                print(f"{'IP Address':<15} {'Hostname':<20} {'Open Ports':<15} {'Marzban':<8} {'Confidence':<10}")
                display_separator(80)
                
                for node in discovered:
                    hostname = node.hostname[:18] + "..." if node.hostname and len(node.hostname) > 18 else (node.hostname or "Unknown")
                    ports = ",".join(map(str, node.open_ports[:3]))  # Show first 3 ports
                    if len(node.open_ports) > 3:
                        ports += "..."
                    marzban = "Yes" if node.marzban_node_detected else "No"
                    confidence = f"{node.confidence_score:.1f}%"
                    
                    print(f"{node.ip_address:<15} {hostname:<20} {ports:<15} {marzban:<8} {confidence:<10}")
                
                success_message(f"Discovery completed! Found {len(discovered)} nodes")
                
                # Show Marzban candidates
                candidates = [n for n in discovered if n.marzban_node_detected]
                if candidates:
                    info_message(f"Found {len(candidates)} potential Marzban nodes!")
            else:
                warning_message("No nodes discovered in local network")
            
        except Exception as e:
            error_message(f"Local network discovery failed: {e}")
        
        pause()
    
    async def _discovery_range(self):
        """Scan network range for nodes."""
        try:
            from ...services.discovery_service import discovery_service, DiscoveryConfig
            
            clear_screen()
            display_header("🎯 Network Range Discovery")
            
            network_range = prompt_for_input("Network range (e.g., 192.168.1.0/24)")
            timeout = int(prompt_for_input("Scan timeout (seconds)", default="5"))
            deep_scan = confirm_action("Enable deep scan?", default=False)
            
            config = DiscoveryConfig(
                timeout=timeout,
                deep_scan=deep_scan
            )
            
            info_message(f"Starting network range discovery for {network_range}...")
            
            # Progress callback
            async def progress_callback(current, total, message):
                print(f"\r🔍 Progress: {current}/{total} - {message}", end="", flush=True)
            
            discovered = await discovery_service.discover_network_range(network_range, config, progress_callback)
            
            clear_screen()
            display_header(f"🎯 Network Range Discovery Results: {network_range}")
            
            if discovered:
                print(f"{'IP Address':<15} {'Hostname':<20} {'Open Ports':<15} {'Marzban':<8} {'Confidence':<10}")
                display_separator(80)
                
                for node in discovered:
                    hostname = node.hostname[:18] + "..." if node.hostname and len(node.hostname) > 18 else (node.hostname or "Unknown")
                    ports = ",".join(map(str, node.open_ports[:3]))
                    if len(node.open_ports) > 3:
                        ports += "..."
                    marzban = "Yes" if node.marzban_node_detected else "No"
                    confidence = f"{node.confidence_score:.1f}%"
                    
                    print(f"{node.ip_address:<15} {hostname:<20} {ports:<15} {marzban:<8} {confidence:<10}")
                
                success_message(f"Discovery completed! Found {len(discovered)} nodes")
            else:
                warning_message(f"No nodes discovered in range {network_range}")
            
        except Exception as e:
            error_message(f"Network range discovery failed: {e}")
        
        pause()
    
    async def _discovery_ip_range(self):
        """Scan IP range for nodes."""
        try:
            from ...services.discovery_service import discovery_service, DiscoveryConfig
            
            clear_screen()
            display_header("📍 IP Range Discovery")
            
            start_ip = prompt_for_input("Start IP address (e.g., 192.168.1.1)")
            end_ip = prompt_for_input("End IP address (e.g., 192.168.1.100)")
            timeout = int(prompt_for_input("Scan timeout (seconds)", default="5"))
            
            config = DiscoveryConfig(timeout=timeout)
            
            info_message(f"Starting IP range discovery: {start_ip} - {end_ip}...")
            
            # Progress callback
            async def progress_callback(current, total, message):
                print(f"\r🔍 Progress: {current}/{total} - {message}", end="", flush=True)
            
            discovered = await discovery_service.discover_ip_range(start_ip, end_ip, config, progress_callback)
            
            clear_screen()
            display_header(f"📍 IP Range Discovery Results: {start_ip} - {end_ip}")
            
            if discovered:
                print(f"{'IP Address':<15} {'Response Time':<15} {'Open Ports':<20} {'Marzban':<8}")
                display_separator(70)
                
                for node in discovered:
                    response_time = f"{node.response_time:.1f}ms" if node.response_time else "N/A"
                    ports = ",".join(map(str, node.open_ports[:4]))
                    if len(node.open_ports) > 4:
                        ports += "..."
                    marzban = "Yes" if node.marzban_node_detected else "No"
                    
                    print(f"{node.ip_address:<15} {response_time:<15} {ports:<20} {marzban:<8}")
                
                success_message(f"Discovery completed! Found {len(discovered)} nodes")
            else:
                warning_message(f"No nodes discovered in IP range {start_ip} - {end_ip}")
            
        except Exception as e:
            error_message(f"IP range discovery failed: {e}")
        
        pause()
    
    async def _discovery_list(self):
        """List all discovered nodes."""
        try:
            from ...services.discovery_service import discovery_service
            
            clear_screen()
            display_header("📋 Discovered Nodes")
            
            discovered = discovery_service.get_discovered_nodes()
            
            if discovered:
                print(f"{'IP Address':<15} {'Hostname':<20} {'Ports':<15} {'Marzban':<8} {'Confidence':<10} {'Discovered':<12}")
                display_separator(90)
                
                for node in discovered:
                    hostname = node.hostname[:18] + "..." if node.hostname and len(node.hostname) > 18 else (node.hostname or "Unknown")
                    ports = ",".join(map(str, node.open_ports[:3]))
                    if len(node.open_ports) > 3:
                        ports += "..."
                    marzban = "Yes" if node.marzban_node_detected else "No"
                    confidence = f"{node.confidence_score:.1f}%"
                    discovered_time = node.discovered_at.strftime("%H:%M:%S") if node.discovered_at else "Unknown"
                    
                    print(f"{node.ip_address:<15} {hostname:<20} {ports:<15} {marzban:<8} {confidence:<10} {discovered_time:<12}")
                
                success_message(f"Total discovered nodes: {len(discovered)}")
            else:
                warning_message("No nodes have been discovered yet")
                info_message("Run a discovery scan first")
            
        except Exception as e:
            error_message(f"Failed to list discovered nodes: {e}")
        
        pause()
    
    async def _discovery_candidates(self):
        """Show Marzban node candidates."""
        try:
            from ...services.discovery_service import discovery_service
            
            clear_screen()
            display_header("🎯 Marzban Node Candidates")
            
            candidates = discovery_service.get_marzban_candidates()
            
            if candidates:
                print(f"{'IP Address':<15} {'Hostname':<20} {'Marzban Ports':<15} {'Version':<10} {'Confidence':<10}")
                display_separator(80)
                
                for candidate in candidates:
                    hostname = candidate.hostname[:18] + "..." if candidate.hostname and len(candidate.hostname) > 18 else (candidate.hostname or "Unknown")
                    
                    # Show only Marzban-related ports
                    marzban_ports = [62050, 62051, 8000, 8080, 8443]
                    relevant_ports = [p for p in candidate.open_ports if p in marzban_ports]
                    ports = ",".join(map(str, relevant_ports))
                    
                    version = candidate.marzban_version or "Unknown"
                    confidence = f"{candidate.confidence_score:.1f}%"
                    
                    print(f"{candidate.ip_address:<15} {hostname:<20} {ports:<15} {version:<10} {confidence:<10}")
                
                success_message(f"Found {len(candidates)} Marzban node candidates")
                
                if confirm_action("Would you like to validate a candidate?"):
                    ip_address = prompt_for_input("Enter IP address to validate")
                    candidate = next((c for c in candidates if c.ip_address == ip_address), None)
                    
                    if candidate:
                        info_message(f"Validating node {ip_address}...")
                        validation = await discovery_service.validate_discovered_node(candidate)
                        
                        clear_screen()
                        display_header(f"✅ Validation Results: {ip_address}")
                        
                        validation_data = {
                            "Valid": "Yes" if validation['valid'] else "No",
                            "Confidence": f"{validation['confidence']:.1f}%",
                            "Issues": len(validation['issues']),
                            "Recommendations": len(validation['recommendations'])
                        }
                        
                        display_key_value_pairs(validation_data)
                        
                        if validation['issues']:
                            print("\n🚨 Issues found:")
                            for issue in validation['issues']:
                                print(f"  • {issue}")
                        
                        if validation['recommendations']:
                            print("\n💡 Recommendations:")
                            for rec in validation['recommendations']:
                                print(f"  • {rec}")
                        
                        pause()
                    else:
                        error_message("IP address not found in candidates")
            else:
                warning_message("No Marzban node candidates found")
                info_message("Run a discovery scan first or check if any nodes are running Marzban")
            
        except Exception as e:
            error_message(f"Failed to get Marzban candidates: {e}")
        
        pause()
    
    async def _discovery_validate(self):
        """Validate a discovered node."""
        try:
            from ...services.discovery_service import discovery_service
            
            ip_address = prompt_for_input("Enter IP address to validate")
            
            # Check if already discovered
            discovered = discovery_service.get_discovered_nodes()
            node = next((n for n in discovered if n.ip_address == ip_address), None)
            
            if not node:
                warning_message("IP address not found in discovered nodes")
                if confirm_action("Would you like to scan this IP first?"):
                    # Scan single host
                    from ...services.discovery_service import DiscoveredNode
                    
                    info_message(f"Scanning {ip_address}...")
                    # This would need to be implemented in discovery service
                    warning_message("Single host scanning not yet implemented")
                    pause()
                    return
                else:
                    pause()
                    return
            
            clear_screen()
            display_header(f"✅ Validating Node: {ip_address}")
            
            info_message("Running validation checks...")
            validation = await discovery_service.validate_discovered_node(node)
            
            validation_data = {
                "IP Address": node.ip_address,
                "Hostname": node.hostname or "Unknown",
                "Valid": "✅ Yes" if validation['valid'] else "❌ No",
                "Confidence Score": f"{validation['confidence']:.1f}%",
                "Open Ports": ",".join(map(str, node.open_ports)),
                "Marzban Detected": "✅ Yes" if node.marzban_node_detected else "❌ No",
                "Issues Found": len(validation['issues']),
                "Recommendations": len(validation['recommendations'])
            }
            
            display_key_value_pairs(validation_data)
            
            if validation['issues']:
                print("\n🚨 Issues Found:")
                for i, issue in enumerate(validation['issues'], 1):
                    print(f"  {i}. {issue}")
            
            if validation['recommendations']:
                print("\n💡 Recommendations:")
                for i, rec in enumerate(validation['recommendations'], 1):
                    print(f"  {i}. {rec}")
            
            if validation['valid']:
                success_message("✅ Node validation passed!")
                if confirm_action("Would you like to add this node to your managed nodes?"):
                    # This would redirect to add node functionality
                    info_message("Redirecting to add node...")
                    # Implementation would go here
            else:
                warning_message("⚠️  Node validation failed!")
            
        except Exception as e:
            error_message(f"Node validation failed: {e}")
        
        pause()
    
    async def _discovery_add(self):
        """Add a discovered node to managed nodes."""
        try:
            from ...services.discovery_service import discovery_service
            
            clear_screen()
            display_header("➕ Add Discovered Node")
            
            # Show candidates
            candidates = discovery_service.get_marzban_candidates()
            
            if not candidates:
                warning_message("No Marzban candidates found")
                info_message("Run a discovery scan first")
                pause()
                return
            
            print("Available Marzban candidates:")
            print(f"{'#':<3} {'IP Address':<15} {'Hostname':<20} {'Confidence':<10}")
            display_separator(50)
            
            for i, candidate in enumerate(candidates, 1):
                hostname = candidate.hostname[:18] + "..." if candidate.hostname and len(candidate.hostname) > 18 else (candidate.hostname or "Unknown")
                confidence = f"{candidate.confidence_score:.1f}%"
                print(f"{i:<3} {candidate.ip_address:<15} {hostname:<20} {confidence:<10}")
            
            choice = int(prompt_for_input(f"Select candidate (1-{len(candidates)})"))
            
            if 1 <= choice <= len(candidates):
                candidate = candidates[choice - 1]
                
                clear_screen()
                display_header(f"➕ Adding Node: {candidate.ip_address}")
                
                # Get node details
                name = prompt_for_input("Node name", default=f"Node-{candidate.ip_address}")
                
                # Suggest ports based on discovered open ports
                suggested_port = 62050 if 62050 in candidate.open_ports else (candidate.open_ports[0] if candidate.open_ports else 62050)
                suggested_api_port = 62051 if 62051 in candidate.open_ports else (suggested_port + 1)
                
                port = int(prompt_for_input("Node port", default=str(suggested_port)))
                api_port = int(prompt_for_input("API port", default=str(suggested_api_port)))
                usage_coefficient = float(prompt_for_input("Usage coefficient", default="1.0"))
                
                add_as_host = confirm_action("Add as new host?", default=True)
                
                info_message(f"Creating node '{name}' from discovered candidate...")
                
                # Add the node using node service
                node = await self.node_service.create_node(
                    name=name,
                    address=candidate.ip_address,
                    port=port,
                    api_port=api_port,
                    usage_coefficient=usage_coefficient,
                    add_as_new_host=add_as_host
                )
                
                success_message(f"Node '{name}' added successfully!")
                display_node_details(node)
                
                if confirm_action("Wait for node to connect?", default=True):
                    info_message("Waiting for node to connect...")
                    connected = await self.node_service.wait_for_node_connection(node.id, timeout=60)
                    
                    if connected:
                        success_message("Node connected successfully!")
                    else:
                        warning_message("Node failed to connect within timeout")
            else:
                error_message("Invalid selection")
            
        except ValueError:
            error_message("Invalid input")
        except Exception as e:
            error_message(f"Failed to add discovered node: {e}")
        
        pause()
    
    async def _discovery_clear(self):
        """Clear discovered nodes cache."""
        try:
            from ...services.discovery_service import discovery_service
            
            discovered = discovery_service.get_discovered_nodes()
            
            if not discovered:
                info_message("No discovered nodes to clear")
                pause()
                return
            
            warning_message(f"This will clear {len(discovered)} discovered nodes from cache")
            
            if confirm_action("Are you sure you want to clear all discovered nodes?"):
                discovery_service.clear_discovered_nodes()
                success_message("✅ Discovered nodes cache cleared")
            else:
                info_message("Clear operation cancelled")
            
        except Exception as e:
            error_message(f"Failed to clear discovered nodes: {e}")
        
        pause()
    
    async def _discovery_stop(self):
        """Stop ongoing discovery scan."""
        try:
            from ...services.discovery_service import discovery_service
            
            if discovery_service.is_scanning:
                info_message("Stopping discovery scan...")
                discovery_service.stop_discovery()
                success_message("⏹️  Discovery scan stopped")
            else:
                warning_message("No discovery scan is currently running")
            
        except Exception as e:
            error_message(f"Failed to stop discovery: {e}")
        
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