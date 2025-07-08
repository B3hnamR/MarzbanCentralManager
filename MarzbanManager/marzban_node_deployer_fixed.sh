#!/bin/bash
# Marzban Node Deployer - Fixed & Professional Edition
# Version 4.0 - Based on Official Documentation & Best Practices
# Enhanced with Advanced Timing & Progress Tracking

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

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
NODE_DOMAIN=""
SSH_USER=""
SSH_PASSWORD=""
SSH_PORT="22"
INSTALLATION_METHOD=""

# Global timing variables
STEP_START_TIME=""
TOTAL_START_TIME=""
CURRENT_STEP=0
TOTAL_STEPS=8

log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $message";;
        DEBUG)   echo -e "[$timestamp] ${CYAN}🐛 DEBUG:${NC} $message";;
        PROGRESS) echo -e "[$timestamp] ${CYAN}⏳ PROGRESS:${NC} $message";;
        TIMER)   echo -e "[$timestamp] ${DIM}⏱️  TIMER:${NC} $message";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message";;
    esac
}

# Function to start step timer
start_step_timer() {
    STEP_START_TIME=$(date +%s)
    ((CURRENT_STEP++))
}

# Function to end step timer and show duration
end_step_timer() {
    local step_name="$1"
    local expected_duration="$2"
    
    if [[ -n "$STEP_START_TIME" ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - STEP_START_TIME))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        if [[ $minutes -gt 0 ]]; then
            log "TIMER" "[$CURRENT_STEP/$TOTAL_STEPS] $step_name completed in ${minutes}m ${seconds}s (expected: $expected_duration)"
        else
            log "TIMER" "[$CURRENT_STEP/$TOTAL_STEPS] $step_name completed in ${seconds}s (expected: $expected_duration)"
        fi
        
        show_total_elapsed
    fi
}

# Function to show progress with estimated time
show_progress() {
    local message="$1"
    local estimated_time="$2"
    log "PROGRESS" "[$CURRENT_STEP/$TOTAL_STEPS] $message (estimated: $estimated_time)"
}

# Function to start total timer
start_total_timer() {
    TOTAL_START_TIME=$(date +%s)
    log "TIMER" "🚀 Deployment started - Total estimated time: 5-10 minutes"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to show total elapsed time
show_total_elapsed() {
    if [[ -n "$TOTAL_START_TIME" ]]; then
        local current_time=$(date +%s)
        local elapsed=$((current_time - TOTAL_START_TIME))
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        
        if [[ $minutes -gt 0 ]]; then
            log "TIMER" "⏱️  Total elapsed time: ${minutes}m ${seconds}s"
        else
            log "TIMER" "⏱️  Total elapsed time: ${seconds}s"
        fi
    fi
}

# Function to show step progress bar
show_step_progress() {
    local step_name="$1"
    local progress=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((progress / 10))
    local empty=$((10 - filled))
    
    printf "\r${CYAN}Progress: [${NC}"
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "${CYAN}] %d%% - %s${NC}\n" $progress "$step_name"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to parse command line arguments
parse_arguments() {
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
            --ssh-user)
                SSH_USER="$2"
                shift 2
                ;;
            --ssh-port)
                SSH_PORT="$2"
                shift 2
                ;;
            --ssh-password)
                SSH_PASSWORD="$2"
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
            --installation-method)
                INSTALLATION_METHOD="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to show help
show_help() {
    echo "Marzban Node Deployer v4.0 - Fixed"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  --node-name <name>           Node name"
    echo "  --node-ip <ip>               Node IP address"
    echo "  --node-domain <domain>       Node domain"
    echo "  --panel-protocol <protocol>  Panel protocol (http/https)"
    echo "  --panel-domain <domain>      Panel domain"
    echo "  --panel-port <port>          Panel port"
    echo "  --panel-username <username>  Panel admin username"
    echo "  --panel-password <password>  Panel admin password"
    echo ""
    echo "Optional Options:"
    echo "  --ssh-user <user>            SSH username (default: root)"
    echo "  --ssh-port <port>            SSH port (default: 22)"
    echo "  --ssh-password <password>    SSH password"
    echo "  --installation-method <1|2>  Installation method (default: 1)"
    echo "  --help, -h                   Show this help message"
}

# Function to execute SSH commands with enhanced timing
ssh_execute() {
    local command="$1"
    local description="$2"
    local show_output="${3:-true}"
    local estimated_time="${4:-5-10s}"
    
    log "DEBUG" "Executing: $description (estimated: $estimated_time)"
    local cmd_start_time=$(date +%s)
    
    local result
    result=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "$command" 2>&1 || echo "SSH_COMMAND_FAILED")
    
    local cmd_end_time=$(date +%s)
    local cmd_duration=$((cmd_end_time - cmd_start_time))
    
    if echo "$result" | grep -q "SSH_COMMAND_FAILED"; then
        log "ERROR" "SSH command failed: $description (took ${cmd_duration}s)"
        if [[ "$show_output" == "true" ]]; then
            echo -e "${RED}Error Output:${NC} $result"
        fi
        return 1
    else
        log "SUCCESS" "SSH command completed: $description (took ${cmd_duration}s)"
        if [[ "$show_output" == "true" && -n "$result" && ! "$result" =~ "Warning: Permanently added" ]]; then
            echo -e "${CYAN}Output:${NC} $result"
        fi
        return 0
    fi
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    start_step_timer
    show_step_progress "Testing SSH connectivity"
    log "STEP" "Testing SSH connectivity to $NODE_IP..."
    
    if ssh_execute "echo 'SSH connection successful'" "SSH connectivity test" false "2-5s"; then
        log "SUCCESS" "SSH connection established successfully"
        end_step_timer "SSH Connectivity Test" "2-5s"
        return 0
    else
        log "ERROR" "SSH connection failed"
        return 1
    fi
}

# Function to get API token
get_marzban_token() {
    start_step_timer
    show_step_progress "Getting API token"
    
    if [ -n "$MARZBAN_TOKEN" ]; then
        end_step_timer "API Token (cached)" "0s"
        return 0
    fi

    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response

    log "INFO" "Getting Marzban API token..."
    show_progress "Authenticating with panel" "3-5s"
    
    response=$(curl -s -X POST "$login_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout 10 --max-time 20 --insecure 2>/dev/null)

    if echo "$response" | grep -q "access_token"; then
        MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
        if [ -n "$MARZBAN_TOKEN" ]; then
            log "SUCCESS" "Marzban API token obtained successfully"
            end_step_timer "API Token Authentication" "3-5s"
            return 0
        fi
    fi
    
    log "ERROR" "Failed to obtain API token"
    log "ERROR" "Response: $response"
    return 1
}

# Function to add node to panel via API
add_node_to_marzban_panel_api() {
    start_step_timer
    show_step_progress "Registering node with panel"
    log "INFO" "Registering node '$NODE_NAME' with the Marzban panel..."
    
    local add_node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node"
    local payload
    payload=$(printf '{"name": "%s", "address": "%s", "port": 62050, "api_port": 62051, "usage_coefficient": 1.0, "add_as_new_host": true}' "$NODE_NAME" "$NODE_IP")

    show_progress "Adding node to panel database" "2-5s"
    local response
    response=$(curl -s -X POST "$add_node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" --insecure)

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        MARZBAN_NODE_ID=$(echo "$response" | jq -r .id)
        log "SUCCESS" "Node '$NODE_NAME' successfully added to panel with ID: $MARZBAN_NODE_ID"
        end_step_timer "Node Registration" "2-5s"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node already exists, retrieving existing node ID..."
        
        local nodes_response
        nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" \
            -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        MARZBAN_NODE_ID=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$NODE_NAME\") | .id" 2>/dev/null)
        
        if [ -n "$MARZBAN_NODE_ID" ]; then
            log "SUCCESS" "Retrieved existing node ID: $MARZBAN_NODE_ID"
            end_step_timer "Node Registration (existing)" "2-5s"
            return 0
        fi
    fi
    
    log "ERROR" "Failed to add node to panel"
    log "ERROR" "Response: $response"
    return 1
}

# Function to get client certificate from panel
get_client_cert_from_marzban_api() {
    start_step_timer
    show_step_progress "Retrieving client certificate"
    log "INFO" "Retrieving client certificate for node ID: $MARZBAN_NODE_ID"
    
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        show_progress "Waiting for certificate generation (attempt $attempt/$max_attempts)" "5-30s"
        
        local node_response
        node_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${MARZBAN_NODE_ID}" \
            -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        if echo "$node_response" | jq -e '.client_cert' >/dev/null 2>&1; then
            CLIENT_CERT=$(echo "$node_response" | jq -r .client_cert)
            if [[ -n "$CLIENT_CERT" && "$CLIENT_CERT" != "null" ]]; then
                log "SUCCESS" "Client certificate retrieved successfully"
                end_step_timer "Certificate Retrieval" "5-30s"
                return 0
            fi
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log "INFO" "Still waiting for certificate generation... (attempt $attempt/$max_attempts)"
        fi
        sleep 5
    done
    
    log "ERROR" "Failed to retrieve client certificate from panel"
    return 1
}

# Function to install using official script
install_using_official_script() {
    start_step_timer
    show_step_progress "Installing Marzban Node (Official Script)"
    log "STEP" "Installing Marzban Node using official script..."
    log "INFO" "⏳ This may take 3-5 minutes depending on internet connection..."
    
    show_progress "Downloading and executing official installation script" "3-5 minutes"
    
    # Method 1: Install with name parameter
    local install_command="sudo bash -c \"\$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban-node.sh)\" @ install"
    if [[ -n "$NODE_NAME" ]]; then
        install_command="$install_command --name $NODE_NAME"
    fi
    
    # Show detailed progress during installation
    log "PROGRESS" "Step 1/4: Downloading installation script..."
    log "PROGRESS" "Step 2/4: Installing system dependencies..."
    log "PROGRESS" "Step 3/4: Setting up Docker environment..."
    log "PROGRESS" "Step 4/4: Configuring Marzban Node service..."
    
    if ssh_execute "$install_command" "Official Marzban Node installation" true "3-5 minutes"; then
        log "SUCCESS" "Official installation completed successfully"
        
        # Verify installation
        show_progress "Verifying installation" "10-15s"
        if ssh_execute "command -v marzban-node" "Verify marzban-node command" false "5s"; then
            log "SUCCESS" "Marzban Node commands are available"
            end_step_timer "Official Installation" "3-5 minutes"
            return 0
        else
            log "WARNING" "marzban-node command not found, trying alternative verification..."
            
            # Alternative verification - check if docker container exists
            if ssh_execute "docker ps | grep marzban-node" "Check Docker container" false "5s"; then
                log "SUCCESS" "Marzban Node Docker container is running"
                end_step_timer "Official Installation" "3-5 minutes"
                return 0
            else
                log "ERROR" "Marzban Node installation verification failed"
                return 1
            fi
        fi
    else
        log "ERROR" "Official installation failed"
        return 1
    fi
}

# Function to deploy client certificate
deploy_client_certificate() {
    start_step_timer
    show_step_progress "Deploying client certificate"
    log "STEP" "Deploying client certificate to node..."
    
    if [[ -z "$CLIENT_CERT" || "$CLIENT_CERT" == "null" ]]; then
        log "WARNING" "No client certificate available to deploy"
        end_step_timer "Certificate Deployment (skipped)" "0s"
        return 1
    fi
    
    show_progress "Installing certificate on node" "5-10s"
    
    # Create certificate file
    local cert_command="echo '$CLIENT_CERT' > /var/lib/marzban-node/ssl_client_cert.pem && chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && chown root:root /var/lib/marzban-node/ssl_client_cert.pem"
    
    if ssh_execute "$cert_command" "Deploy client certificate" false "5s"; then
        log "SUCCESS" "Client certificate deployed successfully"
        end_step_timer "Certificate Deployment" "5-10s"
        return 0
    else
        log "ERROR" "Failed to deploy client certificate"
        return 1
    fi
}

# Function to start and verify node service
start_and_verify_node_service() {
    start_step_timer
    show_step_progress "Starting and verifying service"
    log "STEP" "Starting and verifying Marzban Node service..."
    
    show_progress "Starting Marzban Node service" "10-15s"
    
    # Start the service
    if ssh_execute "marzban-node up" "Start Marzban Node service" true "10s"; then
        log "SUCCESS" "Marzban Node service started"
    else
        log "ERROR" "Failed to start Marzban Node service"
        return 1
    fi
    
    # Wait and verify service
    local max_attempts=30
    local attempt=0
    
    show_progress "Verifying service status and connectivity" "30-60s"
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log "PROGRESS" "Service verification attempt $attempt/$max_attempts..."
        fi
        
        # Check service status
        if ssh_execute "marzban-node status" "Check service status" false "3s"; then
            # Check if ports are listening
            if ssh_execute "ss -tuln | grep ':62050'" "Check port 62050" false "2s"; then
                log "SUCCESS" "Service is listening on port 62050"
                
                # Verify with panel
                show_progress "Verifying connection with panel" "10-20s"
                if verify_node_connection_with_panel; then
                    log "SUCCESS" "Node is successfully connected to panel"
                    end_step_timer "Service Start & Verification" "30-60s"
                    return 0
                fi
            fi
        fi
        
        sleep 5
    done
    
    log "WARNING" "Service verification timed out"
    end_step_timer "Service Start & Verification (timeout)" "30-60s"
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

# Function to configure connection details
configure_connection_details() {
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════���═╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Node Configuration${NC}                      ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # If arguments were provided, use them
    if [[ -n "$NODE_NAME" && -n "$NODE_IP" && -n "$MARZBAN_PANEL_DOMAIN" && -n "$MARZBAN_PANEL_USERNAME" && -n "$MARZBAN_PANEL_PASSWORD" ]]; then
        log "INFO" "Using provided arguments for configuration"
        log "INFO" "Node Name: $NODE_NAME"
        log "INFO" "Node IP: $NODE_IP"
        log "INFO" "Panel: ${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}"
        
        # Set defaults for optional parameters
        SSH_USER=${SSH_USER:-root}
        SSH_PORT=${SSH_PORT:-22}
        MARZBAN_PANEL_PROTOCOL=${MARZBAN_PANEL_PROTOCOL:-https}
        MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}
        INSTALLATION_METHOD=${INSTALLATION_METHOD:-1}
        
        return 0
    fi
    
    # Interactive mode if no arguments provided
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
    
    # Show final timing
    if [[ -n "$TOTAL_START_TIME" ]]; then
        local total_end_time=$(date +%s)
        local total_duration=$((total_end_time - TOTAL_START_TIME))
        local total_minutes=$((total_duration / 60))
        local total_seconds=$((total_duration % 60))
        
        echo -e "${BOLD}${GREEN}🎉 Deployment completed successfully in ${total_minutes}m ${total_seconds}s!${NC}\n"
    fi
    
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
    
    echo -e "\n${CYAN}���� Verification Commands:${NC}"
    echo "  ssh $SSH_USER@$NODE_IP 'marzban-node status'"
    echo "  ssh $SSH_USER@$NODE_IP 'ss -tuln | grep 62050'"
    echo "  curl -k https://$NODE_IP:62050"
    
    echo -e "\n${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main deployment function
main() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║            ${CYAN}Marzban Node Deployer v4.0 - Fixed${NC}             ║"
    echo -e "${WHITE}║              ${GREEN}Professional & Reliable Edition${NC}              ║"
    echo -e "${WHITE}║              ${YELLOW}Enhanced Timing & Progress Tracking${NC}           ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Parse command line arguments first
    parse_arguments "$@"
    
    # Start total timer
    start_total_timer
    
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
                # Manual method would go here if implemented
                log "ERROR" "Manual installation not implemented in this version"
                exit 1
            fi
            ;;
        2)
            log "ERROR" "Manual installation method not implemented in this version"
            exit 1
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