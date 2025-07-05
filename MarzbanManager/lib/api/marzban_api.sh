#!/bin/bash
# Marzban Central Manager - Marzban API Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# API CONFIGURATION
# ============================================================================

# API endpoints
readonly API_ENDPOINTS=(
    "admin/token"
    "admin"
    "nodes"
    "node"
    "users"
    "user"
    "system"
)

# API timeout settings
readonly API_CONNECT_TIMEOUT=10
readonly API_MAX_TIME=30
readonly API_RETRY_COUNT=3
readonly API_RETRY_DELAY=2

# ============================================================================
# API AUTHENTICATION FUNCTIONS
# ============================================================================

# Get Marzban API token
get_marzban_token() {
    local force_refresh="${1:-false}"
    
    # Return existing token if valid and not forcing refresh
    if [[ -n "$MARZBAN_TOKEN" && "$force_refresh" != "true" ]]; then
        log_debug "Using existing Marzban token"
        return 0
    fi
    
    # Check if API credentials are configured
    if ! is_api_configured; then
        log_error "Marzban Panel API credentials are not configured"
        return 1
    fi
    
    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response
    local attempt=1
    
    log_debug "Attempting to get Marzban API token..."
    
    while [[ $attempt -le $API_RETRY_COUNT ]]; do
        response=$(curl -s -X POST "$login_url" \
            -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
            --connect-timeout "$API_CONNECT_TIMEOUT" \
            --max-time "$API_MAX_TIME" \
            --insecure 2>/dev/null)
        
        if [[ $? -eq 0 ]] && echo "$response" | grep -q "access_token"; then
            MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
            if [[ -n "$MARZBAN_TOKEN" && "$MARZBAN_TOKEN" != "null" ]]; then
                log_debug "Marzban API token obtained successfully"
                return 0
            fi
        fi
        
        log_warning "API token request failed (attempt $attempt/$API_RETRY_COUNT)"
        
        if [[ $attempt -lt $API_RETRY_COUNT ]]; then
            sleep "$API_RETRY_DELAY"
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to obtain Marzban API token after $API_RETRY_COUNT attempts"
    log_debug "Last API response: $response"
    MARZBAN_TOKEN=""
    return 1
}

# Test API connection
test_api_connection() {
    local test_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response
    
    log_info "Testing API connection to $MARZBAN_PANEL_DOMAIN:$MARZBAN_PANEL_PORT"
    
    response=$(curl -s -X POST "$test_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout "$API_CONNECT_TIMEOUT" \
        --max-time "$API_MAX_TIME" \
        --insecure 2>/dev/null)
    
    if echo "$response" | grep -q "access_token"; then
        log_success "API connection test successful"
        return 0
    else
        log_error "API connection test failed"
        log_debug "Response: $response"
        return 1
    fi
}

# Refresh API token
refresh_api_token() {
    log_info "Refreshing API token..."
    get_marzban_token "true"
}

# ============================================================================
# API REQUEST FUNCTIONS
# ============================================================================

# Make authenticated API request
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local content_type="${4:-application/json}"
    
    # Ensure we have a valid token
    if ! get_marzban_token; then
        log_error "Cannot make API request without valid token"
        return 1
    fi
    
    local url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/${endpoint}"
    local curl_args=(
        -s
        -X "$method"
        -H "Authorization: Bearer $MARZBAN_TOKEN"
        -H "Accept: application/json"
        --connect-timeout "$API_CONNECT_TIMEOUT"
        --max-time "$API_MAX_TIME"
        --insecure
    )
    
    # Add content type and data for POST/PUT requests
    if [[ -n "$data" ]]; then
        curl_args+=(-H "Content-Type: $content_type")
        curl_args+=(-d "$data")
    fi
    
    local response
    local http_code
    local attempt=1
    
    while [[ $attempt -le $API_RETRY_COUNT ]]; do
        response=$(curl "${curl_args[@]}" "$url" 2>/dev/null)
        http_code=$(curl "${curl_args[@]}" -w "%{http_code}" -o /dev/null "$url" 2>/dev/null)
        
        # Check for successful response
        if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
            echo "$response"
            return 0
        fi
        
        # Check for authentication error
        if [[ $http_code -eq 401 ]]; then
            log_warning "API authentication failed, refreshing token..."
            if get_marzban_token "true"; then
                # Update authorization header with new token
                curl_args[3]="Authorization: Bearer $MARZBAN_TOKEN"
                continue
            else
                log_error "Failed to refresh API token"
                return 1
            fi
        fi
        
        log_warning "API request failed with HTTP $http_code (attempt $attempt/$API_RETRY_COUNT)"
        
        if [[ $attempt -lt $API_RETRY_COUNT ]]; then
            sleep "$API_RETRY_DELAY"
        fi
        
        ((attempt++))
    done
    
    log_error "API request failed after $API_RETRY_COUNT attempts"
    log_debug "Last response: $response"
    return 1
}

# GET request wrapper
api_get() {
    local endpoint="$1"
    api_request "GET" "$endpoint"
}

# POST request wrapper
api_post() {
    local endpoint="$1"
    local data="$2"
    local content_type="${3:-application/json}"
    api_request "POST" "$endpoint" "$data" "$content_type"
}

# PUT request wrapper
api_put() {
    local endpoint="$1"
    local data="$2"
    local content_type="${3:-application/json}"
    api_request "PUT" "$endpoint" "$data" "$content_type"
}

# DELETE request wrapper
api_delete() {
    local endpoint="$1"
    api_request "DELETE" "$endpoint"
}

# ============================================================================
# NODE MANAGEMENT API FUNCTIONS
# ============================================================================

# Get all nodes
get_all_nodes() {
    log_debug "Fetching all nodes from API"
    api_get "nodes"
}

# Get specific node by ID
get_node_by_id() {
    local node_id="$1"
    
    if [[ -z "$node_id" ]]; then
        log_error "Node ID is required"
        return 1
    fi
    
    log_debug "Fetching node $node_id from API"
    api_get "node/$node_id"
}

# Add new node to panel
add_node_to_panel() {
    local node_name="$1"
    local node_ip="$2"
    local node_port="${3:-62050}"
    local api_port="${4:-62051}"
    local usage_coefficient="${5:-1.0}"
    local add_as_new_host="${6:-false}"
    
    if [[ -z "$node_name" || -z "$node_ip" ]]; then
        log_error "Node name and IP are required"
        return 1
    fi
    
    local payload
    payload=$(jq -n \
        --arg name "$node_name" \
        --arg address "$node_ip" \
        --argjson port "$node_port" \
        --argjson api_port "$api_port" \
        --argjson usage_coefficient "$usage_coefficient" \
        --argjson add_as_new_host "$add_as_new_host" \
        '{
            name: $name,
            address: $address,
            port: $port,
            api_port: $api_port,
            usage_coefficient: $usage_coefficient,
            add_as_new_host: $add_as_new_host
        }')
    
    log_info "Adding node '$node_name' to panel..."
    local response
    response=$(api_post "node" "$payload")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local node_id
        node_id=$(echo "$response" | jq -r .id)
        log_success "Node '$node_name' added successfully with ID: $node_id"
        echo "$node_id"
        return 0
    else
        # Check if node already exists
        if echo "$response" | grep -q "already exists"; then
            log_warning "Node '$node_name' already exists, attempting to retrieve ID..."
            local existing_id
            existing_id=$(get_node_id_by_name "$node_name")
            if [[ -n "$existing_id" ]]; then
                log_success "Retrieved existing node ID: $existing_id"
                echo "$existing_id"
                return 0
            fi
        fi
        
        log_error "Failed to add node '$node_name' to panel"
        log_debug "API response: $response"
        return 1
    fi
}

# Get node ID by name
get_node_id_by_name() {
    local node_name="$1"
    
    if [[ -z "$node_name" ]]; then
        log_error "Node name is required"
        return 1
    fi
    
    local nodes_response
    nodes_response=$(get_all_nodes)
    
    if [[ $? -eq 0 ]] && echo "$nodes_response" | jq empty 2>/dev/null; then
        local node_id
        node_id=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$node_name\") | .id" 2>/dev/null)
        
        if [[ -n "$node_id" && "$node_id" != "null" ]]; then
            echo "$node_id"
            return 0
        fi
    fi
    
    return 1
}

# Remove node from panel
remove_node_from_panel() {
    local node_id="$1"
    
    if [[ -z "$node_id" ]]; then
        log_error "Node ID is required"
        return 1
    fi
    
    log_info "Removing node $node_id from panel..."
    local response
    response=$(api_delete "node/$node_id")
    
    if [[ $? -eq 0 ]]; then
        log_success "Node $node_id removed successfully"
        return 0
    else
        log_error "Failed to remove node $node_id"
        log_debug "API response: $response"
        return 1
    fi
}

# Get client certificate for node
get_client_certificate() {
    local node_id="$1"
    
    if [[ -z "$node_id" ]]; then
        log_error "Node ID is required"
        return 1
    fi
    
    log_debug "Retrieving client certificate for node $node_id"
    local response
    response=$(get_node_by_id "$node_id")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.client_cert' >/dev/null 2>&1; then
        local client_cert
        client_cert=$(echo "$response" | jq -r .client_cert)
        
        if [[ -n "$client_cert" && "$client_cert" != "null" ]]; then
            echo "$client_cert"
            return 0
        fi
    fi
    
    log_error "Failed to retrieve client certificate for node $node_id"
    return 1
}

# Update node configuration
update_node_config() {
    local node_id="$1"
    local config_data="$2"
    
    if [[ -z "$node_id" || -z "$config_data" ]]; then
        log_error "Node ID and configuration data are required"
        return 1
    fi
    
    log_info "Updating configuration for node $node_id..."
    local response
    response=$(api_put "node/$node_id" "$config_data")
    
    if [[ $? -eq 0 ]]; then
        log_success "Node $node_id configuration updated successfully"
        return 0
    else
        log_error "Failed to update node $node_id configuration"
        log_debug "API response: $response"
        return 1
    fi
}

# Reconnect node
reconnect_node() {
    local node_id="$1"
    
    if [[ -z "$node_id" ]]; then
        log_error "Node ID is required"
        return 1
    fi
    
    log_info "Reconnecting node $node_id..."
    local response
    response=$(api_post "node/$node_id/reconnect" "")
    
    if [[ $? -eq 0 ]]; then
        log_success "Node $node_id reconnection initiated"
        return 0
    else
        log_error "Failed to reconnect node $node_id"
        log_debug "API response: $response"
        return 1
    fi
}

# Get nodes usage statistics
get_nodes_usage() {
    log_debug "Fetching nodes usage statistics from API"
    api_get "nodes/usage"
}

# Get node usage by ID
get_node_usage() {
    local node_id="$1"
    
    if [[ -z "$node_id" ]]; then
        log_error "Node ID is required"
        return 1
    fi
    
    log_debug "Fetching usage statistics for node $node_id"
    api_get "node/$node_id/usage"
}

# Check node connectivity
check_node_connectivity() {
    local node_id="$1"
    
    if [[ -z "$node_id" ]]; then
        log_error "Node ID is required"
        return 1
    fi
    
    log_debug "Checking connectivity for node $node_id"
    local response
    response=$(get_node_by_id "$node_id")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.status' >/dev/null 2>&1; then
        local status
        status=$(echo "$response" | jq -r .status)
        echo "$status"
        return 0
    fi
    
    return 1
}

# Wait for node to be ready
wait_for_node_ready() {
    local node_id="$1"
    local max_attempts="${2:-30}"
    local wait_interval="${3:-5}"
    
    if [[ -z "$node_id" ]]; then
        log_error "Node ID is required"
        return 1
    fi
    
    log_info "Waiting for node $node_id to be ready..."
    
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        local status
        status=$(check_node_connectivity "$node_id" 2>/dev/null)
        
        case "$status" in
            "connected")
                log_success "Node $node_id is ready and connected"
                return 0
                ;;
            "connecting")
                log_debug "Node $node_id is connecting... (attempt $((attempt+1))/$max_attempts)"
                ;;
            *)
                log_debug "Node $node_id status: $status (attempt $((attempt+1))/$max_attempts)"
                ;;
        esac
        
        sleep "$wait_interval"
        ((attempt++))
    done
    
    log_warning "Node $node_id did not become ready within timeout"
    return 1
}

# ============================================================================
# USER MANAGEMENT API FUNCTIONS
# ============================================================================

# Get all users
get_all_users() {
    log_debug "Fetching all users from API"
    api_get "users"
}

# Get specific user by username
get_user_by_username() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi
    
    log_debug "Fetching user $username from API"
    api_get "user/$username"
}

# ============================================================================
# SYSTEM API FUNCTIONS
# ============================================================================

# Get system statistics
get_system_stats() {
    log_debug "Fetching system statistics from API"
    api_get "system"
}

# Get panel version
get_panel_version() {
    local response
    response=$(get_system_stats)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.version' >/dev/null 2>&1; then
        echo "$response" | jq -r .version
        return 0
    fi
    
    return 1
}

# ============================================================================
# API CONFIGURATION FUNCTIONS
# ============================================================================

# Configure Marzban API connection
configure_marzban_api() {
    log_step "Configuring Marzban Panel API Connection..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Marzban Panel API Setup${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Please provide your Marzban Panel details:${NC}\n"
    
    # Get protocol
    log_prompt "Panel Protocol (http/https) [default: https]:"
    read -r protocol
    protocol=${protocol:-https}
    
    # Get domain
    log_prompt "Panel Domain/IP (e.g., panel.example.com):"
    read -r domain
    
    # Get port
    log_prompt "Panel Port [default: 8000]:"
    read -r port
    port=${port:-8000}
    
    # Get username
    log_prompt "Admin Username:"
    read -r username
    
    # Get password
    log_prompt "Admin Password:"
    read -s password
    echo ""
    
    # Validate inputs
    if [[ -z "$domain" || -z "$username" || -z "$password" ]]; then
        log_error "All fields are required"
        return 1
    fi
    
    # Set global variables
    MARZBAN_PANEL_PROTOCOL="$protocol"
    MARZBAN_PANEL_DOMAIN="$domain"
    MARZBAN_PANEL_PORT="$port"
    MARZBAN_PANEL_USERNAME="$username"
    MARZBAN_PANEL_PASSWORD="$password"
    
    # Test connection
    log_info "Testing API connection..."
    if test_api_connection; then
        log_success "API connection test successful!"
        
        # Save configuration
        save_manager_config
        
        log_success "Marzban API configuration saved successfully"
        return 0
    else
        log_error "API connection test failed. Please check your credentials and panel accessibility"
        return 1
    fi
}

# Show API status
show_api_status() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║           ${CYAN}API Configuration Status${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    if is_api_configured; then
        echo -e "${GREEN}✅ API Status: Configured${NC}"
        echo -e "${BLUE}📡 Panel: ${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}${NC}"
        echo -e "${BLUE}👤 Username: ${MARZBAN_PANEL_USERNAME}${NC}"
        
        # Test connection
        if get_marzban_token >/dev/null 2>&1; then
            echo -e "${GREEN}🔗 Connection: Active${NC}"
            
            # Get panel version if possible
            local version
            version=$(get_panel_version 2>/dev/null)
            if [[ -n "$version" ]]; then
                echo -e "${BLUE}📋 Version: $version${NC}"
            fi
        else
            echo -e "${RED}🔗 Connection: Failed${NC}"
        fi
    else
        echo -e "${RED}❌ API Status: Not Configured${NC}"
        echo -e "${YELLOW}⚠️  Node operations require API configuration${NC}"
    fi
    echo ""
}

# Ensure API is configured
ensure_api_configured() {
    if ! is_api_configured; then
        log_warning "Marzban Panel API is not configured"
        log_info "API configuration is required for node management"
        log_prompt "Would you like to configure it now? (y/n):"
        read -r configure_now
        
        if [[ "$configure_now" =~ ^[Yy]$ ]]; then
            if configure_marzban_api; then
                log_success "API configured successfully. Continuing with operation..."
                return 0
            else
                log_error "Failed to configure API. Cannot proceed"
                return 1
            fi
        else
            log_error "API configuration is required for this operation"
            return 1
        fi
    else
        log_debug "API is already configured for panel: ${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}"
    fi
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize API module
init_marzban_api() {
    log_debug "Marzban API module initialized"
    return 0
}