#!/bin/bash
# Marzban Central Manager - SSH Operations Module
# Professional Edition v3.0
# Author: behnamrjd

# ============================================================================
# SSH CONFIGURATION
# ============================================================================

# SSH connection settings
readonly SSH_CONNECT_TIMEOUT=30
readonly SSH_SERVER_ALIVE_INTERVAL=5
readonly SSH_SERVER_ALIVE_COUNT_MAX=3
readonly SSH_MAX_RETRIES=3
readonly SSH_RETRY_DELAY=5

# SSH options
readonly SSH_OPTIONS=(
    "-o StrictHostKeyChecking=no"
    "-o ConnectTimeout=$SSH_CONNECT_TIMEOUT"
    "-o ServerAliveInterval=$SSH_SERVER_ALIVE_INTERVAL"
    "-o ServerAliveCountMax=$SSH_SERVER_ALIVE_COUNT_MAX"
    "-o UserKnownHostsFile=/dev/null"
    "-o LogLevel=ERROR"
)

# SCP options
readonly SCP_OPTIONS=(
    "-o StrictHostKeyChecking=no"
    "-o ConnectTimeout=$SSH_CONNECT_TIMEOUT"
    "-o UserKnownHostsFile=/dev/null"
    "-o LogLevel=ERROR"
)

# ============================================================================
# CORE SSH FUNCTIONS
# ============================================================================

# Test SSH connection
test_ssh_connection() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local timeout="${5:-10}"
    
    if [[ -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_password" ]]; then
        log_error "All SSH parameters are required"
        return 1
    fi
    
    log_debug "Testing SSH connection to $node_user@$node_ip:$node_port"
    
    # Use a simple echo command to test connectivity
    local test_command="echo 'SSH_TEST_OK'"
    local result
    
    result=$(SSHPASS="$node_password" sshpass -e ssh \
        "${SSH_OPTIONS[@]}" \
        -p "$node_port" \
        "$node_user@$node_ip" \
        "$test_command" 2>/dev/null)
    
    if [[ "$result" == "SSH_TEST_OK" ]]; then
        log_debug "SSH connection test successful"
        return 0
    else
        log_debug "SSH connection test failed"
        return 1
    fi
}

# Execute command on remote server with retry mechanism
ssh_remote() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local command="$5"
    local description="${6:-Remote Command}"
    local max_retries="${7:-$SSH_MAX_RETRIES}"
    
    if [[ -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_password" || -z "$command" ]]; then
        log_error "All SSH parameters are required"
        return 1
    fi
    
    local retry=0
    
    # Rate limiting
    sleep "$API_RATE_LIMIT_DELAY"
    
    while [[ $retry -lt $max_retries ]]; do
        log_debug "Executing ($description) on $node_ip (attempt $((retry+1))/$max_retries)"
        
        # Execute command with password authentication
        if SSHPASS="$node_password" sshpass -e ssh \
           "${SSH_OPTIONS[@]}" \
           -p "$node_port" \
           "$node_user@$node_ip" \
           "$command" 2>&1; then
            log_debug "Remote command ($description) executed successfully"
            return 0
        fi
        
        retry=$((retry+1))
        if [[ $retry -lt $max_retries ]]; then
            log_warning "SSH command failed, retrying in $SSH_RETRY_DELAY seconds... (attempt $retry/$max_retries)"
            sleep "$SSH_RETRY_DELAY"
        fi
    done
    
    log_error "Remote command ($description) failed after $max_retries attempts"
    return 1
}

# Execute command on remote server and capture output
ssh_remote_capture() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local command="$5"
    local description="${6:-Remote Command}"
    
    if [[ -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_password" || -z "$command" ]]; then
        log_error "All SSH parameters are required"
        return 1
    fi
    
    log_debug "Capturing output from ($description) on $node_ip"
    
    # Execute command and capture output
    local output
    output=$(SSHPASS="$node_password" sshpass -e ssh \
        "${SSH_OPTIONS[@]}" \
        -p "$node_port" \
        "$node_user@$node_ip" \
        "$command" 2>/dev/null)
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "$output"
        return 0
    else
        log_error "Failed to capture output from ($description)"
        return 1
    fi
}

# Execute command on remote server without output
ssh_remote_silent() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local command="$5"
    local description="${6:-Remote Command}"
    
    if [[ -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_password" || -z "$command" ]]; then
        log_error "All SSH parameters are required"
        return 1
    fi
    
    log_debug "Executing silent ($description) on $node_ip"
    
    # Execute command silently
    SSHPASS="$node_password" sshpass -e ssh \
        "${SSH_OPTIONS[@]}" \
        -p "$node_port" \
        "$node_user@$node_ip" \
        "$command" >/dev/null 2>&1
    
    return $?
}

# ============================================================================
# FILE TRANSFER FUNCTIONS
# ============================================================================

# Copy file to remote server with retry mechanism
scp_to_remote() {
    local local_path="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_password="$5"
    local remote_path="$6"
    local description="${7:-File Transfer}"
    local max_retries="${8:-$SSH_MAX_RETRIES}"
    
    if [[ -z "$local_path" || -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_password" || -z "$remote_path" ]]; then
        log_error "All SCP parameters are required"
        return 1
    fi
    
    if [[ ! -f "$local_path" ]]; then
        log_error "Local file does not exist: $local_path"
        return 1
    fi
    
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        log_debug "Transferring ($description) to $node_ip (attempt $((retry+1))/$max_retries)"
        
        if SSHPASS="$node_password" sshpass -e scp \
           "${SCP_OPTIONS[@]}" \
           -P "$node_port" \
           "$local_path" \
           "$node_user@$node_ip:$remote_path" 2>&1; then
            log_debug "File transfer ($description) completed successfully"
            return 0
        fi
        
        retry=$((retry+1))
        if [[ $retry -lt $max_retries ]]; then
            log_warning "SCP transfer failed, retrying in $SSH_RETRY_DELAY seconds... (attempt $retry/$max_retries)"
            sleep "$SSH_RETRY_DELAY"
        fi
    done
    
    log_error "File transfer ($description) failed after $max_retries attempts"
    return 1
}

# Copy file from remote server with retry mechanism
scp_from_remote() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local remote_path="$5"
    local local_path="$6"
    local description="${7:-File Download}"
    local max_retries="${8:-$SSH_MAX_RETRIES}"
    
    if [[ -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_password" || -z "$remote_path" || -z "$local_path" ]]; then
        log_error "All SCP parameters are required"
        return 1
    fi
    
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        log_debug "Downloading ($description) from $node_ip (attempt $((retry+1))/$max_retries)"
        
        if SSHPASS="$node_password" sshpass -e scp \
           "${SCP_OPTIONS[@]}" \
           -P "$node_port" \
           "$node_user@$node_ip:$remote_path" \
           "$local_path" 2>&1; then
            log_debug "File download ($description) completed successfully"
            return 0
        fi
        
        retry=$((retry+1))
        if [[ $retry -lt $max_retries ]]; then
            log_warning "SCP download failed, retrying in $SSH_RETRY_DELAY seconds... (attempt $retry/$max_retries)"
            sleep "$SSH_RETRY_DELAY"
        fi
    done
    
    log_error "File download ($description) failed after $max_retries attempts"
    return 1
}

# Copy directory to remote server
scp_dir_to_remote() {
    local local_dir="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_password="$5"
    local remote_dir="$6"
    local description="${7:-Directory Transfer}"
    
    if [[ -z "$local_dir" || -z "$node_ip" || -z "$node_user" || -z "$node_port" || -z "$node_password" || -z "$remote_dir" ]]; then
        log_error "All SCP parameters are required"
        return 1
    fi
    
    if [[ ! -d "$local_dir" ]]; then
        log_error "Local directory does not exist: $local_dir"
        return 1
    fi
    
    log_debug "Transferring directory ($description) to $node_ip"
    
    # Create remote directory first
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "mkdir -p '$remote_dir'" "Create Remote Directory"
    
    # Transfer directory recursively
    if SSHPASS="$node_password" sshpass -e scp \
       "${SCP_OPTIONS[@]}" \
       -r -P "$node_port" \
       "$local_dir"/* \
       "$node_user@$node_ip:$remote_dir/" 2>&1; then
        log_debug "Directory transfer ($description) completed successfully"
        return 0
    else
        log_error "Directory transfer ($description) failed"
        return 1
    fi
}

# ============================================================================
# RSYNC OPERATIONS
# ============================================================================

# Sync files using rsync over SSH
rsync_to_remote() {
    local local_path="$1"
    local node_ip="$2"
    local node_user="$3"
    local node_port="$4"
    local node_password="$5"
    local remote_path="$6"
    local description="${7:-Rsync Transfer}"
    local options="${8:--avz --delete}"
    
    if ! command_exists rsync; then
        log_warning "rsync not available, falling back to scp"
        if [[ -d "$local_path" ]]; then
            return scp_dir_to_remote "$local_path" "$node_ip" "$node_user" "$node_port" "$node_password" "$remote_path" "$description"
        else
            return scp_to_remote "$local_path" "$node_ip" "$node_user" "$node_port" "$node_password" "$remote_path" "$description"
        fi
    fi
    
    log_debug "Syncing ($description) to $node_ip using rsync"
    
    # Create SSH command for rsync
    local ssh_cmd="sshpass -p '$node_password' ssh ${SSH_OPTIONS[*]} -p $node_port"
    
    if rsync $options \
       -e "$ssh_cmd" \
       "$local_path" \
       "$node_user@$node_ip:$remote_path" 2>&1; then
        log_debug "Rsync transfer ($description) completed successfully"
        return 0
    else
        log_error "Rsync transfer ($description) failed"
        return 1
    fi
}

# ============================================================================
# BATCH OPERATIONS
# ============================================================================

# Execute command on multiple nodes
ssh_batch_execute() {
    local command="$1"
    local description="${2:-Batch Command}"
    local nodes=("${@:3}")
    
    if [[ -z "$command" ]]; then
        log_error "Command is required for batch execution"
        return 1
    fi
    
    if [[ ${#nodes[@]} -eq 0 ]]; then
        # Use all configured nodes if none specified
        load_nodes_config
        nodes=("${NODES_ARRAY[@]}")
    fi
    
    if [[ ${#nodes[@]} -eq 0 ]]; then
        log_warning "No nodes available for batch execution"
        return 0
    fi
    
    log_info "Executing ($description) on ${#nodes[@]} nodes..."
    
    local success_count=0
    local failure_count=0
    local failed_nodes=()
    
    for node_entry in "${nodes[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log_info "Executing on node: $name ($ip)"
        
        if ssh_remote "$ip" "$user" "$port" "$password" "$command" "$description"; then
            ((success_count++))
            log_success "Command executed successfully on node: $name"
        else
            ((failure_count++))
            failed_nodes+=("$name")
            log_error "Command failed on node: $name"
        fi
    done
    
    log_info "Batch execution completed: $success_count successful, $failure_count failed"
    
    if [[ $failure_count -gt 0 ]]; then
        log_warning "Failed nodes: ${failed_nodes[*]}"
        return 1
    fi
    
    return 0
}

# Transfer file to multiple nodes
scp_batch_transfer() {
    local local_path="$1"
    local remote_path="$2"
    local description="${3:-Batch Transfer}"
    local nodes=("${@:4}")
    
    if [[ -z "$local_path" || -z "$remote_path" ]]; then
        log_error "Local and remote paths are required for batch transfer"
        return 1
    fi
    
    if [[ ! -f "$local_path" ]]; then
        log_error "Local file does not exist: $local_path"
        return 1
    fi
    
    if [[ ${#nodes[@]} -eq 0 ]]; then
        # Use all configured nodes if none specified
        load_nodes_config
        nodes=("${NODES_ARRAY[@]}")
    fi
    
    if [[ ${#nodes[@]} -eq 0 ]]; then
        log_warning "No nodes available for batch transfer"
        return 0
    fi
    
    log_info "Transferring ($description) to ${#nodes[@]} nodes..."
    
    local success_count=0
    local failure_count=0
    local failed_nodes=()
    
    for node_entry in "${nodes[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log_info "Transferring to node: $name ($ip)"
        
        if scp_to_remote "$local_path" "$ip" "$user" "$port" "$password" "$remote_path" "$description"; then
            ((success_count++))
            log_success "File transferred successfully to node: $name"
        else
            ((failure_count++))
            failed_nodes+=("$name")
            log_error "File transfer failed to node: $name"
        fi
    done
    
    log_info "Batch transfer completed: $success_count successful, $failure_count failed"
    
    if [[ $failure_count -gt 0 ]]; then
        log_warning "Failed nodes: ${failed_nodes[*]}"
        return 1
    fi
    
    return 0
}

# ============================================================================
# SSH KEY MANAGEMENT
# ============================================================================

# Generate SSH key pair
generate_ssh_key() {
    local key_name="${1:-marzban_manager}"
    local key_type="${2:-rsa}"
    local key_bits="${3:-4096}"
    local key_path="$HOME/.ssh/$key_name"
    
    log_info "Generating SSH key pair: $key_name"
    
    if [[ -f "$key_path" ]]; then
        log_warning "SSH key already exists: $key_path"
        log_prompt "Overwrite existing key? (y/n):"
        read -r overwrite
        
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log_info "SSH key generation cancelled"
            return 0
        fi
    fi
    
    # Generate key pair
    if ssh-keygen -t "$key_type" -b "$key_bits" -f "$key_path" -N "" -C "marzban-manager@$(hostname)" >/dev/null 2>&1; then
        log_success "SSH key pair generated: $key_path"
        echo "$key_path"
        return 0
    else
        log_error "Failed to generate SSH key pair"
        return 1
    fi
}

# Deploy SSH public key to node
deploy_ssh_key() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local public_key_path="${5:-$HOME/.ssh/marzban_manager.pub}"
    
    if [[ ! -f "$public_key_path" ]]; then
        log_error "Public key file not found: $public_key_path"
        return 1
    fi
    
    log_info "Deploying SSH public key to $node_ip"
    
    local public_key
    public_key=$(cat "$public_key_path")
    
    # Create .ssh directory and authorized_keys file
    local setup_command="mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$public_key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "$setup_command" "SSH Key Deployment"; then
        log_success "SSH public key deployed successfully"
        return 0
    else
        log_error "Failed to deploy SSH public key"
        return 1
    fi
}

# Test SSH key authentication
test_ssh_key_auth() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local private_key_path="${4:-$HOME/.ssh/marzban_manager}"
    
    if [[ ! -f "$private_key_path" ]]; then
        log_error "Private key file not found: $private_key_path"
        return 1
    fi
    
    log_debug "Testing SSH key authentication to $node_ip"
    
    # Test key-based authentication
    if ssh -i "$private_key_path" \
       "${SSH_OPTIONS[@]}" \
       -p "$node_port" \
       "$node_user@$node_ip" \
       "echo 'SSH_KEY_AUTH_OK'" 2>/dev/null | grep -q "SSH_KEY_AUTH_OK"; then
        log_debug "SSH key authentication successful"
        return 0
    else
        log_debug "SSH key authentication failed"
        return 1
    fi
}

# ============================================================================
# SYSTEM INFORMATION GATHERING
# ============================================================================

# Get system information from remote node
get_remote_system_info() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    
    log_debug "Gathering system information from $node_ip"
    
    local info_command="echo 'OS:' \$(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"'); echo 'Kernel:' \$(uname -r); echo 'Arch:' \$(uname -m); echo 'Memory:' \$(free -h | awk '/^Mem:/ {print \$2}'); echo 'Disk:' \$(df -h / | awk 'NR==2 {print \$2}'); echo 'CPU:' \$(nproc)"
    
    ssh_remote_capture "$node_ip" "$node_user" "$node_port" "$node_password" "$info_command" "System Info"
}

# Get service status from remote node
get_remote_service_status() {
    local node_ip="$1"
    local node_user="$2"
    local node_port="$3"
    local node_password="$4"
    local service_name="$5"
    
    log_debug "Checking service status: $service_name on $node_ip"
    
    local status_command="systemctl is-active $service_name 2>/dev/null || echo 'inactive'"
    
    ssh_remote_capture "$node_ip" "$node_user" "$node_port" "$node_password" "$status_command" "Service Status"
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize SSH operations module
init_ssh_operations() {
    # Check if sshpass is available
    if ! command_exists sshpass; then
        log_warning "sshpass is not installed. SSH operations may not work properly."
        return 1
    fi
    
    log_debug "SSH operations module initialized"
    return 0
}