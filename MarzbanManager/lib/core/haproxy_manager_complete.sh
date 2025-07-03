#!/bin/bash
# HAProxy Management System for Marzban Central Manager - COMPLETE VERSION
# Professional Edition v4.0 - Optimized for Marzban Single Port Configuration

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
        detect_haproxy_structure
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
    HAPROXY_MAIN_PORT="443"
    HAPROXY_HAS_MAIN_FRONTEND=false
    
    # Check if HAProxy is installed
    if ! command_exists haproxy; then
        log_info "HAProxy not installed on main server"
        return 0
    fi
    
    MAIN_HAS_HAPROXY=true
    log_info "HAProxy detected on main server"
    
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
    export HAPROXY_MAIN_PORT HAPROXY_HAS_MAIN_FRONTEND
    
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
    marzban_backends=$(grep -E "backend.*|server.*" "$HAPROXY_CONFIG_PATH" | grep -v "^#" || true)
    
    if [[ -n "$marzban_backends" ]]; then
        log_info "Found existing backends in HAProxy config"
        log_debug "Existing backends: $(echo "$marzban_backends" | wc -l) entries"
    else
        log_info "No existing backends found"
    fi
    
    # Store current configuration hash for sync checking
    HAPROXY_CONFIG_HASH=$(md5sum "$HAPROXY_CONFIG_PATH" | cut -d' ' -f1)
    export HAPROXY_CONFIG_HASH
}

# Detect HAProxy configuration structure for Marzban
detect_haproxy_structure() {
    log_debug "Analyzing HAProxy configuration structure..."
    
    # Check for main HTTPS frontend (port 443)
    if grep -q "bind.*:443" "$HAPROXY_CONFIG_PATH" 2>/dev/null; then
        HAPROXY_MAIN_PORT="443"
        log_info "Main HAProxy port detected: 443"
    else
        # Check for other common ports
        local detected_port
        detected_port=$(grep -o "bind.*:[0-9]*" "$HAPROXY_CONFIG_PATH" 2>/dev/null | head -1 | grep -o '[0-9]*$')
        if [[ -n "$detected_port" ]]; then
            HAPROXY_MAIN_PORT="$detected_port"
            log_info "Main HAProxy port detected: $detected_port"
        else
            HAPROXY_MAIN_PORT="443"
            log_info "No specific port detected, defaulting to 443"
        fi
    fi
    
    # Check for existing frontend sections
    if grep -q "frontend.*https_front\|listen.*front" "$HAPROXY_CONFIG_PATH" 2>/dev/null; then
        HAPROXY_HAS_MAIN_FRONTEND=true
        log_info "Main frontend section found"
    else
        HAPROXY_HAS_MAIN_FRONTEND=false
        log_info "No main frontend section found"
    fi
    
    export HAPROXY_MAIN_PORT HAPROXY_HAS_MAIN_FRONTEND
}

# ============================================================================
# HAPROXY INSTALLATION ON NODES
# ============================================================================

# Install HAProxy on a node if needed
install_haproxy_on_node() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local node_name="$5"
    
    log_step "Checking HAProxy installation on node: $node_name ($node_ip)"
    
    # Check if HAProxy is already installed
    local node_has_haproxy
    node_has_haproxy=$(sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
        "command -v haproxy >/dev/null 2>&1 && echo 'true' || echo 'false'" 2>/dev/null)
    
    if [[ "$node_has_haproxy" == "true" ]]; then
        log_info "HAProxy already installed on node $node_name"
        return 0
    fi
    
    log_info "Installing HAProxy on node: $node_name"
    
    # Detect OS and install HAProxy
    local install_command
    local os_type
    os_type=$(sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
        "if command -v apt-get >/dev/null 2>&1; then echo 'debian'; elif command -v yum >/dev/null 2>&1; then echo 'rhel'; elif command -v dnf >/dev/null 2>&1; then echo 'fedora'; else echo 'unknown'; fi" 2>/dev/null)
    
    case "$os_type" in
        "debian")
            install_command="apt-get update && apt-get install -y haproxy"
            ;;
        "rhel")
            install_command="yum install -y haproxy"
            ;;
        "fedora")
            install_command="dnf install -y haproxy"
            ;;
        *)
            log_error "Unsupported OS type on node $node_name: $os_type"
            return 1
            ;;
    esac
    
    # Install HAProxy
    if sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -p "$node_port" "$node_user@$node_ip" \
        "$install_command" >/dev/null 2>&1; then
        
        # Verify installation
        node_has_haproxy=$(sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
            "command -v haproxy >/dev/null 2>&1 && echo 'true' || echo 'false'" 2>/dev/null)
        
        if [[ "$node_has_haproxy" == "true" ]]; then
            log_success "HAProxy installed successfully on node $node_name"
            
            # Enable and start HAProxy service
            sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
                "systemctl enable haproxy && systemctl start haproxy" >/dev/null 2>&1 || true
            
            return 0
        else
            log_error "HAProxy installation verification failed on node $node_name"
            return 1
        fi
    else
        log_error "Failed to install HAProxy on node $node_name"
        return 1
    fi
}

# Install HAProxy on all nodes that don't have it
install_haproxy_on_all_nodes() {
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        log_info "HAProxy not available on main server, skipping node installations"
        return 0
    fi
    
    log_step "Installing HAProxy on all nodes..."
    
    # Load nodes configuration
    load_nodes_config
    
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        log_info "No nodes configured for HAProxy installation"
        return 0
    fi
    
    local install_success=true
    local installed_nodes=0
    
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        
        if install_haproxy_on_node "$ip" "$user" "$port" "$password" "$name"; then
            ((installed_nodes++))
        else
            install_success=false
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        log_success "HAProxy installation completed on all nodes"
        
        # Send notification
        if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
            send_telegram_notification "✅ HAProxy installed on $installed_nodes nodes" "info"
        fi
    else
        log_warning "HAProxy installation completed with some failures"
        
        if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
            send_telegram_notification "⚠️ HAProxy installation completed with failures on some nodes" "warning"
        fi
    fi
    
    return 0
}

# ============================================================================
# MARZBAN-SPECIFIC HAPROXY FUNCTIONS
# ============================================================================

# Add node to HAProxy configuration based on Marzban structure
add_node_to_haproxy_marzban() {
    local node_name="$1"
    local node_ip="$2"
    local node_domain="$3"
    local backend_port="${4:-10011}"  # Default Marzban node port
    
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        log_info "HAProxy not available, skipping HAProxy configuration"
        return 0
    fi
    
    log_step "Adding node '$node_name' to HAProxy configuration (Marzban structure)..."
    
    # Validate inputs
    if [[ -z "$node_name" || -z "$node_ip" || -z "$node_domain" ]]; then
        log_error "Missing required parameters for HAProxy configuration"
        return 1
    fi
    
    # Check if node already exists in any backend
    if grep -q "server.*$node_name" "$HAPROXY_CONFIG_PATH" 2>/dev/null; then
        log_warning "Node '$node_name' already exists in HAProxy config"
        return 0
    fi
    
    # Create backup before modification
    cp "$HAPROXY_CONFIG_PATH" "${HAPROXY_CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add SNI routing rule to frontend
    add_sni_routing_rule "$node_name" "$node_domain"
    
    # Add backend for the new node
    add_node_backend "$node_name" "$node_ip" "$backend_port"
    
    # Validate configuration
    if validate_haproxy_config; then
        # Reload HAProxy
        if reload_haproxy_service; then
            log_success "Node '$node_name' added to HAProxy successfully"
            
            # Update configuration hash
            HAPROXY_CONFIG_HASH=$(md5sum "$HAPROXY_CONFIG_PATH" | cut -d' ' -f1)
            
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

# Add SNI routing rule to frontend section
add_sni_routing_rule() {
    local node_name="$1"
    local node_domain="$2"
    
    log_debug "Adding SNI routing rule for $node_domain -> $node_name"
    
    # Find the main frontend section (https_front or front)
    local frontend_section=""
    if grep -q "frontend.*https_front" "$HAPROXY_CONFIG_PATH"; then
        frontend_section="frontend.*https_front"
    elif grep -q "listen.*front" "$HAPROXY_CONFIG_PATH"; then
        frontend_section="listen.*front"
    else
        log_error "No main frontend section found in HAProxy config"
        return 1
    fi
    
    # Check if domain already has a routing rule
    if grep -q "req.ssl_sni.*$node_domain" "$HAPROXY_CONFIG_PATH"; then
        log_warning "Domain $node_domain already has a routing rule"
        return 0
    fi
    
    # Add the routing rule before default_backend line
    # Format: use_backend node_name_backend if { req.ssl_sni -m end node_domain }
    local routing_rule="    use_backend ${node_name}_backend if { req.ssl_sni -m end $node_domain }"
    
    # Insert the rule before default_backend or at the end of frontend section
    if grep -q "default_backend" "$HAPROXY_CONFIG_PATH"; then
        # Insert before default_backend
        sed -i "/$frontend_section/,/^backend\|^frontend\|^listen\|^$/{
            /default_backend/i\\$routing_rule
        }" "$HAPROXY_CONFIG_PATH"
    else
        # Insert at the end of frontend section, but before the next section
        # Find the line number of the frontend section
        local frontend_line
        frontend_line=$(grep -n "$frontend_section" "$HAPROXY_CONFIG_PATH" | head -1 | cut -d: -f1)
        
        if [[ -n "$frontend_line" ]]; then
            # Find the end of this section (next backend/frontend/listen or empty line)
            local section_end
            section_end=$(tail -n +$((frontend_line + 1)) "$HAPROXY_CONFIG_PATH" | grep -n "^backend\|^frontend\|^listen\|^$" | head -1 | cut -d: -f1)
            
            if [[ -n "$section_end" ]]; then
                local insert_line=$((frontend_line + section_end - 1))
                sed -i "${insert_line}i\\$routing_rule" "$HAPROXY_CONFIG_PATH"
            else
                # If no end found, append to the end of the file
                echo "$routing_rule" >> "$HAPROXY_CONFIG_PATH"
            fi
        fi
    fi
    
    log_debug "SNI routing rule added: $routing_rule"
}

# Add backend section for the new node
add_node_backend() {
    local node_name="$1"
    local node_ip="$2"
    local backend_port="$3"
    
    log_debug "Adding backend for $node_name -> $node_ip:$backend_port"
    
    # Create backend section
    local backend_config=""
    backend_config+="\n# Backend for $node_name\n"
    backend_config+="backend ${node_name}_backend\n"
    backend_config+="    mode tcp\n"
    backend_config+="    balance roundrobin\n"
    backend_config+="    server $node_name $node_ip:$backend_port\n"
    
    # Append to the end of the file
    echo -e "$backend_config" >> "$HAPROXY_CONFIG_PATH"
    
    log_debug "Backend section added for $node_name"
}

# Remove node from HAProxy configuration (Marzban structure)
remove_node_from_haproxy_marzban() {
    local node_name="$1"
    
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        return 0
    fi
    
    log_step "Removing node '$node_name' from HAProxy configuration..."
    
    # Create backup
    cp "$HAPROXY_CONFIG_PATH" "${HAPROXY_CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove SNI routing rule
    sed -i "/use_backend.*${node_name}_backend/d" "$HAPROXY_CONFIG_PATH"
    
    # Remove backend section - more precise removal
    # First, find the line with the backend declaration
    local backend_start
    backend_start=$(grep -n "^backend ${node_name}_backend$" "$HAPROXY_CONFIG_PATH" | cut -d: -f1)
    
    if [[ -n "$backend_start" ]]; then
        # Find the end of this backend (next backend/frontend/listen or end of file)
        local backend_end
        backend_end=$(tail -n +$((backend_start + 1)) "$HAPROXY_CONFIG_PATH" | grep -n "^backend\|^frontend\|^listen" | head -1 | cut -d: -f1)
        
        if [[ -n "$backend_end" ]]; then
            # Calculate actual line number
            backend_end=$((backend_start + backend_end - 1))
            # Delete from backend_start to backend_end-1
            sed -i "${backend_start},$((backend_end - 1))d" "$HAPROXY_CONFIG_PATH"
        else
            # Delete from backend_start to end of file
            sed -i "${backend_start},\$d" "$HAPROXY_CONFIG_PATH"
        fi
    fi
    
    # Also remove the comment line if it exists
    sed -i "/# Backend for $node_name/d" "$HAPROXY_CONFIG_PATH"
    
    # Remove any remaining server entries with this node name
    sed -i "/server.*$node_name/d" "$HAPROXY_CONFIG_PATH"
    
    # Clean up any empty lines that might have been left
    sed -i '/^$/N;/^\n$/d' "$HAPROXY_CONFIG_PATH"
    
    # Validate and reload
    if validate_haproxy_config; then
        if reload_haproxy_service; then
            log_success "Node '$node_name' removed from HAProxy"
            
            # Update configuration hash
            HAPROXY_CONFIG_HASH=$(md5sum "$HAPROXY_CONFIG_PATH" | cut -d' ' -f1)
            
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

# Update the main add_node_to_haproxy function to use Marzban structure
add_node_to_haproxy() {
    # Delegate to the Marzban-specific function
    add_node_to_haproxy_marzban "$@"
}

# Update the main remove_node_from_haproxy function to use Marzban structure
remove_node_from_haproxy() {
    # Delegate to the Marzban-specific function
    remove_node_from_haproxy_marzban "$@"
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
    local failed_nodes=()
    
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        
        log_info "Syncing HAProxy config to node: $name ($ip)"
        
        if sync_haproxy_to_node "$ip" "$user" "$port" "$password" "$name"; then
            log_success "HAProxy config synced to $name"
            ((synced_nodes++))
        else
            log_error "Failed to sync HAProxy config to $name"
            failed_nodes+=("$name")
            sync_success=false
        fi
    done
    
    if [[ "$sync_success" == "true" ]]; then
        log_success "HAProxy configuration synced to all $synced_nodes nodes"
        
        # Update sync timestamp
        mkdir -p "$(dirname "$MANAGER_CONFIG_FILE")"
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "${MANAGER_DIR}/.haproxy_last_sync"
        
        # Send notification
        if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
            send_telegram_notification "✅ HAProxy configuration synced to $synced_nodes nodes" "info"
        fi
    else
        log_warning "HAProxy sync completed with failures on: ${failed_nodes[*]}"
        
        if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
            send_telegram_notification "⚠️ HAProxy sync failed on nodes: ${failed_nodes[*]}" "warning"
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
    local node_name="$5"
    
    # Check if node has HAProxy
    local node_has_haproxy
    node_has_haproxy=$(sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$node_port" "$node_user@$node_ip" \
        "command -v haproxy >/dev/null 2>&1 && echo 'true' || echo 'false'" 2>/dev/null)
    
    if [[ "$node_has_haproxy" != "true" ]]; then
        log_info "Node $node_ip does not have HAProxy, installing..."
        if ! install_haproxy_on_node "$node_ip" "$node_user" "$node_port" "$node_password" "$node_name"; then
            log_error "Failed to install HAProxy on node $node_name"
            return 1
        fi
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
# AUTOMATIC HAPROXY INTEGRATION WITH NODE DEPLOYMENT
# ============================================================================

# Automatically handle HAProxy when adding a new node
auto_haproxy_integration_on_node_add() {
    local node_name="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_domain="$5"
    local node_password="$6"
    
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        log_info "HAProxy not available on main server, skipping HAProxy integration"
        return 0
    fi
    
    log_step "Performing automatic HAProxy integration for new node: $node_name"
    
    # Step 1: Install HAProxy on the new node if needed
    if ! install_haproxy_on_node "$node_ip" "$node_user" "$node_port" "$node_password" "$node_name"; then
        log_warning "Failed to install HAProxy on new node, continuing without HAProxy integration"
        return 1
    fi
    
    # Step 2: Add node to main server HAProxy configuration
    if ! add_node_to_haproxy "$node_name" "$node_ip" "$node_domain"; then
        log_warning "Failed to add node to main server HAProxy configuration"
        return 1
    fi
    
    # Step 3: Sync updated configuration to all nodes (including the new one)
    if ! sync_haproxy_to_all_nodes; then
        log_warning "Failed to sync HAProxy configuration to all nodes"
        return 1
    fi
    
    log_success "Automatic HAProxy integration completed for node: $node_name"
    
    # Send notification
    if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
        send_telegram_notification "✅ Node '$node_name' added and HAProxy configuration synced to all nodes" "info"
    fi
    
    return 0
}

# Automatically handle HAProxy when removing a node
auto_haproxy_integration_on_node_remove() {
    local node_name="$1"
    
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        return 0
    fi
    
    log_step "Performing automatic HAProxy cleanup for removed node: $node_name"
    
    # Step 1: Remove node from main server HAProxy configuration
    if ! remove_node_from_haproxy "$node_name"; then
        log_warning "Failed to remove node from main server HAProxy configuration"
        return 1
    fi
    
    # Step 2: Sync updated configuration to remaining nodes
    if ! sync_haproxy_to_all_nodes; then
        log_warning "Failed to sync HAProxy configuration after node removal"
        return 1
    fi
    
    log_success "Automatic HAProxy cleanup completed for node: $node_name"
    
    # Send notification
    if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
        send_telegram_notification "✅ Node '$node_name' removed and HAProxy configuration updated on all nodes" "info"
    fi
    
    return 0
}

# ============================================================================
# HAPROXY STATUS AND MONITORING
# ============================================================================

# Check HAProxy sync status across all nodes
check_haproxy_sync_status_all_nodes() {
    if [[ "$MAIN_HAS_HAPROXY" != "true" ]]; then
        return 0
    fi
    
    log_step "Checking HAProxy sync status across all nodes..."
    
    local main_config_hash
    main_config_hash=$(md5sum "$HAPROXY_CONFIG_PATH" | cut -d' ' -f1)
    
    load_nodes_config
    
    local out_of_sync_nodes=()
    local sync_check_success=true
    
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        
        # Check if node has HAProxy
        local node_has_haproxy
        node_has_haproxy=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" "$user@$ip" \
            "command -v haproxy >/dev/null 2>&1 && echo 'true' || echo 'false'" 2>/dev/null)
        
        if [[ "$node_has_haproxy" == "true" ]]; then
            # Get config hash from node
            local node_config_hash
            node_config_hash=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" "$user@$ip" \
                "if [[ -f '/etc/haproxy/haproxy.cfg' ]]; then md5sum '/etc/haproxy/haproxy.cfg' | cut -d' ' -f1; fi" 2>/dev/null)
            
            if [[ "$node_config_hash" != "$main_config_hash" ]]; then
                out_of_sync_nodes+=("$name")
                sync_check_success=false
            fi
        fi
    done
    
    if [[ "$sync_check_success" == "true" ]]; then
        log_success "All nodes are in sync with main HAProxy configuration"
    else
        log_warning "Nodes out of sync: ${out_of_sync_nodes[*]}"
        
        # Auto-resync if enabled
        if [[ "${AUTO_HAPROXY_RESYNC:-true}" == "true" ]]; then
            log_info "Auto-resyncing out-of-sync nodes..."
            sync_haproxy_to_all_nodes
        fi
    fi
    
    return $([[ "$sync_check_success" == "true" ]] && echo 0 || echo 1)
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

# Show HAProxy status
show_haproxy_status() {
    echo -e "\n${CYAN}🔧 HAProxy Status:${NC}"
    
    if [[ "$MAIN_HAS_HAPROXY" == "true" ]]; then
        echo -e "   Status: ${GREEN}Installed${NC}"
        echo -e "   Config: $HAPROXY_CONFIG_PATH"
        echo -e "   Service: $(systemctl is-active haproxy 2>/dev/null || echo 'unknown')"
        echo -e "   Main Port: ${HAPROXY_MAIN_PORT}"
        
        if [[ -f "${MANAGER_DIR}/.haproxy_last_sync" ]]; then
            local last_sync
            last_sync=$(cat "${MANAGER_DIR}/.haproxy_last_sync")
            echo -e "   Last Sync: $last_sync"
        else
            echo -e "   Last Sync: ${YELLOW}Never${NC}"
        fi
        
        # Show sync status
        if check_haproxy_sync_status_all_nodes >/dev/null 2>&1; then
            echo -e "   Sync Status: ${GREEN}All nodes in sync${NC}"
        else
            echo -e "   Sync Status: ${RED}Some nodes out of sync${NC}"
        fi
    else
        echo -e "   Status: ${RED}Not installed${NC}"
    fi
}

# Export functions
export -f init_haproxy_manager detect_haproxy_configuration find_haproxy_config_path
export -f load_haproxy_configuration analyze_haproxy_marzban_config detect_haproxy_structure
export -f install_haproxy_on_node install_haproxy_on_all_nodes
export -f add_node_to_haproxy add_node_to_haproxy_marzban add_sni_routing_rule add_node_backend
export -f remove_node_from_haproxy remove_node_from_haproxy_marzban sync_haproxy_to_all_nodes sync_haproxy_to_node
export -f auto_haproxy_integration_on_node_add auto_haproxy_integration_on_node_remove
export -f check_haproxy_sync_status_all_nodes validate_haproxy_config reload_haproxy_service
export -f restore_haproxy_backup show_haproxy_status