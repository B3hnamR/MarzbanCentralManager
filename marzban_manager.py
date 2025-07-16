#!/usr/bin/env python3
"""
🚀 Marzban Central Manager v4.0
Professional Interactive Management System

Quick start script for interactive mode.
"""

import sys
import os
import asyncio
from pathlib import Path

# Add src to Python path
sys.path.insert(0, str(Path(__file__).parent / "src"))

def check_requirements():
    """Check if required packages are installed."""
    required_packages = ['httpx', 'click', 'pyyaml', 'tabulate']
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package)
        except ImportError:
            missing_packages.append(package)
    
    if missing_packages:
        print("❌ Missing required packages:")
        for package in missing_packages:
            print(f"   - {package}")
        print("\n📦 Install them with:")
        print(f"   pip install {' '.join(missing_packages)}")
        print("\n   Or install all requirements:")
        print("   pip install -r requirements.txt")
        return False
    
    return True

def show_banner():
    """Show application banner."""
    banner = """
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                    🚀 Marzban Central Manager v4.0                          ║
║                   Professional API-Based Management System                  ║
║                                                                              ║
║  📋 Features:                                                                ║
║     • Complete Node Management via API                                      ║
║     • Interactive Professional Menu System                                  ║
║     • Real-time Status Monitoring                                           ║
║     • Usage Statistics & Reporting                                          ║
║     • Professional Logging System                                           ║
║     • Error Handling & Recovery                                             ║
║                                                                              ║
║  👨‍💻 Author: B3hnamR                                                          ║
║  📧 Email: behnamrjd@gmail.com                                               ║
║  🌐 GitHub: https://github.com/B3hnamR                                       ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
    """
    print(banner)

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
        print("\n🚀 Starting Marzban Central Manager...")
        print("   Press Ctrl+C to exit at any time\n")
        
        # Import and start the interactive menu
        from src.cli.ui.menus import start_interactive_menu
        
        # Run the interactive menu
        asyncio.run(start_interactive_menu())
        
    except KeyboardInterrupt:
        print("\n\n👋 Goodbye! Thanks for using Marzban Central Manager")
        sys.exit(0)
    except ImportError as e:
        print(f"\n❌ Import error: {e}")
        print("💡 Make sure you're running this from the project root directory")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        print("💡 Please check the logs for more details")
        sys.exit(1)

if __name__ == "__main__":
    main()