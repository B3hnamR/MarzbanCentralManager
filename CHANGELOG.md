# Changelog

All notable changes to Marzban Central Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2024-01-XX

### 🎉 Major Release - Complete Rewrite

This is a major release with significant new features and improvements.

### ✨ Added

#### 📊 Real-time Live Monitoring System
- **Live Health Dashboard**: Real-time monitoring of all nodes with visual indicators
- **Performance Metrics**: Track response times, health status, and system performance
- **Historical Data**: Store and analyze performance trends over time
- **Smart Alert System**: Automatic notifications for critical issues and warnings
- **Health Scoring**: Intelligent assessment with confidence scores
- **Customizable Intervals**: Configure monitoring frequency (default: 30 seconds)
- **Interactive Dashboard**: Live updating display with color-coded status indicators

#### 🔍 Auto-discovery System
- **Network Scanning**: Automatically discover Marzban nodes in your network
- **Multiple Scan Types**: 
  - Local network auto-discovery
  - Custom network range scanning (CIDR notation)
  - IP range scanning (start-end)
- **Smart Detection**: Identify Marzban services using:
  - Port scanning (62050, 62051, 8000, 8080, etc.)
  - Service fingerprinting and banner analysis
  - HTTP response analysis
- **Validation Engine**: Comprehensive node validation before adding
- **Confidence Scoring**: Rate discovered nodes based on detection confidence
- **Deep Scanning**: Optional detailed analysis for better accuracy
- **Concurrent Scanning**: High-performance parallel scanning

#### 🎯 Enhanced Node Management
- **Advanced Connection Management**: 
  - Circuit breakers for fault tolerance
  - Automatic retry logic with exponential backoff
  - Connection pooling for better performance
- **Token Management**: 
  - Automatic token refresh
  - Secure token storage
  - Session management
- **Bulk Operations**: Manage multiple nodes simultaneously
- **Node Validation**: Comprehensive health checks and recommendations
- **Enhanced Status Tracking**: Detailed node state management

#### 🖥️ Improved User Interface
- **Enhanced Interactive Menu**: 
  - New monitoring and discovery sections
  - Better navigation and user experience
  - Real-time status updates
- **Advanced CLI Commands**:
  - `monitor` command group for live monitoring
  - `discover` command group for auto-discovery
  - Enhanced `node` commands with new features
- **Professional Display**: 
  - Color-coded status indicators
  - Progress bars for long operations
  - Tabular data presentation
  - Real-time updating displays

#### 🛡️ Security & Reliability
- **Enhanced Error Handling**: Graceful handling of network and API errors
- **Input Validation**: Comprehensive validation of all user inputs
- **Secure Communications**: All API communications are encrypted
- **Fault Tolerance**: Circuit breakers and retry mechanisms
- **Logging Improvements**: Structured logging with different levels

### 🔧 Technical Improvements

#### Core Architecture
- **Modular Design**: Better separation of concerns
- **Async/Await**: Full asynchronous operation support
- **Type Hints**: Complete type annotation for better code quality
- **Error Handling**: Comprehensive exception handling system
- **Caching System**: Intelligent caching for better performance

#### New Services
- `MonitoringService`: Real-time monitoring and health tracking
- `DiscoveryService`: Network scanning and node discovery
- `NodeValidatorService`: Node validation and health checks
- `BulkOperationsService`: Batch operations on multiple nodes
- `ConnectionManager`: Advanced connection management
- `TokenManager`: Secure token management with auto-refresh
- `CacheManager`: Intelligent caching system

#### Enhanced CLI
- **Command Groups**: Organized commands into logical groups
- **Rich Output**: Color-coded and formatted output
- **Progress Indicators**: Visual feedback for long operations
- **Interactive Prompts**: User-friendly input collection
- **Help System**: Comprehensive help and examples

### 🔄 Changed

#### Breaking Changes
- **CLI Structure**: Commands are now organized into groups
  - `python main.py node <command>` instead of `python main.py <command>`
  - New command groups: `monitor`, `discover`, `config`
- **Configuration Format**: Enhanced configuration structure
- **API Client**: Complete rewrite with advanced features

#### Improvements
- **Performance**: Significantly faster operations with async/await
- **Reliability**: Better error handling and recovery
- **User Experience**: More intuitive interface and better feedback
- **Code Quality**: Complete type annotations and better structure

### 📦 Dependencies

#### New Dependencies
- `psutil>=5.9.0` - System resource monitoring
- `netifaces>=0.11.0` - Network interface discovery
- `cryptography>=41.0.0` - Enhanced security
- `pyjwt>=2.8.0` - JWT token handling

#### Updated Dependencies
- `httpx>=0.25.0` - Latest async HTTP client
- `click>=8.1.0` - Enhanced CLI framework
- `pyyaml>=6.0` - Latest YAML parser
- `tabulate>=0.9.0` - Table formatting

### 🐛 Fixed
- **Connection Issues**: Improved connection stability and error handling
- **Token Expiration**: Automatic token refresh prevents authentication errors
- **Memory Leaks**: Better resource management and cleanup
- **Race Conditions**: Proper async handling prevents race conditions
- **Input Validation**: Comprehensive validation prevents invalid operations

### 📚 Documentation
- **Complete README**: Comprehensive documentation with examples
- **API Documentation**: Detailed API reference
- **Usage Examples**: Practical examples for all features
- **Troubleshooting Guide**: Common issues and solutions

## [3.x.x] - Previous Versions

### Legacy Features
- Basic node management
- Simple CLI interface
- Configuration management
- Basic API integration

---

## Migration Guide from v3.x to v4.0

### CLI Commands
```bash
# Old (v3.x)
python main.py list-nodes
python main.py add-node

# New (v4.0)
python main.py node list
python main.py node add
```

### Configuration
The configuration format has been enhanced. Run `python main.py config setup` to migrate your settings.

### New Features to Try
```bash
# Start live monitoring
python main.py monitor start

# Discover nodes in your network
python main.py discover network

# Use the enhanced interactive menu
python main.py interactive
```

---

## Upcoming Features (v4.1+)

### Planned Features
- 🌐 **Web Dashboard**: Browser-based management interface
- 📱 **Telegram Bot**: Telegram integration for notifications and management
- 👥 **Advanced User Management**: Complete user lifecycle management
- 🔧 **Admin Management**: Role-based access control
- 💾 **Backup & Restore**: Automated backup system
- 📊 **Analytics Dashboard**: Advanced analytics and reporting
- 🔄 **Auto-scaling**: Automatic node scaling based on load
- 🌍 **Multi-language Support**: Internationalization support

### Community Requests
- Docker containerization
- Kubernetes deployment
- REST API server mode
- Plugin system
- Custom themes

---

**Note**: This changelog follows [Keep a Changelog](https://keepachangelog.com/) format. For detailed commit history, see the Git log.