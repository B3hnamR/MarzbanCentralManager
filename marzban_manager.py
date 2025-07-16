#!/usr/bin/env python3
"""
🚀 Marzban Central Manager v4.0
Professional Interactive Management System

Quick start script for interactive mode with enhanced features.
"""

import sys
import os
import asyncio
from pathlib import Path

# Add src to Python path
sys.path.insert(0, str(Path(__file__).parent / "src"))

def check_requirements():
    """Check if required packages are installed."""
    required_packages = ['httpx', 'click', 'pyyaml', 'tabulate', 'psutil']
    optional_packages = ['paramiko', 'cryptography', 'pyjwt']
    
    missing_required = []
    missing_optional = []
    
    # Check required packages
    for package in required_packages:
        try:
            __import__(package)
        except ImportError:
            missing_required.append(package)
    
    # Check optional packages
    for package in optional_packages:
        try:
            __import__(package)
        except ImportError:
            missing_optional.append(package)
    
    if missing_required:
        print("❌ Missing required packages:")
        for package in missing_required:
            print(f"   - {package}")
        print("\n📦 Install them with:")
        print(f"   pip install {' '.join(missing_required)}")
        print("\n   Or install all requirements:")
        print("   pip install -r requirements.txt")
        return False
    
    if missing_optional:
        print("⚠️  Missing optional packages (some features may be limited):")
        for package in missing_optional:
            print(f"   - {package}")
        print("\n💡 Install them for full functionality:")
        print(f"   pip install {' '.join(missing_optional)}")
    
    return True

def show_banner():
    """Show application banner with updated features."""
    banner = """
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                    🚀 Marzban Central Manager v4.0                          ║
║                   Professional API-Based Management System                  ║
║                                                                              ║
║  ✨ New Features:                                                            ║
║     • 📊 Real-time Live Monitoring & Health Status                          ║
║     • 🔍 Auto-discovery of Marzban Nodes in Network                         ║
║     • 🎯 Smart Node Validation & Recommendations                            ║
║     • 🚨 Advanced Alert System with Real-time Notifications                 ║
║     • 📈 Historical Metrics & Performance Tracking                          ║
║                                                                              ║
║  📋 Core Features:                                                           ║
║     • Complete Node Management via API                                      ║
║     • Interactive Professional Menu System                                  ║
║     • Usage Statistics & Reporting                                          ║
║     • Professional Logging System                                           ║
║     • Error Handling & Recovery                                             ║
║     • Advanced Connection Management                                        ║
║                                                                              ║
║  🛠️  Available Interfaces:                                                   ║
║     • Interactive Menu (this interface)                                     ║
║     • Command Line Interface (CLI)                                          ║
║     • Direct Python API                                                     ║
║                                                                              ║
║  👨‍💻 Author: B3hnamR                                                          ║
║  📧 Email: behnamrjd@gmail.com                                               ║
║  🌐 GitHub: https://github.com/B3hnamR                                       ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
    """
    print(banner)

def show_quick_help():
    """Show quick help and usage examples."""
    help_text = """
🚀 Quick Start Guide:

📋 Interactive Menu (Current):
   • Navigate using numbers
   • Access all features through menus
   • Real-time monitoring and discovery

💻 Command Line Interface:
   python main.py --help                    # Show all commands
   python main.py config setup              # Setup Marzban connection
   python main.py node list                 # List all nodes
   python main.py monitor start             # Start real-time monitoring
   python main.py discover local            # Auto-discover local nodes

🔍 Discovery Examples:
   python main.py discover network 192.168.1.0/24    # Scan network range
   python main.py discover range 192.168.1.1 192.168.1.100  # Scan IP range
   python main.py discover candidates       # Show Marzban candidates

📊 Monitoring Examples:
   python main.py monitor start --interval 30    # Monitor every 30 seconds
   python main.py monitor alerts            # Show current alerts
   python main.py monitor summary           # Show health summary

💡 Tips:
   • Configure Marzban connection first (Menu → Configuration)
   • Use discovery to find nodes automatically
   • Enable monitoring for real-time health tracking
   • Check alerts regularly for system health
    """
    print(help_text)

def main():
    """Main entry point."""
    try:
        # Clear screen
        os.system('clear' if os.name == 'posix' else 'cls')
        
        # Show banner
        show_banner()
        
        # Check requirements
        print("🔍 Checking requirements...")
        if not check_requirements():
            sys.exit(1)
        
        print("✅ All requirements satisfied!")
        
        # Show quick help
        if len(sys.argv) > 1 and sys.argv[1] in ['--help', '-h', 'help']:
            show_quick_help()
            return
        
        print("\n🚀 Starting Marzban Central Manager...")
        print("   Press Ctrl+C to exit at any time")
        print("   Use --help for CLI commands\n")
        
        # Import and start the interactive menu
        from src.cli.ui.menus import start_interactive_menu
        
        # Run the interactive menu
        asyncio.run(start_interactive_menu())
        
    except KeyboardInterrupt:
        print("\n\n👋 Goodbye! Thanks for using Marzban Central Manager")
        print("💡 Tip: Use 'python main.py --help' for CLI commands")
        sys.exit(0)
    except ImportError as e:
        print(f"\n❌ Import error: {e}")
        print("💡 Make sure you're running this from the project root directory")
        print("💡 Install requirements: pip install -r requirements.txt")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        print("💡 Please check the logs for more details")
        print("💡 Try running: python main.py config setup")
        sys.exit(1)

def interactive():
    """Alternative entry point for interactive mode."""
    main()

if __name__ == "__main__":
    main()