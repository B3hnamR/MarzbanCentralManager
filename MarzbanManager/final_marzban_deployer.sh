#!/bin/bash
# Final Marzban Node Deployer - Official Method + API Integration
# Professional Edition v5.0 - Based on Complete Official Documentation

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

# Function to install Marzban Node using official script
install_marzban_node_official() {
    log "STEP" "Installing Marzban Node using official script..."
    log "INFO" "⏳ This may take 2-5 minutes depending on your internet connection..."
    
    # Install using official script
    if curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban-node.sh | sudo bash -s @ install --name "$NODE_NAME"; then
        log "SUCCESS" "Marzban Node installed successfully using official script"
        
        # Verify installation
        if command -v marzban-node >/dev/null 2>&1; then
            log "SUCCESS" "Marzban Node commands are available"
            return 0
        else
            log "ERROR" "Marzban Node commands not found after installation"
            return 1
        fi
    else
        log "ERROR" "Official installation failed"
        return 1
    fi
}

# Function to get API token
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

# Function to add node using API
add_node_via_api() {
    log "INFO" "Adding node '$NODE_NAME' to Marzban panel via API..."
    
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

# Function to get client certificate from panel
get_client_certificate_from_panel() {
    log "INFO" "Retrieving client certificate from panel..."
    
    # Wait for panel to generate certificate
    local max_attempts=30
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
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log "INFO" "Waiting for certificate generation... (attempt $attempt/$max_attempts)"
        fi
        sleep 5
    done
    
    log "ERROR" "Failed to retrieve client certificate"
    return 1
}

# Function to deploy client certificate
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

# Function to configure and start node
configure_and_start_node() {
    log "STEP" "Configuring and starting Marzban Node..."
    
    # Stop node if running
    marzban-node down >/dev/null 2>&1 || true
    
    # Deploy certificate if available
    if [[ -n "$CLIENT_CERT" ]]; then
        deploy_client_certificate
    fi
    
    # Start node using official command
    log "INFO" "Starting Marzban Node service..."
    if marzban-node up; then
        log "SUCCESS" "Marzban Node started successfully"
        
        # Wait for service to be ready
        local max_attempts=20
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            attempt=$((attempt + 1))
            
            if marzban-node status | grep -q "running\|up"; then
                log "SUCCESS" "Marzban Node is running and ready"
                return 0
            fi
            
            if [ $((attempt % 5)) -eq 0 ]; then
                log "INFO" "Waiting for service to be ready... (attempt $attempt/$max_attempts)"
            fi
            sleep 3
        done
        
        log "WARNING" "Service started but status unclear"
        return 0
    else
        log "ERROR" "Failed to start Marzban Node"
        return 1
    fi
}

# Function to verify node connection
verify_node_connection() {
    log "STEP" "Verifying node connection to panel..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        local node_response
        node_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${MARZBAN_NODE_ID}" \
            -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        local status=$(echo "$node_response" | jq -r .status 2>/dev/null || echo "unknown")
        
        case "$status" in
            "connected")
                log "SUCCESS" "🎉 Node is successfully connected to panel!"
                return 0
                ;;
            "connecting")
                if [ $((attempt % 5)) -eq 0 ]; then
                    log "INFO" "Node is connecting... (attempt $attempt/$max_attempts)"
                fi
                ;;
            *)
                log "WARNING" "Node status: $status"
                ;;
        esac
        
        sleep 5
    done
    
    log "WARNING" "Node connection verification timed out"
    return 1
}

# Function to show node management commands
show_management_commands() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Node Management Commands${NC}                  ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${CYAN}📋 Basic Commands:${NC}"
    echo "  marzban-node help          - Show all available commands"
    echo "  marzban-node status        - Check node status"
    echo "  marzban-node logs          - View node logs"
    echo "  marzban-node restart       - Restart node service"
    echo "  marzban-node up            - Start node service"
    echo "  marzban-node down          - Stop node service"
    
    echo -e "\n${CYAN}🔧 Advanced Commands:${NC}"
    echo "  marzban-node update        - Update node to latest version"
    echo "  marzban-node edit          - Edit docker-compose configuration"
    echo "  marzban-node core-update   - Update Xray core version"
    echo "  marzban-node uninstall     - Remove node completely"
    
    echo -e "\n${CYAN}📊 Monitoring:${NC}"
    echo "  marzban-node logs -f       - Follow logs in real-time"
    echo "  docker ps | grep marzban   - Check container status"
    echo "  ss -tuln | grep 62050      - Check port status"
}

# Function to configure API connection
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
    echo -e "${WHITE}║          ${CYAN}Final Marzban Node Deployer v5.0${NC}                ║"
    echo -e "${WHITE}║        ${GREEN}Official Script + API Integration${NC}               ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check dependencies
    if ! command -v curl >/dev/null 2>&1; then
        log "INFO" "Installing curl..."
        apt-get update && apt-get install -y curl
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log "INFO" "Installing jq..."
        apt-get install -y jq
    fi
    
    # Step 1: Configure API connection
    configure_api_connection
    
    # Step 2: Get API token
    get_marzban_token
    
    # Step 3: Add node to panel
    add_node_via_api
    
    # Step 4: Install Marzban Node using official script
    install_marzban_node_official
    
    # Step 5: Get client certificate
    get_client_certificate_from_panel
    
    # Step 6: Configure and start node
    configure_and_start_node
    
    # Step 7: Verify connection
    verify_node_connection
    
    # Success message
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Deployment Complete!${NC}                     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "SUCCESS" "🎉 Marzban Node deployed successfully!"
    log "INFO" "Node Name: $NODE_NAME"
    log "INFO" "Node ID: $MARZBAN_NODE_ID"
    log "INFO" "Service endpoint: https://$NODE_IP:62050"
    
    # Show management commands
    show_management_commands
    
    return 0
}

# Execute main function
main "$@"