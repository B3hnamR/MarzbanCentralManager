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

## 📦 Installation

```bash
pip install -r requirements.txt
python main.py
```

## 🔧 Configuration

Edit `config/settings.yaml` to configure your Marzban panel connection.

## 📖 Usage

```bash
# Interactive mode
python main.py

# Direct commands
python main.py node list
python main.py node add --name "Node1" --address "1.2.3.4"
python main.py node status --id 1
```