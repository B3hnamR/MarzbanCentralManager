#!/bin/bash
# HAProxy Management System for Marzban Central Manager
# Professional Edition v4.0

# ============================================================================
# HAPROXY DETECTION AND CONFIGURATION
# ============================================================================

# Initialize HAProxy management
init_haproxy_manager() {
    log_debug "Initializing HAProxy manager..."
    
    # Detect HAProxy installation and configuration
    detect_haproxy_configuration
    
    # Load existing HAProxy configuration if available
    if [[ "$MAIN_HAS_HAPROXY" == "true" ]]; then
        load_haproxy_configuration
        detect_single_port_usage
    fi
    
    log_success "HAProxy manager initialized"
    return 0
}

# Comprehensive HAProxy detection
detect_haproxy_configuration() {
    log_step "Detecting HAProxy configuration..."
    
    # Reset variables
    MAIN_HAS_HAPROXY=false
    HAPROXY_CONFIG_PATH=""
    HAPROXY_SINGLE_PORT_MODE=false
    HAPROXY_SINGLE_PORT=""
    
    # Check if HAProxy is installed
    if ! command_exists haproxy; then
        log_info "HAProxy not installed"
        return 0
    fi
    
    MAIN_HAS_HAPROXY=true
    log_info "HAProxy detected"
    
    # Find HAProxy configuration file
    find_haproxy_config_path
    
    # Check if HAProxy is running
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        log_info "HAProxy service is running"
        HAPROXY_SERVICE_RUNNING=true
    else
        log_warning "HAProxy service is not running"
        HAPROXY_SERVICE_RUNNING=false
    fi
    
    # Export variables
    export MAIN_HAS_HAPROXY HAPROXY_CONFIG_PATH HAPROXY_SERVICE_RUNNING
    export HAPROXY_SINGLE_PORT_MODE HAPROXY_SINGLE_PORT
    
    return 0
}

# Find HAProxy configuration file path
find_haproxy_config_path() {
    local possible_paths=(
        "/etc/haproxy/haproxy.cfg"
        "/usr/local/etc/haproxy/haproxy.cfg"
        "/opt/haproxy/haproxy.cfg"
    )
    
    # Check common paths
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            HAPROXY_CONFIG_PATH="$path"
            log_info "HAProxy config found at: $path"
            return 0
        fi
    done
    
    # Try to find from running process
    local haproxy_proc
    haproxy_proc=$(ps aux | grep haproxy | grep -v grep | head -1 || true)
    if [[ -n "$haproxy_proc" ]]; then
        HAPROXY_CONFIG_PATH=$(echo "$haproxy_proc" | grep -o '\-f [^ ]*' | cut -d' ' -f2 || true)
        if [[ -n "$HAPROXY_CONFIG_PATH" && -f "$HAPROXY_CONFIG_PATH" ]]; then
            log_info "HAProxy config found from process: $HAPROXY_CONFIG_PATH"
            return 0
        fi
    fi
    
    log_warning "HAProxy config file not found"
    return 1
}

# Load and analyze existing HAProxy configuration
load_haproxy_configuration() {
    if [[ ! -f "$HAPROXY_CONFIG_PATH" ]]; then
        log_warning "HAProxy config file not found: $HAPROXY_CONFIG_PATH"
        return 1
    fi
    
    log_info "Loading HAProxy configuration..."
    
    # Create backup of current config
    cp "$HAPROXY_CONFIG_PATH" "${HAPROXY_CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Analyze configuration for Marzban nodes
    analyze_haproxy_marzban_config
    
    return 0
}

# Analyze HAProxy configuration for Marzban-specific settings
analyze_haproxy_marzban_config() {
    log_debug "Analyzing HAProxy configuration for Marzban nodes..."
    
    # Check for existing Marzban backends
    local marzban_backends
    marzban_backends=$(grep -E "backend.*marzban|server.*marzban" "$HAPROXY_CONFIG_PATH" || true)
    
    if [[ -n "$marzban_backends" ]]; then
        log_info "Found existing Marzban backends in HAProxy config"
        log_debug "Existing backends: $marzban_backends"
    else
        log_info "No existing Marzban backends found"
    fi
    
    # Store current configuration hash for sync checking
    HAPROXY_CONFIG_HASH=$(md5sum "$HAPROXY_CONFIG_PATH" | cut -d' ' -f1)
    export HAPROXY_CONFIG_HASH
}

# Detect if HAProxy is being used for single port configuration
detect_single_port_usage() {
    log_debug "Detecting single port usage pattern..."
    
    # Look for common single port patterns
    local single_port_patterns=(
        "bind.*:443"
        "bind.*:80"
        "bind.*:8080"
        "bind.*:2053"
        "bind.*:2083"
        "bind.*:2087"
        "bind.*:2096"
    )
    
    for pattern in "${single_port_patterns[@]}"; do
        if grep -q "$pattern" "$HAPROXY_CONFIG_PATH" 2>/dev/null; then
            local port
            port=$(grep "$pattern" "$HAPROXY_CONFIG_PATH" | head -1 | grep -o ':[0-9]*' | cut -d':' -f2)
            if [[ -n "$port" ]]; then
                HAPROXY_SINGLE_PORT_MODE=true
                HAPROXY_SINGLE_PORT="$port"
                log_info "Single port mode detected: Port $port"
                break
            fi
        fi
    done
    
    if [[ "$HAPROXY_SINGLE_PORT_MODE" != "true" ]]; then
        log_info "Single port mode not detected"
    fi
}

# ============================================================================
# HAPROXY CONFIGURATION MANAGEMENT
# ============================================================================

# Add new node to HAProxy configuration
add_node_to_haproxy() {
    local node_name="$1"
    local node_ip="$2"
    local node_domain="$3"
    local node_port="${4:-443}"
    
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        log_info "HAProxy not available, skipping HAProxy configuration"
        return 0
    fi
    
    log_step "Adding node '$node_name' to HAProxy configuration..."
    
    # Validate inputs
    if [[ -z "$node_name" || -z "$node_ip" || -z "$node_domain" ]]; then
        log_error "Missing required parameters for HAProxy configuration"
        return 1
    fi
    
    # Check if node already exists
    if grep -q "server.*$node_name" "$HAPROXY_CONFIG_PATH" 2>/dev/null; then
        log_warning "Node '$node_name' already exists in HAProxy config"
        return 0
    fi
    
    # Create backup before modification
    cp "$HAPROXY_CONFIG_PATH" "${HAPROXY_CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add node to appropriate backend
    if [[ "$HAPROXY_SINGLE_PORT_MODE" == "true" ]]; then
        add_node_to_single_port_config "$node_name" "$node_ip" "$node_domain" "$HAPROXY_SINGLE_PORT"
    else
        add_node_to_multi_port_config "$node_name" "$node_ip" "$node_domain" "$node_port"
    fi
    
    # Validate configuration
    if validate_haproxy_config; then
        # Reload HAProxy
        if reload_haproxy_service; then
            log_success "Node '$node_name' added to HAProxy successfully"
            
            # Sync to all nodes
            sync_haproxy_to_all_nodes
            return 0
        else
            log_error "Failed to reload HAProxy service"
            restore_haproxy_backup
            return 1
        fi
    else
        log_error "HAProxy configuration validation failed"
        restore_haproxy_backup
        return 1
    fi
}

# Add node to single port configuration
add_node_to_single_port_config() {
    local node_name="$1"
    local node_ip="$2"
    local node_domain="$3"
    local port="$4"
    
    log_info "Adding node to single port configuration (port $port)..."
    
    # Find or create backend section
    if ! grep -q "backend marzban_nodes" "$HAPROXY_CONFIG_PATH"; then
        # Create new backend section
        cat >> "$HAPROXY_CONFIG_PATH" << EOF

# Marzban Nodes Backend
backend marzban_nodes
    mode http
    balance roundrobin
    option httpchk GET /
    server $node_name $node_ip:$port check
EOF
    else
        # Add to existing backend
        sed -i "/backend marzban_nodes/,/^backend\|^frontend\|^listen\|^$/{
            /^backend\|^frontend\|^listen\|^$/!{
                /server.*$node_name/d
                $a\    server $node_name $node_ip:$port check
            }
        }" "$HAPROXY_CONFIG_PATH"
    fi
    
    # Add ACL for domain if not exists
    if ! grep -q "acl.*$node_domain" "$HAPROXY_CONFIG_PATH"; then
        # Find frontend section and add ACL
        sed -i "/frontend.*$HAPROXY_SINGLE_PORT/,/^backend\|^frontend\|^listen\|^$/{
            /default_backend\|use_backend/i\    acl is_$node_name hdr(host) -i $node_domain
            /default_backend\|use_backend/i\    use_backend marzban_nodes if is_$node_name
        }" "$HAPROXY_CONFIG_PATH"
    fi
}

# Add node to multi-port configuration
add_node_to_multi_port_config() {
    local node_name="$1"
    local node_ip="$2"
    local node_domain="$3"
    local port="$4"
    
    log_info "Adding node to multi-port configuration..."
    
    # Create dedicated backend for this node
    cat >> "$HAPROXY_CONFIG_PATH" << EOF

# Backend for $node_name
backend backend_$node_name
    mode http
    server $node_name $node_ip:$port check ssl verify none

# Frontend for $node_domain
frontend frontend_$node_name
    bind *:$port ssl crt /path/to/cert.pem
    mode http
    default_backend backend_$node_name
EOF
}

# Remove node from HAProxy configuration
remove_node_from_haproxy() {
    local node_name="$1"
    
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        return 0
    fi
    
    log_step "Removing node '$node_name' from HAProxy configuration..."
    
    # Create backup
    cp "$HAPROXY_CONFIG_PATH" "${HAPROXY_CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove server entries
    sed -i "/server.*$node_name/d" "$HAPROXY_CONFIG_PATH"
    
    # Remove ACL entries
    sed -i "/acl.*is_$node_name/d" "$HAPROXY_CONFIG_PATH"
    sed -i "/use_backend.*is_$node_name/d" "$HAPROXY_CONFIG_PATH"
    
    # Remove dedicated backend/frontend if exists
    sed -i "/# Backend for $node_name/,/^$/d" "$HAPROXY_CONFIG_PATH"
    sed -i "/# Frontend for.*$node_name/,/^$/d" "$HAPROXY_CONFIG_PATH"
    
    # Validate and reload
    if validate_haproxy_config; then
        if reload_haproxy_service; then
            log_success "Node '$node_name' removed from HAProxy"
            sync_haproxy_to_all_nodes
        else
            restore_haproxy_backup
            return 1
        fi
    else
        restore_haproxy_backup
        return 1
    fi
}

# ============================================================================
# HAPROXY SYNCHRONIZATION
# ============================================================================

# Sync HAProxy configuration to all nodes
sync_haproxy_to_all_nodes() {
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        log_info "HAProxy not available, skipping sync"
        return 0
    fi
    
    log_step "Syncing HAProxy configuration to all nodes..."
    
    # Load nodes configuration
    load_nodes_config
    
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        log_info "No nodes configured for HAProxy sync"
        return 0
    fi
    
    local sync_success=true
    local synced_nodes=0
    
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        
        log_info "Syncing HAProxy config to node: $name ($ip)"
        
        if sync_haproxy_to_node "$ip" "$user" "$port" "$password"; then
            log_success "HAProxy config synced to $name"
            ((synced_nodes++))
        else
            log_error "Failed to sync HAProxy config to $name"
            sync_success=false
        fi
    done
    
    if [[ "$sync_success" == "true" ]]; then
        log_success "HAProxy configuration synced to all $synced_nodes nodes"
        
        # Update sync timestamp
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$CONFIG_DIR/.haproxy_last_sync"
        
        # Send notification
        if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
            send_telegram_notification "✅ HAProxy configuration synced to $synced_nodes nodes" "info"
        fi
    else
        log_warning "HAProxy sync completed with some failures"
        
        if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
            send_telegram_notification "⚠️ HAProxy sync completed with failures. Check logs for details." "warning"
        fi
    fi
    
    return 0
}

# Sync HAProxy configuration to a specific node
sync_haproxy_to_node() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    
    # Check if node has HAProxy
    local node_has_haproxy
    node_has_haproxy=$(sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
        "command -v haproxy >/dev/null 2>&1 && echo 'true' || echo 'false'" 2>/dev/null)
    
    if [[ "$node_has_haproxy" != "true" ]]; then
        log_info "Node $node_ip does not have HAProxy, skipping"
        return 0
    fi
    
    # Find HAProxy config path on node
    local node_haproxy_path
    node_haproxy_path=$(sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
        "if [[ -f '/etc/haproxy/haproxy.cfg' ]]; then echo '/etc/haproxy/haproxy.cfg'; elif [[ -f '/usr/local/etc/haproxy/haproxy.cfg' ]]; then echo '/usr/local/etc/haproxy/haproxy.cfg'; fi" 2>/dev/null)
    
    if [[ -z "$node_haproxy_path" ]]; then
        log_warning "HAProxy config path not found on node $node_ip"
        return 1
    fi
    
    # Create backup on node
    sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
        "cp '$node_haproxy_path' '${node_haproxy_path}.backup.$(date +%Y%m%d_%H%M%S)'" 2>/dev/null
    
    # Copy configuration file
    if sshpass -p "$node_password" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -P "$node_port" \
        "$HAPROXY_CONFIG_PATH" "$node_user@$node_ip:$node_haproxy_path" 2>/dev/null; then
        
        # Validate configuration on node
        local validation_result
        validation_result=$(sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
            "haproxy -c -f '$node_haproxy_path' >/dev/null 2>&1 && echo 'valid' || echo 'invalid'" 2>/dev/null)
        
        if [[ "$validation_result" == "valid" ]]; then
            # Reload HAProxy on node
            sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
                "systemctl reload haproxy 2>/dev/null || service haproxy reload 2>/dev/null || true"
            return 0
        else
            log_error "HAProxy config validation failed on node $node_ip"
            # Restore backup
            sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
                "cp '${node_haproxy_path}.backup.'* '$node_haproxy_path' 2>/dev/null || true"
            return 1
        fi
    else
        log_error "Failed to copy HAProxy config to node $node_ip"
        return 1
    fi
}

# ============================================================================
# HAPROXY UTILITIES
# ============================================================================

# Validate HAProxy configuration
validate_haproxy_config() {
    if [[ ! -f "$HAPROXY_CONFIG_PATH" ]]; then
        log_error "HAProxy config file not found: $HAPROXY_CONFIG_PATH"
        return 1
    fi
    
    log_debug "Validating HAProxy configuration..."
    
    if haproxy -c -f "$HAPROXY_CONFIG_PATH" >/dev/null 2>&1; then
        log_debug "HAProxy configuration is valid"
        return 0
    else
        log_error "HAProxy configuration validation failed"
        haproxy -c -f "$HAPROXY_CONFIG_PATH" 2>&1 | head -10
        return 1
    fi
}

# Reload HAProxy service
reload_haproxy_service() {
    log_debug "Reloading HAProxy service..."
    
    if systemctl reload haproxy 2>/dev/null; then
        log_debug "HAProxy reloaded successfully"
        return 0
    elif service haproxy reload 2>/dev/null; then
        log_debug "HAProxy reloaded successfully"
        return 0
    else
        log_error "Failed to reload HAProxy service"
        return 1
    fi
}

# Restore HAProxy backup
restore_haproxy_backup() {
    log_warning "Restoring HAProxy configuration from backup..."
    
    local latest_backup
    latest_backup=$(ls -t "${HAPROXY_CONFIG_PATH}.backup."* 2>/dev/null | head -1)
    
    if [[ -n "$latest_backup" ]]; then
        cp "$latest_backup" "$HAPROXY_CONFIG_PATH"
        reload_haproxy_service
        log_info "HAProxy configuration restored from backup"
    else
        log_error "No HAProxy backup found"
        return 1
    fi
}

# Check HAProxy sync status
check_haproxy_sync_status() {
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        return 0
    fi
    
    log_debug "Checking HAProxy sync status..."
    
    local current_hash
    current_hash=$(md5sum "$HAPROXY_CONFIG_PATH" | cut -d' ' -f1)
    
    if [[ "$current_hash" != "$HAPROXY_CONFIG_HASH" ]]; then
        log_warning "HAProxy configuration has changed, sync may be needed"
        HAPROXY_CONFIG_HASH="$current_hash"
        return 1
    fi
    
    return 0
}

# Show HAProxy status
show_haproxy_status() {
    echo -e "\n${CYAN}🔧 HAProxy Status:${NC}"
    
    if [[ "$MAIN_HAS_HAPROXY" == "true" ]]; then
        echo -e "   Status: ${GREEN}Installed${NC}"
        echo -e "   Config: $HAPROXY_CONFIG_PATH"
        echo -e "   Service: $(systemctl is-active haproxy 2>/dev/null || echo 'unknown')"
        echo -e "   Single Port Mode: $([ "$HAPROXY_SINGLE_PORT_MODE" == "true" ] && echo "${GREEN}Yes (Port $HAPROXY_SINGLE_PORT)${NC}" || echo "${YELLOW}No${NC}")"
        
        if [[ -f "$CONFIG_DIR/.haproxy_last_sync" ]]; then
            local last_sync
            last_sync=$(cat "$CONFIG_DIR/.haproxy_last_sync")
            echo -e "   Last Sync: $last_sync"
        else
            echo -e "   Last Sync: ${YELLOW}Never${NC}"
        fi
    else
        echo -e "   Status: ${RED}Not installed${NC}"
    fi
}

# Export functions
export -f init_haproxy_manager detect_haproxy_configuration find_haproxy_config_path
export -f load_haproxy_configuration analyze_haproxy_marzban_config detect_single_port_usage
export -f add_node_to_haproxy add_node_to_single_port_config add_node_to_multi_port_config
export -f remove_node_from_haproxy sync_haproxy_to_all_nodes sync_haproxy_to_node
export -f validate_haproxy_config reload_haproxy_service restore_haproxy_backup
export -f check_haproxy_sync_status show_haproxy_status