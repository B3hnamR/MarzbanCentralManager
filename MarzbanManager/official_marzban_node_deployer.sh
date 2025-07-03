#!/bin/bash
# Official Marzban Node Deployer - Based on Official Documentation
# Professional Edition v4.0

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

# Global variables
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Docker (official method)
install_docker_official() {
    log "STEP" "Installing Docker using official method..."
    
    # Update system
    apt-get update
    apt-get install curl socat git -y
    
    # Install Docker
    curl -fsSL https://get.docker.com | sh
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Verify installation
    if docker --version >/dev/null 2>&1; then
        log "SUCCESS" "Docker installed successfully"
        return 0
    else
        log "ERROR" "Docker installation failed"
        return 1
    fi
}

# Setup Marzban Node environment (official method)
setup_marzban_node_official() {
    log "STEP" "Setting up Marzban Node environment (official method)..."
    
    # Clone official repository
    if [ -d "~/Marzban-node" ]; then
        rm -rf ~/Marzban-node
    fi
    
    git clone https://github.com/Gozargah/Marzban-node ~/Marzban-node
    
    # Create data directory
    mkdir -p /var/lib/marzban-node
    
    # Navigate to Marzban-node directory
    cd ~/Marzban-node
    
    log "SUCCESS" "Marzban Node environment setup completed"
    return 0
}

# Create official docker-compose.yml
create_official_docker_compose() {
    log "STEP" "Creating official docker-compose.yml..."
    
    cd ~/Marzban-node
    
    # Create docker-compose.yml based on official documentation
    cat > docker-compose.yml << 'EOF'
services:
  marzban-node:
    # build: .
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host

    # env_file: .env
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"

    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
EOF
    
    log "SUCCESS" "Official docker-compose.yml created"
    return 0
}

# Get API token
get_marzban_token() {
    if [ -n "$MARZBAN_TOKEN" ]; then
        return 0
    fi

    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response

    log "INFO" "Getting Marzban API token..."
    response=$(curl -s -X POST "$login_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout 10 --max-time 20 --insecure 2>/dev/null)

    if echo "$response" | grep -q "access_token"; then
        MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
        if [ -n "$MARZBAN_TOKEN" ]; then
            log "SUCCESS" "API token obtained successfully"
            return 0
        fi
    fi
    
    log "ERROR" "Failed to obtain API token"
    return 1
}

# Add node to panel
add_node_to_panel() {
    log "INFO" "Adding node '$NODE_NAME' to Marzban panel..."
    
    local add_node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node"
    local payload
    payload=$(printf '{"name": "%s", "address": "%s", "port": 62050, "api_port": 62051, "usage_coefficient": 1.0, "add_as_new_host": true}' "$NODE_NAME" "$NODE_IP")

    local response
    response=$(curl -s -X POST "$add_node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" --insecure)

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        MARZBAN_NODE_ID=$(echo "$response" | jq -r .id)
        log "SUCCESS" "Node added to panel with ID: $MARZBAN_NODE_ID"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node already exists, retrieving ID..."
        
        local nodes_response
        nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" \
            -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        MARZBAN_NODE_ID=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$NODE_NAME\") | .id" 2>/dev/null)
        
        if [ -n "$MARZBAN_NODE_ID" ]; then
            log "SUCCESS" "Retrieved existing node ID: $MARZBAN_NODE_ID"
            return 0
        fi
    fi
    
    log "ERROR" "Failed to add node to panel"
    return 1
}

# Get client certificate from panel
get_client_certificate() {
    log "INFO" "Retrieving client certificate from panel..."
    
    # Wait for panel to generate certificate
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        local node_response
        node_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${MARZBAN_NODE_ID}" \
            -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        if echo "$node_response" | jq -e '.client_cert' >/dev/null 2>&1; then
            CLIENT_CERT=$(echo "$node_response" | jq -r .client_cert)
            if [[ -n "$CLIENT_CERT" && "$CLIENT_CERT" != "null" ]]; then
                log "SUCCESS" "Client certificate retrieved successfully"
                return 0
            fi
        fi
        
        log "INFO" "Waiting for certificate generation... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    
    log "ERROR" "Failed to retrieve client certificate"
    return 1
}

# Deploy client certificate
deploy_client_certificate() {
    log "STEP" "Deploying client certificate..."
    
    if [[ -z "$CLIENT_CERT" || "$CLIENT_CERT" == "null" ]]; then
        log "ERROR" "No client certificate to deploy"
        return 1
    fi
    
    # Write certificate to file
    echo "$CLIENT_CERT" > /var/lib/marzban-node/ssl_client_cert.pem
    chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
    chown root:root /var/lib/marzban-node/ssl_client_cert.pem
    
    log "SUCCESS" "Client certificate deployed"
    return 0
}

# Start Marzban Node service
start_marzban_node() {
    log "STEP" "Starting Marzban Node service..."
    
    cd ~/Marzban-node
    
    # Start the service
    docker compose up -d
    
    # Monitor startup
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        # Check if container is running
        if docker ps | grep -q "marzban-node"; then
            # Check if port is listening
            if ss -tuln | grep -q ':62050'; then
                log "SUCCESS" "Marzban Node service started successfully"
                return 0
            fi
        fi
        
        # Show progress
        if [ $((attempt % 5)) -eq 0 ]; then
            log "INFO" "Waiting for service to start... (attempt $attempt/$max_attempts)"
        fi
        
        sleep 3
    done
    
    log "ERROR" "Service failed to start properly"
    return 1
}

# Verify node connection
verify_node_connection() {
    log "STEP" "Verifying node connection to panel..."
    
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        local node_response
        node_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${MARZBAN_NODE_ID}" \
            -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        local status=$(echo "$node_response" | jq -r .status 2>/dev/null || echo "unknown")
        
        case "$status" in
            "connected")
                log "SUCCESS" "Node is successfully connected to panel"
                return 0
                ;;
            "connecting")
                log "INFO" "Node is connecting... (attempt $attempt/$max_attempts)"
                ;;
            *)
                log "WARNING" "Node status: $status"
                ;;
        esac
        
        sleep 10
    done
    
    log "WARNING" "Node connection verification timed out"
    return 1
}

# Configure API connection
configure_api_connection() {
    log "STEP" "Configuring API connection..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Marzban Panel API Setup${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -n "Panel Protocol (http/https) [default: https]: "
    read -r protocol
    MARZBAN_PANEL_PROTOCOL=${protocol:-https}
    
    echo -n "Panel Domain/IP: "
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
    
    echo -n "Node Name: "
    read -r node_name
    NODE_NAME="$node_name"
    
    echo -n "Node IP: "
    read -r node_ip
    NODE_IP="$node_ip"
    
    # Validate inputs
    if [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ] || [ -z "$NODE_NAME" ] || [ -z "$NODE_IP" ]; then
        log "ERROR" "All fields are required"
        return 1
    fi
    
    return 0
}

# Main deployment function
main() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║          ${CYAN}Official Marzban Node Deployer v4.0${NC}              ║"
    echo -e "${WHITE}║              ${GREEN}Based on Official Documentation${NC}              ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Step 1: Install Docker if needed
    if ! command_exists docker; then
        install_docker_official
    else
        log "INFO" "Docker is already installed"
    fi
    
    # Step 2: Setup Marzban Node environment
    setup_marzban_node_official
    
    # Step 3: Create official docker-compose
    create_official_docker_compose
    
    # Step 4: Configure API connection
    configure_api_connection
    
    # Step 5: Get API token
    get_marzban_token
    
    # Step 6: Add node to panel
    add_node_to_panel
    
    # Step 7: Get client certificate
    get_client_certificate
    
    # Step 8: Deploy client certificate
    deploy_client_certificate
    
    # Step 9: Start Marzban Node
    start_marzban_node
    
    # Step 10: Verify connection
    verify_node_connection
    
    # Success message
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Deployment Complete!${NC}                     ║"
    echo -e "${WHITE}╚══════════��═════════════════════════════════════════════════════╝${NC}\n"
    
    log "SUCCESS" "🎉 Marzban Node deployed successfully using official method!"
    log "INFO" "Node Name: $NODE_NAME"
    log "INFO" "Node ID: $MARZBAN_NODE_ID"
    log "INFO" "Service endpoint: https://$NODE_IP:62050"
    
    echo -e "\n${CYAN}🔧 Useful Commands:${NC}"
    echo "- Check status: cd ~/Marzban-node && docker compose ps"
    echo "- View logs: cd ~/Marzban-node && docker compose logs -f"
    echo "- Restart: cd ~/Marzban-node && docker compose restart"
    echo "- Update: cd ~/Marzban-node && docker compose pull && docker compose down --remove-orphans && docker compose up -d"
    
    return 0
}

# Execute main function
main "$@"