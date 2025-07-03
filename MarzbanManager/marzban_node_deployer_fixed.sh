#!/bin/bash
# Marzban Node Deployer - Fixed & Professional Edition
# Version 4.0 - Based on Official Documentation & Best Practices

set -euo pipefail

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
SSH_USER=""
SSH_PASSWORD=""
SSH_PORT="22"
INSTALLATION_METHOD=""

log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $message";;
        DEBUG)   echo -e "[$timestamp] ${CYAN}🐛 DEBUG:${NC} $message";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message";;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to execute SSH commands with detailed logging
ssh_execute() {
    local command="$1"
    local description="$2"
    local show_output="${3:-true}"
    
    log "DEBUG" "Executing SSH: $description"
    
    local result
    result=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "$command" 2>&1 || echo "SSH_COMMAND_FAILED")
    
    if echo "$result" | grep -q "SSH_COMMAND_FAILED"; then
        log "ERROR" "SSH command failed: $description"
        if [[ "$show_output" == "true" ]]; then
            echo -e "${RED}Error Output:${NC} $result"
        fi
        return 1
    else
        log "SUCCESS" "SSH command completed: $description"
        if [[ "$show_output" == "true" && -n "$result" && ! "$result" =~ "Warning: Permanently added" ]]; then
            echo -e "${CYAN}Output:${NC} $result"
        fi
        return 0
    fi
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    log "STEP" "Testing SSH connectivity to $NODE_IP..."
    
    if ssh_execute "echo 'SSH connection successful'" "SSH connectivity test" false; then
        log "SUCCESS" "SSH connection established successfully"
        return 0
    else
        log "ERROR" "SSH connection failed"
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
            log "SUCCESS" "Marzban API token obtained successfully"
            return 0
        fi
    fi
    
    log "ERROR" "Failed to obtain API token"
    log "ERROR" "Response: $response"
    return 1
}

# Function to add node to panel via API
add_node_to_marzban_panel_api() {
    log "INFO" "Registering node '$NODE_NAME' with the Marzban panel..."
    
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
        log "SUCCESS" "Node '$NODE_NAME' successfully added to panel with ID: $MARZBAN_NODE_ID"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node already exists, retrieving existing node ID..."
        
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
    log "ERROR" "Response: $response"
    return 1
}

# Function to get client certificate from panel
get_client_cert_from_marzban_api() {
    log "INFO" "Retrieving client certificate for node ID: $MARZBAN_NODE_ID"
    
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
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log "INFO" "Waiting for certificate generation... (attempt $attempt/$max_attempts)"
        fi
        sleep 5
    done
    
    log "ERROR" "Failed to retrieve client certificate from panel"
    return 1
}

# Function to install using official script
install_using_official_script() {
    log "STEP" "Installing Marzban Node using official script..."
    log "INFO" "⏳ This may take 3-5 minutes depending on internet connection..."
    
    local install_command="sudo bash -c \"\$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban-node.sh)\" @ install"
    if [[ -n "$NODE_NAME" ]]; then
        install_command="$install_command --name $NODE_NAME"
    fi
    
    if ssh_execute "$install_command" "Official Marzban Node installation"; then
        log "SUCCESS" "Official installation completed successfully"
        
        # Verify installation
        if ssh_execute "command -v marzban-node" "Verify marzban-node command" false; then
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

# Function to deploy client certificate
deploy_client_certificate() {
    log "STEP" "Deploying client certificate to node..."
    
    if [[ -z "$CLIENT_CERT" || "$CLIENT_CERT" == "null" ]]; then
        log "WARNING" "No client certificate available to deploy"
        return 1
    fi
    
    # Create certificate file
    local cert_command="echo '$CLIENT_CERT' > /var/lib/marzban-node/ssl_client_cert.pem && chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && chown root:root /var/lib/marzban-node/ssl_client_cert.pem"
    
    if ssh_execute "$cert_command" "Deploy client certificate" false; then
        log "SUCCESS" "Client certificate deployed successfully"
        return 0
    else
        log "ERROR" "Failed to deploy client certificate"
        return 1
    fi
}

# Function to start and verify node service
start_and_verify_node_service() {
    log "STEP" "Starting and verifying Marzban Node service..."
    
    # Start the service
    if ssh_execute "marzban-node up" "Start Marzban Node service"; then
        log "SUCCESS" "Marzban Node service started"
    else
        log "ERROR" "Failed to start Marzban Node service"
        return 1
    fi
    
    # Wait and verify service
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        # Check service status
        if ssh_execute "marzban-node status" "Check service status" false; then
            # Check if ports are listening
            if ssh_execute "ss -tuln | grep ':62050'" "Check port 62050" false; then
                log "SUCCESS" "Service is listening on port 62050"
                
                # Verify with panel
                if verify_node_connection_with_panel; then
                    log "SUCCESS" "Node is successfully connected to panel"
                    return 0
                fi
            fi
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log "INFO" "Waiting for service to be ready... (attempt $attempt/$max_attempts)"
        fi
        sleep 5
    done
    
    log "WARNING" "Service verification timed out"
    return 1
}

# Function to verify node connection with panel
verify_node_connection_with_panel() {
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        local node_response
        node_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${MARZBAN_NODE_ID}" \
            -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure 2>/dev/null)
        
        local status=$(echo "$node_response" | jq -r .status 2>/dev/null || echo "unknown")
        
        case "$status" in
            "connected")
                return 0
                ;;
            "connecting")
                if [ $((attempt % 5)) -eq 0 ]; then
                    log "DEBUG" "Node is connecting... (attempt $attempt/$max_attempts)"
                fi
                ;;
            *)
                log "DEBUG" "Node status: $status"
                ;;
        esac
        
        sleep 3
    done
    
    return 1
}

# Function to install using manual method (fallback)
install_using_manual_method() {
    log "STEP" "Installing using manual method (fallback)..."
    log "INFO" "⏳ This may take 5-10 minutes..."
    
    # Install Docker
    log "INFO" "Installing Docker..."
    local docker_install="curl -fsSL https://get.docker.com | sh && systemctl start docker && systemctl enable docker"
    if ! ssh_execute "$docker_install" "Install Docker"; then
        log "ERROR" "Failed to install Docker"
        return 1
    fi
    
    # Clone repository and setup
    log "INFO" "Setting up Marzban Node environment..."
    local setup_commands="
        git clone https://github.com/Gozargah/Marzban-node ~/Marzban-node &&
        mkdir -p /var/lib/marzban-node &&
        cd ~/Marzban-node &&
        cat > docker-compose.yml << 'EOF'
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CERT_FILE: \"/var/lib/marzban-node/ssl_cert.pem\"
      SSL_KEY_FILE: \"/var/lib/marzban-node/ssl_key.pem\"
      SSL_CLIENT_CERT_FILE: \"/var/lib/marzban-node/ssl_client_cert.pem\"
      SERVICE_PROTOCOL: \"rest\"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
EOF"
    
    if ssh_execute "$setup_commands" "Setup Marzban Node environment"; then
        log "SUCCESS" "Manual setup completed"
        
        # Start service
        if ssh_execute "cd ~/Marzban-node && docker compose up -d" "Start service manually"; then
            log "SUCCESS" "Service started manually"
            return 0
        fi
    fi
    
    log "ERROR" "Manual installation failed"
    return 1
}

# Function to configure connection details
configure_connection_details() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Node Configuration${NC}                      ║"
    echo -e "${WHITE}╚═══════════════════���════════════════════════════════════════════╝${NC}\n"
    
    # Node details
    echo -n "Node Name: "
    read -r NODE_NAME
    echo -n "Node IP Address: "
    read -r NODE_IP
    echo -n "SSH Username [default: root]: "
    read -r ssh_user
    SSH_USER=${ssh_user:-root}
    echo -n "SSH Password: "
    read -s SSH_PASSWORD
    echo ""
    echo -n "SSH Port [default: 22]: "
    read -r ssh_port
    SSH_PORT=${ssh_port:-22}
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                   ${CYAN}Panel Configuration${NC}                     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Panel details
    echo -n "Panel Protocol (http/https) [default: https]: "
    read -r protocol
    MARZBAN_PANEL_PROTOCOL=${protocol:-https}
    echo -n "Panel Domain/IP: "
    read -r MARZBAN_PANEL_DOMAIN
    echo -n "Panel Port [default: 8000]: "
    read -r port
    MARZBAN_PANEL_PORT=${port:-8000}
    echo -n "Admin Username: "
    read -r MARZBAN_PANEL_USERNAME
    echo -n "Admin Password: "
    read -s MARZBAN_PANEL_PASSWORD
    echo ""
    
    # Installation method
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                 ${CYAN}Installation Method${NC}                      ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo "1. Official Script (Recommended)"
    echo "2. Manual Installation (Fallback)"
    echo -n "Choose installation method [default: 1]: "
    read -r method
    INSTALLATION_METHOD=${method:-1}
    
    # Validate inputs
    if [ -z "$NODE_NAME" ] || [ -z "$NODE_IP" ] || [ -z "$SSH_PASSWORD" ] || [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ]; then
        log "ERROR" "All fields are required"
        return 1
    fi
    
    return 0
}

# Function to show final status and commands
show_final_status() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Deployment Complete!${NC}                     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "SUCCESS" "🎉 Marzban Node deployed successfully!"
    log "INFO" "Node Name: $NODE_NAME"
    log "INFO" "Node IP: $NODE_IP"
    log "INFO" "Node ID: $MARZBAN_NODE_ID"
    log "INFO" "Service Endpoint: https://$NODE_IP:62050"
    
    echo -e "\n${CYAN}🔧 Management Commands (run on node server):${NC}"
    echo "  marzban-node status        - Check node status"
    echo "  marzban-node logs          - View node logs"
    echo "  marzban-node restart       - Restart node service"
    echo "  marzban-node update        - Update node"
    echo "  marzban-node help          - Show all commands"
    
    echo -e "\n${CYAN}📊 Verification Commands:${NC}"
    echo "  ssh $SSH_USER@$NODE_IP 'marzban-node status'"
    echo "  ssh $SSH_USER@$NODE_IP 'ss -tuln | grep 62050'"
    echo "  curl -k https://$NODE_IP:62050"
}

# Main deployment function
main() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║            ${CYAN}Marzban Node Deployer v4.0 - Fixed${NC}             ║"
    echo -e "${WHITE}║              ${GREEN}Professional & Reliable Edition${NC}              ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check dependencies
    if ! command_exists sshpass; then
        log "ERROR" "sshpass is required but not installed"
        log "INFO" "Install with: apt-get install sshpass"
        exit 1
    fi
    
    if ! command_exists jq; then
        log "ERROR" "jq is required but not installed"
        log "INFO" "Install with: apt-get install jq"
        exit 1
    fi
    
    # Step 1: Configure connection details
    if ! configure_connection_details; then
        log "ERROR" "Configuration failed"
        exit 1
    fi
    
    # Step 2: Test SSH connectivity
    if ! test_ssh_connectivity; then
        log "ERROR" "SSH connectivity test failed"
        exit 1
    fi
    
    # Step 3: Get API token
    if ! get_marzban_token; then
        log "ERROR" "Failed to get API token"
        exit 1
    fi
    
    # Step 4: Add node to panel
    if ! add_node_to_marzban_panel_api; then
        log "ERROR" "Failed to add node to panel"
        exit 1
    fi
    
    # Step 5: Install Marzban Node
    case "$INSTALLATION_METHOD" in
        1)
            if ! install_using_official_script; then
                log "WARNING" "Official installation failed, trying manual method..."
                if ! install_using_manual_method; then
                    log "ERROR" "Both installation methods failed"
                    exit 1
                fi
            fi
            ;;
        2)
            if ! install_using_manual_method; then
                log "ERROR" "Manual installation failed"
                exit 1
            fi
            ;;
    esac
    
    # Step 6: Get and deploy client certificate
    if get_client_cert_from_marzban_api; then
        deploy_client_certificate
    else
        log "WARNING" "Could not retrieve client certificate, continuing without it"
    fi
    
    # Step 7: Start and verify service
    if ! start_and_verify_node_service; then
        log "WARNING" "Service verification failed, but installation may still be successful"
    fi
    
    # Step 8: Show final status
    show_final_status
    
    return 0
}

# Execute main function
main "$@"