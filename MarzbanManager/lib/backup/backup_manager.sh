#!/bin/bash
# Marzban Central Manager - Backup Management Module
# Professional Edition v3.0
# Author: behnamrjd

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================

# Backup types
readonly BACKUP_TYPE_FULL="full"
readonly BACKUP_TYPE_MAIN="main"
readonly BACKUP_TYPE_NODES="nodes"

# Compression settings
readonly COMPRESSION_LEVEL=6
readonly USE_PIGZ=true

# ============================================================================
# BACKUP CREATION FUNCTIONS
# ============================================================================

# Create full system backup
create_full_backup() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_full_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log_backup "Starting comprehensive backup process..."
    
    # Create temporary backup directory
    if ! mkdir -p "$temp_backup_dir"; then
        log_error "Failed to create temporary backup directory"
        return 1
    fi
    
    # Phase 1: Backup main server
    log_step "Phase 1: Backing up main server..."
    if ! backup_main_server "$temp_backup_dir"; then
        log_error "Main server backup failed"
        cleanup_temp_backup "$temp_backup_dir"
        return 1
    fi
    
    # Phase 2: Backup all nodes
    log_step "Phase 2: Backing up all nodes..."
    if ! backup_all_nodes "$temp_backup_dir"; then
        log_warning "Some node backups may have failed"
    fi
    
    # Phase 3: Create compressed archive
    log_step "Phase 3: Creating compressed archive..."
    if ! create_backup_archive "$temp_backup_dir" "$final_archive"; then
        log_error "Failed to create backup archive"
        cleanup_temp_backup "$temp_backup_dir"
        return 1
    fi
    
    # Phase 4: Apply retention policy
    log_step "Phase 4: Applying retention policy..."
    apply_backup_retention_policy
    
    # Cleanup
    cleanup_temp_backup "$temp_backup_dir"
    
    # Get backup size
    local backup_size
    backup_size=$(get_file_size "$final_archive")
    
    log_success "Full backup completed: $final_archive ($backup_size)"
    
    # Send notification
    send_backup_notification "$BACKUP_TYPE_FULL" "$final_archive" "$backup_size" "success"
    
    return 0
}

# Create main server only backup
create_main_server_backup() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_main_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log_backup "Starting main server backup..."
    
    # Create temporary backup directory
    if ! mkdir -p "$temp_backup_dir"; then
        log_error "Failed to create temporary backup directory"
        return 1
    fi
    
    # Backup main server
    if ! backup_main_server "$temp_backup_dir"; then
        log_error "Main server backup failed"
        cleanup_temp_backup "$temp_backup_dir"
        return 1
    fi
    
    # Create compressed archive
    if ! create_backup_archive "$temp_backup_dir" "$final_archive"; then
        log_error "Failed to create backup archive"
        cleanup_temp_backup "$temp_backup_dir"
        return 1
    fi
    
    # Cleanup
    cleanup_temp_backup "$temp_backup_dir"
    
    # Get backup size
    local backup_size
    backup_size=$(get_file_size "$final_archive")
    
    log_success "Main server backup completed: $final_archive ($backup_size)"
    
    # Send notification
    send_backup_notification "$BACKUP_TYPE_MAIN" "$final_archive" "$backup_size" "success"
    
    return 0
}

# Create nodes only backup
create_nodes_backup() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_nodes_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log_backup "Starting nodes backup..."
    
    # Create temporary backup directory
    if ! mkdir -p "$temp_backup_dir"; then
        log_error "Failed to create temporary backup directory"
        return 1
    fi
    
    # Backup all nodes
    if ! backup_all_nodes "$temp_backup_dir"; then
        log_error "Nodes backup failed"
        cleanup_temp_backup "$temp_backup_dir"
        return 1
    fi
    
    # Create compressed archive
    if ! create_backup_archive "$temp_backup_dir" "$final_archive"; then
        log_error "Failed to create backup archive"
        cleanup_temp_backup "$temp_backup_dir"
        return 1
    fi
    
    # Cleanup
    cleanup_temp_backup "$temp_backup_dir"
    
    # Get backup size
    backup_size=$(get_file_size "$final_archive")
    
    log_success "Nodes backup completed: $final_archive ($backup_size)"
    
    # Send notification
    send_backup_notification "$BACKUP_TYPE_NODES" "$final_archive" "$backup_size" "success"
    
    return 0
}

# ============================================================================
# COMPONENT BACKUP FUNCTIONS
# ============================================================================

# Backup main server components
backup_main_server() {
    local backup_dir="$1/main_server"
    
    if ! mkdir -p "$backup_dir"; then
        log_error "Failed to create main server backup directory"
        return 1
    fi
    
    log_backup "Backing up main server components..."
    
    local backup_success=true
    
    # Backup Marzban
    if [[ -d "/opt/marzban" ]]; then
        log_info "Backing up Marzban configuration..."
        if ! cp -r /opt/marzban "$backup_dir/" 2>/dev/null; then
            log_warning "Failed to backup Marzban configuration"
            backup_success=false
        fi
    fi
    
    # Backup Marzban data
    if [[ -d "/var/lib/marzban" ]]; then
        log_info "Backing up Marzban data..."
        if ! cp -r /var/lib/marzban "$backup_dir/" 2>/dev/null; then
            log_warning "Failed to backup Marzban data"
            backup_success=false
        fi
    fi
    
    # Backup HAProxy (if user confirms and exists)
    if [[ "$MAIN_HAS_HAPROXY" == "true" ]]; then
        log_prompt "Backup HAProxy configuration? (y/n):"
        read -r backup_haproxy
        if [[ "$backup_haproxy" =~ ^[Yy]$ ]]; then
            log_info "Backing up HAProxy configuration..."
            if ! mkdir -p "$backup_dir/haproxy" || ! cp -r /etc/haproxy/* "$backup_dir/haproxy/" 2>/dev/null; then
                log_warning "Failed to backup HAProxy configuration"
                backup_success=false
            fi
        fi
    fi
    
    # Backup Nginx (if user confirms and exists)
    if [[ "$MAIN_HAS_NGINX" == "true" ]]; then
        log_prompt "Backup Nginx configuration? (y/n):"
        read -r backup_nginx
        if [[ "$backup_nginx" =~ ^[Yy]$ ]]; then
            log_info "Backing up Nginx configuration..."
            if ! mkdir -p "$backup_dir/nginx" || ! cp -r /etc/nginx/* "$backup_dir/nginx/" 2>/dev/null; then
                log_warning "Failed to backup Nginx configuration"
                backup_success=false
            fi
        fi
    fi
    
    # Backup Geo files
    if [[ -n "$GEO_FILES_PATH" && -d "$GEO_FILES_PATH" ]]; then
        log_info "Backing up Geo files..."
        if ! mkdir -p "$backup_dir/geo_files" || ! cp -r "$GEO_FILES_PATH"/* "$backup_dir/geo_files/" 2>/dev/null; then
            log_warning "Failed to backup Geo files"
            backup_success=false
        fi
    fi
    
    # Backup Manager configuration
    log_info "Backing up Manager configuration..."
    if ! cp -r "$MANAGER_DIR" "$backup_dir/manager_config" 2>/dev/null; then
        log_warning "Failed to backup Manager configuration"
        backup_success=false
    fi
    
    # Backup system certificates
    if [[ -d "/etc/ssl/certs" ]]; then
        log_info "Backing up system certificates..."
        if ! mkdir -p "$backup_dir/ssl_certs" || ! cp -r /etc/ssl/certs/* "$backup_dir/ssl_certs/" 2>/dev/null; then
            log_warning "Failed to backup system certificates"
        fi
    fi
    
    # Create backup metadata
    create_backup_metadata "$backup_dir" "main_server"
    
    if [[ "$backup_success" == "true" ]]; then
        log_success "Main server backup completed successfully"
        return 0
    else
        log_warning "Main server backup completed with some warnings"
        return 0
    fi
}

# Backup all nodes
backup_all_nodes() {
    local backup_dir="$1/nodes"
    
    if ! mkdir -p "$backup_dir"; then
        log_error "Failed to create nodes backup directory"
        return 1
    fi
    
    load_nodes_config
    
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        log_warning "No nodes configured for backup"
        return 0
    fi
    
    log_backup "Backing up ${#NODES_ARRAY[@]} nodes..."
    
    local success_count=0
    local failure_count=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log_info "Backing up node: $name ($ip)"
        
        if backup_single_node "$backup_dir" "$name" "$ip" "$user" "$port" "$password"; then
            ((success_count++))
            log_success "Node $name backup completed"
        else
            ((failure_count++))
            log_error "Node $name backup failed"
        fi
    done
    
    log_info "Nodes backup completed: $success_count successful, $failure_count failed"
    
    # Create nodes backup metadata
    create_backup_metadata "$backup_dir" "nodes" "$success_count" "$failure_count"
    
    return 0
}

# Backup single node
backup_single_node() {
    local backup_base_dir="$1"
    local node_name="$2"
    local node_ip="$3"
    local node_user="$4"
    local node_port="$5"
    local node_password="$6"
    
    local node_backup_dir="$backup_base_dir/$node_name"
    
    if ! mkdir -p "$node_backup_dir"; then
        log_error "Failed to create backup directory for node $node_name"
        return 1
    fi
    
    # Create backup on remote node
    local remote_backup_file="/tmp/node_backup_${node_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local backup_command="tar -czf $remote_backup_file --warning=no-file-changed"
    backup_command+=" /opt/marzban-node/"
    backup_command+=" /var/lib/marzban-node/"
    backup_command+=" /etc/systemd/system/marzban-node*"
    backup_command+=" /etc/haproxy/"
    backup_command+=" 2>/dev/null || true"
    
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "$backup_command" "Node Backup Creation"; then
        # Transfer backup to main server
        if scp_from_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
           "$remote_backup_file" "$node_backup_dir/backup.tar.gz" "Node Backup Transfer"; then
            
            # Create node info file
            create_node_backup_info "$node_backup_dir" "$node_name" "$node_ip" "$node_user" "$node_port" "$domain" "$node_id"
            
            # Cleanup remote backup
            ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
                "rm -f $remote_backup_file" "Remote Cleanup" || true
            
            return 0
        else
            log_error "Failed to transfer backup from node $node_name"
            return 1
        fi
    else
        log_error "Failed to create backup on node $node_name"
        return 1
    fi
}

# ============================================================================
# BACKUP ARCHIVE FUNCTIONS
# ============================================================================

# Create compressed backup archive
create_backup_archive() {
    local source_dir="$1"
    local archive_path="$2"
    
    log_backup "Creating compressed archive..."
    
    # Choose compression method
    if [[ "$USE_PIGZ" == "true" ]] && command_exists pigz; then
        log_debug "Using pigz for faster compression"
        if tar -cf - -C "$(dirname "$source_dir")" "$(basename "$source_dir")" | pigz -$COMPRESSION_LEVEL > "$archive_path"; then
            log_debug "Archive created with pigz compression"
        else
            log_error "Failed to create archive with pigz"
            return 1
        fi
    else
        log_debug "Using standard gzip compression"
        if tar -czf "$archive_path" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"; then
            log_debug "Archive created with gzip compression"
        else
            log_error "Failed to create archive with gzip"
            return 1
        fi
    fi
    
    # Verify archive integrity
    if verify_backup_integrity "$archive_path"; then
        local archive_size
        archive_size=$(get_file_size "$archive_path")
        log_success "Archive created successfully: $archive_size"
        
        # Create checksum
        create_backup_checksum "$archive_path"
        
        return 0
    else
        log_error "Archive verification failed"
        return 1
    fi
}

# Verify backup integrity
verify_backup_integrity() {
    local archive_path="$1"
    
    if [[ ! -f "$archive_path" ]]; then
        log_error "Archive file not found: $archive_path"
        return 1
    fi
    
    log_debug "Verifying archive integrity: $(basename "$archive_path")"
    
    # Test archive
    if tar -tzf "$archive_path" >/dev/null 2>&1; then
        log_debug "Archive integrity verification passed"
        return 0
    else
        log_error "Archive integrity verification failed"
        return 1
    fi
}

# Create backup checksum
create_backup_checksum() {
    local archive_path="$1"
    local checksum_file="${archive_path}.md5"
    
    log_debug "Creating checksum for backup archive"
    
    if calculate_checksum "$archive_path" "md5" > "$checksum_file"; then
        log_debug "Checksum created: $(basename "$checksum_file")"
        return 0
    else
        log_warning "Failed to create checksum file"
        return 1
    fi
}

# ============================================================================
# BACKUP METADATA FUNCTIONS
# ============================================================================

# Create backup metadata
create_backup_metadata() {
    local backup_dir="$1"
    local backup_type="$2"
    local success_count="${3:-}"
    local failure_count="${4:-}"
    
    local metadata_file="$backup_dir/backup_metadata.json"
    
    local metadata
    metadata=$(jq -n \
        --arg backup_type "$backup_type" \
        --arg timestamp "$(date -Iseconds)" \
        --arg hostname "$(hostname)" \
        --arg version "$SCRIPT_VERSION" \
        --arg success_count "${success_count:-0}" \
        --arg failure_count "${failure_count:-0}" \
        '{
            backup_type: $backup_type,
            timestamp: $timestamp,
            hostname: $hostname,
            manager_version: $version,
            success_count: ($success_count | tonumber),
            failure_count: ($failure_count | tonumber)
        }')
    
    echo "$metadata" > "$metadata_file"
    log_debug "Backup metadata created"
}

# Create node backup info
create_node_backup_info() {
    local node_backup_dir="$1"
    local node_name="$2"
    local node_ip="$3"
    local node_user="$4"
    local node_port="$5"
    local node_domain="$6"
    local node_id="$7"
    
    local info_file="$node_backup_dir/node_info.json"
    
    local node_info
    node_info=$(jq -n \
        --arg name "$node_name" \
        --arg ip "$node_ip" \
        --arg user "$node_user" \
        --arg port "$node_port" \
        --arg domain "$node_domain" \
        --arg node_id "${node_id:-null}" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            name: $name,
            ip: $ip,
            ssh_user: $user,
            ssh_port: ($port | tonumber),
            domain: $domain,
            node_id: $node_id,
            backup_timestamp: $timestamp
        }')
    
    echo "$node_info" > "$info_file"
    log_debug "Node backup info created for $node_name"
}

# ============================================================================
# BACKUP MANAGEMENT FUNCTIONS
# ============================================================================

# List available backups
list_available_backups() {
    log_info "Listing available backups..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Available Backups${NC}                        ║"
    echo -e "${WHITE}╚══════���═══════════════════════════════════════════════════════╝${NC}\n"
    
    if ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        printf "%-5s %-35s %-15s %-10s %-10s\n" "No." "Backup Name" "Date" "Size" "Type"
        echo -e "${DIM}─────────────────────────────────────────────────────────────────────${NC}"
        
        local i=1
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            local filename=$(basename "$backup")
            local filesize=$(get_file_size "$backup")
            local filedate=$(date -r "$backup" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "Unknown")
            
            # Determine backup type from filename
            local backup_type="Unknown"
            if [[ "$filename" =~ full_backup ]]; then
                backup_type="Full"
            elif [[ "$filename" =~ main_backup ]]; then
                backup_type="Main"
            elif [[ "$filename" =~ nodes_backup ]]; then
                backup_type="Nodes"
            fi
            
            printf "%-5s %-35s %-15s %-10s %-10s\n" "$i" "$filename" "$filedate" "$filesize" "$backup_type"
            ((i++))
        done
        echo -e "${DIM}─────────────────────────────────────────────────────────────────────${NC}"
    else
        echo "No backups found in $BACKUP_ARCHIVE_DIR"
    fi
}

# Apply backup retention policy
apply_backup_retention_policy() {
    log_backup "Applying retention policy (keeping last $BACKUP_RETENTION_COUNT backups)..."
    
    local removed_count=0
    
    # Remove old full backups
    local full_backups=($(ls -t "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null || true))
    if [[ ${#full_backups[@]} -gt $BACKUP_RETENTION_COUNT ]]; then
        for ((i=BACKUP_RETENTION_COUNT; i<${#full_backups[@]}; i++)); do
            local old_backup="${full_backups[$i]}"
            log_info "Removing old full backup: $(basename "$old_backup")"
            rm -f "$old_backup" "${old_backup}.md5"
            ((removed_count++))
        done
    fi
    
    # Remove old main backups
    local main_backups=($(ls -t "$BACKUP_ARCHIVE_DIR"/marzban_main_backup_*.tar.gz 2>/dev/null || true))
    if [[ ${#main_backups[@]} -gt $BACKUP_RETENTION_COUNT ]]; then
        for ((i=BACKUP_RETENTION_COUNT; i<${#main_backups[@]}; i++)); do
            local old_backup="${main_backups[$i]}"
            log_info "Removing old main backup: $(basename "$old_backup")"
            rm -f "$old_backup" "${old_backup}.md5"
            ((removed_count++))
        done
    fi
    
    # Remove old nodes backups
    local nodes_backups=($(ls -t "$BACKUP_ARCHIVE_DIR"/marzban_nodes_backup_*.tar.gz 2>/dev/null || true))
    if [[ ${#nodes_backups[@]} -gt $BACKUP_RETENTION_COUNT ]]; then
        for ((i=BACKUP_RETENTION_COUNT; i<${#nodes_backups[@]}; i++)); do
            local old_backup="${nodes_backups[$i]}"
            log_info "Removing old nodes backup: $(basename "$old_backup")"
            rm -f "$old_backup" "${old_backup}.md5"
            ((removed_count++))
        done
    fi
    
    local remaining_count
    remaining_count=$(ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz 2>/dev/null | wc -l)
    log_success "Retention policy applied: $removed_count backups removed, $remaining_count remaining"
}

# Cleanup old backups manually
cleanup_old_backups() {
    log_step "Manual backup cleanup..."
    
    list_available_backups
    
    if ! ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        log_info "No backups found to cleanup"
        return 0
    fi
    
    echo ""
    log_prompt "Enter number of backups to keep for each type [default: $BACKUP_RETENTION_COUNT]:"
    read -r keep_count
    keep_count=${keep_count:-$BACKUP_RETENTION_COUNT}
    
    if ! [[ "$keep_count" =~ ^[0-9]+$ ]] || [[ $keep_count -lt 1 ]]; then
        log_error "Invalid number. Must be a positive integer."
        return 1
    fi
    
    log_warning "This will remove backups older than the $keep_count most recent ones for each type."
    log_prompt "Continue? (y/n):"
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        return 0
    fi
    
    # Temporarily change retention count
    local old_retention=$BACKUP_RETENTION_COUNT
    BACKUP_RETENTION_COUNT=$keep_count
    
    apply_backup_retention_policy
    
    # Restore original retention count
    BACKUP_RETENTION_COUNT=$old_retention
    
    return 0
}

# ============================================================================
# AUTOMATED BACKUP FUNCTIONS
# ============================================================================

# Setup automated backup
setup_automated_backup() {
    log_step "Setting up automated backup system..."
    
    echo -e "\n${WHITE}╔════════════════════��═══════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Automated Backup Setup${NC}          ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Backup Schedule Options:${NC}"
    echo " 1. Daily at 3:30 AM (default)"
    echo " 2. Custom schedule"
    echo " 3. Disable automated backup"
    echo ""
    
    log_prompt "Choose backup schedule option:"
    read -r schedule_choice
    
    case "$schedule_choice" in
        1)
            setup_daily_backup "03" "30"
            ;;
        2)
            setup_custom_backup_schedule
            ;;
        3)
            disable_automated_backup
            ;;
        *)
            log_warning "Invalid choice, using default schedule"
            setup_daily_backup "03" "30"
            ;;
    esac
}

# Setup daily backup
setup_daily_backup() {
    local hour="${1:-03}"
    local minute="${2:-30}"
    
    log_info "Setting up daily backup at $hour:$minute..."
    
    # Create backup script
    create_backup_script
    
    # Setup cron job
    local cron_entry="$minute $hour * * * TZ=$BACKUP_TIMEZONE /usr/local/bin/marzban-auto-backup.sh"
    
    # Remove existing cron job if exists
    crontab -l 2>/dev/null | grep -v "marzban-auto-backup" | crontab -
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    log_success "Automated backup scheduled for $hour:$minute daily ($BACKUP_TIMEZONE)"
    
    # Update configuration
    set_config_value "AUTO_BACKUP_ENABLED" "true"
    set_config_value "BACKUP_SCHEDULE_HOUR" "$hour"
    set_config_value "BACKUP_SCHEDULE_MINUTE" "$minute"
    
    send_telegram_notification "⏰ Automated Backup Enabled%0A%0A📅 Schedule: Daily at $hour:$minute ($BACKUP_TIMEZONE)%0A🔄 Retention: $BACKUP_RETENTION_COUNT backups" "normal"
}

# Setup custom backup schedule
setup_custom_backup_schedule() {
    echo -e "\n${YELLOW}Custom Backup Schedule Configuration:${NC}"
    
    log_prompt "Enter hour (0-23) [default: 03]:"
    read -r custom_hour
    custom_hour=${custom_hour:-03}
    
    log_prompt "Enter minute (0-59) [default: 30]:"
    read -r custom_minute
    custom_minute=${custom_minute:-30}
    
    # Validate input
    if ! [[ "$custom_hour" =~ ^[0-9]+$ ]] || [[ $custom_hour -lt 0 ]] || [[ $custom_hour -gt 23 ]]; then
        log_error "Invalid hour. Must be between 0-23."
        return 1
    fi
    
    if ! [[ "$custom_minute" =~ ^[0-9]+$ ]] || [[ $custom_minute -lt 0 ]] || [[ $custom_minute -gt 59 ]]; then
        log_error "Invalid minute. Must be between 0-59."
        return 1
    fi
    
    setup_daily_backup "$custom_hour" "$custom_minute"
}

# Create backup script
create_backup_script() {
    local backup_script="/usr/local/bin/marzban-auto-backup.sh"
    
    cat > "$backup_script" << EOF
#!/bin/bash
# Automated Marzban Backup Script
# Generated by Marzban Central Manager

# Set working directory
cd "$MANAGER_DIR" || exit 1

# Execute backup
if [[ -f "./marzban_central_manager.sh" ]]; then
    ./marzban_central_manager.sh --backup-full >> /var/log/marzban-backup.log 2>&1
else
    echo "Error: Marzban Central Manager script not found" >> /var/log/marzban-backup.log
    exit 1
fi
EOF
    
    chmod +x "$backup_script"
    log_debug "Automated backup script created: $backup_script"
}

# Disable automated backup
disable_automated_backup() {
    log_info "Disabling automated backup..."
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "marzban-auto-backup" | crontab -
    
    # Remove backup script
    rm -f /usr/local/bin/marzban-auto-backup.sh
    
    # Update configuration
    set_config_value "AUTO_BACKUP_ENABLED" "false"
    
    log_success "Automated backup disabled"
    send_telegram_notification "⏰ Automated Backup Disabled%0A%0AScheduled backups have been turned off" "normal"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Cleanup temporary backup directory
cleanup_temp_backup() {
    local temp_dir="$1"
    
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        log_debug "Temporary backup directory cleaned up"
    fi
}

# Get backup statistics
get_backup_statistics() {
    local total_backups=0
    local total_size=0
    local full_backups=0
    local main_backups=0
    local nodes_backups=0
    
    if ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            ((total_backups++))
            
            # Get file size in bytes
            local size_bytes
            size_bytes=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup" 2>/dev/null || echo 0)
            total_size=$((total_size + size_bytes))
            
            # Count by type
            local filename=$(basename "$backup")
            if [[ "$filename" =~ full_backup ]]; then
                ((full_backups++))
            elif [[ "$filename" =~ main_backup ]]; then
                ((main_backups++))
            elif [[ "$filename" =~ nodes_backup ]]; then
                ((nodes_backups++))
            fi
        done
    fi
    
    # Convert total size to human readable
    local total_size_human
    if command_exists numfmt; then
        total_size_human=$(numfmt --to=iec-i --suffix=B "$total_size")
    else
        total_size_human="$total_size bytes"
    fi
    
    echo "Backup Statistics:"
    echo "=================="
    echo "Total backups: $total_backups"
    echo "Total size: $total_size_human"
    echo "Full backups: $full_backups"
    echo "Main backups: $main_backups"
    echo "Nodes backups: $nodes_backups"
    echo "Retention policy: $BACKUP_RETENTION_COUNT backups"
    echo "Auto backup: ${AUTO_BACKUP_ENABLED:-false}"
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize backup manager module
init_backup_manager() {
    # Ensure backup directories exist
    if ! init_config_directories; then
        log_error "Failed to initialize backup directories"
        return 1
    fi
    
    log_debug "Backup manager module initialized"
    return 0
}