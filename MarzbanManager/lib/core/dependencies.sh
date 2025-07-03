#!/bin/bash
# Marzban Central Manager - Dependencies Management Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# DEPENDENCY DEFINITIONS
# ============================================================================

# Core system dependencies
readonly CORE_DEPENDENCIES=(
    "curl"
    "jq"
    "git"
    "rsync"
    "pigz"
    "sshpass"
    "python3"
)

# Optional dependencies for enhanced features
readonly OPTIONAL_DEPENDENCIES=(
    "htop"
    "iotop"
    "nethogs"
    "ncdu"
    "tree"
    "zip"
    "unzip"
)

# Python modules required
readonly PYTHON_MODULES=(
    "json"
    "urllib.parse"
    "datetime"
    "base64"
    "hashlib"
)

# Service dependencies
readonly SERVICE_DEPENDENCIES=(
    "docker"
    "docker-compose"
    "systemctl"
)

# ============================================================================
# DEPENDENCY CHECK FUNCTIONS
# ============================================================================

# Check if a single dependency exists
check_dependency() {
    local dep="$1"
    command -v "$dep" >/dev/null 2>&1
}

# Check core dependencies
check_core_dependencies() {
    local missing_deps=()
    
    log_info "Checking core dependencies..."
    
    for dep in "${CORE_DEPENDENCIES[@]}"; do
        if ! check_dependency "$dep"; then
            missing_deps+=("$dep")
            log_warning "Missing dependency: $dep"
        else
            log_debug "Found dependency: $dep"
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing core dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    log_success "All core dependencies are available"
    return 0
}

# Check optional dependencies
check_optional_dependencies() {
    local missing_deps=()
    
    log_info "Checking optional dependencies..."
    
    for dep in "${OPTIONAL_DEPENDENCIES[@]}"; do
        if ! check_dependency "$dep"; then
            missing_deps+=("$dep")
            log_debug "Optional dependency not found: $dep"
        else
            log_debug "Found optional dependency: $dep"
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "Optional dependencies not installed: ${missing_deps[*]}"
        log_info "These are not required but may enhance functionality"
    fi
    
    return 0
}

# Check Python modules
check_python_modules() {
    local missing_modules=()
    
    log_info "Checking Python modules..."
    
    if ! check_dependency "python3"; then
        log_error "Python3 is not installed"
        return 1
    fi
    
    for module in "${PYTHON_MODULES[@]}"; do
        if ! python3 -c "import $module" 2>/dev/null; then
            missing_modules+=("$module")
            log_warning "Missing Python module: $module"
        else
            log_debug "Found Python module: $module"
        fi
    done
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        log_warning "Some Python modules are missing: ${missing_modules[*]}"
        log_info "These are usually part of Python standard library"
        return 1
    fi
    
    log_success "All required Python modules are available"
    return 0
}

# Check service dependencies
check_service_dependencies() {
    local missing_services=()
    
    log_info "Checking service dependencies..."
    
    # Check Docker
    if ! check_dependency "docker"; then
        missing_services+=("docker")
        log_warning "Docker is not installed"
    else
        # Check if Docker daemon is running
        if ! docker info >/dev/null 2>&1; then
            log_warning "Docker is installed but daemon is not running"
        else
            log_debug "Docker is installed and running"
        fi
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1 && ! docker-compose --version >/dev/null 2>&1; then
        missing_services+=("docker-compose")
        log_warning "Docker Compose is not available"
    else
        log_debug "Docker Compose is available"
    fi
    
    # Check systemctl
    if ! check_dependency "systemctl"; then
        missing_services+=("systemctl")
        log_warning "systemctl is not available (non-systemd system?)"
    else
        log_debug "systemctl is available"
    fi
    
    if [[ ${#missing_services[@]} -gt 0 ]]; then
        log_warning "Missing service dependencies: ${missing_services[*]}"
        return 1
    fi
    
    log_success "All service dependencies are available"
    return 0
}

# ============================================================================
# DEPENDENCY INSTALLATION FUNCTIONS
# ============================================================================

# Detect package manager
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Install packages using detected package manager
install_packages() {
    local packages=("$@")
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    log_info "Installing packages using $pkg_manager: ${packages[*]}"
    
    case "$pkg_manager" in
        "apt")
            apt update >/dev/null 2>&1 || {
                log_error "Failed to update package index"
                return 1
            }
            apt install -y "${packages[@]}" >/dev/null 2>&1 || {
                log_error "Failed to install packages with apt"
                return 1
            }
            ;;
        "yum")
            yum install -y "${packages[@]}" >/dev/null 2>&1 || {
                log_error "Failed to install packages with yum"
                return 1
            }
            ;;
        "dnf")
            dnf install -y "${packages[@]}" >/dev/null 2>&1 || {
                log_error "Failed to install packages with dnf"
                return 1
            }
            ;;
        "pacman")
            pacman -Sy --noconfirm "${packages[@]}" >/dev/null 2>&1 || {
                log_error "Failed to install packages with pacman"
                return 1
            }
            ;;
        "zypper")
            zypper install -y "${packages[@]}" >/dev/null 2>&1 || {
                log_error "Failed to install packages with zypper"
                return 1
            }
            ;;
        *)
            log_error "Unknown package manager. Please install packages manually: ${packages[*]}"
            return 1
            ;;
    esac
    
    log_success "Packages installed successfully"
    return 0
}

# Install core dependencies
install_core_dependencies() {
    local missing_deps=()
    
    log_step "Installing missing core dependencies..."
    
    # Check which dependencies are missing
    for dep in "${CORE_DEPENDENCIES[@]}"; do
        if ! check_dependency "$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log_info "All core dependencies are already installed"
        return 0
    fi
    
    # Install missing dependencies
    if ! install_packages "${missing_deps[@]}"; then
        log_error "Failed to install core dependencies"
        return 1
    fi
    
    # Verify installation
    local still_missing=()
    for dep in "${missing_deps[@]}"; do
        if ! check_dependency "$dep"; then
            still_missing+=("$dep")
        fi
    done
    
    if [[ ${#still_missing[@]} -gt 0 ]]; then
        log_error "Some dependencies failed to install: ${still_missing[*]}"
        return 1
    fi
    
    log_success "All core dependencies installed successfully"
    return 0
}

# Install Python dependencies
install_python_dependencies() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    log_step "Installing Python dependencies..."
    
    case "$pkg_manager" in
        "apt")
            if ! install_packages "python3-full" "python3-pip"; then
                log_warning "Failed to install python3-full, trying basic python3"
                install_packages "python3" "python3-pip" || {
                    log_error "Failed to install Python dependencies"
                    return 1
                }
            fi
            ;;
        "yum"|"dnf")
            install_packages "python3" "python3-pip" "python3-devel" || {
                log_error "Failed to install Python dependencies"
                return 1
            }
            ;;
        *)
            log_warning "Unknown package manager for Python installation"
            ;;
    esac
    
    # Verify Python modules
    if ! check_python_modules; then
        log_warning "Some Python modules are still missing after installation"
        log_info "This might not affect core functionality"
    fi
    
    return 0
}

# Install Docker
install_docker() {
    log_step "Installing Docker..."
    
    if check_dependency "docker"; then
        log_info "Docker is already installed"
        return 0
    fi
    
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    case "$pkg_manager" in
        "apt")
            # Install prerequisites
            install_packages "ca-certificates" "curl" "gnupg" "lsb-release" || return 1
            
            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || {
                log_error "Failed to add Docker GPG key"
                return 1
            }
            chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add Docker repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            apt update >/dev/null 2>&1
            install_packages "docker-ce" "docker-ce-cli" "containerd.io" "docker-compose-plugin" || return 1
            ;;
        *)
            log_error "Automatic Docker installation not supported for $pkg_manager"
            log_info "Please install Docker manually from https://docs.docker.com/engine/install/"
            return 1
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker 2>/dev/null
    systemctl enable docker 2>/dev/null
    
    # Verify installation
    if docker info >/dev/null 2>&1; then
        log_success "Docker installed and running successfully"
        return 0
    else
        log_error "Docker installation completed but service is not running"
        return 1
    fi
}

# ============================================================================
# DEPENDENCY MANAGEMENT FUNCTIONS
# ============================================================================

# Check all dependencies
check_all_dependencies() {
    local core_ok=true
    local python_ok=true
    local services_ok=true
    
    log_info "Performing comprehensive dependency check..."
    
    # Check core dependencies
    if ! check_core_dependencies; then
        core_ok=false
    fi
    
    # Check Python modules
    if ! check_python_modules; then
        python_ok=false
    fi
    
    # Check service dependencies
    if ! check_service_dependencies; then
        services_ok=false
    fi
    
    # Check optional dependencies (non-blocking)
    check_optional_dependencies
    
    # Summary
    if [[ "$core_ok" == "true" && "$python_ok" == "true" && "$services_ok" == "true" ]]; then
        log_success "All required dependencies are satisfied"
        return 0
    else
        log_error "Some required dependencies are missing"
        return 1
    fi
}

# Install all missing dependencies
install_all_dependencies() {
    log_step "Installing all missing dependencies..."
    
    local success=true
    
    # Install core dependencies
    if ! install_core_dependencies; then
        success=false
    fi
    
    # Install Python dependencies
    if ! install_python_dependencies; then
        log_warning "Python dependency installation had issues"
    fi
    
    # Install Docker if needed
    if ! check_dependency "docker"; then
        if ! install_docker; then
            success=false
        fi
    fi
    
    if [[ "$success" == "true" ]]; then
        log_success "All dependencies installed successfully"
        return 0
    else
        log_error "Some dependencies failed to install"
        return 1
    fi
}

# Get dependency status report
get_dependency_status() {
    echo "=== Dependency Status Report ==="
    echo
    
    echo "Core Dependencies:"
    for dep in "${CORE_DEPENDENCIES[@]}"; do
        if check_dependency "$dep"; then
            echo "  ✅ $dep"
        else
            echo "  ❌ $dep"
        fi
    done
    
    echo
    echo "Optional Dependencies:"
    for dep in "${OPTIONAL_DEPENDENCIES[@]}"; do
        if check_dependency "$dep"; then
            echo "  ✅ $dep"
        else
            echo "  ⚪ $dep (optional)"
        fi
    done
    
    echo
    echo "Python Modules:"
    for module in "${PYTHON_MODULES[@]}"; do
        if python3 -c "import $module" 2>/dev/null; then
            echo "  ✅ $module"
        else
            echo "  ❌ $module"
        fi
    done
    
    echo
    echo "Service Dependencies:"
    for service in "${SERVICE_DEPENDENCIES[@]}"; do
        case "$service" in
            "docker")
                if check_dependency "docker" && docker info >/dev/null 2>&1; then
                    echo "  ✅ $service (running)"
                elif check_dependency "docker"; then
                    echo "  ⚠️  $service (installed but not running)"
                else
                    echo "  ❌ $service"
                fi
                ;;
            "docker-compose")
                if docker compose version >/dev/null 2>&1 || docker-compose --version >/dev/null 2>&1; then
                    echo "  ✅ $service"
                else
                    echo "  ❌ $service"
                fi
                ;;
            *)
                if check_dependency "$service"; then
                    echo "  ✅ $service"
                else
                    echo "  ❌ $service"
                fi
                ;;
        esac
    done
    
    echo
    echo "=== End of Report ==="
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize dependencies module
init_dependencies() {
    log_debug "Dependencies module initialized"
    return 0
}