#!/bin/bash
set -euo pipefail

# Marzban Node Deployer - Enhanced Professional Edition v3.1
# Aligned with Central Manager Professional-3.1
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

log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $message";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message";;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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

# Enhanced docker-compose creation with geo files support
create_enhanced_docker_compose() {
    log "STEP" "Creating enhanced docker-compose configuration..."
    
    cat > docker-compose.yml << 'EOF'
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
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
      - /var/lib/marzban-node/chocolate:/var/lib/marzban-node/chocolate
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "ss", "-tuln", "|", "grep", ":62050"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
    
    log "SUCCESS" "Enhanced docker-compose.yml created with geo files and health check support"
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
    
    log "SUCCESS" "SSL certificates generated successfully with 10-year validity"
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
    
    # Download geoip.dat
    if curl -fsSL -o "$geo_dir/geoip.dat" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"; then
        log "SUCCESS" "Downloaded geoip.dat successfully"
    else
        log "WARNING" "Failed to download geoip.dat, service will use default"
    fi
    
    # Download geosite.dat
    if curl -fsSL -o "$geo_dir/geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"; then
        log "SUCCESS" "Downloaded geosite.dat successfully"
    else
        log "WARNING" "Failed to download geosite.dat, service will use default"
    fi
    
    # Set proper permissions
    chmod 644 "$geo_dir"/*.dat 2>/dev/null || true
    chown root:root "$geo_dir"/*.dat 2>/dev/null || true
    
    return 0
}

# Enhanced service startup with health checks
start_marzban_service() {
    log "STEP" "Starting Marzban Node service with health monitoring..."
    
    # Check if ports are already in use
    if ss -tuln | grep -q ':62050'; then
        log "WARNING" "Port 62050 is already in use, attempting to free it..."
        # Try to find and stop the process using the port
        local pid=$(ss -tulnp | grep ':62050' | awk '{print $7}' | cut -d',' -f2 | cut -d'=' -f2 | head -1)
        if [ -n "$pid" ] && [ "$pid" != "-" ]; then
            log "INFO" "Stopping process $pid using port 62050"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 3
        fi
    fi
    
    # Stop any existing containers
    docker compose down >/dev/null 2>&1 || true
    
    # Wait a moment for cleanup
    sleep 2
    
    # Pull latest image
    if ! docker compose pull >/dev/null 2>&1; then
        log "WARNING" "Failed to pull latest image, using cached version"
    fi
    
    # Validate docker-compose.yml
    if ! docker compose config >/dev/null 2>&1; then
        log "ERROR" "Invalid docker-compose.yml configuration"
        docker compose config
        return 1
    fi
    
    # Start service
    if ! docker compose up -d; then
        log "ERROR" "Failed to start Marzban Node service"
        docker compose logs --tail=20
        return 1
    fi
    
    # Wait for container to be running
    log "INFO" "Waiting for container to start..."
    local container_attempts=20
    local attempt=0
    
    while [ $attempt -lt $container_attempts ]; do
        # Try with jq first, fallback to grep
        local container_state=""
        if command_exists jq; then
            container_state=$(docker compose ps --format json 2>/dev/null | jq -r '.[0].State' 2>/dev/null || echo "")
        fi
        
        if [ -n "$container_state" ] && echo "$container_state" | grep -q "running"; then
            log "SUCCESS" "Container is running"
            break
        elif docker compose ps 2>/dev/null | grep -q "Up"; then
            log "SUCCESS" "Container is running"
            break
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -eq $container_attempts ]; then
            log "ERROR" "Container failed to start"
            docker compose logs --tail=30
            return 1
        fi
        
        sleep 3
    done
    
    # Wait for service to be ready (increased timeout)
    log "INFO" "Waiting for service to listen on port 62050..."
    local max_attempts=60  # Increased from 30 to 60 (3 minutes)
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if port is listening
        if ss -tuln | grep -q ':62050'; then
            log "SUCCESS" "Service is listening on port 62050"
            break
        fi
        
        # Check if container is still running
        local container_running=false
        if command_exists jq; then
            local state=$(docker compose ps --format json 2>/dev/null | jq -r '.[0].State' 2>/dev/null || echo "")
            if [ -n "$state" ] && echo "$state" | grep -q "running"; then
                container_running=true
            fi
        fi
        
        if [ "$container_running" = "false" ] && ! docker compose ps 2>/dev/null | grep -q "Up"; then
            log "ERROR" "Container stopped unexpectedly"
            docker compose logs --tail=30
            return 1
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -eq $max_attempts ]; then
            log "ERROR" "Service failed to start within expected time (3 minutes)"
            debug_service_status
            return 1
        fi
        
        # Show progress every 10 attempts
        if [ $((attempt % 10)) -eq 0 ]; then
            log "INFO" "Still waiting... (attempt $attempt/$max_attempts)"
        fi
        
        sleep 3
    done
    
    # Final verification
    sleep 5
    local final_check=false
    if command_exists jq; then
        local final_state=$(docker compose ps --format json 2>/dev/null | jq -r '.[0].State' 2>/dev/null || echo "")
        if [ -n "$final_state" ] && echo "$final_state" | grep -q "running"; then
            final_check=true
        fi
    fi
    
    if [ "$final_check" = "true" ] || docker compose ps 2>/dev/null | grep -q "Up"; then
        log "SUCCESS" "Marzban Node service is running successfully"
        log "INFO" "Service is ready and listening on port 62050"
    else
        log "ERROR" "Service appears to have failed after startup"
        docker compose logs --tail=30
        return 1
    fi
    
    return 0
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

# Main deployment function
main() {
    log "STEP" "Starting Marzban Node Deployer - Professional Edition v3.1"
    
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
            *)
                log "WARNING" "Unknown parameter: $1"
                shift
                ;;
        esac
    done
    
    # Check system requirements
    if ! check_system_requirements; then
        log "ERROR" "System requirements check failed"
        exit 1
    fi
    
    # Step 1: Install Docker if not present
    if ! command_exists docker; then
        if ! install_docker; then
            log "ERROR" "Docker installation failed"
            exit 1
        fi
    else
        log "INFO" "Docker is already installed"
    fi
    
    # Step 2: Prepare Marzban Node environment
    if ! prepare_marzban_environment; then
        log "ERROR" "Failed to prepare Marzban Node environment"
        exit 1
    fi
    
    # Step 3: Create enhanced docker-compose configuration
    if ! create_enhanced_docker_compose; then
        log "ERROR" "Failed to create docker-compose configuration"
        exit 1
    fi
    
    # Step 4: Generate SSL certificates
    if ! generate_ssl_certificates; then
        log "ERROR" "Failed to generate SSL certificates"
        exit 1
    fi
    
    # Step 5: Download geo files
    download_geo_files
    
    # Step 6: Configure API and get client certificate (if not standalone)
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
    else
        log "WARNING" "Running in standalone mode - node will not be registered with panel"
        # Create a dummy client cert file to prevent errors
        touch /var/lib/marzban-node/ssl_client_cert.pem
        chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
    fi
    
    # Step 7: Start the service
    if ! start_marzban_service; then
        log "ERROR" "Failed to start Marzban Node service"
        exit 1
    fi
    
    if [ "${STANDALONE_MODE:-false}" = "true" ]; then
        log "SUCCESS" "🎉 Marzban Node deployment completed in standalone mode!"
        log "WARNING" "Node is running in standalone mode and needs manual registration with panel"
    else
        log "SUCCESS" "🎉 Marzban Node deployment completed successfully!"
        log "INFO" "Node is registered with panel and ready for use"
        log "INFO" "Node ID: $MARZBAN_NODE_ID"
    fi
    
    log "INFO" "Service endpoint: https://$(hostname -I | awk '{print $1}'):62050"
    
    return 0
}

# Execute main function
main "$@"