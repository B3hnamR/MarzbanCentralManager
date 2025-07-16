# Marzban Central Manager v4.0
## Professional API-Based Management System

A comprehensive, API-driven management system for Marzban panel and nodes.

## 🏗️ Project Structure

```
MarzbanCentralManager/
├── src/                          # Source code
│   ├── core/                     # Core functionality
│   │   ├── config.py            # Configuration management
│   │   ├── logger.py            # Logging system
│   │   ├── exceptions.py        # Custom exceptions
│   │   └── utils.py             # Utility functions
│   ├── api/                     # API clients
│   │   ├── base.py              # Base API client
│   │   ├── auth.py              # Authentication handler
│   │   └── endpoints/           # API endpoints
│   │       ├── nodes.py         # Node management APIs
│   │       ├── users.py         # User management APIs
│   │       ├── admins.py        # Admin management APIs
│   │       └── system.py        # System APIs
│   ├── models/                  # Data models
│   │   ├── node.py              # Node model
│   │   ├── user.py              # User model
│   │   └── response.py          # API response models
│   ├── services/                # Business logic
│   │   ├── node_service.py      # Node management service
│   │   ├── monitoring.py       # Monitoring service
│   │   └── backup.py            # Backup service
│   └── cli/                     # Command line interface
│       ├── main.py              # Main CLI entry point
│       ├── commands/            # CLI commands
│       │   ├── node.py          # Node commands
│       │   ├── user.py          # User commands
│       │   └── system.py        # System commands
│       └── ui/                  # User interface
│           ├── menus.py         # Interactive menus
│           └── display.py       # Display utilities
├── config/                      # Configuration files
│   ├── settings.yaml           # Main settings
│   └── logging.yaml            # Logging configuration
├── tests/                       # Test files
│   ├── unit/                   # Unit tests
│   └── integration/            # Integration tests
���── docs/                       # Documentation
├── requirements.txt            # Python dependencies
└── main.py                     # Application entry point
```

## 🚀 Features

### Node Management
- ✅ Add/Remove nodes via API
- ✅ Monitor node status and health
- ✅ Update node configurations
- ✅ Reconnect nodes
- ✅ View usage statistics
- ✅ Certificate management

### Coming Soon
- 👥 User Management
- 🔧 Admin Management  
- 📊 System Monitoring
- 💾 Backup & Restore
- 📱 Telegram Notifications

## 🛠️ Technology Stack

- **Language**: Python 3.8+
- **HTTP Client**: httpx (async support)
- **CLI Framework**: Click
- **Configuration**: PyYAML
- **Data Validation**: Pydantic
- **Testing**: pytest
- **Logging**: structlog

## 🚀 Quick Start

### 📦 Automatic Installation (Recommended)

```bash
# Clone the repository
git clone https://github.com/B3hnamR/MarzbanCentralManager.git
cd MarzbanCentralManager

# Run the installation script
chmod +x install.sh
sudo ./install.sh

# Start the application
marzban-manager
```

### 📋 Manual Installation

```bash
# Install dependencies
pip install -r requirements.txt

# Start interactive mode
python3 marzban_manager.py

# Or use the main CLI
python3 main.py interactive
```

## 🎯 Usage

### 🖥️ Interactive Mode (Recommended)

```bash
# Quick start with professional menu
./marzban_manager.py

# Or system-wide command (after installation)
marzban-manager
```

### 📱 CLI Commands

```bash
# Configuration
python3 main.py config setup
python3 main.py config test

# Node management
python3 main.py node list
python3 main.py node add --name "Node1" --address "1.2.3.4"
python3 main.py node show 1
python3 main.py node delete 1

# Interactive mode
python3 main.py interactive
```

### ⚙️ Systemd Service (Linux)

```bash
# Start service
sudo systemctl start marzban-manager

# Enable auto-start
sudo systemctl enable marzban-manager

# Check status
sudo systemctl status marzban-manager
```