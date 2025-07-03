#!/bin/bash
set -euo pipefail

# Marzban Node Deployer - Enhanced Professional Edition v3.1
# Comprehensive Issue Detection and Resolution
# Author: B3hnamR

# Enhanced logging with colors and timestamps
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

# Global variables for Marzban API
MARZBAN_PANEL_PROTOCOL=""
MARZBAN_PANEL_DOMAIN=""
MARZBAN_PANEL_PORT=""
MARZBAN_PANEL_USERNAME=""
MARZBAN_PANEL_PASSWORD=""
MARZBAN_TOKEN=""
CLIENT_CERT=""
MARZBAN_NODE_ID=""
NODE_NAME=""
NODE_IP=""
NODE_DOMAIN=""

# Deployment flags
ISSUES_DETECTED=false
VERBOSE_MODE=false

log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $message";;
        DEBUG)   [[ "$VERBOSE_MODE" == "true" ]] && echo -e "[$timestamp] ${CYAN}🐛 DEBUG:${NC} $message";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message";;
    esac
}

# Silent execution with error capture
execute_silent() {
    local command="$1"
    local error_message="${2:-Command failed}"
    
    if eval "$command" >/dev/null 2>&1; then
        return 0
    else
        log "ERROR" "$error_message"
        ISSUES_DETECTED=true
        return 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#

# Enhanced Docker installation with better error handling
install_docker() {
    log "STEP" "Installing Docker with enhanced error handling..."
    
    # Remove old Docker versions
    apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true
    
    # Update package index
    if ! apt-get update -y >/dev/null 2>&1; then
        log "ERROR" "Failed to update package index"
        return 1
    fi
    
    # Install prerequisites including jq
    if ! apt-get install -y ca-certificates curl gnupg lsb-release jq >/dev/null 2>&1; then
        log "ERROR" "Failed to install prerequisites"
        return 1
    fi
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log "ERROR" "Failed to add Docker GPG key"
        return 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    if ! apt-get update -y >/dev/null 2>&1; then
        log "ERROR" "Failed to update package index after adding Docker repository"
        return 1
    fi
    
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1; then
        log "ERROR" "Failed to install Docker packages"
        return 1
    fi
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log "SUCCESS" "Docker installed and configured successfully"
    return 0
}

# Enhanced Marzban Node environment preparation
prepare_marzban_environment() {
    log "STEP" "Preparing enhanced Marzban Node environment..."
    
    # Create directories with proper permissions
    mkdir -p /opt/marzban-node /var/lib/marzban-node /var/lib/marzban-node/chocolate
    chmod 755 /opt/marzban-node /var/lib/marzban-node /var/lib/marzban-node/chocolate
    
    cd /opt/marzban-node
    
    # Clone or update Marzban Node repository
    if [ ! -d ".git" ]; then
        log "INFO" "Cloning Marzban Node repository..."
        if ! git clone https://github.com/Gozargah/Marzban-node.git . >/dev/null 2>&1; then
            log "ERROR" "Failed to clone Marzban Node repository"
            return 1
        fi
    else
        log "INFO" "Updating existing Marzban Node repository..."
        if ! git pull >/dev/null 2>&1; then
            log "WARNING" "Failed to update repository, continuing with existing version"
        fi
    fi
    
    log "SUCCESS" "Marzban Node environment prepared successfully"
    return 0
}

# Enhanced docker-compose creation with optimized configuration
create_enhanced_docker_compose() {
    log "STEP" "Creating optimized docker-compose configuration..."
    
    # Backup existing file if it exists
    if [[ -f "docker-compose.yml" ]]; then
        cp docker-compose.yml "docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    container_name: marzban-node
    network_mode: host
    environment:
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /opt/marzban-node:/opt/marzban-node
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "SUCCESS" "Optimized docker-compose.yml created (without client cert and health check)"
    return 0
}

# Enhanced SSL certificate generation
generate_ssl_certificates() {
    log "STEP" "Generating enhanced SSL certificates..."
    
    # Generate private key with stronger encryption
    if ! openssl genrsa -out /var/lib/marzban-node/ssl_key.pem 4096 >/dev/null 2>&1; then
        log "ERROR" "Failed to generate SSL private key"
        return 1
    fi
    
    # Generate self-signed certificate with extended validity and better subject
    if ! openssl req -new -x509 -key /var/lib/marzban-node/ssl_key.pem \
         -out /var/lib/marzban-node/ssl_cert.pem -days 3650 \
         -subj "/C=US/ST=State/L=City/O=MarzbanNode/OU=IT/CN=marzban-node" \
         >/dev/null 2>&1; then
        log "ERROR" "Failed to generate SSL certificate"
        return 1
    fi
    
    # Set proper permissions
    chmod 600 /var/lib/marzban-node/ssl_key.pem
    chmod 644 /var/lib/marzban-node/ssl_cert.pem
    chown root:root /var/lib/marzban-node/ssl_*.pem
    
    # Create temporary client certificate (copy of server cert)
    # This will be replaced by the actual client cert from panel later
    cp /var/lib/marzban-node/ssl_cert.pem /var/lib/marzban-node/ssl_client_cert.pem
    chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
    chown root:root /var/lib/marzban-node/ssl_client_cert.pem
    
    log "SUCCESS" "SSL certificates generated successfully with 10-year validity"
    log "INFO" "Temporary client certificate created (will be replaced by panel certificate)"
    return 0
}

# Function to get Marzban API token
get_marzban_token() {
    if [ -n "$MARZBAN_TOKEN" ]; then
        return 0
    fi

    if [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ]; then
        log "ERROR" "Marzban Panel API credentials are not configured."
        return 1
    fi

    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response

    log "INFO" "Attempting to get Marzban API token..."
    response=$(curl -s -X POST "$login_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout 10 --max-time 20 \
        --insecure 2>/dev/null)

    if echo "$response" | grep -q "access_token"; then
        MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
        if [ -n "$MARZBAN_TOKEN" ]; then
            log "SUCCESS" "Marzban API token obtained successfully."
            return 0
        else
            log "ERROR" "Failed to parse access token from API response."
            return 1
        fi
    else
        log "ERROR" "Failed to obtain Marzban API token. Check credentials and panel accessibility."
        log "DEBUG" "API Response: $response"
        MARZBAN_TOKEN=""
        return 1
    fi
}

# Function to add node to Marzban panel
add_node_to_marzban_panel_api() {
    log "INFO" "Registering node '$NODE_NAME' with the Marzban panel..."
    
    local add_node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node"
    local payload
    payload=$(printf '{"name": "%s", "address": "%s", "port": 62050, "api_port": 62051, "usage_coefficient": 1.0, "add_as_new_host": false}' "$NODE_NAME" "$NODE_IP")

    local response
    response=$(curl -s -X POST "$add_node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Content-Type: application/json" -H "Accept: application/json" \
        -d "$payload" --insecure)

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        MARZBAN_NODE_ID=$(echo "$response" | jq -r .id)
        log "SUCCESS" "Node '$NODE_NAME' successfully added to panel with ID: $MARZBAN_NODE_ID"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node '$NODE_NAME' already exists in the panel. Attempting to retrieve its ID..."
        
        local nodes_list_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes"
        local nodes_response
        nodes_response=$(curl -s -X GET "$nodes_list_url" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        local existing_id
        existing_id=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$NODE_NAME\") | .id" 2>/dev/null)
        
        if [ -n "$existing_id" ]; then
            MARZBAN_NODE_ID="$existing_id"
            log "SUCCESS" "Successfully retrieved ID for existing node: $MARZBAN_NODE_ID"
            return 0
        else
            log "ERROR" "Node is said to exist, but could not retrieve its ID from the panel."
            return 1
        fi
    else
        log "ERROR" "Failed to add node to Marzban panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

# Function to get client certificate from Marzban API
get_client_cert_from_marzban_api() {
    log "INFO" "Retrieving client certificate for node ID: $MARZBAN_NODE_ID"
    
    local node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${MARZBAN_NODE_ID}"
    
    local response
    response=$(curl -s -X GET "$node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Accept: application/json" \
        --insecure)
        
    if echo "$response" | jq -e '.client_cert' >/dev/null 2>&1; then
        CLIENT_CERT=$(echo "$response" | jq -r .client_cert)
        if [ -n "$CLIENT_CERT" ]; then
            log "SUCCESS" "Client certificate retrieved successfully."
            return 0
        else
            log "ERROR" "Client certificate is empty in the API response."
            return 1
        fi
    else
        log "ERROR" "Failed to retrieve client certificate from panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

# Function to configure Marzban API connection
configure_marzban_api() {
    log "STEP" "Configuring Marzban Panel API Connection..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Marzban Panel API Setup${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Please provide your Marzban Panel details:${NC}\n"
    
    echo -n "Panel Protocol (http/https) [default: https]: "
    read -r protocol
    MARZBAN_PANEL_PROTOCOL=${protocol:-https}
    
    echo -n "Panel Domain/IP (e.g., panel.example.com): "
    read -r domain
    MARZBAN_PANEL_DOMAIN="$domain"
    
    echo -n "Panel Port [default: 8000]: "
    read -r port
    MARZBAN_PANEL_PORT=${port:-8000}
    
    echo -n "Admin Username: "
    read -r username
    MARZBAN_PANEL_USERNAME="$username"
    
    echo -n "Admin Password: "
    read -s password
    MARZBAN_PANEL_PASSWORD="$password"
    echo ""
    
    # Validate inputs
    if [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ]; then
        log "ERROR" "All fields are required."
        return 1
    fi
    
    # Test connection
    log "INFO" "Testing API connection..."
    if get_marzban_token; then
        log "SUCCESS" "API connection test successful!"
        return 0
    else
        log "ERROR" "API connection test failed. Please check your credentials and panel accessibility."
        return 1
    fi
}

# Function to deploy client certificate
deploy_client_certificate() {
    log "STEP" "Deploying client certificate..."
    
    if [ -z "$CLIENT_CERT" ]; then
        log "ERROR" "No client certificate available"
        return 1
    fi
    
    # Write client certificate to file
    echo "$CLIENT_CERT" > /var/lib/marzban-node/ssl_client_cert.pem
    
    # Set proper permissions
    chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
    chown root:root /var/lib/marzban-node/ssl_client_cert.pem
    
    log "SUCCESS" "Client certificate deployed successfully"
    return 0
}

# Debug function to show detailed information
debug_service_status() {
    log "INFO" "=== DEBUG INFORMATION ==="
    log "INFO" "Docker version:"
    docker --version 2>/dev/null || log "ERROR" "Docker not found"
    
    log "INFO" "Docker compose version:"
    docker compose version 2>/dev/null || log "ERROR" "Docker compose not found"
    
    log "INFO" "Container status:"
    docker compose ps 2>/dev/null || log "ERROR" "Failed to get container status"
    
    log "INFO" "Container logs (last 50 lines):"
    docker compose logs --tail=50 2>/dev/null || log "ERROR" "Failed to get container logs"
    
    log "INFO" "Port status:"
    ss -tuln | grep -E "(62050|62051)" || log "INFO" "No services listening on ports 62050/62051"
    
    log "INFO" "System resources:"
    free -h 2>/dev/null || log "WARNING" "Failed to get memory info"
    df -h / 2>/dev/null || log "WARNING" "Failed to get disk info"
    
    log "INFO" "=== END DEBUG INFORMATION ==="
}

# Download fresh geo files
download_geo_files() {
    log "STEP" "Downloading fresh geo files..."
    
    local geo_dir="/var/lib/marzban-node/chocolate"
    
    # Ensure directory exists and has proper permissions
    mkdir -p "$geo_dir"
    chmod 755 "$geo_dir"
    
    # Download geoip.dat with better error handling
    log "DEBUG" "Downloading geoip.dat..."
    if curl -fsSL --connect-timeout 30 --max-time 120 -o "$geo_dir/geoip.dat.tmp" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat" 2>/dev/null; then
        mv "$geo_dir/geoip.dat.tmp" "$geo_dir/geoip.dat"
        log "SUCCESS" "Downloaded geoip.dat successfully"
    else
        rm -f "$geo_dir/geoip.dat.tmp" 2>/dev/null || true
        log "WARNING" "Failed to download geoip.dat, service will use default"
    fi
    
    # Download geosite.dat with better error handling
    log "DEBUG" "Downloading geosite.dat..."
    if curl -fsSL --connect-timeout 30 --max-time 120 -o "$geo_dir/geosite.dat.tmp" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat" 2>/dev/null; then
        mv "$geo_dir/geosite.dat.tmp" "$geo_dir/geosite.dat"
        log "SUCCESS" "Downloaded geosite.dat successfully"
    else
        rm -f "$geo_dir/geosite.dat.tmp" 2>/dev/null || true
        log "WARNING" "Failed to download geosite.dat, service will use default"
    fi
    
    # Set proper permissions for any downloaded files
    chmod 644 "$geo_dir"/*.dat 2>/dev/null || true
    chown root:root "$geo_dir"/*.dat 2>/dev/null || true
    
    return 0
}

# Check and fix package manager lock
check_and_fix_package_lock() {
    log "DEBUG" "Checking package manager lock..."
    
    if pgrep -f unattended-upgr >/dev/null 2>&1; then
        log "WARNING" "Package manager is locked by unattended-upgrades"
        log "STEP" "Fixing package manager lock..."
        
        systemctl stop unattended-upgrades 2>/dev/null || true
        pkill -f unattended-upgr 2>/dev/null || true
        sleep 3
        
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
        dpkg --configure -a >/dev/null 2>&1 || true
        
        log "SUCCESS" "Package manager lock fixed"
        ISSUES_DETECTED=true
    fi
    return 0
}

# Check and install Docker
check_and_install_docker() {
    log "DEBUG" "Checking Docker installation..."
    
    if ! command_exists docker; then
        log "WARNING" "Docker is not installed"
        ISSUES_DETECTED=true
        if ! install_docker; then
            return 1
        fi
    fi
    return 0
}

# Check and install Docker Compose
check_and_install_docker_compose() {
    log "DEBUG" "Checking Docker Compose installation..."
    
    if ! command_exists docker-compose; then
        log "WARNING" "Docker Compose is not installed"
        log "STEP" "Installing Docker Compose..."
        ISSUES_DETECTED=true
        
        if ! apt-get install -y docker-compose >/dev/null 2>&1; then
            log "ERROR" "Failed to install Docker Compose"
            return 1
        fi
        log "SUCCESS" "Docker Compose installed successfully"
    fi
    return 0
}

# Check and setup environment
check_and_setup_environment() {
    log "DEBUG" "Checking Marzban Node environment..."
    
    if [[ ! -d "/opt/marzban-node" ]] || [[ ! -d "/var/lib/marzban-node" ]]; then
        log "WARNING" "Marzban Node environment needs setup"
        ISSUES_DETECTED=true
        if ! prepare_marzban_environment; then
            return 1
        fi
    fi
    return 0
}

# Check and generate SSL certificates
check_and_generate_ssl_certificates() {
    log "DEBUG" "Checking SSL certificates..."
    
    local needs_generation=false
    
    # Check server certificates
    if [[ ! -f "/var/lib/marzban-node/ssl_cert.pem" ]] || [[ ! -f "/var/lib/marzban-node/ssl_key.pem" ]]; then
        needs_generation=true
    fi
    
    # Check client certificate
    if [[ ! -f "/var/lib/marzban-node/ssl_client_cert.pem" ]]; then
        needs_generation=true
    fi
    
    if [[ "$needs_generation" == "true" ]]; then
        log "WARNING" "SSL certificates need to be generated"
        ISSUES_DETECTED=true
        if ! generate_ssl_certificates; then
            return 1
        fi
    else
        # Ensure client cert exists (create from server cert if missing)
        if [[ ! -f "/var/lib/marzban-node/ssl_client_cert.pem" ]]; then
            log "DEBUG" "Creating missing client certificate..."
            cp /var/lib/marzban-node/ssl_cert.pem /var/lib/marzban-node/ssl_client_cert.pem
            chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
            chown root:root /var/lib/marzban-node/ssl_client_cert.pem
            ISSUES_DETECTED=true
        fi
    fi
    return 0
}

# Create optimized docker-compose
create_optimized_docker_compose() {
    log "STEP" "Checking docker-compose configuration..."
    
    cd /opt/marzban-node 2>/dev/null || return 1
    
    local needs_update=false
    
    # Check if docker-compose.yml exists
    if [[ ! -f "docker-compose.yml" ]]; then
        log "WARNING" "Docker Compose file does not exist"
        needs_update=true
    else
        # Check if SSL_CLIENT_CERT_FILE is missing (we need it now!)
        if ! grep -q "SSL_CLIENT_CERT_FILE" docker-compose.yml 2>/dev/null; then
            log "WARNING" "Docker Compose missing SSL_CLIENT_CERT_FILE"
            needs_update=true
        fi
        # Check for problematic health checks
        if grep -q "healthcheck" docker-compose.yml 2>/dev/null; then
            log "WARNING" "Docker Compose has problematic health checks"
            needs_update=true
        fi
    fi
    
    if [[ "$needs_update" == "true" ]]; then
        log "WARNING" "Docker Compose configuration needs optimization"
        ISSUES_DETECTED=true
        if ! create_enhanced_docker_compose; then
            return 1
        fi
    else
        log "SUCCESS" "Docker Compose configuration is already optimized"
    fi
    return 0
}

# Comprehensive system check and fix function
comprehensive_system_check() {
    log "DEBUG" "Starting comprehensive system check..."
    
    # Reset issues flag
    ISSUES_DETECTED=false
    
    # Run all checks in correct order
    check_and_fix_package_lock
    check_and_install_docker
    check_and_install_docker_compose
    check_and_setup_environment
    
    # IMPORTANT: Generate SSL certificates BEFORE creating docker-compose
    check_and_generate_ssl_certificates
    
    # Create docker-compose AFTER SSL certificates are ready
    create_optimized_docker_compose
    
    # Download geo files (optional)
    download_geo_files
    
    if [[ "$ISSUES_DETECTED" == "true" ]]; then
        log "WARNING" "Issues were detected and fixed during system check"
        return 1
    else
        log "SUCCESS" "System check completed - no issues detected"
        return 0
    fi
}

# Enhanced service startup with comprehensive monitoring
start_marzban_service() {
    log "STEP" "Starting Marzban Node service with comprehensive monitoring..."
    
    cd /opt/marzban-node
    
    # Pre-flight checks
    log "DEBUG" "Performing pre-flight checks..."
    
    # Ensure SSL certificates exist
    if [[ ! -f "/var/lib/marzban-node/ssl_cert.pem" ]] || [[ ! -f "/var/lib/marzban-node/ssl_key.pem" ]] || [[ ! -f "/var/lib/marzban-node/ssl_client_cert.pem" ]]; then
        log "ERROR" "SSL certificates missing before service start"
        log "INFO" "Generating missing certificates..."
        
        # Generate missing certificates
        if ! generate_ssl_certificates; then
            log "ERROR" "Failed to generate SSL certificates"
            return 1
        fi
    fi
    
    # Ensure docker-compose.yml has SSL_CLIENT_CERT_FILE
    if ! grep -q "SSL_CLIENT_CERT_FILE" docker-compose.yml 2>/dev/null; then
        log "WARNING" "docker-compose.yml missing SSL_CLIENT_CERT_FILE, recreating..."
        if ! create_enhanced_docker_compose; then
            log "ERROR" "Failed to create proper docker-compose.yml"
            return 1
        fi
    fi
    
    # Clean up any existing containers
    log "DEBUG" "Cleaning up existing containers..."
    docker stop marzban-node 2>/dev/null || true
    docker rm marzban-node 2>/dev/null || true
    docker-compose down 2>/dev/null || true
    
    # Wait for cleanup
    sleep 2
    
    # Pull latest image
    log "DEBUG" "Pulling latest image..."
    if ! docker-compose pull >/dev/null 2>&1; then
        log "WARNING" "Failed to pull latest image, using cached version"
    fi
    
    # Validate docker-compose.yml
    if ! docker-compose config >/dev/null 2>&1; then
        log "ERROR" "Invalid docker-compose.yml configuration"
        return 1
    fi
    
    # Start service
    log "DEBUG" "Starting container..."
    if ! docker-compose up -d >/dev/null 2>&1; then
        log "ERROR" "Failed to start Marzban Node service"
        docker-compose logs --tail=20
        return 1
    fi
    
    # Monitor startup with enhanced error detection and timeout
    log "DEBUG" "Monitoring service startup..."
    local max_attempts=40  # Reduced from 60 to 40 (2 minutes)
    local attempt=0
    local container_healthy=false
    local ssl_errors=0
    local startup_detected=false
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if container is running
        if ! docker ps | grep -q "marzban-node"; then
            log "ERROR" "Container is not running"
            docker logs marzban-node --tail=10 2>/dev/null || echo "No logs available"
            return 1
        fi
        
        # Check for SSL errors in logs
        local recent_logs=$(docker logs marzban-node --tail=5 2>/dev/null || echo "")
        
        # Check for SSL_CLIENT_CERT_FILE required error
        if echo "$recent_logs" | grep -q "SSL_CLIENT_CERT_FILE is required"; then
            ssl_errors=$((ssl_errors + 1))
            if [ $ssl_errors -ge 3 ]; then
                log "ERROR" "SSL_CLIENT_CERT_FILE is required for rest service"
                log "INFO" "Creating client certificate and restarting..."
                
                # Create client certificate if missing
                if [[ ! -f "/var/lib/marzban-node/ssl_client_cert.pem" ]]; then
                    cp /var/lib/marzban-node/ssl_cert.pem /var/lib/marzban-node/ssl_client_cert.pem
                    chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
                    chown root:root /var/lib/marzban-node/ssl_client_cert.pem
                fi
                
                # Restart container
                docker restart marzban-node >/dev/null 2>&1
                sleep 5
                ssl_errors=0  # Reset counter after fix
            fi
        fi
        
        # Check for other SSL errors
        if echo "$recent_logs" | grep -q "SSLError.*NO_CERTIFICATE_OR_CRL_FOUND"; then
            ssl_errors=$((ssl_errors + 1))
            if [ $ssl_errors -ge 5 ]; then
                log "ERROR" "Persistent SSL certificate errors detected"
                log "INFO" "This usually means client certificate authentication is causing issues"
                return 1
            fi
        fi
        
        # Check for successful startup message
        if echo "$recent_logs" | grep -q "Uvicorn running on https://0.0.0.0:62050"; then
            if [ "$startup_detected" = false ]; then
                log "SUCCESS" "Service startup message detected"
                startup_detected=true
            fi
        fi
        
        # Check if port is listening
        if ss -tuln | grep -q ':62050'; then
            log "SUCCESS" "Service is listening on port 62050"
            container_healthy=true
            break
        fi
        
        # Show progress every 8 attempts (more frequent updates)
        if [ $((attempt % 8)) -eq 0 ] && [ $attempt -gt 0 ]; then
            log "INFO" "Still waiting for port 62050... (attempt $attempt/$max_attempts)"
            
            # Show recent logs for debugging
            if [ $((attempt % 16)) -eq 0 ]; then
                log "DEBUG" "Recent logs: $(docker logs marzban-node --tail=2 2>/dev/null | tr '\n' ' ' || echo 'No logs')"
            fi
        fi
        
        sleep 3
        attempt=$((attempt + 1))
    done
    
    if [ "$container_healthy" = true ]; then
        # Final verification
        sleep 3
        
        # Test local connectivity
        local response
        response=$(curl -k -s --connect-timeout 5 --max-time 10 -w "%{http_code}" "https://localhost:62050" -o /dev/null 2>/dev/null || echo "000")
        
        if [[ "$response" != "000" ]]; then
            log "SUCCESS" "Service is responding to HTTPS requests (HTTP $response)"
        else
            log "WARNING" "Service is listening but not responding to HTTPS requests"
        fi
        
        log "SUCCESS" "Marzban Node service started successfully"
        return 0
    else
        log "ERROR" "Service failed to start within expected time"
        
        # Show diagnostic information
        echo -e "\n${RED}=== Diagnostic Information ===${NC}"
        echo -e "${CYAN}Container Status:${NC}"
        docker ps -a | grep marzban-node || echo "No container found"
        
        echo -e "\n${CYAN}Recent Logs:${NC}"
        docker logs marzban-node --tail=20 2>/dev/null || echo "No logs available"
        
        echo -e "\n${CYAN}Port Status:${NC}"
        ss -tuln | grep -E '(62050|62051)' || echo "No relevant ports listening"
        
        return 1
    fi
}

# Check system requirements
check_system_requirements() {
    log "STEP" "Checking system requirements..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        return 1
    fi
    
    # Check OS
    if [ ! -f /etc/os-release ]; then
        log "ERROR" "Cannot determine operating system"
        return 1
    fi
    
    local os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    log "INFO" "Detected OS: $os_id"
    
    # Check if it's a supported OS
    case "$os_id" in
        ubuntu|debian)
            log "SUCCESS" "Supported operating system detected"
            ;;
        *)
            log "WARNING" "Unsupported OS detected. This script is designed for Ubuntu/Debian."
            log "PROMPT" "Do you want to continue anyway? (y/n):"
            read -r continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                log "INFO" "Installation cancelled by user"
                return 1
            fi
            ;;
    esac
    
    # Check available disk space (minimum 2GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local min_space=2097152  # 2GB in KB
    
    if [ "$available_space" -lt "$min_space" ]; then
        log "ERROR" "Insufficient disk space. At least 2GB free space required."
        log "INFO" "Available: $(($available_space / 1024 / 1024))GB"
        return 1
    fi
    
    log "SUCCESS" "System requirements check passed"
    return 0
}

# Main deployment function with comprehensive checks
main() {
    echo -e "${WHITE}╔═══════════════════��════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║          ${CYAN}Marzban Node Deployer - Professional v3.1${NC}          ║"
    echo -e "${WHITE}║              ${GREEN}Comprehensive Issue Detection${NC}                ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-name)
                NODE_NAME="$2"
                shift 2
                ;;
            --node-ip)
                NODE_IP="$2"
                shift 2
                ;;
            --node-domain)
                NODE_DOMAIN="$2"
                shift 2
                ;;
            --panel-protocol)
                MARZBAN_PANEL_PROTOCOL="$2"
                shift 2
                ;;
            --panel-domain)
                MARZBAN_PANEL_DOMAIN="$2"
                shift 2
                ;;
            --panel-port)
                MARZBAN_PANEL_PORT="$2"
                shift 2
                ;;
            --panel-username)
                MARZBAN_PANEL_USERNAME="$2"
                shift 2
                ;;
            --panel-password)
                MARZBAN_PANEL_PASSWORD="$2"
                shift 2
                ;;
            --standalone)
                STANDALONE_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            *)
                log "WARNING" "Unknown parameter: $1"
                shift
                ;;
        esac
    done
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Step 1: Comprehensive system check
    log "STEP" "Performing comprehensive system check and fixes..."
    if ! comprehensive_system_check; then
        log "INFO" "System issues were detected and fixed"
    fi
    
    # Step 2: Start the service
    if ! start_marzban_service; then
        log "ERROR" "Failed to start Marzban Node service"
        exit 1
    fi
    
    # Step 3: Configure API and get client certificate (if not standalone)
    if [ "${STANDALONE_MODE:-false}" != "true" ]; then
        # If API credentials are provided via command line, use them
        if [ -n "$MARZBAN_PANEL_DOMAIN" ] && [ -n "$MARZBAN_PANEL_USERNAME" ] && [ -n "$MARZBAN_PANEL_PASSWORD" ]; then
            log "INFO" "Using provided API credentials"
        else
            # Otherwise, ask for API configuration
            if ! configure_marzban_api; then
                log "ERROR" "Failed to configure Marzban API"
                exit 1
            fi
        fi
        
        # Get API token
        if ! get_marzban_token; then
            log "ERROR" "Failed to get API token"
            exit 1
        fi
        
        # Add node to panel
        if ! add_node_to_marzban_panel_api; then
            log "ERROR" "Failed to add node to panel"
            exit 1
        fi
        
        # Get client certificate
        if ! get_client_cert_from_marzban_api; then
            log "ERROR" "Failed to get client certificate"
            exit 1
        fi
        
        # Deploy client certificate
        if ! deploy_client_certificate; then
            log "ERROR" "Failed to deploy client certificate"
            exit 1
        fi
        
        # Restart service with client certificate
        log "STEP" "Restarting service with client certificate..."
        docker restart marzban-node >/dev/null 2>&1
        sleep 10
        
        # Verify service is still working
        if ss -tuln | grep -q ':62050'; then
            log "SUCCESS" "Service restarted successfully with client certificate"
        else
            log "WARNING" "Service may have issues after client certificate deployment"
        fi
    else
        log "WARNING" "Running in standalone mode - node will not be registered with panel"
    fi
    
    # Final verification
    log "STEP" "Performing final verification..."
    
    # Check container status
    if docker ps | grep -q "marzban-node"; then
        log "SUCCESS" "✅ Container is running"
    else
        log "ERROR" "❌ Container is not running"
        exit 1
    fi
    
    # Check port status
    if ss -tuln | grep -q ':62050'; then
        log "SUCCESS" "✅ Port 62050 is listening"
    else
        log "ERROR" "❌ Port 62050 is not listening"
        exit 1
    fi
    
    # Test HTTPS connectivity
    local response
    response=$(curl -k -s --connect-timeout 5 --max-time 10 -w "%{http_code}" "https://localhost:62050" -o /dev/null 2>/dev/null || echo "000")
    
    if [[ "$response" != "000" ]]; then
        log "SUCCESS" "✅ HTTPS service is responding (HTTP $response)"
    else
        log "WARNING" "⚠️  HTTPS service test failed (may be normal during startup)"
    fi
    
    # Success message
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Deployment Complete!${NC}                     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    if [ "${STANDALONE_MODE:-false}" = "true" ]; then
        log "SUCCESS" "🎉 Marzban Node deployment completed in standalone mode!"
        log "WARNING" "Node is running in standalone mode and needs manual registration with panel"
    else
        log "SUCCESS" "🎉 Marzban Node deployment completed successfully!"
        log "INFO" "Node is registered with panel and ready for use"
        if [[ -n "$MARZBAN_NODE_ID" ]]; then
            log "INFO" "Node ID: $MARZBAN_NODE_ID"
        fi
    fi
    
    local server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    log "INFO" "Service endpoint: https://$server_ip:62050"
    
    echo -e "\n${CYAN}🔧 Useful Commands:${NC}"
    echo "- Check status: docker ps | grep marzban-node"
    echo "- View logs: docker logs marzban-node -f"
    echo "- Restart: docker restart marzban-node"
    echo "- Check ports: ss -tuln | grep -E '(62050|62051)'"
    echo "- Test HTTPS: curl -k https://localhost:62050"
    
    return 0
}

# Execute main function
main "$@"