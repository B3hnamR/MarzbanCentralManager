#!/bin/bash

# Marzban Central Manager v4.0 - Installation Script
# Author: B3hnamR

set -e

# Default options
USE_VENV=false
INSTALL_OPTIONAL=false
SKIP_TESTS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        --help|-h)
            echo "Marzban Central Manager Installation Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --venv           Install in virtual environment"
            echo "  --with-optional  Install optional dependencies"
            echo "  --skip-tests     Skip installation tests"
            echo "  --help, -h       Show this help message"
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
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo ""
    print_color $CYAN "╔══════════════════════════════════════════════════════════════════════════════╗"
    print_color $CYAN "║                                                                              ║"
    print_color $CYAN "║                    🚀 Marzban Central Manager v4.0                          ║"
    print_color $CYAN "║                        Installation & Setup Script                         ║"
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
        print_warning "Running as root. This is recommended for system-wide installation."
        return 0
    else
        print_info "Running as regular user. Will install in user directory."
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
            exit 1
        fi
    else
        print_error "Python 3 not found. Please install Python 3.8+"
        exit 1
    fi
    
    # Check pip
    if command -v pip3 &> /dev/null; then
        print_success "pip3 found"
    else
        print_error "pip3 not found. Please install pip3"
        exit 1
    fi
    
    # Check git (optional)
    if command -v git &> /dev/null; then
        print_success "git found"
    else
        print_warning "git not found. Manual installation required"
    fi
}

# Install Python dependencies
install_dependencies() {
    print_step "Installing Python dependencies..."
    
    # Check if virtual environment should be used
    if [[ "$USE_VENV" == "true" ]]; then
        print_step "Creating virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        print_success "Virtual environment created and activated"
        
        # Create activation script for future use
        cat > activate_venv.sh << 'EOF'
#!/bin/bash
source venv/bin/activate
echo "Virtual environment activated"
echo "To run the application: ./marzban_manager.py"
EOF
        chmod +x activate_venv.sh
        print_info "Created activate_venv.sh for future use"
    fi
    
    # Upgrade pip first
    pip3 install --upgrade pip
    
    if [[ -f "requirements.txt" ]]; then
        pip3 install -r requirements.txt
        print_success "Dependencies installed successfully"
        
        # Install optional dependencies if requested
        if [[ "$INSTALL_OPTIONAL" == "true" ]]; then
            print_step "Installing optional dependencies..."
            pip3 install pytest pytest-asyncio black flake8 cryptography pyjwt paramiko
            print_success "Optional dependencies installed"
        fi
    else
        print_warning "requirements.txt not found, installing core dependencies..."
        pip3 install httpx>=0.25.0 click>=8.1.0 pyyaml>=6.0 tabulate>=0.9.0 psutil>=5.9.0 netifaces>=0.11.0
        
        if [[ "$INSTALL_OPTIONAL" == "true" ]]; then
            pip3 install cryptography>=41.0.0 pyjwt>=2.8.0 paramiko>=3.0.0
        fi
        
        print_success "Core dependencies installed"
    fi
}

# Setup directories
setup_directories() {
    print_step "Setting up directories..."
    
    # Create config directory if it doesn't exist
    mkdir -p config
    
    # Create logs directory
    mkdir -p logs
    
    # Set permissions
    chmod 755 config logs
    
    print_success "Directories created"
}

# Create systemd service (if running as root)
create_systemd_service() {
    if check_root; then
        print_step "Creating systemd service..."
        
        local service_file="/etc/systemd/system/marzban-manager.service"
        local install_dir=$(pwd)
        
        cat > "$service_file" << EOF
[Unit]
Description=Marzban Central Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$install_dir
ExecStart=/usr/bin/python3 $install_dir/marzban_manager.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        print_success "Systemd service created"
        print_info "You can now use: systemctl start marzban-manager"
    fi
}

# Create desktop shortcut
create_shortcut() {
    print_step "Creating executable shortcut..."
    
    # Make main script executable
    chmod +x marzban_manager.py
    chmod +x main.py
    
    # Create symlink in /usr/local/bin if running as root
    if check_root; then
        ln -sf "$(pwd)/marzban_manager.py" /usr/local/bin/marzban-manager
        print_success "Created system-wide command: marzban-manager"
    else
        print_info "Add $(pwd) to your PATH to use marzban_manager.py globally"
    fi
}

# Test installation
test_installation() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        print_warning "Skipping installation tests as requested"
        return 0
    fi
    
    print_step "Testing installation..."
    
    # Use the dedicated test script
    if [[ -f "test_install.py" ]]; then
        python3 test_install.py
        local test_result=$?
        
        if [[ $test_result -eq 0 ]]; then
            print_success "All installation tests passed successfully"
        else
            print_error "Installation tests failed"
            exit 1
        fi
    else
        # Fallback to basic test
        print_step "Running basic import test..."
        python3 -c "
import sys
sys.path.insert(0, 'src')
try:
    from src.core.utils import is_valid_ip
    from src.core.logger import get_logger
    assert is_valid_ip('192.168.1.1') == True
    print('✅ Basic test passed')
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

# Show usage instructions
show_usage() {
    print_color $WHITE "╔══════════════════════════════════════════════════════════════════════════════╗"
    print_color $WHITE "║                              🎉 Installation Complete!                      ║"
    print_color $WHITE "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    print_color $GREEN "🚀 How to run Marzban Central Manager:"
    echo ""
    
    if check_root; then
        print_color $CYAN "   System-wide command:"
        print_color $WHITE "   marzban-manager"
        echo ""
        
        print_color $CYAN "   Or using systemd:"
        print_color $WHITE "   systemctl start marzban-manager"
        print_color $WHITE "   systemctl enable marzban-manager  # Auto-start on boot"
        echo ""
    fi
    
    if [[ "$USE_VENV" == "true" ]]; then
        print_color $CYAN "   With virtual environment:"
        print_color $WHITE "   ./activate_venv.sh && ./marzban_manager.py"
        echo ""
    fi
    
    print_color $CYAN "   Direct execution:"
    print_color $WHITE "   ./marzban_manager.py"
    echo ""
    
    print_color $CYAN "   CLI mode examples:"
    print_color $WHITE "   python3 main.py interactive          # Interactive menu"
    print_color $WHITE "   python3 main.py config setup        # Setup configuration"
    print_color $WHITE "   python3 main.py node list           # List nodes"
    print_color $WHITE "   python3 main.py monitor start       # Start monitoring"
    print_color $WHITE "   python3 main.py discover network    # Auto-discover nodes"
    echo ""
    
    print_color $YELLOW "📋 Next steps:"
    print_color $WHITE "   1. Run the application: ./marzban_manager.py"
    print_color $WHITE "   2. Configure Marzban panel connection (Menu → Configuration)"
    print_color $WHITE "   3. Add your first node (Menu → Node Management)"
    print_color $WHITE "   4. Start live monitoring (Menu → Live Monitoring)"
    print_color $WHITE "   5. Try auto-discovery (Menu → Auto Discovery)"
    echo ""
    
    print_color $PURPLE "📚 Documentation:"
    print_color $WHITE "   • README.md - Complete documentation"
    print_color $WHITE "   ��� QUICK_START.md - Quick start guide"
    print_color $WHITE "   • ARCHITECTURE.md - Technical architecture"
    print_color $WHITE "   • DEVELOPER_GUIDE.md - For developers"
    echo ""
    
    print_color $BLUE "💡 Support & Community:"
    print_color $WHITE "   • GitHub: https://github.com/B3hnamR/MarzbanCentralManager"
    print_color $WHITE "   • Issues: Report bugs and request features"
    print_color $WHITE "   • Email: behnamrjd@gmail.com"
    echo ""
    
    print_color $GREEN "✨ Features available:"
    print_color $WHITE "   • 🔧 Complete node management"
    print_color $WHITE "   • 📊 Real-time monitoring with alerts"
    print_color $WHITE "   • 🔍 Auto-discovery of Marzban nodes"
    print_color $WHITE "   • 🎛️ Interactive menu and CLI interface"
    print_color $WHITE "   • 📈 Performance tracking and health scoring"
    echo ""
}

# Main installation function
main() {
    print_header
    
    # Show recommendation for virtual environment if running as root
    if [[ "$USE_VENV" != "true" ]] && [[ $EUID -eq 0 ]]; then
        print_color $YELLOW "💡 Recommendation: Use virtual environment to avoid system conflicts"
        print_color $WHITE "   Run with: $0 --venv"
        echo ""
        
        read -p "Continue with system-wide installation? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled. Run with --venv for virtual environment."
            exit 0
        fi
        echo ""
    fi
    
    print_info "Starting installation process..."
    echo ""
    
    # Check requirements
    check_requirements
    
    # Install dependencies
    install_dependencies
    
    # Setup directories
    setup_directories
    
    # Create shortcuts and services
    create_shortcut
    create_systemd_service
    
    # Test installation
    test_installation
    
    # Show usage instructions
    show_usage
    
    print_success "Installation completed successfully! 🎉"
}

# Run main function
main "$@"