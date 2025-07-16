#!/bin/bash

# Marzban Central Manager v4.0 - Professional Installation Script
# Author: B3hnamR
# Email: behnamrjd@gmail.com

set -e

# --- Global Variables ---
USE_VENV=true
INSTALL_OPTIONAL=false
SKIP_TESTS=false
FORCE_INSTALL=false
INSTALLATION_COMPLETED=false # Global flag for cleanup logic

# --- Robust Color Definitions using tput ---
if command -v tput >/dev/null && tput setaf 1 >/dev/null 2>&1; then
    # Terminal supports colors
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    PURPLE=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    BOLD=$(tput bold)
    NC=$(tput sgr0) # No Color (reset)
else
    # Terminal does not support colors, disable them
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    WHITE=""
    BOLD=""
    NC=""
fi


# --- Function Definitions ---

print_color() {
    # No -e needed as tput handles terminal control directly
    echo "${1}${2}${NC}"
}

print_header() {
    clear
    echo ""
    print_color "$CYAN" "╔══════════════════════════════════════════════════════════════════════════════╗"
    print_color "$CYAN" "║                    🚀 Marzban Central Manager v4.0                          ║"
    print_color "$CYAN" "║                     Professional Installation Script                        ║"
    print_color "$CYAN" "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_step() { print_color "$BLUE" "🔄 $1"; }
print_success() { print_color "$GREEN" "✅ $1"; }
print_error() { print_color "$RED" "❌ $1"; }
print_warning() { print_color "$YELLOW" "⚠️  $1"; }
print_info() { print_color "$PURPLE" "ℹ️  $1"; }

# --- Cleanup Logic ---

cleanup() {
    if [[ "$INSTALLATION_COMPLETED" != "true" ]]; then
        print_warning "
Installation did not complete. Cleaning up generated files..."
        if [[ "$USE_VENV" == "true" ]]; then
            rm -rf venv activate_venv.sh run.sh 2>/dev/null || true
            print_info "Removed virtual environment and related scripts."
        fi
    fi
}

# Trap signals for cleanup on interruption
trap cleanup INT TERM

# --- Core Functions (No changes needed below this line for the color fix) ---

check_root() {
    [[ $EUID -eq 0 ]]
}

check_requirements() {
    print_step "Checking system requirements..."
    if ! command -v python3 &>/dev/null; then
        print_error "Python 3 not found."
        exit 1
    fi
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f2)
    if ! [[ $PYTHON_MAJOR -ge 3 && $PYTHON_MINOR -ge 8 ]]; then
        print_error "Python 3.8+ required, found $PYTHON_VERSION"
        exit 1
    fi
    print_success "Python $PYTHON_VERSION found"

    if ! command -v pip3 &>/dev/null; then
        print_error "pip3 not found"
        exit 1
    fi
    print_success "pip3 found"

    if [[ "$USE_VENV" == "true" ]]; then
        if ! python3 -c "import venv" &>/dev/null; then
            print_error "Python venv module not found. Please install python3-venv."
            exit 1
        fi
        print_success "Python venv module available"
    fi
    
    if command -v git &>/dev/null; then
        print_success "git found"
    else
        print_warning "git not found (optional)"
    fi
}

show_installation_summary() {
    print_color "$BOLD" "📋 Installation Summary:"
    echo ""
    if [[ "$USE_VENV" == "true" ]]; then
        print_color "$GREEN" "   🔒 Installation Type: Virtual Environment (Recommended)"
        print_color "$WHITE" "   📁 Location: $(pwd)/venv"
    else
        print_color "$YELLOW" "   🌐 Installation Type: System-wide"
    fi
    echo ""
}

confirm_installation() {
    if [[ "$FORCE_INSTALL" == "true" ]]; then return 0; fi
    show_installation_summary
    if [[ "$USE_VENV" == "false" ]]; then
        print_warning "System-wide installation may conflict with existing packages."
    fi
    read -p "Continue with installation? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
}

install_dependencies() {
    print_step "Installing Python dependencies..."
    if [[ "$USE_VENV" == "true" ]]; then
        if [[ -d "venv" ]]; then
            print_warning "Virtual environment already exists."
            if [[ "$FORCE_INSTALL" != "true" ]]; then
                read -p "Remove existing virtual environment? (y/N): " -n 1 -r; echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then rm -rf venv; fi
            else
                rm -rf venv
            fi
        fi
        if [[ ! -d "venv" ]]; then
            print_step "Creating virtual environment..."
            python3 -m venv venv
            print_success "Virtual environment created"
        fi
        source venv/bin/activate
        print_success "Virtual environment activated"
    fi
    
    print_step "Upgrading pip..."
    pip install --upgrade pip --quiet
    print_success "pip upgraded"
    
    print_step "Installing core dependencies from requirements.txt..."
    pip install -r requirements.txt --quiet
    print_success "Core dependencies installed"
}

setup_directories_and_shortcuts() {
    print_step "Setting up directories, permissions, and shortcuts..."
    mkdir -p config logs
    chmod 755 config logs
    chmod +x marzban_manager.py main.py 2>/dev/null || true

    if [[ "$USE_VENV" == "true" ]]; then
        # Create run.sh script
        cat > run.sh << 'EOF'
#!/bin/bash
# Marzban Central Manager - Quick Run Script

# Change to script directory
cd "$(dirname "$0")"

# Check if virtual environment exists
if [[ ! -f "venv/bin/activate" ]]; then
    echo "❌ Virtual environment not found!"
    echo "💡 Run ./install.sh to install first"
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check if main script exists
if [[ ! -f "marzban_manager.py" ]]; then
    echo "❌ marzban_manager.py not found!"
    echo "💡 Make sure you're in the correct directory"
    exit 1
fi

# Run the application
exec python3 marzban_manager.py "$@"
EOF
        chmod +x run.sh
        
        # Create activate_venv.sh script
        cat > activate_venv.sh << 'EOF'
#!/bin/bash
# Marzban Central Manager - Virtual Environment Activation Script

cd "$(dirname "$0")"

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
        
        print_success "Created run.sh script"
        print_success "Created activate_venv.sh script"
    fi
}

test_installation() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        print_warning "Skipping installation tests."
        return 0
    fi
    print_step "Testing installation..."
    (
      if [[ "$USE_VENV" == "true" ]]; then source venv/bin/activate; fi
      python3 -c "import sys; sys.path.insert(0, 'src'); from src.core.utils import is_valid_ip; assert is_valid_ip('1.1.1.1')"
    )
    if [[ $? -eq 0 ]]; then
        print_success "Basic installation test passed"
    else
        print_error "Basic installation test failed"
        exit 1
    fi
}

show_usage_instructions() {
    print_color "$WHITE" "╔══════════════════════════════════════════════════════════════════════════════╗"
    print_color "$WHITE" "║                              🎉 Installation Complete!                      ║"
    print_color "$WHITE" "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    print_color "$GREEN" "🚀 How to run Marzban Central Manager:"
    if [[ "$USE_VENV" == "true" ]]; then
        echo ""
        print_color "$CYAN" "   📦 Virtual Environment Mode:"
        print_color "$WHITE" "   ./run.sh                              # Quick run (recommended)"
    else
        echo
    fi
}

# --- Main Logic ---

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system) USE_VENV=false; shift ;;
            --force) FORCE_INSTALL=true; shift ;;
            --help|-h)
                echo "Usage: $0 [--venv|--system] [--force]"; exit 0 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
}

main() {
    parse_args "$@"
    print_header
    confirm_installation
    check_requirements
    install_dependencies
    setup_directories_and_shortcuts
    test_installation
    
    # Set the global flag to prevent cleanup on successful exit
    INSTALLATION_COMPLETED=true
    
    show_usage_instructions
    print_success "Installation process finished successfully! 🎉"
    if [[ "$USE_VENV" == "true" ]]; then
        print_color "$BOLD" "🚀 Quick start: ./run.sh"
    fi
}

main "$@"
