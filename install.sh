#!/bin/bash

# Marzban Central Manager v4.0 - Professional Installation Script
# Author: B3hnamR
# Email: behnamrjd@gmail.com

set -e

# Default options
USE_VENV=true  # Default to virtual environment (best practice)
INSTALL_OPTIONAL=false
SKIP_TESTS=false
FORCE_INSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --system)
            USE_VENV=false
            shift
            ;;
        --venv)
            USE_VENV=true
            shift
            ;;
        --with-optional)
            INSTALL_OPTIONAL=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --help|-h)
            echo "Marzban Central Manager v4.0 - Installation Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --venv           Install in virtual environment (default)"
            echo "  --system         Install system-wide (requires root)"
            echo "  --with-optional  Install optional dependencies (dev tools)"
            echo "  --skip-tests     Skip installation tests"
            echo "  --force          Force installation without prompts"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Install with virtual environment (recommended)"
            echo "  $0 --system          # Install system-wide"
            echo "  $0 --with-optional   # Install with development tools"
            echo "  $0 --force           # Install without prompts"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    clear
    echo ""
    print_color $CYAN "╔═══════════��══════════════════════════════════════════════════════════════════╗"
    print_color $CYAN "║                                                                              ║"
    print_color $CYAN "║                    🚀 Marzban Central Manager v4.0                          ║"
    print_color $CYAN "║                     Professional Installation Script                        ║"
    print_color $CYAN "║                                                                              ║"
    print_color $CYAN "║  ✨ Features: Live Monitoring • Auto-discovery • Node Management           ║"
    print_color $CYAN "║                                                                              ║"
    print_color $CYAN "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_step() {
    print_color $BLUE "🔄 $1"
}

print_success() {
    print_color $GREEN "✅ $1"
}

print_error() {
    print_color $RED "❌ $1"
}

print_warning() {
    print_color $YELLOW "⚠️  $1"
}

print_info() {
    print_color $PURPLE "ℹ️  $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Check system requirements
check_requirements() {
    print_step "Checking system requirements..."
    
    # Check Python version
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
        PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d'.' -f1)
        PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d'.' -f2)
        
        if [[ $PYTHON_MAJOR -ge 3 && $PYTHON_MINOR -ge 8 ]]; then
            print_success "Python $PYTHON_VERSION found"
        else
            print_error "Python 3.8+ required, found $PYTHON_VERSION"
            print_info "Please install Python 3.8 or higher"
            exit 1
        fi
    else
        print_error "Python 3 not found"
        print_info "Please install Python 3.8+ first:"
        print_info "  Ubuntu/Debian: sudo apt update && sudo apt install python3 python3-pip python3-venv"
        print_info "  CentOS/RHEL: sudo yum install python3 python3-pip"
        print_info "  Arch: sudo pacman -S python python-pip"
        exit 1
    fi
    
    # Check pip
    if command -v pip3 &> /dev/null; then
        print_success "pip3 found"
    else
        print_error "pip3 not found"
        print_info "Please install pip3 first"
        exit 1
    fi
    
    # Check venv module if using virtual environment
    if [[ "$USE_VENV" == "true" ]]; then
        if python3 -c "import venv" 2>/dev/null; then
            print_success "Python venv module available"
        else
            print_error "Python venv module not found"
            print_info "Please install python3-venv:"
            print_info "  Ubuntu/Debian: sudo apt install python3-venv"
            exit 1
        fi
    fi
    
    # Check git (optional)
    if command -v git &> /dev/null; then
        print_success "git found"
    else
        print_warning "git not found (optional)"
    fi
    
    # Check available disk space
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 100000 ]]; then  # Less than ~100MB
        print_warning "Low disk space available"
    fi
}

# Show installation summary
show_installation_summary() {
    print_color $BOLD "📋 Installation Summary:"
    echo ""
    
    if [[ "$USE_VENV" == "true" ]]; then
        print_color $GREEN "   🔒 Installation Type: Virtual Environment (Recommended)"
        print_color $WHITE "   📁 Location: $(pwd)/venv"
    else
        print_color $YELLOW "   🌐 Installation Type: System-wide"
        if check_root; then
            print_color $WHITE "   📁 Location: System Python packages"
        else
            print_color $WHITE "   📁 Location: User Python packages"
        fi
    fi
    
    if [[ "$INSTALL_OPTIONAL" == "true" ]]; then
        print_color $BLUE "   🛠️  Optional Dependencies: Yes (development tools)"
    else
        print_color $WHITE "   🛠️  Optional Dependencies: No"
    fi
    
    if [[ "$SKIP_TESTS" == "true" ]]; then
        print_color $YELLOW "   🧪 Installation Tests: Skipped"
    else
        print_color $GREEN "   🧪 Installation Tests: Enabled"
    fi
    
    echo ""
}

# Confirm installation
confirm_installation() {
    if [[ "$FORCE_INSTALL" == "true" ]]; then
        return 0
    fi
    
    show_installation_summary
    
    # Special warning for system-wide installation
    if [[ "$USE_VENV" == "false" ]]; then
        print_warning "System-wide installation may conflict with existing packages"
        print_info "Virtual environment is recommended for safety"
        echo ""
    fi
    
    read -p "Continue with installation? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
    echo ""
}

# Install Python dependencies
install_dependencies() {
    print_step "Installing Python dependencies..."
    
    # Setup virtual environment if requested
    if [[ "$USE_VENV" == "true" ]]; then
        if [[ -d "venv" ]]; then
            print_warning "Virtual environment already exists"
            if [[ "$FORCE_INSTALL" != "true" ]]; then
                read -p "Remove existing virtual environment? (y/N): " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm -rf venv
                    print_info "Existing virtual environment removed"
                else
                    print_info "Using existing virtual environment"
                fi
            else
                rm -rf venv
                print_info "Existing virtual environment removed (force mode)"
            fi
        fi
        
        if [[ ! -d "venv" ]]; then
            print_step "Creating virtual environment..."
            python3 -m venv venv
            print_success "Virtual environment created"
        fi
        
        print_step "Activating virtual environment..."
        source venv/bin/activate
        print_success "Virtual environment activated"
        
        # Create activation script for future use
        cat > activate_venv.sh << 'EOF'
#!/bin/bash
# Marzban Central Manager - Virtual Environment Activation Script

if [[ ! -d "venv" ]]; then
    echo "❌ Virtual environment not found!"
    echo "💡 Run ./install.sh to install first"
    exit 1
fi

source venv/bin/activate

echo "🟢 Virtual environment activated"
echo "📁 Location: $(pwd)/venv"
echo "🐍 Python: $(python --version)"
echo ""
echo "🚀 To run Marzban Central Manager:"
echo "   ./marzban_manager.py"
echo ""
echo "💡 To deactivate: deactivate"
EOF
        chmod +x activate_venv.sh
        print_success "Created activate_venv.sh script"
    fi
    
    # Upgrade pip first
    print_step "Upgrading pip..."
    pip install --upgrade pip --quiet
    print_success "pip upgraded"
    
    # Install dependencies
    if [[ -f "requirements.txt" ]]; then
        print_step "Installing core dependencies from requirements.txt..."
        pip install -r requirements.txt --quiet
        print_success "Core dependencies installed"
        
        # Install optional dependencies if requested
        if [[ "$INSTALL_OPTIONAL" == "true" ]]; then
            print_step "Installing optional development dependencies..."
            pip install pytest pytest-asyncio black flake8 mypy --quiet
            print_success "Optional dependencies installed"
        fi
    else
        print_warning "requirements.txt not found, installing core dependencies manually..."
        pip install httpx>=0.25.0 click>=8.1.0 pyyaml>=6.0 tabulate>=0.9.0 psutil>=5.9.0 netifaces>=0.11.0 --quiet
        
        if [[ "$INSTALL_OPTIONAL" == "true" ]]; then
            pip install cryptography>=41.0.0 pyjwt>=2.8.0 paramiko>=3.0.0 --quiet
        fi
        
        print_success "Core dependencies installed"
    fi
    
    # Show installed packages summary
    print_info "Installed packages: $(pip list --format=freeze | wc -l) total"
}

# Setup directories and permissions
setup_directories() {
    print_step "Setting up directories and permissions..."
    
    # Create necessary directories
    mkdir -p config logs
    
    # Set appropriate permissions
    chmod 755 config logs
    
    # Make scripts executable
    chmod +x marzban_manager.py main.py 2>/dev/null || true
    
    # Create .gitignore for logs and config if not exists
    if [[ ! -f ".gitignore" ]]; then
        cat > .gitignore << 'EOF'
# Logs
logs/*.log
*.log

# Configuration files with sensitive data
config/settings.yaml
config/local_*.yaml

# Virtual environment
venv/
__pycache__/
*.pyc
*.pyo

# IDE files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db
EOF
        print_info "Created .gitignore file"
    fi
    
    print_success "Directories and permissions configured"
}

# Create systemd service (only for system-wide installation with root)
create_systemd_service() {
    if [[ "$USE_VENV" == "false" ]] && check_root; then
        print_step "Creating systemd service..."
        
        local service_file="/etc/systemd/system/marzban-manager.service"
        local install_dir=$(pwd)
        local python_exec="/usr/bin/python3"
        
        cat > "$service_file" << EOF
[Unit]
Description=Marzban Central Manager
Documentation=https://github.com/B3hnamR/MarzbanCentralManager
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$install_dir
ExecStart=$python_exec $install_dir/marzban_manager.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$install_dir

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        print_success "Systemd service created"
        print_info "Service commands:"
        print_info "  Start: systemctl start marzban-manager"
        print_info "  Enable: systemctl enable marzban-manager"
        print_info "  Status: systemctl status marzban-manager"
    fi
}

# Create shortcuts and commands
create_shortcuts() {
    print_step "Creating shortcuts and commands..."
    
    # Make main scripts executable
    chmod +x marzban_manager.py main.py test_install.py 2>/dev/null || true
    
    # Create system-wide command if root and system installation
    if [[ "$USE_VENV" == "false" ]] && check_root; then
        ln -sf "$(pwd)/marzban_manager.py" /usr/local/bin/marzban-manager
        print_success "Created system-wide command: marzban-manager"
    fi
    
    # Create convenient run script
    if [[ "$USE_VENV" == "true" ]]; then
        cat > run.sh << 'EOF'
#!/bin/bash
# Marzban Central Manager - Quick Run Script

cd "$(dirname "$0")"

if [[ ! -d "venv" ]]; then
    echo "❌ Virtual environment not found!"
    echo "💡 Run ./install.sh to install first"
    exit 1
fi

source venv/bin/activate
exec ./marzban_manager.py "$@"
EOF
        chmod +x run.sh
        print_success "Created run.sh script for easy execution"
    fi
    
    print_success "Shortcuts created"
}

# Test installation
test_installation() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        print_warning "Skipping installation tests as requested"
        return 0
    fi
    
    print_step "Testing installation..."
    
    # Test using dedicated test script
    if [[ -f "test_install.py" ]]; then
        if python3 test_install.py; then
            print_success "All installation tests passed"
        else
            print_error "Installation tests failed"
            print_info "Try running: python3 test_install.py"
            exit 1
        fi
    else
        # Fallback basic test
        print_step "Running basic functionality test..."
        python3 -c "
import sys
sys.path.insert(0, 'src')
try:
    from src.core.utils import is_valid_ip
    from src.core.logger import get_logger
    from src.models.node import Node, NodeStatus
    
    # Test basic functionality
    assert is_valid_ip('192.168.1.1') == True
    assert is_valid_ip('invalid') == False
    
    logger = get_logger('test')
    assert logger is not None
    
    print('✅ Basic functionality test passed')
except Exception as e:
    print(f'❌ Basic test failed: {e}')
    sys.exit(1)
"
        
        if [[ $? -eq 0 ]]; then
            print_success "Basic installation test passed"
        else
            print_error "Basic installation test failed"
            exit 1
        fi
    fi
}

# Show final usage instructions
show_usage_instructions() {
    print_color $WHITE "╔════════════════════════════════════��═════════════════════════════════════════╗"
    print_color $WHITE "║                              🎉 Installation Complete!                      ║"
    print_color $WHITE "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    print_color $GREEN "🚀 How to run Marzban Central Manager:"
    echo ""
    
    if [[ "$USE_VENV" == "true" ]]; then
        print_color $CYAN "   📦 Virtual Environment Mode:"
        print_color $WHITE "   ./run.sh                              # Quick run (recommended)"
        print_color $WHITE "   ./activate_venv.sh && ./marzban_manager.py  # Manual activation"
        echo ""
        
        print_color $CYAN "   🔧 CLI Commands:"
        print_color $WHITE "   ./activate_venv.sh && python3 main.py interactive"
        print_color $WHITE "   ./activate_venv.sh && python3 main.py config setup"
        print_color $WHITE "   ./activate_venv.sh && python3 main.py node list"
        echo ""
    else
        if check_root; then
            print_color $CYAN "   🌐 System-wide Commands:"
            print_color $WHITE "   marzban-manager                       # Global command"
            print_color $WHITE "   systemctl start marzban-manager       # As service"
            echo ""
        fi
        
        print_color $CYAN "   📁 Direct Execution:"
        print_color $WHITE "   ./marzban_manager.py"
        print_color $WHITE "   python3 main.py interactive"
        echo ""
    fi
    
    print_color $YELLOW "📋 Quick Start Steps:"
    print_color $WHITE "   1. Run the application"
    if [[ "$USE_VENV" == "true" ]]; then
        print_color $WHITE "      ./run.sh"
    else
        print_color $WHITE "      ./marzban_manager.py"
    fi
    print_color $WHITE "   2. Configure Marzban panel connection (Menu → Configuration)"
    print_color $WHITE "   3. Add your first node (Menu → Node Management)"
    print_color $WHITE "   4. Start live monitoring (Menu → Live Monitoring)"
    print_color $WHITE "   5. Try auto-discovery (Menu → Auto Discovery)"
    echo ""
    
    print_color $PURPLE "📚 Documentation:"
    print_color $WHITE "   • README.md - Complete documentation"
    print_color $WHITE "   • QUICK_START.md - Quick start guide"
    print_color $WHITE "   • ARCHITECTURE.md - Technical architecture"
    print_color $WHITE "   • DEVELOPER_GUIDE.md - For developers"
    echo ""
    
    print_color $BLUE "💡 Support & Community:"
    print_color $WHITE "   • GitHub: https://github.com/B3hnamR/MarzbanCentralManager"
    print_color $WHITE "   • Issues: Report bugs and request features"
    print_color $WHITE "   • Email: behnamrjd@gmail.com"
    echo ""
    
    print_color $GREEN "✨ Available Features:"
    print_color $WHITE "   • 🔧 Complete node management with validation"
    print_color $WHITE "   • 📊 Real-time monitoring with smart alerts"
    print_color $WHITE "   • 🔍 Auto-discovery of Marzban nodes in network"
    print_color $WHITE "   • 🎛️ Interactive menu and powerful CLI interface"
    print_color $WHITE "   • 📈 Performance tracking and health scoring"
    print_color $WHITE "   • 🔒 Secure token management and encryption"
    echo ""
    
    if [[ "$USE_VENV" == "true" ]]; then
        print_color $CYAN "💡 Virtual Environment Tips:"
        print_color $WHITE "   • Use ./run.sh for the easiest experience"
        print_color $WHITE "   • Activate manually: source venv/bin/activate"
        print_color $WHITE "   • Deactivate: deactivate"
        print_color $WHITE "   • Update: ./install.sh --force"
        echo ""
    fi
}

# Cleanup function for interrupted installation
cleanup() {
    if [[ "$USE_VENV" == "true" ]] && [[ -d "venv" ]] && [[ "$installation_completed" != "true" ]]; then
        print_warning "Installation interrupted, cleaning up..."
        rm -rf venv activate_venv.sh run.sh 2>/dev/null || true
    fi
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main installation function
main() {
    local installation_completed=false
    
    print_header
    
    # Show installation mode
    if [[ "$USE_VENV" == "true" ]]; then
        print_info "Installation Mode: Virtual Environment (Recommended)"
    else
        print_info "Installation Mode: System-wide"
        if ! check_root && [[ "$USE_VENV" == "false" ]]; then
            print_warning "Running as non-root user for system-wide installation"
            print_info "Some features (systemd service, global commands) will be unavailable"
        fi
    fi
    echo ""
    
    # Confirm installation
    confirm_installation
    
    # Check system requirements
    check_requirements
    
    # Install dependencies
    install_dependencies
    
    # Setup directories and permissions
    setup_directories
    
    # Create shortcuts and services
    create_shortcuts
    create_systemd_service
    
    # Test installation
    test_installation
    
    # Mark installation as completed
    installation_completed=true
    
    # Show usage instructions
    show_usage_instructions
    
    print_success "Installation completed successfully! 🎉"
    
    if [[ "$USE_VENV" == "true" ]]; then
        print_color $BOLD "🚀 Quick start: ./run.sh"
    else
        print_color $BOLD "🚀 Quick start: ./marzban_manager.py"
    fi
}

# Run main function
main "$@"