#!/bin/bash
# Marzban Central Manager - Node Management Module with HAProxy Integration
# Professional Edition v4.0 - Complete HAProxy Integration

# ============================================================================
# NODE CONFIGURATION MANAGEMENT
# ============================================================================

# Load nodes configuration from file
load_nodes_config() {
    if [[ -f "$NODES_CONFIG_FILE" ]]; then
        mapfile -t NODES_ARRAY < <(grep -vE '^\s*#|^\s*$' "$NODES_CONFIG_FILE" || true)
        log_debug "Loaded ${#NODES_ARRAY[@]} nodes from configuration"
    else
        NODES_ARRAY=()
        log_debug "No nodes configuration file found, starting with empty array"
    fi
}

# Save nodes configuration to file
save_nodes_config() {
    if [[ ${#NODES_ARRAY[@]} -gt 0 ]]; then
        printf "%s\n" "${NODES_ARRAY[@]}" > "$NODES_CONFIG_FILE"
    else
        # Create empty file if no nodes
        touch "$NODES_CONFIG_FILE"
    fi
    
    chmod 600 "$NODES_CONFIG_FILE"
    log_debug "Nodes configuration saved to $NODES_CONFIG_FILE"
}

# Add node to configuration
add_node_to_config() {
    local name="$1"
    local ip="$2"
    local user="$3"
    local port="$4"
    local domain="$5"
    local password="$6"
    local node_id="${7:-}"
    
    # Validate required parameters
    if [[ -z "$name" || -z "$ip" || -z "$user" || -z "$port" || -z "$domain" || -z "$password" ]]; then
        log_error "All node parameters are required"
        return 1
    fi
    
    # Check if node already exists
    if get_node_config_by_name "$name" >/dev/null 2>&1; then
        log_error "Node '$name' already exists in configuration"
        return 1
    fi
    
    # Add node to array
    NODES_ARRAY+=("${name};${ip};${user};${port};${domain};${password};${node_id}")
    log_info "Node '$name' added to configuration"
    
    return 0
}

# Get node configuration by name
get_node_config_by_name() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Node name is required"
        return 1
    fi
    
    for entry in "${NODES_ARRAY[@]}"; do
        if [[ "$entry" == "${name};"* ]]; then
            echo "$entry"
            return 0
        fi
    done
    
    return 1
}

# Get node configuration by IP
get_node_config_by_ip() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        log_error "Node IP is required"
        return 1
    fi
    
    for entry in "${NODES_ARRAY[@]}"; do
        local node_ip=$(echo "$entry" | cut -d';' -f2)
        if [[ "$node_ip" == "$ip" ]]; then
            echo "$entry"
            return 0
        fi
    done
    
    return 1
}

# Update node configuration
update_node_config() {
    local old_name="$1"
    local new_name="$2"
    local new_ip="$3"
    local new_user="$4"
    local new_port="$5"
    local new_domain="$6"
    local new_password="$7"
    local new_node_id="${8:-}"
    
    # Find and update the node
    local updated=false
    for i in "${!NODES_ARRAY[@]}"; do
        local entry="${NODES_ARRAY[$i]}"
        local node_name=$(echo "$entry" | cut -d';' -f1)
        
        if [[ "$node_name" == "$old_name" ]]; then
            # Get existing node_id if not provided
            if [[ -z "$new_node_id" ]]; then
                new_node_id=$(echo "$entry" | cut -d';' -f7)
            fi
            
            NODES_ARRAY[$i]="${new_name};${new_ip};${new_user};${new_port};${new_domain};${new_password};${new_node_id}"
            updated=true
            log_info "Node '$old_name' configuration updated"
            break
        fi
    done
    
    if [[ "$updated" == "false" ]]; then
        log_error "Node '$old_name' not found in configuration"
        return 1
    fi
    
    return 0
}

# Remove node from configuration
remove_node_from_config() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Node name is required"
        return 1
    fi
    
    local new_array=()
    local removed=false
    
    for entry in "${NODES_ARRAY[@]}"; do
        local node_name=$(echo "$entry" | cut -d';' -f1)
        if [[ "$node_name" != "$name" ]]; then
            new_array+=("$entry")
        else
            removed=true
        fi
    done
    
    if [[ "$removed" == "true" ]]; then
        NODES_ARRAY=("${new_array[@]}")
        log_info "Node '$name' removed from configuration"
        return 0
    else
        log_error "Node '$name' not found in configuration"
        return 1
    fi
}

# List all configured nodes
list_configured_nodes() {
    load_nodes_config
    
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        echo "No nodes configured"
        return 0
    fi
    
    echo "Configured Nodes:"
    echo "=================="
    
    local i=1
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        echo "$i. $name"
        echo "   IP: $ip"
        echo "   Domain: $domain"
        echo "   SSH: $user@$ip:$port"
        echo "   Node ID: ${node_id:-'Not set'}"
        echo ""
        ((i++))
    done
}

# Get node count
get_node_count() {
    load_nodes_config
    echo "${#NODES_ARRAY[@]}"
}

# ============================================================================
# NODE OPERATIONS WITH HAPROXY INTEGRATION
# ============================================================================

# Deploy new node with automatic HAProxy integration
deploy_new_node() {
    local node_name="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_domain="$5"
    local node_password="$6"
    
    log_step "Deploying new node with HAProxy integration: $node_name"
    
    # Validate inputs
    if [[ -z "$node_name" || -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_domain" || -z "$node_password" ]]; then
        log_error "All node parameters are required for deployment"
        return 1
    fi
    
    # Check if API is configured
    if ! ensure_api_configured; then
        return 1
    fi
    
    # Test SSH connectivity
    log_info "Testing SSH connectivity to $node_ip..."
    if ! test_ssh_connection "$node_ip" "$node_user" "$node_port" "$node_password"; then
        log_error "SSH connectivity test failed"
        return 1
    fi
    
    # Deploy using the node deployer
    log_info "Starting node deployment process..."
    if deploy_node_with_deployer "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
        log_success "Node deployment completed successfully"
        
        # Automatic HAProxy integration
        if command -v auto_haproxy_integration_on_node_add >/dev/null 2>&1; then
            log_info "Performing automatic HAProxy integration..."
            if auto_haproxy_integration_on_node_add "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
                log_success "HAProxy integration completed successfully"
            else
                log_warning "HAProxy integration failed, but node deployment was successful"
            fi
        else
            log_debug "HAProxy integration function not available"
        fi
        
        return 0
    else
        log_error "Node deployment failed"
        return 1
    fi
}

# Deploy node using the deployer script
deploy_node_with_deployer() {
    local node_name="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_domain="$5"
    local node_password="$6"
    
    # Use the fixed deployer script
    local deployer_script="$(dirname "$0")/marzban_node_deployer_fixed.sh"
    
    if [[ ! -f "$deployer_script" ]]; then
        log_error "Node deployer script not found: $deployer_script"
        return 1
    fi
    
    # Execute deployer locally with SSH parameters
    log_info "Executing node deployer..."
    
    # Set environment variables for the deployer
    export NODE_NAME="$node_name"
    export NODE_IP="$node_ip"
    export SSH_USER="$node_user"
    export SSH_PORT="$node_port"
    export SSH_PASSWORD="$node_password"
    export MARZBAN_PANEL_PROTOCOL="${MARZBAN_PANEL_PROTOCOL:-https}"
    export MARZBAN_PANEL_DOMAIN="$MARZBAN_PANEL_DOMAIN"
    export MARZBAN_PANEL_PORT="${MARZBAN_PANEL_PORT:-8000}"
    export MARZBAN_PANEL_USERNAME="$MARZBAN_PANEL_USERNAME"
    export MARZBAN_PANEL_PASSWORD="$MARZBAN_PANEL_PASSWORD"
    
    # Execute the deployer
    if bash "$deployer_script"; then
        # Get node ID from API
        local node_id
        node_id=$(get_node_id_by_name "$node_name")
        
        # Add to local configuration
        add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$node_id"
        save_nodes_config
        
        # Send notification
        send_telegram_notification "🎉 New Node Deployed%0A%0ANode: $node_name%0AIP: $node_ip%0ADomain: $node_domain%0AStatus: ✅ Online" "normal"
        
        return 0
    else
        log_error "Node deployment failed"
        return 1
    fi
}

# Import existing node with HAProxy integration
import_existing_node() {
    local node_name="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_domain="$5"
    local node_password="$6"
    
    log_step "Importing existing node with HAProxy integration: $node_name"
    
    # Test SSH connectivity
    log_info "Testing SSH connectivity to $node_ip..."
    if ! test_ssh_connection "$node_ip" "$node_user" "$node_port" "$node_password"; then
        log_error "SSH connectivity test failed"
        return 1
    fi
    
    # Check if Marzban Node is installed
    log_info "Checking if Marzban Node is installed..."
    local check_command="docker ps 2>/dev/null | grep -q marzban-node && echo 'INSTALLED' || echo 'NOT_INSTALLED'"
    local install_status
    
    install_status=$(ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "$check_command" "Installation Check" 2>/dev/null | tail -1)
    
    if [[ "$install_status" == "INSTALLED" ]]; then
        log_success "Marzban Node is already installed"
        
        # Check if node is registered in panel
        if ensure_api_configured; then
            local node_id
            node_id=$(get_node_id_by_name "$node_name")
            
            if [[ -n "$node_id" ]]; then
                log_success "Node is already registered in panel with ID: $node_id"
            else
                log_warning "Node is not registered in panel, registering now..."
                node_id=$(add_node_to_panel "$node_name" "$node_ip")
                
                if [[ -n "$node_id" ]]; then
                    # Deploy new client certificate
                    deploy_client_certificate_to_node "$node_id" "$node_ip" "$node_user" "$node_port" "$node_password"
                fi
            fi
            
            # Add to configuration
            add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$node_id"
            save_nodes_config
            
            # Automatic HAProxy integration
            if command -v auto_haproxy_integration_on_node_add >/dev/null 2>&1; then
                log_info "Performing automatic HAProxy integration..."
                if auto_haproxy_integration_on_node_add "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
                    log_success "HAProxy integration completed successfully"
                else
                    log_warning "HAProxy integration failed, but node import was successful"
                fi
            fi
            
            log_success "Node '$node_name' imported successfully"
            return 0
        else
            log_error "API configuration required for node import"
            return 1
        fi
    else
        log_warning "Marzban Node is not installed on this server"
        log_prompt "Would you like to install it now? (y/n):"
        read -r install_choice
        
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            return deploy_new_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"
        else
            log_info "Node import cancelled"
            return 1
        fi
    fi
}

# Remove node completely with HAProxy cleanup
remove_node_completely() {
    local node_name="$1"
    
    log_step "Removing node with HAProxy cleanup: $node_name"
    
    # Get node configuration
    local node_config
    node_config=$(get_node_config_by_name "$node_name")
    
    if [[ -z "$node_config" ]]; then
        log_error "Node '$node_name' not found in configuration"
        return 1
    fi
    
    IFS=';' read -r name ip user port domain password node_id <<< "$node_config"
    
    # Confirm removal
    echo -e "\n${YELLOW}⚠️  WARNING: This will remove node '$node_name' from:${NC}"
    echo "- Local configuration"
    echo "- Marzban Panel (if connected)"
    echo "- HAProxy configuration (all nodes)"
    echo ""
    
    log_prompt "Are you sure you want to remove node '$node_name'? (yes/no):"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Node removal cancelled"
        return 0
    fi
    
    # Remove from Marzban Panel
    if [[ -n "$node_id" && "$node_id" != "null" ]] && ensure_api_configured; then
        log_info "Removing node from Marzban Panel..."
        if remove_node_from_panel "$node_id"; then
            log_success "Node removed from Marzban Panel"
        else
            log_warning "Failed to remove node from Marzban Panel"
        fi
    fi
    
    # Automatic HAProxy cleanup
    if command -v auto_haproxy_integration_on_node_remove >/dev/null 2>&1; then
        log_info "Performing automatic HAProxy cleanup..."
        if auto_haproxy_integration_on_node_remove "$name"; then
            log_success "HAProxy cleanup completed successfully"
        else
            log_warning "HAProxy cleanup failed"
        fi
    else
        log_debug "HAProxy integration function not available"
    fi
    
    # Remove from local configuration
    if remove_node_from_config "$node_name"; then
        save_nodes_config
        log_success "Node '$node_name' removed from local configuration"
    fi
    
    # Send notification
    send_telegram_notification "🗑️ Node Removed%0A%0ANode: $node_name%0AIP: $ip%0ADomain: $domain" "normal"
    
    log_success "Node '$node_name' removed successfully"
    return 0
}

# ============================================================================
# NODE HEALTH AND STATUS
# ============================================================================

# Check node health via API
check_node_health() {
    local node_name="$1"
    
    # Get node configuration
    local node_config
    node_config=$(get_node_config_by_name "$node_name")
    
    if [[ -z "$node_config" ]]; then
        log_error "Node '$node_name' not found in configuration"
        return 1
    fi
    
    IFS=';' read -r name ip user port domain password node_id <<< "$node_config"
    
    if [[ -z "$node_id" || "$node_id" == "null" ]]; then
        log_warning "Node '$node_name' has no API ID, cannot check health via panel"
        return 1
    fi
    
    # Check via Marzban API
    if ensure_api_configured; then
        local node_info
        node_info=$(get_node_by_id "$node_id")
        
        if [[ $? -eq 0 ]] && echo "$node_info" | jq -e '.status' >/dev/null 2>&1; then
            local status
            status=$(echo "$node_info" | jq -r '.status')
            echo "$status"
            return 0
        fi
    fi
    
    return 1
}

# Check node SSH connectivity
check_node_ssh() {
    local node_name="$1"
    
    # Get node configuration
    local node_config
    node_config=$(get_node_config_by_name "$node_name")
    
    if [[ -z "$node_config" ]]; then
        log_error "Node '$node_name' not found in configuration"
        return 1
    fi
    
    IFS=';' read -r name ip user port domain password node_id <<< "$node_config"
    
    # Test SSH connection
    if test_ssh_connection "$ip" "$user" "$port" "$password"; then
        echo "connected"
        return 0
    else
        echo "disconnected"
        return 1
    fi
}

# Get comprehensive node status
get_node_status() {
    local node_name="$1"
    
    # Get node configuration
    local node_config
    node_config=$(get_node_config_by_name "$node_name")
    
    if [[ -z "$node_config" ]]; then
        echo "not_found"
        return 1
    fi
    
    IFS=';' read -r name ip user port domain password node_id <<< "$node_config"
    
    local ssh_status="unknown"
    local api_status="unknown"
    local service_status="unknown"
    local haproxy_status="unknown"
    
    # Check SSH connectivity
    if test_ssh_connection "$ip" "$user" "$port" "$password" >/dev/null 2>&1; then
        ssh_status="connected"
        
        # Check service status via SSH
        local service_check="docker ps 2>/dev/null | grep -q marzban-node && echo 'running' || echo 'stopped'"
        service_status=$(ssh_remote "$ip" "$user" "$port" "$password" "$service_check" "Service Check" 2>/dev/null | tail -1)
        
        # Check HAProxy status via SSH
        local haproxy_check="command -v haproxy >/dev/null 2>&1 && systemctl is-active --quiet haproxy 2>/dev/null && echo 'running' || echo 'not_running'"
        haproxy_status=$(ssh_remote "$ip" "$user" "$port" "$password" "$haproxy_check" "HAProxy Check" 2>/dev/null | tail -1)
    else
        ssh_status="disconnected"
    fi
    
    # Check API status
    if [[ -n "$node_id" && "$node_id" != "null" ]]; then
        api_status=$(check_node_health "$node_name" 2>/dev/null || echo "unknown")
    fi
    
    # Return status as JSON
    jq -n \
        --arg name "$name" \
        --arg ip "$ip" \
        --arg domain "$domain" \
        --arg ssh_status "$ssh_status" \
        --arg api_status "$api_status" \
        --arg service_status "$service_status" \
        --arg haproxy_status "$haproxy_status" \
        --arg node_id "${node_id:-null}" \
        '{
            name: $name,
            ip: $ip,
            domain: $domain,
            ssh_status: $ssh_status,
            api_status: $api_status,
            service_status: $service_status,
            haproxy_status: $haproxy_status,
            node_id: $node_id
        }'
}

# Monitor all nodes health with HAProxy status
monitor_all_nodes_health() {
    load_nodes_config
    
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        log_info "No nodes configured for monitoring"
        return 0
    fi
    
    log_info "Monitoring health of ${#NODES_ARRAY[@]} nodes (including HAProxy status)..."
    
    local healthy_count=0
    local unhealthy_count=0
    local unhealthy_nodes=()
    local haproxy_issues=()
    
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        
        local status
        status=$(get_node_status "$name")
        
        local ssh_status api_status haproxy_status
        ssh_status=$(echo "$status" | jq -r '.ssh_status')
        api_status=$(echo "$status" | jq -r '.api_status')
        haproxy_status=$(echo "$status" | jq -r '.haproxy_status')
        
        if [[ "$ssh_status" == "connected" && ("$api_status" == "connected" || "$api_status" == "unknown") ]]; then
            ((healthy_count++))
            log_debug "Node $name: Healthy"
            
            # Check HAProxy sync if main server has HAProxy
            if [[ "$MAIN_HAS_HAPROXY" == "true" && "$haproxy_status" != "running" ]]; then
                haproxy_issues+=("$name:no_haproxy")
            fi
        else
            ((unhealthy_count++))
            unhealthy_nodes+=("$name:$ssh_status/$api_status")
            log_warning "Node $name: Unhealthy (SSH: $ssh_status, API: $api_status)"
        fi
        
        # Rate limiting
        sleep "$API_RATE_LIMIT_DELAY"
    done
    
    log_info "Health monitoring completed: $healthy_count healthy, $unhealthy_count unhealthy"
    
    # Check HAProxy sync status if enabled
    if [[ "$MAIN_HAS_HAPROXY" == "true" ]] && command -v check_haproxy_sync_status_all_nodes >/dev/null 2>&1; then
        if ! check_haproxy_sync_status_all_nodes >/dev/null 2>&1; then
            log_warning "Some nodes are out of sync with HAProxy configuration"
        fi
    fi
    
    # Send notification if there are issues
    if [[ $unhealthy_count -gt 0 || ${#haproxy_issues[@]} -gt 0 ]]; then
        local notification_message="🔴 Node Health Alert%0A%0A"
        
        if [[ $unhealthy_count -gt 0 ]]; then
            notification_message+="Unhealthy nodes: ${unhealthy_nodes[*]}%0A"
        fi
        
        if [[ ${#haproxy_issues[@]} -gt 0 ]]; then
            notification_message+="HAProxy issues: ${haproxy_issues[*]}%0A"
        fi
        
        notification_message+="%0A✅ Healthy: $healthy_count%0A"
        notification_message+="❌ Unhealthy: $unhealthy_count"
        
        send_telegram_notification "$notification_message" "high"
    fi
    
    return 0
}

# ============================================================================
# NODE CERTIFICATE MANAGEMENT
# ============================================================================

# Deploy client certificate to node
deploy_client_certificate_to_node() {
    local node_id="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_password="$5"
    
    log_info "Deploying client certificate to node..."
    
    # Get client certificate from API
    local client_cert
    client_cert=$(get_client_certificate "$node_id")
    
    if [[ -z "$client_cert" ]]; then
        log_error "Failed to retrieve client certificate"
        return 1
    fi
    
    # Create temporary certificate file
    local temp_cert
    temp_cert=$(mktemp)
    echo "$client_cert" > "$temp_cert"
    
    # Deploy certificate to node
    if scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" \
       "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"; then
        
        # Set proper permissions
        ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
            "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && chown root:root /var/lib/marzban-node/ssl_client_cert.pem" \
            "Certificate Permissions"
        
        # Restart node service
        ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
            "cd /opt/marzban-node && docker compose restart" \
            "Service Restart"
        
        log_success "Client certificate deployed successfully"
        rm -f "$temp_cert"
        return 0
    else
        log_error "Failed to deploy client certificate"
        rm -f "$temp_cert"
        return 1
    fi
}

# Update certificates on all nodes
update_all_node_certificates() {
    load_nodes_config
    
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        log_warning "No nodes configured for certificate update"
        return 0
    fi
    
    if ! ensure_api_configured; then
        log_error "API configuration required for certificate updates"
        return 1
    fi
    
    log_step "Updating certificates on all nodes..."
    
    local updated=0
    local failed=0
    
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        
        if [[ -n "$node_id" && "$node_id" != "null" ]]; then
            log_info "Updating certificate for node: $name"
            
            if deploy_client_certificate_to_node "$node_id" "$ip" "$user" "$port" "$password"; then
                ((updated++))
                log_success "Certificate updated for node: $name"
            else
                ((failed++))
                log_error "Failed to update certificate for node: $name"
            fi
        else
            log_warning "Node '$name' has no API ID, skipping certificate update"
        fi
    done
    
    log_success "Certificate update completed: $updated updated, $failed failed"
    
    # Send notification
    send_telegram_notification "🔐 Certificate Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
    
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize node manager module
init_node_manager() {
    # Load existing nodes configuration
    load_nodes_config
    
    log_debug "Node manager module initialized with ${#NODES_ARRAY[@]} nodes"
    return 0
}