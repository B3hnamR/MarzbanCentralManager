#!/bin/bash

# Marzban Central Manager v4.0 - Installation Script
# Author: B3hnamR

set -e

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
    
    if [[ -f "requirements.txt" ]]; then
        pip3 install -r requirements.txt
        print_success "Dependencies installed successfully"
    else
        print_warning "requirements.txt not found, installing core dependencies..."
        pip3 install httpx click pyyaml tabulate
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
    print_step "Testing installation..."
    
    # Test Python imports
    python3 -c "
import sys
sys.path.insert(0, 'src')
try:
    from src.core.config import config_manager
    from src.core.logger import logger
    from src.cli.ui.menus import MenuSystem
    print('✅ All imports successful')
except ImportError as e:
    print(f'❌ Import error: {e}')
    sys.exit(1)
"
    
    if [[ $? -eq 0 ]]; then
        print_success "Installation test passed"
    else
        print_error "Installation test failed"
        exit 1
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
    
    print_color $CYAN "   Direct execution:"
    print_color $WHITE "   ./marzban_manager.py"
    echo ""
    
    print_color $CYAN "   CLI mode:"
    print_color $WHITE "   python3 main.py interactive"
    print_color $WHITE "   python3 main.py node list"
    print_color $WHITE "   python3 main.py config setup"
    echo ""
    
    print_color $YELLOW "📋 Next steps:"
    print_color $WHITE "   1. Run the application"
    print_color $WHITE "   2. Configure Marzban panel connection"
    print_color $WHITE "   3. Start managing your nodes!"
    echo ""
    
    print_color $PURPLE "📚 Documentation:"
    print_color $WHITE "   • README.md - General information"
    print_color $WHITE "   • docs/API_REFERENCE.md - API documentation"
    echo ""
    
    print_color $BLUE "💡 Support:"
    print_color $WHITE "   • GitHub: https://github.com/B3hnamR/MarzbanCentralManager"
    print_color $WHITE "   • Email: behnamrjd@gmail.com"
    echo ""
}

# Main installation function
main() {
    print_header
    
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