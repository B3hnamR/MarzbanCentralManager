# 🚀 Marzban Central Manager v4.0
## Professional API-Based Management System

A comprehensive, API-driven management system for Marzban panel and nodes with advanced monitoring and auto-discovery capabilities.

## ✨ New Features in v4.0

### 📊 Real-time Live Monitoring
- **Live Health Dashboard**: Real-time node status monitoring
- **Performance Metrics**: Response time, CPU, memory, and network usage tracking
- **Historical Data**: Store and analyze performance trends
- **Smart Alerts**: Automatic notifications for critical issues
- **Health Scoring**: Intelligent health assessment with confidence scores

### 🔍 Auto-discovery System
- **Network Scanning**: Automatically discover Marzban nodes in your network
- **Smart Detection**: Identify Marzban services using port scanning and service fingerprinting
- **Validation Engine**: Verify discovered nodes before adding them
- **Multiple Scan Types**: Local network, IP range, and custom network range scanning
- **Candidate Ranking**: Score potential nodes based on confidence levels

### 🎯 Enhanced Node Management
- **Advanced Connection Management**: Circuit breakers, retry logic, and connection pooling
- **Token Management**: Automatic token refresh and secure storage
- **Bulk Operations**: Manage multiple nodes simultaneously
- **Node Validation**: Comprehensive health checks and recommendations

## 🏗️ Project Structure

```
MarzbanCentralManager/
├── src/                          # Source code
│   ├── core/                     # Core functionality
│   │   ├── config.py            # Configuration management
│   │   ├── logger.py            # Advanced logging system
│   │   ├── exceptions.py        # Custom exceptions
│   │   ├── connection_manager.py # Advanced connection management
│   │   ├── token_manager.py     # Token management with auto-refresh
│   │   ├── cache_manager.py     # Intelligent caching system
│   │   ├── network_validator.py # Network validation utilities
│   │   └── utils.py             # Utility functions
│   ├── api/                     # API clients
│   │   ├── base.py              # Enhanced base API client
│   │   └── endpoints/           # API endpoints
│   │       ├── nodes.py         # Node management APIs
│   │       ├── users.py         # User management APIs
│   │       ├── admins.py        # Admin management APIs
│   │       └── system.py        # System APIs
│   ├── models/                  # Data models
│   │   ├── node.py              # Node model with status tracking
│   │   ├── user.py              # User model
│   │   └── response.py          # API response models
│   ├── services/                # Business logic
│   │   ├── node_service.py      # Enhanced node management
│   │   ├── monitoring_service.py # Real-time monitoring service
│   │   ├── discovery_service.py # Auto-discovery service
│   │   ├── node_validator_service.py # Node validation
│   │   └── bulk_operations_service.py # Bulk operations
│   └── cli/                     # Command line interface
│       ├── commands/            # CLI commands
│       │   ├── node.py          # Node commands
│       │   ├── monitor.py       # Monitoring commands
│       │   ├── discover.py      # Discovery commands
│       │   ├── user.py          # User commands
│       │   └── system.py        # System commands
│       └── ui/                  # User interface
│           ├── menus.py         # Enhanced interactive menus
│           ├── display.py       # Display utilities
│           └── enhanced_display.py # Advanced UI components
├── config/                      # Configuration files
├── tests/                       # Test files
├── docs/                        # Documentation
├── requirements.txt            # Python dependencies
├── main.py                     # Main CLI entry point
└── marzban_manager.py          # Quick start interactive mode
```

## 🚀 Features

### ✅ Node Management
- Add/Remove nodes via API with validation
- Real-time node status and health monitoring
- Update node configurations dynamically
- Automatic reconnection with retry logic
- Comprehensive usage statistics
- Certificate management and validation
- Bulk operations for multiple nodes

### ✅ Live Monitoring
- Real-time health dashboard
- Performance metrics tracking
- Historical data analysis
- Smart alert system
- Health scoring and recommendations
- Customizable monitoring intervals

### ✅ Auto-discovery
- Network scanning for Marzban nodes
- Smart service detection
- Node validation and scoring
- Multiple scanning methods
- Automatic node addition

### 🔄 Coming Soon
- 👥 Advanced User Management
- 🔧 Admin Management with RBAC
- 📊 Advanced Analytics Dashboard
- 💾 Backup & Restore System
- 📱 Telegram Bot Integration
- 🌐 Web Dashboard

## 🛠️ Technology Stack

- **Language**: Python 3.8+
- **HTTP Client**: httpx (async support)
- **CLI Framework**: Click
- **Configuration**: PyYAML
- **Monitoring**: psutil
- **Network Discovery**: netifaces
- **Security**: cryptography, PyJWT
- **Testing**: pytest, pytest-asyncio
- **Logging**: Advanced structured logging

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

## 🎯 Usage Examples

### 🖥️ Interactive Mode (Recommended)

```bash
# Quick start with professional menu
./marzban_manager.py

# Features available in interactive mode:
# 1. Node Management - Complete node lifecycle management
# 2. Live Monitoring - Real-time health dashboard
# 3. Auto Discovery - Network scanning and node discovery
# 4. Configuration - System settings and connection setup
```

### 📱 CLI Commands

#### Configuration
```bash
# Setup Marzban panel connection
python3 main.py config setup

# Test connection
python3 main.py config test

# Show current configuration
python3 main.py config show
```

#### Node Management
```bash
# List all nodes
python3 main.py node list

# Add a new node
python3 main.py node add --name "Node1" --address "192.168.1.100"

# Show node details
python3 main.py node show 1

# Update node
python3 main.py node update 1 --name "Updated Node"

# Delete node
python3 main.py node delete 1

# Get node status
python3 main.py node status

# Show healthy/unhealthy nodes
python3 main.py node healthy
python3 main.py node unhealthy
```

#### Live Monitoring
```bash
# Start real-time monitoring
python3 main.py monitor start --interval 30

# Show current monitoring status
python3 main.py monitor status

# View alerts
python3 main.py monitor alerts

# Show health summary
python3 main.py monitor summary

# Force metrics update
python3 main.py monitor force-update

# Stop monitoring
python3 main.py monitor stop
```

#### Auto-discovery
```bash
# Discover nodes in local network
python3 main.py discover network

# Scan specific network range
python3 main.py discover network --network 192.168.1.0/24

# Scan IP range
python3 main.py discover range 192.168.1.1 192.168.1.100

# List discovered nodes
python3 main.py discover list

# Show Marzban candidates
python3 main.py discover candidates

# Validate a specific IP
python3 main.py discover validate 192.168.1.100

# Add discovered node
python3 main.py discover add 192.168.1.100 --name "Discovered Node"

# Clear discovery cache
python3 main.py discover clear
```

### ⚙️ Advanced Usage

#### Deep Network Scanning
```bash
# Enable deep scan for detailed information
python3 main.py discover network --deep-scan --timeout 10

# Scan specific ports
python3 main.py discover network --ports 62050,62051,8080

# High concurrency scanning
python3 main.py discover range 192.168.1.1 192.168.1.254 --max-concurrent 100
```

#### Monitoring with Alerts
```bash
# Start monitoring with custom interval
python3 main.py monitor start --interval 15

# Monitor for specific duration
python3 main.py monitor start --duration 3600  # 1 hour

# Show only alerts
python3 main.py monitor start --alerts-only
```

## 📊 Monitoring Dashboard

The live monitoring system provides:

- **Real-time Metrics**: Node status, response times, health scores
- **Visual Indicators**: Color-coded health status (🟢 Healthy, 🟡 Warning, 🔴 Critical)
- **Alert System**: Automatic notifications for issues
- **Historical Tracking**: Performance trends over time
- **Health Scoring**: Intelligent assessment of node health

## 🔍 Discovery System

The auto-discovery feature includes:

- **Network Scanning**: Automatic detection of devices in your network
- **Service Fingerprinting**: Identify Marzban services by port and banner analysis
- **Validation Engine**: Comprehensive checks before adding nodes
- **Confidence Scoring**: Rate potential nodes based on detection confidence
- **Multiple Methods**: Ping sweep, port scanning, ARP scanning, and more

## 🛡️ Security Features

- **Secure Token Management**: Automatic token refresh and secure storage
- **Connection Encryption**: All API communications are encrypted
- **Input Validation**: Comprehensive validation of all inputs
- **Error Handling**: Graceful handling of network and API errors
- **Circuit Breakers**: Automatic protection against failing services

## 📝 Configuration

### Main Configuration File
```yaml
# config/settings.yaml
marzban:
  base_url: "https://your-panel.com:8000"
  username: "admin"
  password: "your-password"
  timeout: 30
  verify_ssl: true

monitoring:
  interval: 30
  history_size: 100
  alert_thresholds:
    response_time: 1000  # ms
    health_percentage: 80

discovery:
  timeout: 5
  max_concurrent: 50
  target_ports: [62050, 62051, 22, 80, 443, 8080, 8443]
```

## 🐛 Troubleshooting

### Common Issues

1. **Connection Failed**
   ```bash
   # Test your connection
   python3 main.py config test
   
   # Check configuration
   python3 main.py config show
   ```

2. **Discovery Not Finding Nodes**
   ```bash
   # Try with deep scan
   python3 main.py discover network --deep-scan
   
   # Check specific IP
   python3 main.py discover validate <IP_ADDRESS>
   ```

3. **Monitoring Issues**
   ```bash
   # Force update metrics
   python3 main.py monitor force-update
   
   # Check monitoring status
   python3 main.py monitor status
   ```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👨‍💻 Author

**B3hnamR**
- Email: behnamrjd@gmail.com
- GitHub: [@B3hnamR](https://github.com/B3hnamR)

## 🙏 Acknowledgments

- Marzban project for the excellent VPN panel
- Python community for amazing libraries
- Contributors and users for feedback and suggestions

---

**⭐ If you find this project useful, please give it a star!**