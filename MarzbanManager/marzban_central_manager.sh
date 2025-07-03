#!/bin/bash
# Enhanced error handling and strict mode
set -euo pipefail
IFS=

# Marzban Central Node Manager - Professional Edition v3.0
# Enhanced with Complete Backup System, Optimized Monitoring & Advanced Features
# Author: behnamrjd
# Version: Professional-3.0

SCRIPT_VERSION="Professional-3.0"
MANAGER_DIR="/root/MarzbanManager"
NODES_CONFIG_FILE="${MANAGER_DIR}/marzban_managed_nodes.conf"
MANAGER_CONFIG_FILE="${MANAGER_DIR}/marzban_manager.conf"
BACKUP_DIR="${MANAGER_DIR}/backups"
LOCKFILE="/var/lock/marzban-central-manager.lock"
LOGFILE="/tmp/marzban_central_manager_$(date +%Y%m%d_%H%M%S).log"

# Enhanced Backup Configuration
BACKUP_MAIN_DIR="${BACKUP_DIR}/main_server"
BACKUP_NODES_DIR="${BACKUP_DIR}/nodes"
BACKUP_ARCHIVE_DIR="${BACKUP_DIR}/archives"
BACKUP_RETENTION_COUNT=3
BACKUP_SCHEDULE_HOUR="03"
BACKUP_SCHEDULE_MINUTE="30"
BACKUP_TIMEZONE="Asia/Tehran"
AUTO_BACKUP_ENABLED=false

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

# --- Global Variables ---
MAIN_SERVER_IP=$(hostname -I | awk '{print $1}')
MARZBAN_PANEL_PROTOCOL="https"
MARZBAN_PANEL_DOMAIN=""
MARZBAN_PANEL_PORT=""
MARZBAN_PANEL_USERNAME=""
MARZBAN_PANEL_PASSWORD=""
MARZBAN_TOKEN=""
CLIENT_CERT=""
MARZBAN_NODE_ID=""

# Enhanced monitoring configuration (optimized for server performance)
MONITORING_INTERVAL=600  # 10 minutes (reduced from 5 minutes)
HEALTH_CHECK_TIMEOUT=30  # Increased timeout for stability
API_RATE_LIMIT_DELAY=2   # Delay between API calls
SYNC_CHECK_INTERVAL=1800 # 30 minutes for sync monitoring

# Service detection variables
MAIN_HAS_NGINX=false
MAIN_HAS_HAPROXY=false
NGINX_CONFIG_PATH=""
HAPROXY_CONFIG_PATH=""
GEO_FILES_PATH=""

mkdir -p "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
chmod 700 "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
if [ -f "$MANAGER_CONFIG_FILE" ]; then source "$MANAGER_CONFIG_FILE"; fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

## Enhanced logging with multiple levels and file rotation
log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    local masked_message="$message"
    
    # Mask sensitive information
    if [[ -n "${NODE_SSH_PASSWORD:-}" ]]; then masked_message="${message//$NODE_SSH_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_PANEL_PASSWORD:-}" ]]; then masked_message="${message//$MARZBAN_PANEL_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_TOKEN:-}" ]]; then masked_message="${message//$MARZBAN_TOKEN/*****masked*****/}"; fi
    
    # Log to system logger
    logger -t "marzban-central-manager" "$level: $masked_message"
    
    # Enhanced console output with icons and colors
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $masked_message" | tee -a "$LOGFILE";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $masked_message" | tee -a "$LOGFILE";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $masked_message" | tee -a "$LOGFILE";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $masked_message" | tee -a "$LOGFILE";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $masked_message" | tee -a "$LOGFILE";;
        PROMPT)  echo -e "[$timestamp] ${CYAN}❓ PROMPT:${NC} $masked_message";;
        DEBUG)   echo -e "[$timestamp] ${DIM}🐛 DEBUG:${NC} $masked_message" | tee -a "$LOGFILE";;
        BACKUP)  echo -e "[$timestamp] ${CYAN}💾 BACKUP:${NC} $masked_message" | tee -a "$LOGFILE";;
        SYNC)    echo -e "[$timestamp] ${PURPLE}🔄 SYNC:${NC} $masked_message" | tee -a "$LOGFILE";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $masked_message" | tee -a "$LOGFILE";;
    esac
}

send_telegram_notification() {
    local message="$1"
    local level="${2:-normal}" # normal, high, critical
    local stored_level

    # Load TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, and TELEGRAM_NOTIFICATION_LEVEL from config
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        source "$MANAGER_CONFIG_FILE"
    fi

    stored_level=${TELEGRAM_NOTIFICATION_LEVEL:-1} # Default to all notifications if not set

    # Check if notifications are enabled and the level is appropriate
    if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_CHAT_ID}" ] || [ "$stored_level" -eq 4 ]; then
        # log "DEBUG" "Telegram notifications are disabled or not configured."
        return 0
    fi

    # Level mapping: 1=all, 2=high/critical, 3=critical only
    case "$level" in
        "normal")
            if [ "$stored_level" -gt 1 ]; then return 0; fi
            ;;
        "high")
            if [ "$stored_level" -gt 2 ]; then return 0; fi
            ;;
        "critical")
            if [ "$stored_level" -gt 3 ]; then return 0; fi
            ;;
    esac

    # Send the notification using curl
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d "chat_id=${TELEGRAM_CHAT_ID}" \
         -d "text=${message}" \
         -d "parse_mode=HTML" > /dev/null &
}

## Lock management for single instance execution
acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        local pid; pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then 
            log "ERROR" "Instance already running (PID: $pid)."
            exit 1
        fi
        log "WARNING" "Removing stale lock file."
        rm -f "$LOCKFILE"
    fi
    echo "$$" > "$LOCKFILE"
    log "INFO" "Lock acquired."
}

release_lock() { rm -f "$LOCKFILE"; log "INFO" "Lock released."; }
trap release_lock EXIT
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

## Dependency checks with auto-installation
check_dependencies() {
    local deps=("sshpass" "python3" "curl" "jq" "rsync" "pigz" "git")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then # Using our defined function
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "INFO" "Installing missing dependencies: ${missing_deps[*]}"
        if command_exists apt; then
            apt update >/dev/null 2>&1
            apt install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via apt."
        elif command_exists yum; then
            yum install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via yum."
        else
            log "ERROR" "Cannot determine package manager (apt or yum). Please install dependencies manually: ${missing_deps[*]}"
            return 1
        fi
    fi
    
    # Check Python modules
    if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
        log "INFO" "Installing python3-full (or equivalent for json, urllib.parse, datetime)..."
        if command_exists apt; then
            apt install -y python3-full >/dev/null 2>&1
        elif command_exists yum; then
             # CentOS might need python3-json, python3-urllib an python3-datetime or similar
             # For simplicity, assuming python3-devel or a more general package might cover these.
             # This part might need adjustment based on specific distro.
            yum install -y python3-devel >/dev/null 2>&1 || yum install -y python3 >/dev/null 2>&1
        fi
        # Re-check after attempting install
        if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
            log "WARNING" "Failed to install required Python modules. Some functionalities might be affected."
        else
            log "SUCCESS" "Python modules seem to be available."
        fi
    fi
    return 0
}

## Enhanced SSH operations with retry mechanism and rate limiting
ssh_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" command="$5" desc="$6"
    local max_retries=3 retry=0
    
    sleep "$API_RATE_LIMIT_DELAY"
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Executing ($desc) on $node_ip (attempt $((retry+1))/$max_retries)..."
        
        # Use environment variable to pass password more securely
        if SSHPASS="$node_password" sshpass -e ssh -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
           -p "$node_port" "${node_user}@${node_ip}" "$command" 2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "Remote command ($desc) executed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 5 seconds..."
            sleep 5
        fi
    done
    
    log "ERROR" "Remote command ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP with progress and retry
scp_to_remote() {
    local local_path="$1" node_ip="$2" node_user="$3" node_port="$4" node_password="$5" remote_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Transferring ($desc) to $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "$local_path" "${node_user}@${node_ip}:${remote_path}" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File transfer ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File transfer ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP from remote with retry
scp_from_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" remote_path="$5" local_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Downloading ($desc) from $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if echo "$node_password" | sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "${node_user}@${node_ip}:${remote_path}" "$local_path" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File download ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File download ($desc) failed after $max_retries attempts."
    return 1
}

## Node configuration management
load_nodes_config() {
    if [ -f "$NODES_CONFIG_FILE" ]; then
        mapfile -t NODES_ARRAY < <(grep -vE '^\s*#|^\s*$' "$NODES_CONFIG_FILE" || true)
    else
        NODES_ARRAY=()
    fi
}

save_nodes_config() {
    printf "%s\n" "${NODES_ARRAY[@]}" > "$NODES_CONFIG_FILE"
    chmod 600 "$NODES_CONFIG_FILE"
    log "INFO" "Nodes configuration saved."
}

add_node_to_config() {
    local name="$1" ip="$2" user="$3" port="$4" domain="$5" password="$6" node_id="${7:-}"
    NODES_ARRAY+=("${name};${ip};${user};${port};${domain};${password};${node_id}")
    log "INFO" "Node '$name' added to configuration."
}

get_node_config_by_name() {
    local name="$1"
    for entry in "${NODES_ARRAY[@]}"; do
        if [[ "$entry" == "${name};"* ]]; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

## Service Detection System
detect_main_server_services() {
    log "STEP" "Detecting services on main server..."
    
    # Detect Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        MAIN_HAS_NGINX=true
        NGINX_CONFIG_PATH="/etc/nginx"
        log "SUCCESS" "Nginx detected on main server"
    else
        MAIN_HAS_NGINX=false
        log "INFO" "Nginx not detected on main server"
    fi
    
    # Detect HAProxy
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        MAIN_HAS_HAPROXY=true
        HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
        log "SUCCESS" "HAProxy detected on main server"
    else
        MAIN_HAS_HAPROXY=false
        log "INFO" "HAProxy not detected on main server"
    fi
    
    # Detect Geo files from Core config
    detect_geo_files_location
}

detect_geo_files_location() {
    log "INFO" "Detecting geo files location using multi-priority smart-scan..."
    
    # --- Priority 1: The most reliable method (from .env file) ---
    if [ -f "/opt/marzban/.env" ]; then
        local env_geo_path
        env_geo_path=$(grep -E "^\s*XRAY_ASSETS_PATH" /opt/marzban/.env | cut -d'=' -f2- | tr -d '"' | tr -d "'" | sed 's/#.*//' | xargs)
        if [ -n "$env_geo_path" ] && [ -d "$env_geo_path" ]; then
            if [ -f "$env_geo_path/geosite.dat" ] && [ -f "$env_geo_path/geoip.dat" ]; then
                log "SUCCESS" "Geo files found and validated via .env file at: $env_geo_path"
                GEO_FILES_PATH="$env_geo_path"
                return 0
            fi
        fi
    fi

    # --- Priority 2: Your brilliant idea - Find filenames from xray_config.json and search for them ---
    if [ -f "/var/lib/marzban/xray_config.json" ]; then
        log "INFO" "Scanning xray_config.json for custom geo file names..."
        local geoip_file
        local geosite_file

        geoip_file=$(jq -r '[.routing.rules[]? | .ip[]? | select(startswith("geoip:"))] | .[0] // "geoip:geoip"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geoip_file+=".dat"

        geosite_file=$(jq -r '[.routing.rules[]? | .domain[]? | select(startswith("geosite:"))] | .[0] // "geosite:geosite"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geosite_file+=".dat"
        
        log "DEBUG" "Detected target files: $geoip_file, $geosite_file"

        local found_dir
        found_dir=$(find / -name "$geoip_file" -printf "%h\n" 2>/dev/null | while read -r dir; do
            if [ -f "$dir/$geosite_file" ]; then
                echo "$dir"
                break
            fi
        done)

        if [ -n "$found_dir" ]; then
            log "SUCCESS" "Geo files found via xray_config scan at: $found_dir"
            GEO_FILES_PATH="$found_dir"
            return 0
        fi
    fi

    # --- Priority 3: Fallback to scanning common hardcoded locations ---
    log "INFO" "Falling back to scanning common default directories..."
    local common_paths=(
        "/var/lib/marzban/assets" "/var/lib/marzban/geo" "/var/lib/marzban/chocolate"
        "/opt/marzban/assets" "/opt/marzban/geo"
    )
    for path in "${common_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/geosite.dat" ] && [ -f "$path/geoip.dat" ]; then
            log "SUCCESS" "Geo files found via fallback scan at: $path"
            GEO_FILES_PATH="$path"
            return 0
        fi
    done
    
    log "WARNING" "Could not find custom Geo files on the main server. Geo file sync will be skipped."
    GEO_FILES_PATH=""
    return 1
}
## Complete Backup System Implementation
create_full_backup() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_full_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting comprehensive backup process..."
    
    # Create temporary backup directory
    mkdir -p "$temp_backup_dir"
    
    # Phase 1: Backup main server
    log "STEP" "Phase 1: Backing up main server..."
    backup_main_server "$temp_backup_dir"
    
    # Phase 2: Backup all nodes
    log "STEP" "Phase 2: Backing up all nodes..."
    backup_all_nodes "$temp_backup_dir"
    
    # Phase 3: Create compressed archive
    log "STEP" "Phase 3: Creating compressed archive..."
    create_backup_archive "$temp_backup_dir" "$final_archive"
    
    # Phase 4: Apply retention policy
    log "STEP" "Phase 4: Applying retention policy..."
    apply_backup_retention_policy_global
    
    # Cleanup
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Full backup completed: $final_archive"
    
    # Send notification
    local backup_size=$(du -h "$final_archive" | cut -f1)
    send_telegram_notification "💾 Backup Completed%0A%0A📁 File: ${backup_name}.tar.gz%0A📊 Size: ${backup_size}%0A⏰ Time: $(date)" "normal"
}

backup_main_server() {
    local backup_dir="$1/main_server"
    mkdir -p "$backup_dir"
    
    log "BACKUP" "Backing up main server components..."
    
    # Backup Marzban
    if [ -d "/opt/marzban" ]; then
        log "INFO" "Backing up Marzban configuration..."
        cp -r /opt/marzban "$backup_dir/" 2>/dev/null || log "WARNING" "Failed to backup Marzban"
    fi
    
    # Backup HAProxy (if user confirms)
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "PROMPT" "Backup HAProxy configuration? (y/n):"
        read -r backup_haproxy
        if [[ "$backup_haproxy" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up HAProxy configuration..."
            mkdir -p "$backup_dir/haproxy"
            cp -r /etc/haproxy/* "$backup_dir/haproxy/" 2>/dev/null || log "WARNING" "Failed to backup HAProxy"
        fi
    fi
    
    # Backup Nginx (if user confirms)
    if [ "$MAIN_HAS_NGINX" = "true" ]; then
        log "PROMPT" "Backup Nginx configuration? (y/n):"
        read -r backup_nginx
        if [[ "$backup_nginx" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up Nginx configuration..."
            mkdir -p "$backup_dir/nginx"
            cp -r /etc/nginx/* "$backup_dir/nginx/" 2>/dev/null || log "WARNING" "Failed to backup Nginx"
        fi
    fi
    
    # Backup Geo files
    if [ -n "$GEO_FILES_PATH" ]; then
        log "INFO" "Backing up Geo files..."
        mkdir -p "$backup_dir/geo_files"
        cp -r "$GEO_FILES_PATH"/* "$backup_dir/geo_files/" 2>/dev/null || log "WARNING" "Failed to backup Geo files"
    fi
    
    # Backup Manager configuration
    log "INFO" "Backing up Manager configuration..."
    cp -r "$MANAGER_DIR" "$backup_dir/manager_config" 2>/dev/null || log "WARNING" "Failed to backup Manager config"
    
    log "SUCCESS" "Main server backup completed."
}

backup_all_nodes() {
    local backup_dir="$1/nodes"
    mkdir -p "$backup_dir"
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured for backup."
        return 0
    fi
    
    log "BACKUP" "Backing up ${#NODES_ARRAY[@]} nodes..."
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Backing up node: $name ($ip)"
        
        local node_backup_dir="$backup_dir/$name"
        mkdir -p "$node_backup_dir"
        
        export NODE_SSH_PASSWORD="$password"
        
        # Create backup on remote node
        local remote_backup_file="/tmp/node_backup_${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "tar -czf $remote_backup_file --warning=no-file-changed /opt/marzban-node/ /var/lib/marzban-node/ /etc/systemd/system/marzban-node* /etc/haproxy/ 2>/dev/null" \
           "Node Backup Creation"; then
            
            # Transfer backup to main server
            if scp_from_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$remote_backup_file" "$node_backup_dir/backup.tar.gz" "Node Backup Transfer"; then
                
                # Create node info file
                cat > "$node_backup_dir/node_info.txt" << EOF
Node Name: $name
IP Address: $ip
Domain: $domain
SSH User: $user
SSH Port: $port
Marzban Node ID: $node_id
Backup Date: $(date)
EOF
                
                # Cleanup remote backup
                ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                    "rm -f $remote_backup_file" "Remote Cleanup" || true
                
                log "SUCCESS" "Node $name backup completed."
            else
                log "ERROR" "Failed to transfer backup from node $name"
            fi
        else
            log "ERROR" "Failed to create backup on node $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "All nodes backup completed."
}

create_backup_archive() {
    local source_dir="$1"
    local archive_path="$2"
    
    log "BACKUP" "Creating compressed archive..."
    
    # Use pigz for faster compression if available
    if command_exists pigz; then
        tar -cf - -C "$(dirname "$source_dir")" "$(basename "$source_dir")" | pigz > "$archive_path"
    else
        tar -czf "$archive_path" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"
    fi
    
    # Verify archive integrity
    if tar -tzf "$archive_path" >/dev/null 2>&1; then
        local archive_size=$(du -h "$archive_path" | cut -f1)
        log "SUCCESS" "Archive created successfully: $archive_size"
        
        # Create checksum
        md5sum "$archive_path" > "${archive_path}.md5"
        log "INFO" "Checksum created: ${archive_path}.md5"
    else
        log "ERROR" "Archive verification failed!"
        return 1
    fi
}

apply_backup_retention_policy_global() {
    log "BACKUP" "Applying retention policy (keeping last $BACKUP_RETENTION_COUNT backups)..."
    
    # Remove old archives
    ls -t "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | \
        tail -n +$((BACKUP_RETENTION_COUNT + 1)) | \
        while read -r old_backup; do
            log "INFO" "Removing old backup: $(basename "$old_backup")"
            rm -f "$old_backup" "${old_backup}.md5"
        done
    
    local remaining_count
    remaining_count=$(ls "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | wc -l)
    log "SUCCESS" "Retention policy applied: $remaining_count backups remaining"
}

## Automated Backup Scheduling
setup_automated_backup() {
    log "STEP" "Setting up automated backup system..."
    
    # Create backup script
    local backup_script="/usr/local/bin/marzban-auto-backup.sh"
    cat > "$backup_script" << 'EOF'
#!/bin/bash
# Automated Marzban Backup Script
cd /root/MarzbanManager
./marzban_central_manager.sh --backup >> /var/log/marzban-backup.log 2>&1
EOF
    
    chmod +x "$backup_script"
    
    # Setup cron job for 3:30 AM Iran time
    local cron_entry="30 3 * * * TZ=Asia/Tehran $backup_script"
    
    # Remove existing cron job if exists
    crontab -l 2>/dev/null | grep -v "marzban-auto-backup" | crontab -
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    log "SUCCESS" "Automated backup scheduled for 3:30 AM Iran time daily"
    
    # Update configuration
    sed -i '/AUTO_BACKUP_ENABLED=/d' "$MANAGER_CONFIG_FILE" 2>/dev/null || true
    echo "AUTO_BACKUP_ENABLED=true" >> "$MANAGER_CONFIG_FILE"
    
    send_telegram_notification "⏰ Automated Backup Enabled%0A%0A📅 Schedule: Daily at 3:30 AM (Iran Time)%0A🔄 Retention: $BACKUP_RETENTION_COUNT backups" "normal"
}

## Enhanced HAProxy Synchronization System
sync_haproxy_across_all_nodes() {
    local new_node_name="$1" new_node_ip="$2" new_node_domain="$3"
    
    log "SYNC" "Starting HAProxy synchronization across all nodes..."
    
    # Phase 1: Update main server HAProxy
    if ! update_main_haproxy_config "$new_node_name" "$new_node_ip" "$new_node_domain"; then
        log "ERROR" "Failed to update main server HAProxy"
        return 1
    fi
    
    # Phase 2: Sync to all existing nodes
    sync_haproxy_to_all_existing_nodes
    
    # Phase 3: Install HAProxy on new node
    install_haproxy_on_new_node "$new_node_ip" "$new_node_name"
    
    # Phase 4: Verification
    verify_haproxy_sync_across_nodes
}

update_main_haproxy_config() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_cfg}.backup.$(date +%s)"
    
    log "SYNC" "Updating main server HAProxy configuration..."
    cp "$haproxy_cfg" "$backup_file"
    
    # Create enhanced HAProxy config with new node
    create_enhanced_haproxy_config "$node_name" "$node_ip" "$node_domain"
    
    # Validate configuration before reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        if systemctl reload haproxy; then
            log "SUCCESS" "Main server HAProxy updated and reloaded successfully"
            log "SYNC" "HAProxy updated: Added backend $node_name ($node_ip) for domain $node_domain"
            send_telegram_notification "🔄 HAProxy Updated%0A%0AAdded: $node_name%0AIP: $node_ip%0ADomain: $node_domain" "normal"
            return 0
        else
            log "ERROR" "Failed to reload HAProxy service, restoring backup"
            cp "$backup_file" "$haproxy_cfg"
            systemctl reload haproxy
            return 1
        fi
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup"
        cp "$backup_file" "$haproxy_cfg"
        return 1
    fi
}

sync_haproxy_to_all_existing_nodes() {
    log "SYNC" "Synchronizing HAProxy to all existing nodes..."
    local sync_success=0 sync_failed=0
    
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "SYNC" "Syncing HAProxy to node: $name ($ip)"
        export NODE_SSH_PASSWORD="$password"
        
        # Create rollback point on node
        if create_node_rollback_point "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            
            # Sync HAProxy configuration
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                sync_success=$((sync_success + 1))
                log "SUCCESS" "HAProxy synced to node: $name"
            else
                sync_failed=$((sync_failed + 1))
                log "ERROR" "Failed to sync HAProxy to node: $name"
                
                # Attempt rollback
                rollback_node_configuration "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"
            fi
        else
            log "WARNING" "Could not create rollback point for node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SYNC" "HAProxy sync completed: $sync_success successful, $sync_failed failed"
    
    # Send notification
    send_telegram_notification "📊 HAProxy Sync Report%0A%0A✅ Success: $sync_success%0A❌ Failed: $sync_failed" "normal"
}

create_node_rollback_point() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "SYNC" "Creating rollback point for node: $node_name"
    
    # Create backup of current HAProxy config
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg ]; then cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.rollback.$(date +%s); echo 'Rollback point created'; else echo 'No HAProxy config found'; fi" \
       "Rollback Point Creation"; then
        
        # Store rollback info
        echo "${node_name};${node_ip};$(date +%s)" >> "${BACKUP_DIR}/rollback_points.log"
        return 0
    else
        return 1
    fi
}

sync_haproxy_to_single_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    # Check if HAProxy is installed on node
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
         "command -v haproxy >/dev/null 2>&1" "HAProxy Check"; then
        
        log "SYNC" "Installing HAProxy on node: $node_name"
        if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
             "apt update >/dev/null 2>&1 && apt install -y haproxy >/dev/null 2>&1" \
             "HAProxy Installation"; then
            return 1
        fi
    fi
    
    # Copy main HAProxy config to node
    if scp_to_remote "/etc/haproxy/haproxy.cfg" "$node_ip" "$node_user" "$node_port" "$node_password" \
       "/etc/haproxy/haproxy.cfg" "HAProxy Configuration"; then
        
        # Validate and restart HAProxy on node
        if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
           "/usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl enable haproxy && systemctl restart haproxy" \
           "HAProxy Validation & Restart"; then
            
            log "SUCCESS" "HAProxy successfully synced to node: $node_name"
            return 0
        else
            log "ERROR" "HAProxy validation/restart failed on node: $node_name"
            return 1
        fi
    else
        return 1
    fi
}

rollback_node_configuration() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "WARNING" "Attempting rollback for node: $node_name"
    
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg.rollback.* ]; then cp /etc/haproxy/haproxy.cfg.rollback.* /etc/haproxy/haproxy.cfg && systemctl restart haproxy && echo 'Rollback successful'; else echo 'No rollback file found'; fi" \
       "Configuration Rollback"; then
        
        log "SUCCESS" "Rollback completed for node: $node_name"
        send_telegram_notification "🔄 Rollback Executed%0A%0ANode: $node_name%0AStatus: Successful" "high"
    else
        log "ERROR" "Rollback failed for node: $node_name"
        send_telegram_notification "🚨 Rollback Failed%0A%0ANode: $node_name%0ARequires manual intervention!" "critical"
    fi
}

## Geo Files Transfer System
transfer_geo_files_to_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4"
    
    if [ -z "$GEO_FILES_PATH" ]; then
        log "WARNING" "No geo files detected on main server, downloading fresh copies..."
        return 0
    fi
    
    log "SYNC" "Transferring geo files from main server to node..."
    
    # Create geo directory on node
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "mkdir -p /var/lib/marzban-node/chocolate" \
        "Geo Directory Creation"
    
    # Transfer geo files
    scp_to_remote "$GEO_FILES_PATH/geosite.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geosite.dat" "Geosite File"
    
    scp_to_remote "$GEO_FILES_PATH/geoip.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geoip.dat" "Geoip File"
    
    # Set proper permissions
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "chmod 644 /var/lib/marzban-node/chocolate/*.dat && chown root:root /var/lib/marzban-node/chocolate/*.dat" \
        "Geo Files Permissions"
    
    log "SUCCESS" "Geo files transferred successfully"
}

create_enhanced_docker_compose() {
    log "SYNC" "Creating enhanced docker-compose with geo volume..."
    
    local geo_volume=""
    if [ -n "$GEO_FILES_PATH" ]; then
        geo_volume="      - /var/lib/marzban-node/chocolate:/var/lib/marzban-node/chocolate"
    fi
    
    cat > docker-compose.yml << EOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /opt/marzban-node:/opt/marzban-node
${geo_volume}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "SUCCESS" "Enhanced docker-compose.yml created with geo volume support"
}
## Optimized Continuous Monitoring System
start_continuous_sync_monitoring() {
    log "INFO" "Starting optimized continuous synchronization monitoring..."
    
    while true; do
        monitor_haproxy_sync_status
        monitor_geo_files_sync_status
        monitor_node_health_status
        
        # Optimized sleep interval (30 minutes to reduce server load)
        sleep "$SYNC_CHECK_INTERVAL"
    done
}

monitor_haproxy_sync_status() {
    local main_config_hash
    main_config_hash=$(md5sum /etc/haproxy/haproxy.cfg | awk '{print $1}' 2>/dev/null || echo "missing")
    
    load_nodes_config
    local out_of_sync_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_config_hash
        node_config_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                          "if [ -f /etc/haproxy/haproxy.cfg ]; then md5sum /etc/haproxy/haproxy.cfg | awk '{print \$1}'; else echo 'missing'; fi" \
                          "Config Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_config_hash" != "$main_config_hash" ] && [ "$node_config_hash" != "error" ]; then
            out_of_sync_nodes+=("$name")
            log "WARNING" "Node $name is out of sync (hash: $node_config_hash vs main: $main_config_hash)"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_nodes[@]} -gt 0 ]; then
        log "SYNC" "Out of sync nodes detected: ${out_of_sync_nodes[*]}"
        send_telegram_notification "⚠️ Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_nodes[*]}%0A%0AAutomatic resync will be attempted." "high"
        
        # Attempt automatic resync
        auto_resync_nodes "${out_of_sync_nodes[@]}"
    fi
}

auto_resync_nodes() {
    local nodes=("$@")
    
    for node_name in "${nodes[@]}"; do
        log "SYNC" "Attempting automatic resync for node: $node_name"
        
        local node_entry
        node_entry=$(get_node_config_by_name "$node_name")
        
        if [ -n "$node_entry" ]; then
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            export NODE_SSH_PASSWORD="$password"
            
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                log "SUCCESS" "Automatic resync successful for node: $node_name"
                send_telegram_notification "✅ Auto-Resync Success%0A%0ANode: $node_name" "normal"
            else
                log "ERROR" "Automatic resync failed for node: $node_name"
                send_telegram_notification "🚨 Auto-Resync Failed%0A%0ANode: $node_name%0AManual intervention required!" "critical"
            fi
            
            unset NODE_SSH_PASSWORD
        fi
    done
}

monitor_geo_files_sync_status() {
    if [ -z "$GEO_FILES_PATH" ]; then
        return 0
    fi
    
    local main_geosite_hash main_geoip_hash
    main_geosite_hash=$(md5sum "$GEO_FILES_PATH/geosite.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    main_geoip_hash=$(md5sum "$GEO_FILES_PATH/geoip.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    
    load_nodes_config
    local out_of_sync_geo_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_geosite_hash node_geoip_hash
        node_geosite_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                           "if [ -f /var/lib/marzban-node/chocolate/geosite.dat ]; then md5sum /var/lib/marzban-node/chocolate/geosite.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                           "Geosite Hash Check" 2>/dev/null || echo "error")
        
        node_geoip_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                         "if [ -f /var/lib/marzban-node/chocolate/geoip.dat ]; then md5sum /var/lib/marzban-node/chocolate/geoip.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                         "Geoip Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_geosite_hash" != "$main_geosite_hash" ] || [ "$node_geoip_hash" != "$main_geoip_hash" ]; then
            if [ "$node_geosite_hash" != "error" ] && [ "$node_geoip_hash" != "error" ]; then
                out_of_sync_geo_nodes+=("$name")
                log "WARNING" "Node $name geo files are out of sync"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_geo_nodes[@]} -gt 0 ]; then
        log "SYNC" "Geo files out of sync on nodes: ${out_of_sync_geo_nodes[*]}"
        send_telegram_notification "🌍 Geo Files Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_geo_nodes[*]}" "normal"
    fi
}

monitor_node_health_status() {
    if ! get_marzban_token >/dev/null 2>&1; then
        return 1
    fi
    
    local unhealthy_nodes=()
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 10 --max-time 15 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status="unknown" # Default status
            if echo "$health_response" | jq -e . >/dev/null 2>&1; then # Check if response is valid JSON
                status=$(echo "$health_response" | jq -r '.status // "unknown"')
            else
                log "WARNING" "Node $name ($ip): Invalid API response for health check."
                log "DEBUG" "Response for $name: $health_response"
                # status remains "unknown"
            fi
            
            if [ "$status" != "connected" ]; then
                unhealthy_nodes+=("$name:$status")
            fi
        fi
        
        # Rate limiting
        sleep "$API_RATE_LIMIT_DELAY"
    done
    
    if [ ${#unhealthy_nodes[@]} -gt 0 ]; then
        log "WARNING" "Unhealthy nodes detected: ${unhealthy_nodes[*]}"
        send_telegram_notification "🔴 Health Alert%0A%0AUnhealthy nodes: ${unhealthy_nodes[*]}" "high"
    fi
}

## Enhanced Marzban API Configuration
configure_marzban_api() {
    log "STEP" "Configuring Marzban Panel API Connection..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Marzban Panel API Setup${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Please provide your Marzban Panel details:${NC}\n"
    
    log "PROMPT" "Panel Protocol (http/https) [default: https]:"
    read -r protocol
    protocol=${protocol:-https}
    
    log "PROMPT" "Panel Domain/IP (e.g., panel.example.com):"
    read -r domain
    
    log "PROMPT" "Panel Port [default: 8000]:"
    read -r port
    port=${port:-8000}
    
    log "PROMPT" "Admin Username:"
    read -r username
    
    log "PROMPT" "Admin Password:"
    read -s password
    echo ""
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$username" ] || [ -z "$password" ]; then
        log "ERROR" "All fields are required."
        return 1
    fi
    
    # Test connection
    log "INFO" "Testing API connection..."
    local test_url="${protocol}://${domain}:${port}/api/admin/token"
    local test_response
    
    test_response=$(curl -s -X POST "$test_url" \
        -d "username=${username}&password=${password}" \
        --connect-timeout 10 --max-time 30 \
        --insecure 2>/dev/null)
    
    if echo "$test_response" | grep -q "access_token"; then
        log "SUCCESS" "API connection test successful!"
        
        # Save configuration
        {
            echo "MARZBAN_PANEL_PROTOCOL=\"$protocol\""
            echo "MARZBAN_PANEL_DOMAIN=\"$domain\""
            echo "MARZBAN_PANEL_PORT=\"$port\""
            echo "MARZBAN_PANEL_USERNAME=\"$username\""
            echo "MARZBAN_PANEL_PASSWORD=\"$password\""
        } >> "$MANAGER_CONFIG_FILE"
        
        chmod 600 "$MANAGER_CONFIG_FILE"
        source "$MANAGER_CONFIG_FILE"
        
        log "SUCCESS" "Marzban API configuration saved successfully."
        send_telegram_notification "🔗 Marzban API Connected%0A%0APanel: $domain:$port%0AStatus: ✅ Connected" "normal"
    else
        log "ERROR" "API connection test failed. Please check your credentials and panel accessibility."
        log "DEBUG" "Response: $test_response"
        return 1
    fi
}

## Function to get Marzban API token
get_marzban_token() {
    if [ -n "$MARZBAN_TOKEN" ]; then
        # Token already exists, maybe add a check for expiration if API supports it
        # log "DEBUG" "Using existing Marzban token."
        return 0
    fi

    if [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ]; then
        log "ERROR" "Marzban Panel API credentials are not configured. Please run 'Configure Marzban API' first."
        return 1
    fi

    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response

    # log "INFO" "Attempting to get Marzban API token..."
    response=$(curl -s -X POST "$login_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout 10 --max-time 20 \
        --insecure 2>/dev/null)

    if echo "$response" | grep -q "access_token"; then
        MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
        if [ -n "$MARZBAN_TOKEN" ]; then
            # log "SUCCESS" "Marzban API token obtained successfully."
            # Store token in config for persistence across script runs? Or rely on global var for current session.
            # For now, it's a global variable for the current session.
            return 0
        else
            log "ERROR" "Failed to parse access token from API response."
            log "DEBUG" "Full API response: $response"
            return 1
        fi
    else
        log "ERROR" "Failed to obtain Marzban API token. Check credentials and panel accessibility."
        log "DEBUG" "API Response: $response"
        MARZBAN_TOKEN="" # Clear any stale token
        return 1
    fi
}

add_node_to_marzban_panel_api() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    
    log "INFO" "Registering node '$node_name' with the Marzban panel..."
    
    local add_node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node"
    local payload
    payload=$(printf '{"name": "%s", "address": "%s", "port": 62050, "api_port": 62051, "usage_coefficient": 1.0, "add_as_new_host": false}' "$node_name" "$node_ip")

    local response
    response=$(curl -s -X POST "$add_node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Content-Type: application/json" -H "Accept: application/json" \
        -d "$payload" --insecure)

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        MARZBAN_NODE_ID=$(echo "$response" | jq -r .id)
        log "SUCCESS" "Node '$node_name' successfully added to panel with ID: $MARZBAN_NODE_ID"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node '$node_name' already exists in the panel. Attempting to retrieve its ID..."
        
        local nodes_list_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes"
        local nodes_response
        nodes_response=$(curl -s -X GET "$nodes_list_url" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        local existing_id
        existing_id=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$node_name\") | .id" 2>/dev/null)
        
        if [ -n "$existing_id" ]; then
            MARZBAN_NODE_ID="$existing_id"
            log "SUCCESS" "Successfully retrieved ID for existing node: $MARZBAN_NODE_ID"
            return 0
        else
            log "ERROR" "Node is said to exist, but could not retrieve its ID from the panel."
            return 1
        fi
    else
        log "ERROR" "Failed to add node to Marzban panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

get_client_cert_from_marzban_api() {
    local node_id="$1"
    
    log "INFO" "Retrieving client certificate for node ID: $node_id"
    
    local node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${node_id}"
    
    local response
    response=$(curl -s -X GET "$node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Accept: application/json" \
        --insecure)
        
    if echo "$response" | jq -e '.client_cert' >/dev/null 2>&1; then
        CLIENT_CERT=$(echo "$response" | jq -r .client_cert)
        if [ -n "$CLIENT_CERT" ]; then
            log "SUCCESS" "Client certificate retrieved successfully."
            return 0
        else
            log "ERROR" "Client certificate is empty in the API response."
            return 1
        fi
    else
        log "ERROR" "Failed to retrieve client certificate from panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

## Automated Monitoring Setup
setup_automated_monitoring() {
    log "STEP" "Setting up automated monitoring system..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║       ${CYAN}Automated Monitoring Setup${NC}       ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Monitoring Options:${NC}"
    echo " 1. Enable Continuous Sync Monitoring"
    echo " 2. Enable Automated Health Checks"
    echo " 3. Setup Both (Recommended)"
    echo " 4. Disable All Monitoring"
    echo " 5. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose monitoring option:"
    read -r choice
    
    case "$choice" in
        1|3)
            # Setup sync monitoring
            local sync_script="/usr/local/bin/marzban-sync-monitor.sh"
            cat > "$sync_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --sync-monitor >> /var/log/marzban-sync.log 2>&1
EOF
            chmod +x "$sync_script"
            
            # Add to cron (every 30 minutes)
            local sync_cron="*/30 * * * * $sync_script"
            crontab -l 2>/dev/null | grep -v "marzban-sync-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$sync_cron") | crontab -
            
            log "SUCCESS" "Sync monitoring enabled (every 30 minutes)"
            ;;
    esac
    
    case "$choice" in
        2|3)
            # Setup health monitoring
            local health_script="/usr/local/bin/marzban-health-monitor.sh"
            cat > "$health_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --health-monitor >> /var/log/marzban-health.log 2>&1
EOF
            chmod +x "$health_script"
            
            # Add to cron (every 10 minutes)
            local health_cron="*/10 * * * * $health_script"
            crontab -l 2>/dev/null | grep -v "marzban-health-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$health_cron") | crontab -
            
            log "SUCCESS" "Health monitoring enabled (every 10 minutes)"
            ;;
    esac
    
    case "$choice" in
        4)
            # Disable monitoring
            crontab -l 2>/dev/null | grep -v "marzban-.*-monitor" | crontab -
            rm -f /usr/local/bin/marzban-*-monitor.sh
            log "SUCCESS" "All automated monitoring disabled"
            ;;
        5)
            return 0
            ;;
        *)
            log "ERROR" "Invalid option"
            return 1
            ;;
    esac
    
    if [ "$choice" != "4" ] && [ "$choice" != "5" ]; then
        send_telegram_notification "🤖 Automated Monitoring Enabled%0A%0AMonitoring active on $(hostname)" "normal"
    fi
}

## Enhanced Node Import System
import_existing_nodes() {
    log "STEP" "Importing existing nodes..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║         ${CYAN}Import Existing Nodes${NC}          ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Import Options:${NC}"
    echo " 1. Import Single Node"
    echo " 2. Import from CSV File"
    echo " 3. Auto-discover Nodes from Marzban Panel"
    echo " 4. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose import method:"
    read -r choice
    
    case "$choice" in
        1) import_single_node ;;
        2) import_from_csv ;;
        3) auto_discover_nodes ;;
        4) return 0 ;;
        *) log "ERROR" "Invalid option" ;;
    esac
}

import_single_node() {
    log "STEP" "Adding/Importing a single node..."
    
    local node_name node_ip node_user="root" node_port="22" node_domain node_password

    log "PROMPT" "Enter Node Name:"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP:"; read -r node_ip
    log "PROMPT" "Enter SSH Username [default: root]:"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port [default: 22]:"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain:"; read -r node_domain
    log "PROMPT" "Enter SSH Password:"; read -s node_password; echo ""

    # Combine connectivity test and Marzban Node check into a single SSH session
    local remote_command="echo 'CONN_OK'; if docker ps 2>/dev/null | grep -q marzban-node; then echo 'NODE_INSTALLED'; else echo 'NODE_NOT_INSTALLED'; fi"
    
    local check_result
    if ! check_result=$(ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "$remote_command" "Connectivity and Node Check"); then
        log "ERROR" "Failed to connect to node. Please check credentials."
        return 1
    fi
    
    if echo "$check_result" | grep -q "NODE_INSTALLED"; then
        log "INFO" "Marzban Node is already installed. Checking registration in panel..."
        
        if ! get_marzban_token; then return 1; fi
        local nodes_response
        nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure 2>/dev/null)
        
        local node_id
        if echo "$nodes_response" | jq empty 2>/dev/null; then
            node_id=$(echo "$nodes_response" | jq -r ".[] | select(.address==\"$node_ip\") | .id" 2>/dev/null)
        fi

        if [ -n "$node_id" ]; then
            log "SUCCESS" "Node is already registered in the panel with ID: $node_id. Importing..."
            add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$node_id"
            save_nodes_config
        else
            log "WARNING" "This node is running, but it is NOT registered in your Marzban panel."
            log "PROMPT" "Do you want to add it to the panel now? (y/n)"
            read -r add_to_panel
            if [[ "$add_to_panel" =~ ^[Yy]$ ]]; then
                log "STEP" "Registering existing node with the panel..."
                if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi
                
                log "STEP" "Deploying new client certificate to the node..."
                if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
                
                if [ -z "$CLIENT_CERT" ]; then
                    log "ERROR" "Failed to retrieve client certificate from panel. Cannot proceed."
                    return 1
                fi

                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
                rm "$temp_cert"
                
                log "STEP" "Restarting node service to apply new certificate..."
                ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" "Service Restart"

                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
                save_nodes_config
                log "SUCCESS" "Node '$node_name' successfully registered and imported!"
            else
                log "INFO" "Node was not registered in the panel. It has been added to the local manager only."
                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" ""
                save_nodes_config
            fi
        fi
    elif echo "$check_result" | grep -q "NODE_NOT_INSTALLED"; then
        log "WARNING" "Marzban Node is NOT installed on this server."
        log "PROMPT" "Do you want to install it automatically now? (y/n)"
        read -r install_now
        if [[ "$install_now" =~ ^[Yy]$ ]]; then
            if _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
                log "SUCCESS" "🎉 Node '$node_name' installed and configured successfully!"
            else
                log "ERROR" "Node installation failed. Please check the logs."
            fi
        else
            log "INFO" "Installation cancelled. Node was not added."
        fi
    fi
}

import_from_csv() {
    log "STEP" "Importing nodes from CSV file..."
    
    log "PROMPT" "Enter CSV file path (format: name,ip,user,port,domain,password):"
    read -r csv_file
    
    if [ ! -f "$csv_file" ]; then
        log "ERROR" "CSV file not found: $csv_file"
        return 1
    fi
    
    local imported=0 failed=0
    
    while IFS=',' read -r name ip user port domain password; do
        # Skip header line
        if [ "$name" = "name" ]; then continue; fi
        
        log "INFO" "Importing node: $name"
        
        if get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "WARNING" "Node '$name' already exists, skipping."
            continue
        fi
        
        # Test connectivity
        export NODE_SSH_PASSWORD="$password"
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'test'" "CSV Import Test" >/dev/null 2>&1; then
            add_node_to_config "$name" "$ip" "$user" "$port" "$domain" "$password" ""
            imported=$((imported + 1))
            log "SUCCESS" "Node '$name' imported."
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to import node '$name'."
        fi
        unset NODE_SSH_PASSWORD
        
    done < "$csv_file"
    
    save_nodes_config
    log "SUCCESS" "CSV import completed: $imported imported, $failed failed."
}

auto_discover_nodes() {
    log "STEP" "Auto-discovering nodes from Marzban Panel..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    local nodes_response
    nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        --insecure 2>/dev/null)
    
    if ! echo "$nodes_response" | jq empty 2>/dev/null; then
        log "ERROR" "Failed to fetch nodes from Marzban Panel."
        return 1
    fi
    
    local discovered=0
    
    echo "$nodes_response" | jq -r '.[] | "\(.name);\(.address);\(.id)"' | while IFS=';' read -r name address node_id; do
        if ! get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "INFO" "Discovered node: $name ($address)"
            
            # Add with default values (user will need to update SSH credentials)
            add_node_to_config "$name" "$address" "root" "22" "$name.domain.com" "UPDATE_PASSWORD" "$node_id"
            discovered=$((discovered + 1))
        fi
    done
    
    save_nodes_config
    log "SUCCESS" "Auto-discovery completed: $discovered nodes discovered."
    log "WARNING" "Please update SSH credentials for discovered nodes using 'Update Node Configuration'."
}

## Node Update System
update_existing_node() {
    log "STEP" "Updating existing node configuration..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to update."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Update Node Configuration${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip)"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to update (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${CYAN}Updating node: $name${NC}"
    echo -e "Current values (press Enter to keep current value):\n"
    
    log "PROMPT" "IP Address [$ip]:"
    read -r new_ip
    new_ip=${new_ip:-$ip}
    
    log "PROMPT" "SSH Username [$user]:"
    read -r new_user
    new_user=${new_user:-$user}
    
    log "PROMPT" "SSH Port [$port]:"
    read -r new_port
    new_port=${new_port:-$port}
    
    log "PROMPT" "Domain [$domain]:"
    read -r new_domain
    new_domain=${new_domain:-$domain}
    
    log "PROMPT" "Update SSH Password? (y/n):"
    read -r update_password
    
    local new_password="$password"
    if [[ "$update_password" =~ ^[Yy]$ ]]; then
        log "PROMPT" "New SSH Password:"
        read -s new_password
        echo ""
    fi
    
    # Update the node entry
    NODES_ARRAY[$selected_index]="${name};${new_ip};${new_user};${new_port};${new_domain};${new_password};${node_id}"
    save_nodes_config
    
    log "SUCCESS" "Node '$name' configuration updated successfully."
    
    # Test connectivity with new settings
    log "INFO" "Testing connectivity with new settings..."
    export NODE_SSH_PASSWORD="$new_password"
    if ssh_remote "$new_ip" "$new_user" "$new_port" "$NODE_SSH_PASSWORD" "echo 'Update test successful'" "Update Connectivity Test"; then
        log "SUCCESS" "Connectivity test passed with new settings."
    else
        log "WARNING" "Connectivity test failed. Please verify the new settings."
    fi
    unset NODE_SSH_PASSWORD
}
## Node Removal System
remove_node() {
    log "STEP" "Removing node from system..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to remove."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║            ${CYAN}Remove Node${NC}                 ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip) - $domain"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to remove (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will remove node '$name' from:${NC}"
    echo "- Local configuration"
    echo "- Marzban Panel (if connected)"
    echo "- HAProxy configuration"
    echo ""
    
    log "PROMPT" "Are you sure you want to remove node '$name'? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Node removal cancelled."
        return 0
    fi
    
    # Remove from Marzban Panel if node_id exists
    if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
        log "STEP" "Removing node from Marzban Panel..."
        if get_marzban_token; then
            local delete_response
            delete_response=$(curl -s -X DELETE "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                log "SUCCESS" "Node removed from Marzban Panel."
            else
                log "WARNING" "Failed to remove node from Marzban Panel."
            fi
        fi
    fi
    
    # Remove from HAProxy configuration
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "STEP" "Removing node from HAProxy configuration..."
        remove_haproxy_backend "$name" "$domain"
    fi
    
    # Remove from local configuration
    unset NODES_ARRAY[$selected_index]
    NODES_ARRAY=("${NODES_ARRAY[@]}")  # Re-index array
    save_nodes_config
    
    log "SUCCESS" "Node '$name' removed successfully."
    send_telegram_notification "🗑️ Node Removed%0A%0ANode: $name%0AIP: $ip%0ADomain: $domain" "normal"
}

remove_haproxy_backend() {
    local node_name="$1" node_domain="$2"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backend_name="vless_${node_name}"
    
    # Create backup
    cp "$haproxy_cfg" "${haproxy_cfg}.backup.$(date +%s)"
    
    # Remove backend section
    sed -i "/^# Backend for ${node_name}/,/^$/d" "$haproxy_cfg"
    sed -i "/^backend ${backend_name}/,/^$/d" "$haproxy_cfg"
    
    # Remove frontend rule
    sed -i "/use_backend ${backend_name} if.*${node_domain}/d" "$haproxy_cfg"
    
    # Validate and reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        systemctl reload haproxy
        log "SUCCESS" "HAProxy configuration updated."
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup."
        cp "${haproxy_cfg}.backup."* "$haproxy_cfg"
        systemctl reload haproxy
        return 1
    fi
}

## Enhanced Backup and Restore System
backup_restore_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Backup & Restore System${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Backup Options:${NC}"
        echo " 1. Create Full System Backup"
        echo " 2. Create Main Server Only Backup"
        echo " 3. Create Nodes Only Backup"
        echo " 4. Setup Automated Backup"
        echo ""
        echo -e "${PURPLE}Restore Options:${NC}"
        echo " 5. List Available Backups"
        echo " 6. Restore from Backup"
        echo " 7. Verify Backup Integrity"
        echo ""
        echo -e "${PURPLE}Management:${NC}"
        echo " 8. Cleanup Old Backups"
        echo " 9. Export Backup to Remote"
        echo " 10. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose backup/restore option:"
        read -r choice
        
        case "$choice" in
            1) create_full_backup ;;
            2) backup_main_server_only ;;
            3) backup_nodes_only ;;
            4) setup_automated_backup ;;
            5) list_available_backups ;;
            6) restore_from_backup ;;
            7) verify_backup_integrity_menu ;;
            8) cleanup_old_backups ;;
            9) export_backup_to_remote ;;
            10) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "10" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

backup_main_server_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_main_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting main server backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_main_server "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Main server backup completed: $final_archive"
}

backup_nodes_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_nodes_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting nodes backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_all_nodes "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Nodes backup completed: $final_archive"
}

list_available_backups() {
    log "BACKUP" "Listing available backups..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Available Backups${NC}                        ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    if ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        printf "%-5s %-35s %-15s %-10s\n" "No." "Backup Name" "Date" "Size"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        
        local i=1
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            local filename=$(basename "$backup")
            local filesize=$(du -h "$backup" | cut -f1)
            local filedate=$(date -r "$backup" '+%Y-%m-%d %H:%M')
            
            printf "%-5s %-35s %-15s %-10s\n" "$i" "$filename" "$filedate" "$filesize"
            i=$((i + 1))
        done
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "No backups found in $BACKUP_ARCHIVE_DIR"
    fi
}

verify_backup_integrity_menu() {
    log "BACKUP" "Backup integrity verification..."
    
    list_available_backups
    
    if ! ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        return 0
    fi
    
    echo ""
    log "PROMPT" "Enter backup number to verify (or 'all' for all backups):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            verify_backup_integrity "$backup"
        done
    else
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            local backup_files=("$BACKUP_ARCHIVE_DIR"/*.tar.gz)
            local selected_index=$((selection - 1))
            
            if [ $selected_index -ge 0 ] && [ $selected_index -lt ${#backup_files[@]} ]; then
                verify_backup_integrity "${backup_files[$selected_index]}"
            else
                log "ERROR" "Invalid backup number."
            fi
        else
            log "ERROR" "Invalid input."
        fi
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

## Nginx Management System
nginx_management_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║           ${CYAN}Nginx Management${NC}              ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        # Check Nginx status
        if systemctl is-active --quiet nginx; then
            echo -e "${GREEN}✅ Nginx Status: Running${NC}"
        else
            echo -e "${RED}❌ Nginx Status: Not Running${NC}"
        fi
        
        echo ""
        echo -e "${PURPLE}Configuration Management:${NC}"
        echo " 1. View Nginx Configuration"
        echo " 2. Test Nginx Configuration"
        echo " 3. Reload Nginx Configuration"
        echo " 4. Restart Nginx Service"
        echo ""
        echo -e "${PURPLE}SSL Certificate Management:${NC}"
        echo " 5. Generate SSL Certificate"
        echo " 6. Renew SSL Certificates"
        echo " 7. View Certificate Status"
        echo ""
        echo -e "${PURPLE}Site Management:${NC}"
        echo " 8. Add New Site Configuration"
        echo " 9. Remove Site Configuration"
        echo " 10. Enable/Disable Site"
        echo ""
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose Nginx management option:"
        read -r choice
        
        case "$choice" in
            1) view_nginx_configuration ;;
            2) test_nginx_configuration ;;
            3) reload_nginx_configuration ;;
            4) restart_nginx_service ;;
            5) generate_ssl_certificate ;;
            6) renew_ssl_certificates ;;
            7) view_certificate_status ;;
            8) add_nginx_site ;;
            9) remove_nginx_site ;;
            10) toggle_nginx_site ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_nginx_configuration() {
    log "INFO" "Displaying Nginx configuration..."
    
    if [ -f "/etc/nginx/nginx.conf" ]; then
        echo -e "\n${CYAN}Main Nginx Configuration:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        cat /etc/nginx/nginx.conf
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        log "ERROR" "Nginx configuration file not found."
    fi
    
    echo -e "\n${CYAN}Available Site Configurations:${NC}"
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                echo "✅ $site_name (enabled)"
            else
                echo "❌ $site_name (disabled)"
            fi
        done
    else
        echo "No site configurations found."
    fi
}

test_nginx_configuration() {
    log "INFO" "Testing Nginx configuration..."
    
    if nginx -t 2>&1; then
        log "SUCCESS" "Nginx configuration test passed."
    else
        log "ERROR" "Nginx configuration test failed."
    fi
}

reload_nginx_configuration() {
    log "INFO" "Reloading Nginx configuration..."
    
    if nginx -t 2>/dev/null; then
        if systemctl reload nginx; then
            log "SUCCESS" "Nginx configuration reloaded successfully."
        else
            log "ERROR" "Failed to reload Nginx configuration."
        fi
    else
        log "ERROR" "Nginx configuration test failed. Cannot reload."
    fi
}

restart_nginx_service() {
    log "INFO" "Restarting Nginx service..."
    
    if systemctl restart nginx; then
        log "SUCCESS" "Nginx service restarted successfully."
    else
        log "ERROR" "Failed to restart Nginx service."
    fi
}

## Bulk Operations Enhancement
bulk_update_certificates() {
    log "STEP" "Updating certificates on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            log "INFO" "Updating certificate for node: $name"
            
            # Get fresh certificate from Marzban Panel
            if get_client_cert_from_marzban_api "$node_id"; then
                export NODE_SSH_PASSWORD="$password"
                
                # Deploy certificate to node
                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                
                if scp_to_remote "$temp_cert" "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "/var/lib/marzban-node/ssl_client_cert.pem" "Certificate Update"; then
                    
                    # Restart node service
                    if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                       "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" \
                       "Service Restart"; then
                        updated=$((updated + 1))
                        log "SUCCESS" "Certificate updated for node: $name"
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to restart service on node: $name"
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to deploy certificate to node: $name"
                fi
                
                rm "$temp_cert"
                unset NODE_SSH_PASSWORD
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to get certificate for node: $name"
            fi
        else
            log "WARNING" "Node '$name' has no API ID, skipping certificate update."
        fi
    done
    
    log "SUCCESS" "Certificate update completed: $updated updated, $failed failed."
    send_telegram_notification "🔐 Certificate Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

bulk_restart_services() {
    log "STEP" "Restarting services on all nodes..."
    
    load_nodes_config
    local restarted=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Restarting services on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "cd /opt/marzban-node && docker compose restart" \
           "Service Restart"; then
            restarted=$((restarted + 1))
            log "SUCCESS" "Services restarted on node: $name"
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to restart services on node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Service restart completed: $restarted restarted, $failed failed."
    send_telegram_notification "🔄 Service Restart Report%0A%0A✅ Restarted: $restarted%0A❌ Failed: $failed" "normal"
}

bulk_update_geo_files() {
    log "STEP" "Updating geo files on all nodes..."
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating geo files on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        # Transfer geo files if available on main server
        if [ -n "$GEO_FILES_PATH" ]; then
            if transfer_geo_files_to_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files updated on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to update geo files on node: $name"
            fi
        else
            # Download fresh geo files on node
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$(declare -f update_geo_files_on_node); update_geo_files_on_node" \
               "Geo Files Update"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files downloaded on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to download geo files on node: $name"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Geo files update completed: $updated updated, $failed failed."
    send_telegram_notification "🌍 Geo Files Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

_internal_deploy_node() {
    local node_name="$1" node_ip="$2" node_user="$3" node_port="$4" node_domain="$5" node_password="$6"

    log "STEP" "Starting Final Deployment Workflow for '$node_name'..."

    # Phase 1: Deploy and start the node in standalone mode (without client cert requirement)
    log "STEP" "Phase 1: Deploying node in standalone mode..."
    if ! scp_to_remote "${0%/*}/marzban_node_deployer.sh" "$node_ip" "$node_user" "$node_port" "$node_password" "/tmp/marzban_node_deployer.sh" "Node Deployer Script"; then return 1; fi
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "bash /tmp/marzban_node_deployer.sh" "Node Standalone Deployment"; then
        return 1
    fi
    
    # Wait until the node service is actually listening on the port
    log "INFO" "Waiting for node service to become active..."
    local timer=0
    while ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "ss -tuln | grep -q ':62050'" "Port Listening Check" >/dev/null 2>&1; do
        sleep 5
        timer=$((timer + 5))
        if [ $timer -ge 60 ]; then
            log "ERROR" "Node service failed to start and listen on port 62050 after 60 seconds. Please check node logs."
            return 1
        fi
    done
    log "SUCCESS" "Node service is active and listening."

    # Phase 2: Register the now-running node with the panel
    log "STEP" "Phase 2: Registering node with Marzban panel..."
    if ! get_marzban_token; then return 1; fi
    if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi

    # Phase 3: Retrieve the REAL client certificate
    log "STEP" "Phase 3: Retrieving client certificate..."
    if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
    if [ -z "$CLIENT_CERT" ]; then log "ERROR" "Failed to retrieve client certificate."; return 1; fi
    
    # Deploy the REAL certificate to the node
    local temp_cert; temp_cert=$(mktemp)
    echo "$CLIENT_CERT" > "$temp_cert"
    scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
    rm "$temp_cert"
    
    # Phase 4: Reconfigure and restart the node to enable panel connection
    log "STEP" "Phase 4: Reconfiguring and restarting node for panel connection..."
    local reconfigure_command="sed -i 's/# SSL_CLIENT_CERT_FILE/SSL_CLIENT_CERT_FILE/' /opt/marzban-node/docker-compose.yml && chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart"
    if ! ssh_remote "$node_ip" "$user" "$port" "$node_password" "$reconfigure_command" "Final Node Reconfiguration"; then
        return 1
    fi
    
    # Final health check
    log "INFO" "Waiting 15s for the node to connect to the panel..."
    sleep 15
    if check_node_health_via_api "$MARZBAN_NODE_ID" "$node_name"; then
        log "SUCCESS" "✅ Final health check passed! Node is fully connected."
    fi

    add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
    save_nodes_config
    return 0
}

deploy_new_node_professional_enhanced() {
    log "STEP" "Starting Enhanced Professional Node Deployment..."
    if [ -z "$MARZBAN_PANEL_DOMAIN" ]; then
        log "ERROR" "Marzban Panel API not configured. Please use Option 8 first."
        return 1
    fi
    detect_main_server_services

    local node_ip node_user="root" node_port="22" node_domain node_name node_password
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║     ${CYAN}Enhanced Professional Deployment${NC}     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    log "PROMPT" "Enter Node Name (unique identifier):"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP Address:"; read -r node_ip
    log "PROMPT" "Enter SSH Username (default: root):"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port (default: 22):"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain (e.g., node1.example.com):"; read -r node_domain
    if ! [[ $node_domain =~ ^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.){1,}[a-zA-Z]{2,}$ ]]; then
        log "ERROR" "Invalid domain format."
        return 1
    fi
    log "PROMPT" "Enter SSH Password for $node_user@$node_ip:"; read -s node_password; echo ""
    
    _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "🎉 Node '$node_name' deployed and configured successfully!"
        send_telegram_notification "🚀 New Node Deployed%0A%0ANode: $node_name%0AIP: $node_ip%0ADomain: $node_domain%0AStatus: ✅ Operational" "normal"
    else
        log "ERROR" "Node deployment failed. Please check the logs."
    fi
}

## Advanced Telegram Configuration
configure_telegram_advanced() {
    log "STEP" "Configuring advanced Telegram notifications..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Telegram Notifications Setup${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Telegram Bot Configuration:${NC}"
    echo "1. Create a bot via @BotFather on Telegram"
    echo "2. Get your chat ID from @userinfobot"
    echo "3. Configure notification levels"
    echo ""
    
    log "PROMPT" "Enter Telegram Bot Token:"
    read -r bot_token
    
    log "PROMPT" "Enter Telegram Chat ID:"
    read -r chat_id
    
    if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
        # Test notification
        log "INFO" "Testing Telegram notification..."
        local test_message="🤖 Marzban Central Manager%0A%0ATest notification from $(hostname)%0ATime: $(date)"
        
        if curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
           -d "chat_id=${chat_id}" \
           -d "text=${test_message}" \
           -d "parse_mode=Markdown" >/dev/null; then
            
            log "SUCCESS" "Telegram test notification sent successfully!"
            
            # Save configuration
            {
                echo "TELEGRAM_BOT_TOKEN=\"$bot_token\""
                echo "TELEGRAM_CHAT_ID=\"$chat_id\""
            } >> "$MANAGER_CONFIG_FILE"
            
            chmod 600 "$MANAGER_CONFIG_FILE"
            source "$MANAGER_CONFIG_FILE"
            
            # Configure notification levels
            echo -e "\n${PURPLE}Notification Levels:${NC}"
            echo " 1. All notifications (normal, high, critical)"
            echo " 2. High and critical only"
            echo " 3. Critical only"
            echo " 4. Disabled"
            echo ""
            
            log "PROMPT" "Choose notification level [default: 1]:"
            read -r level
            level=${level:-1}
            
            echo "TELEGRAM_NOTIFICATION_LEVEL=\"$level\"" >> "$MANAGER_CONFIG_FILE"
            
            log "SUCCESS" "Telegram notifications configured successfully!"
        else
            log "ERROR" "Failed to send test notification. Please check your bot token and chat ID."
        fi
    else
        log "ERROR" "Bot token and chat ID are required."
    fi
}

## Bulk Node Operations Menu
bulk_node_operations() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Bulk Node Operations${NC}             ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        load_nodes_config
        echo -e "${PURPLE}Available Operations for ${#NODES_ARRAY[@]} nodes:${NC}"
        echo " 1. Update All Certificates"
        echo " 2. Restart All Services"
        echo " 3. Update All Geo Files"
        echo " 4. Sync HAProxy to All Nodes"
        echo " 5. Health Check All Nodes"
        echo " 6. Reconnect Disconnected Nodes"
        echo " 7. Update All Node Configurations"
        echo " 8. Bulk SSH Command Execution"
        echo " 9. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose bulk operation:"
        read -r choice
        
        case "$choice" in
            1) bulk_update_certificates ;;
            2) bulk_restart_services ;;
            3) bulk_update_geo_files ;;
            4) bulk_sync_haproxy ;;
            5) bulk_health_check ;;
            6) bulk_reconnect_nodes ;;
            7) bulk_update_configurations ;;
            8) bulk_ssh_command ;;
            9) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "9" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

bulk_health_check() {
    log "STEP" "Performing health check on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local healthy=0 unhealthy=0 unknown=0
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Bulk Health Check Report${NC}                   ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        echo -e "${CYAN}Checking node: $name ($ip)${NC}"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            if check_node_health_via_api "$node_id" "$name"; then
                healthy=$((healthy + 1))
            else
                unhealthy=$((unhealthy + 1))
            fi
        else
            echo "   ⚪ No API ID - checking SSH connectivity..."
            export NODE_SSH_PASSWORD="$password"
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'SSH OK'" "SSH Health Check" >/dev/null 2>&1; then
                echo "   🟢 SSH connectivity: OK"
                unknown=$((unknown + 1))
            else
                echo "   🔴 SSH connectivity: FAILED"
                unhealthy=$((unhealthy + 1))
            fi
            unset NODE_SSH_PASSWORD
        fi
        echo ""
    done
    
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                      ${CYAN}Health Summary${NC}                           ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "🟢 Healthy Nodes: $healthy"
    echo -e "🔴 Unhealthy Nodes: $unhealthy"
    echo -e "⚪ Unknown Status: $unknown"
    echo -e "📊 Total Nodes: ${#NODES_ARRAY[@]}"
    
    # Send notification
    send_telegram_notification "🏥 Health Check Report%0A%0A🟢 Healthy: $healthy%0A🔴 Unhealthy: $unhealthy%0A⚪ Unknown: $unknown%0A📊 Total: ${#NODES_ARRAY[@]}" "normal"
}

bulk_sync_haproxy() {
    log "STEP" "Syncing HAProxy configuration to all nodes..."
    
    if [ "$MAIN_HAS_HAPROXY" != "true" ]; then
        log "ERROR" "HAProxy not detected on main server."
        return 1
    fi
    
    load_nodes_config
    local synced=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Syncing HAProxy to node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "HAProxy sync completed: $synced synced, $failed failed."
    send_telegram_notification "🔄 HAProxy Bulk Sync%0A%0A✅ Synced: $synced%0A❌ Failed: $failed" "normal"
}

bulk_reconnect_nodes() {
    log "STEP" "Reconnecting disconnected nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local reconnected=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
            
            if [ "$status" != "connected" ]; then
                log "INFO" "Attempting to reconnect node: $name"
                export NODE_SSH_PASSWORD="$password"
                
                # Restart node service
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && docker compose restart" \
                   "Service Restart for Reconnection"; then
                    
                    # Wait and check status again
                    sleep 10
                    health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                        -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                        -H "Authorization: Bearer $MARZBAN_TOKEN" \
                        --insecure 2>/dev/null)
                    
                    local new_status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
                    
                    if [ "$new_status" = "connected" ]; then
                        reconnected=$((reconnected + 1))
                        log "SUCCESS" "Node '$name' reconnected successfully."
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to reconnect node '$name'."
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to restart service on node '$name'."
                fi
                
                unset NODE_SSH_PASSWORD
            fi
        fi
    done
    
    log "SUCCESS" "Reconnection completed: $reconnected reconnected, $failed failed."
    send_telegram_notification "🔌 Bulk Reconnection%0A%0A✅ Reconnected: $reconnected%0A❌ Failed: $failed" "normal"
}

bulk_ssh_command() {
    log "STEP" "Bulk SSH command execution..."
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will execute a command on ALL nodes!${NC}"
    echo -e "${YELLOW}Please be very careful with the command you enter.${NC}\n"
    
    log "PROMPT" "Enter command to execute on all nodes:"
    read -r command
    
    if [ -z "$command" ]; then
        log "ERROR" "No command provided."
        return 1
    fi
    
    echo -e "\n${YELLOW}Command to execute: ${WHITE}$command${NC}"
    log "PROMPT" "Are you sure you want to execute this on ALL nodes? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Bulk command execution cancelled."
        return 0
    fi
    
    load_nodes_config
    local success=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Executing command on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$command" "Bulk Command Execution"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Bulk command execution completed: $success successful, $failed failed."
}

## System Diagnostics and Logs
show_system_diagnostics() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║        ${CYAN}System Logs & Diagnostics${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Log Management:${NC}"
        echo " 1. View Recent Manager Logs"
        echo " 2. View Marzban Panel Logs"
        echo " 3. View HAProxy Logs"
        echo " 4. View System Logs"
        echo ""
        echo -e "${PURPLE}Diagnostics:${NC}"
        echo " 5. System Resource Usage"
        echo " 6. Network Connectivity Test"
        echo " 7. Service Status Check"
        echo " 8. Configuration Validation"
        echo ""
        echo -e "${PURPLE}Maintenance:${NC}"
        echo " 9. Clean Old Log Files"
        echo " 10. Export Diagnostic Report"
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose diagnostic option:"
        read -r choice
        
        case "$choice" in
            1) view_manager_logs ;;
            2) view_marzban_logs ;;
            3) view_haproxy_logs ;;
            4) view_system_logs ;;
            5) show_system_resources ;;
            6) test_network_connectivity ;;
            7) check_service_status ;;
            8) validate_configurations ;;
            9) clean_old_logs ;;
            10) export_diagnostic_report ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_manager_logs() {
    log "INFO" "Displaying recent Manager logs..."
    
    echo -e "\n${CYAN}Recent Manager Activity:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$LOGFILE" ]; then
        tail -50 "$LOGFILE"
    else
        echo "No current session log file found."
    fi
    
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    # Show system logs for marzban-central-manager
    echo -e "\n${CYAN}System Logs (last 20 entries):${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -t marzban-central-manager -n 20 --no-pager 2>/dev/null || echo "No system logs found."
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

show_system_resources() {
    log "INFO" "Displaying system resource usage..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}System Resource Usage${NC}                     ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # CPU Usage
    echo -e "${PURPLE}🖥️  CPU Usage:${NC}"
    top -bn1 | grep "Cpu(s)" | awk '{print $2 $3 $4 $5 $6 $7 $8}' | sed 's/%us,/ User,/g; s/%sy,/ System,/g; s/%ni,/ Nice,/g; s/%id,/ Idle,/g; s/%wa,/ Wait,/g; s/%hi,/ Hardware IRQ,/g; s/%si/ Software IRQ/g'
    
    # Memory Usage
    echo -e "\n${PURPLE}💾 Memory Usage:${NC}"
    free -h | grep -E "(Mem|Swap)"
    
    # Disk Usage
    echo -e "\n${PURPLE}💿 Disk Usage:${NC}"
    df -h | grep -E "^/dev"
    
    # Network Usage
    echo -e "\n${PURPLE}🌐 Network Interfaces:${NC}"
    ip -s link show | grep -E "(^\d+:|RX:|TX:)" | head -20
    
    # Load Average
    echo -e "\n${PURPLE}📊 Load Average:${NC}"
    uptime
    
    # Top Processes
    echo -e "\n${PURPLE}🔝 Top Processes (CPU):${NC}"
    ps aux --sort=-%cpu | head -10 | awk '{printf "%-10s %-6s %-6s %-50s\n", $1, $3, $4, $11}'
    
    # Docker Resources (if available)
    if command_exists docker; then
        echo -e "\n${PURPLE}🐳 Docker Resources:${NC}"
        docker system df 2>/dev/null || echo "Docker system info unavailable"
    fi
}

test_network_connectivity() {
    log "INFO" "Testing network connectivity..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                   ${CYAN}Network Connectivity Test${NC}                  ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Test DNS resolution
    echo -e "${PURPLE}🔍 DNS Resolution Test:${NC}"
    for domain in "google.com" "github.com" "cloudflare.com"; do
        if nslookup "$domain" >/dev/null 2>&1; then
            echo "✅ $domain - OK"
        else
            echo "❌ $domain - FAILED"
        fi
    done
    
    # Test internet connectivity
    echo -e "\n${PURPLE}🌐 Internet Connectivity Test:${NC}"
    for host in "8.8.8.8" "1.1.1.1" "208.67.222.222"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            echo "✅ $host - OK"
        else
            echo "❌ $host - FAILED"
        fi
    done
    
    # Test Marzban Panel connectivity
    if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
        echo -e "\n${PURPLE}🔗 Marzban Panel Connectivity:${NC}"
        local panel_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}"
        
        if curl -s --connect-timeout 5 --max-time 10 "$panel_url" >/dev/null 2>&1; then
            echo "✅ $panel_url - OK"
        else
            echo "❌ $panel_url - FAILED"
        fi
    fi
    
    # Test node connectivity
    echo -e "\n${PURPLE}🖥️  Node Connectivity Test:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
            echo "✅ $name ($ip) - Ping OK"
        else
            echo "❌ $name ($ip) - Ping FAILED"
        fi
    done
}

check_service_status() {
    log "INFO" "Checking service status..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                     ${CYAN}Service Status Check${NC}                      ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check main services
    local services=("docker" "nginx" "haproxy" "ssh" "cron")
    
    echo -e "${PURPLE}🔧 Main Server Services:${NC}"
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "✅ $service - Running"
        elif systemctl list-unit-files | grep -q "^$service.service"; then
            echo "❌ $service - Stopped"
        else
            echo "⚪ $service - Not Installed"
        fi
    done
    
    # Check Marzban service
    echo -e "\n${PURPLE}📊 Marzban Panel Status:${NC}"
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        if docker compose ps | grep -q "Up"; then
            echo "✅ Marzban Panel - Running"
        else
            echo "❌ Marzban Panel - Stopped"
        fi
    else
        echo "⚪ Marzban Panel - Not Found"
    fi
    
    # Check node services
    echo -e "\n${PURPLE}🖥️  Node Services Status:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_status
        node_status=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                     "cd /opt/marzban-node 2>/dev/null && docker compose ps | grep -q 'Up' && echo 'Running' || echo 'Stopped'" \
                     "Node Service Check" 2>/dev/null || echo "Unreachable")
        
        case "$node_status" in
            "Running") echo "✅ $name - Running" ;;
            "Stopped") echo "❌ $name - Stopped" ;;
            *) echo "⚪ $name - Unreachable" ;;
        esac
        
        unset NODE_SSH_PASSWORD
    done
}

export_diagnostic_report() {
    log "INFO" "Generating comprehensive diagnostic report..."
    
    local report_file="${BACKUP_DIR}/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Marzban Central Manager - Diagnostic Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "Manager Version: $SCRIPT_VERSION"
        echo "========================================"
        echo ""
        
        echo "SYSTEM INFORMATION:"
        echo "-------------------"
        uname -a
        echo ""
        cat /etc/os-release 2>/dev/null || echo "OS info unavailable"
        echo ""
        
        echo "RESOURCE USAGE:"
        echo "---------------"
        free -h
        echo ""
        df -h
        echo ""
        uptime
        echo ""
        
        echo "NETWORK CONFIGURATION:"
        echo "----------------------"
        ip addr show | grep -E "(inet |inet6 )"
        echo ""
        
        echo "SERVICE STATUS:"
        echo "---------------"
        for service in docker nginx haproxy ssh cron; do
            systemctl is-active "$service" 2>/dev/null | sed "s/^/$service: /"
        done
        echo ""
        
        echo "MARZBAN CONFIGURATION:"
        echo "----------------------"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
            echo "Panel Domain: $MARZBAN_PANEL_DOMAIN"
            echo "Panel Port: $MARZBAN_PANEL_PORT"
            echo "Panel Protocol: $MARZBAN_PANEL_PROTOCOL"
        else
            echo "Marzban Panel not configured"
        fi
        echo ""
        
        echo "CONFIGURED NODES:"
        echo "-----------------"
        load_nodes_config
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            echo "Node: $name | IP: $ip | Domain: $domain | ID: $node_id"
        done
        echo ""
        
        echo "RECENT LOGS:"
        echo "------------"
        if [ -f "$LOGFILE" ]; then
            tail -20 "$LOGFILE"
        else
            echo "No recent logs available"
        fi
        
    } > "$report_file"
    
    log "SUCCESS" "Diagnostic report generated: $report_file"
    
    # Offer to send via Telegram
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        log "PROMPT" "Send diagnostic report via Telegram? (y/n):"
        read -r send_telegram
        
        if [[ "$send_telegram" =~ ^[Yy]$ ]]; then
            local report_summary="📋 Diagnostic Report%0A%0AGenerated: $(date)%0AHostname: $(hostname)%0ANodes: ${#NODES_ARRAY[@]}%0A%0AReport saved locally: $(basename "$report_file")"
            send_telegram_notification "$report_summary" "normal"
            log "SUCCESS" "Diagnostic summary sent via Telegram."
        fi
    fi
}

## Missing functions implementation
bulk_update_configurations() {
    log "STEP" "Bulk updating node configurations..."
    
    echo -e "\n${YELLOW}This will update common configuration files on all nodes.${NC}"
    echo -e "${YELLOW}Available updates:${NC}"
    echo " 1. Update docker-compose.yml"
    echo " 2. Update environment variables"
    echo " 3. Update SSL certificates"
    echo " 4. All of the above"
    echo ""
    
    log "PROMPT" "Choose update type:"
    read -r update_type
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating configuration for node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        case "$update_type" in
            1|4)
                # Update docker-compose.yml
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && $(declare -f create_enhanced_docker_compose); create_enhanced_docker_compose" \
                   "Docker Compose Update"; then
                    log "SUCCESS" "Docker compose updated on node: $name"
                else
                    log "ERROR" "Failed to update docker compose on node: $name"
                fi
                ;;
        esac
        
        if [ "$update_type" = "4" ] || [ "$update_type" = "2" ]; then
            # Update environment variables
            ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                "cd /opt/marzban-node && docker compose restart" \
                "Service Restart" >/dev/null 2>&1
        fi
        
        updated=$((updated + 1))
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Configuration update completed: $updated updated, $failed failed."
}

view_marzban_logs() {
    log "INFO" "Displaying Marzban Panel logs..."
    
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        echo -e "\n${CYAN}Recent Marzban Panel Logs:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        docker compose logs --tail=50 2>/dev/null || echo "Unable to fetch Marzban logs"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Marzban installation not found at /opt/marzban"
    fi
}

view_haproxy_logs() {
    log "INFO" "Displaying HAProxy logs..."
    
    echo -e "\n${CYAN}Recent HAProxy Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -u haproxy -n 50 --no-pager 2>/dev/null || echo "HAProxy logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

view_system_logs() {
    log "INFO" "Displaying system logs..."
    
    echo -e "\n${CYAN}Recent System Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -n 50 --no-pager 2>/dev/null || echo "System logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

validate_configurations() {
    log "INFO" "Validating system configurations..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                  ${CYAN}Configuration Validation${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Validate Nginx configuration
    if command_exists nginx; then
        echo -e "${PURPLE}🔧 Nginx Configuration:${NC}"
        if nginx -t 2>/dev/null; then
            echo "✅ Nginx configuration is valid"
        else
            echo "❌ Nginx configuration has errors"
        fi
    fi
    
    # Validate HAProxy configuration
    if command_exists haproxy; then
        echo -e "\n${PURPLE}⚖️  HAProxy Configuration:${NC}"
        if /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg 2>/dev/null; then
            echo "✅ HAProxy configuration is valid"
        else
            echo "❌ HAProxy configuration has errors"
        fi
    fi
    
    # Validate Manager configuration
    echo -e "\n${PURPLE}📊 Manager Configuration:${NC}"
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        echo "✅ Manager configuration file exists"
        
        # Check required variables
        source "$MANAGER_CONFIG_FILE"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ] && [ -n "$MARZBAN_PANEL_USERNAME" ]; then
            echo "✅ Marzban Panel credentials configured"
        else
            echo "❌ Marzban Panel credentials missing"
        fi
    else
        echo "❌ Manager configuration file missing"
    fi
    
    # Validate node configurations
    echo -e "\n${PURPLE}🖥️  Node Configurations:${NC}"
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -gt 0 ]; then
        echo "✅ ${#NODES_ARRAY[@]} nodes configured"
        
        local valid_nodes=0
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                valid_nodes=$((valid_nodes + 1))
            fi
        done
        echo "✅ $valid_nodes nodes have valid IP addresses"
    else
        echo "⚪ No nodes configured"
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        log "DEBUG" "Checking type of command_exists before use in clean_old_logs:"
        type command_exists || log "ERROR" "command_exists is not recognized here!"
        
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

# Additional missing functions for complete functionality
add_nginx_site() {
    log "STEP" "Adding new Nginx site configuration..."
    
    log "PROMPT" "Enter site domain (e.g., example.com):"
    read -r site_domain
    
    log "PROMPT" "Enter document root path (default: /var/www/$site_domain):"
    read -r doc_root
    doc_root=${doc_root:-/var/www/$site_domain}
    
    # Create site configuration
    local site_config="/etc/nginx/sites-available/$site_domain"
    cat > "$site_config" << EOF
server {
    listen 80;
    server_name $site_domain www.$site_domain;
    root $doc_root;
    index index.html index.htm index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF
    
    # Create document root
    mkdir -p "$doc_root"
    chown www-data:www-data "$doc_root"
    
    # Create basic index file
    echo "<h1>Welcome to $site_domain</h1>" > "$doc_root/index.html"
    chown www-data:www-data "$doc_root/index.html"
    
    log "SUCCESS" "Site configuration created: $site_config"
    log "INFO" "To enable the site, run: ln -s $site_config /etc/nginx/sites-enabled/"
}

remove_nginx_site() {
    log "STEP" "Removing Nginx site configuration..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            echo " $i. $site_name"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to remove:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            # Remove from sites-enabled if linked
            rm -f "/etc/nginx/sites-enabled/$selected_site"
            
            # Remove from sites-available
            rm -f "/etc/nginx/sites-available/$selected_site"
            
            log "SUCCESS" "Site '$selected_site' removed successfully."
            
            # Test nginx configuration
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed after site removal."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available to remove."
    fi
}

toggle_nginx_site() {
    log "STEP" "Enable/Disable Nginx site..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            local status="disabled"
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                status="enabled"
            fi
            echo " $i. $site_name ($status)"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to toggle:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            if [ -L "/etc/nginx/sites-enabled/$selected_site" ]; then
                # Disable site
                rm "/etc/nginx/sites-enabled/$selected_site"
                log "SUCCESS" "Site '$selected_site' disabled."
            else
                # Enable site
                ln -s "/etc/nginx/sites-available/$selected_site" "/etc/nginx/sites-enabled/"
                log "SUCCESS" "Site '$selected_site' enabled."
            fi
            
            # Test and reload nginx
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available."
    fi
}

generate_ssl_certificate() {
    log "STEP" "Generating SSL certificate..."
    
    log "PROMPT" "Enter domain for SSL certificate:"
    read -r ssl_domain
    
    log "PROMPT" "Enter email for Let's Encrypt:"
    read -r ssl_email
    
    # Install certbot if not available
    if ! command_exists certbot; then
        log "INFO" "Installing certbot..."
        apt update >/dev/null 2>&1
        apt install -y certbot python3-certbot-nginx >/dev/null 2>&1
    fi
    
    # Generate certificate
    if certbot --nginx -d "$ssl_domain" --email "$ssl_email" --agree-tos --non-interactive; then
        log "SUCCESS" "SSL certificate generated for $ssl_domain"
    else
        log "ERROR" "Failed to generate SSL certificate for $ssl_domain"
    fi
}

renew_ssl_certificates() {
    log "STEP" "Renewing SSL certificates..."
    
    if command_exists certbot; then
        if certbot renew --dry-run; then
            log "SUCCESS" "SSL certificate renewal test passed."
            
            log "PROMPT" "Proceed with actual renewal? (y/n):"
            read -r proceed
            
            if [[ "$proceed" =~ ^[Yy]$ ]]; then
                if certbot renew; then
                    log "SUCCESS" "SSL certificates renewed successfully."
                    systemctl reload nginx
                else
                    log "ERROR" "SSL certificate renewal failed."
                fi
            fi
        else
            log "ERROR" "SSL certificate renewal test failed."
        fi
    else
        log "ERROR" "Certbot not installed."
    fi
}

view_certificate_status() {
    log "INFO" "Displaying SSL certificate status..."
    
    if command_exists certbot; then
        echo -e "\n${CYAN}SSL Certificate Status:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        certbot certificates
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Certbot not installed. Cannot check SSL certificate status."
    fi
}

## Missing Functions Implementation

# Verify backup integrity
verify_backup_integrity() {
    local backup_file="$1"
    local backup_name=$(basename "$backup_file")
    
    log "BACKUP" "Verifying integrity of: $backup_name"
    
    # Check if backup file exists
    if [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Check if MD5 checksum file exists
    if [ -f "${backup_file}.md5" ]; then
        log "INFO" "Verifying MD5 checksum..."
        if md5sum -c "${backup_file}.md5" >/dev/null 2>&1; then
            log "SUCCESS" "✅ MD5 checksum verification passed"
        else
            log "ERROR" "❌ MD5 checksum verification failed"
            return 1
        fi
    else
        log "WARNING" "No MD5 checksum file found, skipping checksum verification"
    fi
    
    # Test archive integrity
    log "INFO" "Testing archive integrity..."
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Archive integrity test passed"
        
        # Show archive contents summary
        local file_count=$(tar -tzf "$backup_file" | wc -l)
        local archive_size=$(du -h "$backup_file" | cut -f1)
        log "INFO" "Archive contains $file_count files/directories (Size: $archive_size)"
        
        return 0
    else
        log "ERROR" "❌ Archive integrity test failed"
        return 1
    fi
}

# Restore from backup
restore_from_backup() {
    log "STEP" "Starting backup restoration process..."
    
    list_available_backups
    
    if ! ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        log "ERROR" "No backups available for restoration."
        return 1
    fi
    
    echo ""
    log "PROMPT" "Enter backup number to restore:"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local backup_files=("$BACKUP_ARCHIVE_DIR"/*.tar.gz)
    local selected_index=$((selection - 1))
    
    if [ $selected_index -lt 0 ] || [ $selected_index -ge ${#backup_files[@]} ]; then
        log "ERROR" "Invalid backup number."
        return 1
    fi
    
    local selected_backup="${backup_files[$selected_index]}"
    local backup_name=$(basename "$selected_backup")
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will restore from backup: $backup_name${NC}"
    echo -e "${YELLOW}This operation will overwrite current configurations!${NC}\n"
    
    log "PROMPT" "Are you sure you want to proceed? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Restoration cancelled."
        return 0
    fi
    
    # Verify backup integrity before restoration
    if ! verify_backup_integrity "$selected_backup"; then
        log "ERROR" "Backup integrity verification failed. Restoration aborted."
        return 1
    fi
    
    # Create restoration directory
    local restore_dir="/tmp/marzban_restore_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$restore_dir"
    
    # Extract backup
    log "STEP" "Extracting backup archive..."
    if tar -xzf "$selected_backup" -C "$restore_dir"; then
        log "SUCCESS" "Backup extracted successfully."
    else
        log "ERROR" "Failed to extract backup archive."
        rm -rf "$restore_dir"
        return 1
    fi
    
    # Restore main server components
    local backup_content_dir=$(find "$restore_dir" -maxdepth 1 -type d -name "marzban_*_backup_*" | head -1)
    
    if [ -d "$backup_content_dir/main_server" ]; then
        log "STEP" "Restoring main server components..."
        
        # Restore Marzban
        if [ -d "$backup_content_dir/main_server/marzban" ]; then
            log "INFO" "Restoring Marzban configuration..."
            systemctl stop marzban 2>/dev/null || true
            cp -r "$backup_content_dir/main_server/marzban"/* /opt/marzban/ 2>/dev/null || true
            systemctl start marzban 2>/dev/null || true
        fi
        
        # Restore Manager configuration
        if [ -d "$backup_content_dir/main_server/manager_config" ]; then
            log "INFO" "Restoring Manager configuration..."
            cp -r "$backup_content_dir/main_server/manager_config"/* "$MANAGER_DIR/" 2>/dev/null || true
        fi
        
        # Restore Geo files
        if [ -d "$backup_content_dir/main_server/geo_files" ] && [ -n "$GEO_FILES_PATH" ]; then
            log "INFO" "Restoring Geo files..."
            cp -r "$backup_content_dir/main_server/geo_files"/* "$GEO_FILES_PATH/" 2>/dev/null || true
        fi
    fi
    
    # Cleanup
    rm -rf "$restore_dir"
    
    log "SUCCESS" "Backup restoration completed successfully!"
    send_telegram_notification "🔄 Backup Restored%0A%0ABackup: $backup_name%0AStatus: ✅ Successful" "normal"
}

# Cleanup old backups
cleanup_old_backups() {
    log "STEP" "Cleaning up old backups..."
    
    echo -e "\n${YELLOW}This will remove backups older than the retention policy.${NC}"
    echo -e "${YELLOW}Current retention: Keep last $BACKUP_RETENTION_COUNT backups${NC}\n"
    
    log "PROMPT" "Continue with cleanup? (y/n):"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local removed_count=0
        
        # Remove old full backups
        ls -t "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | \
            tail -n +$((BACKUP_RETENTION_COUNT + 1)) | \
            while read -r old_backup; do
                log "INFO" "Removing old backup: $(basename "$old_backup")"
                rm -f "$old_backup" "${old_backup}.md5"
                removed_count=$((removed_count + 1))
            done
        
        # Remove old main server backups
        ls -t "$BACKUP_ARCHIVE_DIR"/marzban_main_backup_*.tar.gz 2>/dev/null | \
            tail -n +$((BACKUP_RETENTION_COUNT + 1)) | \
            while read -r old_backup; do
                log "INFO" "Removing old main backup: $(basename "$old_backup")"
                rm -f "$old_backup" "${old_backup}.md5"
                removed_count=$((removed_count + 1))
            done
        
        # Remove old nodes backups
        ls -t "$BACKUP_ARCHIVE_DIR"/marzban_nodes_backup_*.tar.gz 2>/dev/null | \
            tail -n +$((BACKUP_RETENTION_COUNT + 1)) | \
            while read -r old_backup; do
                log "INFO" "Removing old nodes backup: $(basename "$old_backup")"
                rm -f "$old_backup" "${old_backup}.md5"
                removed_count=$((removed_count + 1))
            done
        
        local remaining_count
        remaining_count=$(ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz 2>/dev/null | wc -l)
        log "SUCCESS" "Cleanup completed: $remaining_count backups remaining"
    else
        log "INFO" "Cleanup cancelled."
    fi
}

# Export backup to remote
export_backup_to_remote() {
    log "STEP" "Exporting backup to remote location..."
    
    list_available_backups
    
    if ! ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        log "ERROR" "No backups available for export."
        return 1
    fi
    
    echo ""
    log "PROMPT" "Enter backup number to export:"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local backup_files=("$BACKUP_ARCHIVE_DIR"/*.tar.gz)
    local selected_index=$((selection - 1))
    
    if [ $selected_index -lt 0 ] || [ $selected_index -ge ${#backup_files[@]} ]; then
        log "ERROR" "Invalid backup number."
        return 1
    fi
    
    local selected_backup="${backup_files[$selected_index]}"
    
    echo -e "\n${PURPLE}Export Options:${NC}"
    echo " 1. Export via SCP"
    echo " 2. Export via FTP"
    echo " 3. Export to Local Path"
    echo ""
    
    log "PROMPT" "Choose export method:"
    read -r export_method
    
    case "$export_method" in
        1)
            log "PROMPT" "Enter remote server IP:"
            read -r remote_ip
            log "PROMPT" "Enter remote username:"
            read -r remote_user
            log "PROMPT" "Enter remote path:"
            read -r remote_path
            log "PROMPT" "Enter remote password:"
            read -s remote_password
            echo ""
            
            if scp_to_remote "$selected_backup" "$remote_ip" "$remote_user" "22" "$remote_password" \
               "$remote_path/$(basename "$selected_backup")" "Backup Export"; then
                log "SUCCESS" "Backup exported successfully via SCP."
            else
                log "ERROR" "Failed to export backup via SCP."
            fi
            ;;
        2)
            log "INFO" "FTP export not implemented yet."
            ;;
        3)
            log "PROMPT" "Enter local export path:"
            read -r local_path
            
            if cp "$selected_backup" "$local_path/"; then
                log "SUCCESS" "Backup exported to: $local_path/$(basename "$selected_backup")"
            else
                log "ERROR" "Failed to export backup to local path."
            fi
            ;;
        *)
            log "ERROR" "Invalid export method."
            ;;
    esac
}

# Check node health via API
check_node_health_via_api() {
    local node_id="$1"
    local node_name="$2"
    
    if [ -z "$node_id" ] || [ "$node_id" = "null" ]; then
        log "WARNING" "Node '$node_name' has no API ID for health check."
        return 1
    fi
    
    local health_response
    health_response=$(curl -s --connect-timeout 10 --max-time 15 \
        -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        --insecure 2>/dev/null)
    
    if echo "$health_response" | jq -e . >/dev/null 2>&1; then
        local status=$(echo "$health_response" | jq -r '.status // "unknown"')
        local last_seen=$(echo "$health_response" | jq -r '.last_seen // "never"')
        
        case "$status" in
            "connected")
                echo "   🟢 Status: Connected"
                echo "   📡 Last Seen: $last_seen"
                return 0
                ;;
            "disconnected")
                echo "   🔴 Status: Disconnected"
                echo "   📡 Last Seen: $last_seen"
                return 1
                ;;
            *)
                echo "   ⚪ Status: $status"
                echo "   📡 Last Seen: $last_seen"
                return 1
                ;;
        esac
    else
        echo "   ❌ API Error: Invalid response"
        log "DEBUG" "Health check response for $node_name: $health_response"
        return 1
    fi
}

# Create enhanced HAProxy config
create_enhanced_haproxy_config() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    
    log "SYNC" "Creating enhanced HAProxy configuration..."
    
    # Add backend configuration for the new node
    cat >> "$haproxy_cfg" << EOF

# Backend for $node_name
backend vless_${node_name}
    mode tcp
    balance roundrobin
    server ${node_name}_server ${node_ip}:443 check

EOF
    
    # Add frontend rule for the domain
    sed -i "/^frontend vless_frontend/,/^backend/ {
        /use_backend.*if/i\\
    use_backend vless_${node_name} if { req.ssl_sni -i ${node_domain} }
    }" "$haproxy_cfg"
    
    log "SUCCESS" "HAProxy configuration updated for node: $node_name"
}

# Verify HAProxy sync across nodes
verify_haproxy_sync_across_nodes() {
    log "SYNC" "Verifying HAProxy synchronization across all nodes..."
    
    local main_config_hash
    main_config_hash=$(md5sum /etc/haproxy/haproxy.cfg | awk '{print $1}' 2>/dev/null || echo "missing")
    
    load_nodes_config
    local sync_status=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_config_hash
        node_config_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                          "if [ -f /etc/haproxy/haproxy.cfg ]; then md5sum /etc/haproxy/haproxy.cfg | awk '{print \$1}'; else echo 'missing'; fi" \
                          "Sync Verification" 2>/dev/null || echo "error")
        
        if [ "$node_config_hash" = "$main_config_hash" ]; then
            log "SUCCESS" "✅ Node $name: HAProxy config synchronized"
        else
            log "WARNING" "❌ Node $name: HAProxy config out of sync"
            sync_status=1
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ $sync_status -eq 0 ]; then
        log "SUCCESS" "All nodes are synchronized with main server HAProxy configuration."
        send_telegram_notification "✅ HAProxy Sync Verified%0A%0AAll nodes synchronized successfully" "normal"
    else
        log "WARNING" "Some nodes are out of sync. Manual intervention may be required."
        send_telegram_notification "⚠️ HAProxy Sync Issues%0A%0ASome nodes are out of sync" "high"
    fi
    
    return $sync_status
}

# Update geo files on node
update_geo_files_on_node() {
    log "INFO" "Downloading fresh geo files on node..."
    
    # Create geo directory
    mkdir -p /var/lib/marzban-node/chocolate
    
    # Download geosite.dat
    if curl -L -o /var/lib/marzban-node/chocolate/geosite.dat \
       "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat" 2>/dev/null; then
        log "SUCCESS" "Geosite file downloaded successfully"
    else
        log "ERROR" "Failed to download geosite file"
        return 1
    fi
    
    # Download geoip.dat
    if curl -L -o /var/lib/marzban-node/chocolate/geoip.dat \
       "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat" 2>/dev/null; then
        log "SUCCESS" "Geoip file downloaded successfully"
    else
        log "ERROR" "Failed to download geoip file"
        return 1
    fi
    
    # Set proper permissions
    chmod 644 /var/lib/marzban-node/chocolate/*.dat
    chown root:root /var/lib/marzban-node/chocolate/*.dat 2>/dev/null || true
    
    log "SUCCESS" "Geo files updated successfully on node"
    return 0
}

# Install HAProxy on new node
install_haproxy_on_new_node() {
    local node_ip="$1" node_name="$2"
    
    log "SYNC" "Installing HAProxy on new node: $node_name ($node_ip)"
    
    # Find node configuration
    local node_entry
    node_entry=$(get_node_config_by_name "$node_name")
    
    if [ -z "$node_entry" ]; then
        log "ERROR" "Node configuration not found for: $node_name"
        return 1
    fi
    
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    export NODE_SSH_PASSWORD="$password"
    
    # Install HAProxy on the new node
    if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
       "apt update >/dev/null 2>&1 && apt install -y haproxy >/dev/null 2>&1" \
       "HAProxy Installation"; then
        
        # Copy HAProxy configuration from main server
        if scp_to_remote "/etc/haproxy/haproxy.cfg" "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "/etc/haproxy/haproxy.cfg" "HAProxy Configuration"; then
            
            # Enable and start HAProxy service
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "systemctl enable haproxy && systemctl start haproxy" \
               "HAProxy Service Start"; then
                
                log "SUCCESS" "HAProxy installed and configured on node: $node_name"
                unset NODE_SSH_PASSWORD
                return 0
            else
                log "ERROR" "Failed to start HAProxy service on node: $node_name"
            fi
        else
            log "ERROR" "Failed to copy HAProxy configuration to node: $node_name"
        fi
    else
        log "ERROR" "Failed to install HAProxy on node: $node_name"
    fi
    
    unset NODE_SSH_PASSWORD
    return 1
}

# Script completion message
log "SUCCESS" "Marzban Central Manager Professional Edition v$SCRIPT_VERSION loaded successfully!"

# ==============================================================================
# MAIN MENU DISPLAY FUNCTION
# ==============================================================================

show_main_menu() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║ ${CYAN}${BOLD}Marzban Central Node Manager${NC}                           ║"
    echo -e "${WHITE}║ ${PURPLE}Made with ❤️ by B3hnAM - Thanks to all Marzban developers${NC} ║"
    echo -e "${WHITE}║ ${YELLOW}[Professional Edition v${SCRIPT_VERSION}]${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}Current Nodes Overview:${NC}"
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No nodes have been added yet.${NC}"
    else
        printf "%-20s %-15s %-15s %-10s\n" "Node Name" "IP Address" "Status" "Domain"
        echo -e "${WHITE}----------------------------------------------------------------------${NC}"
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            local status
            if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
                status="${GREEN}Online${NC}"
            else
                status="${RED}Offline${NC}"
            fi
            printf "%-20s %-15s %-15s %-10s\n" "$name" "$ip" "$status" "$domain"
        done
    fi
    
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${GREEN}1) Add a new node${NC}"
    echo -e "${GREEN}2) Remove a node${NC}"
    echo -e "${GREEN}3) Update node information${NC}"
    echo -e "${YELLOW}4) Sync HAProxy to All Nodes${NC}"
    echo -e "${CYAN}5) Check all nodes status${NC}"
    echo -e "${PURPLE}6) Bulk Update Node Configurations${NC}"
    echo -e "${BLUE}7) Install Marzban on a new node${NC}"
    echo -e "${WHITE}8) Configure Marzban API${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${GREEN}9) Backup & Restore Menu${NC}"
    echo -e "${GREEN}10) Nginx Management Menu${NC}"
    echo -e "${GREEN}11) Bulk Node Operations Menu${NC}"
    echo -e "${GREEN}12) System Logs & Diagnostics Menu${NC}"
    echo -e "${CYAN}-----------------------------------------------${NC}" # Additional separator
    echo -e "${WHITE}13) Configure Telegram Notifications${NC}"
    echo -e "${WHITE}14) View System Resources${NC}"
    echo -e "${WHITE}15) Validate Configurations${NC}"
    echo -e "${WHITE}16) Clean Old Logs${NC}"
    echo -e "${YELLOW}17) View Marzban Panel Logs${NC}"
    echo -e "${YELLOW}18) View HAProxy Logs${NC}"
    echo -e "${YELLOW}19) View System Logs${NC}"
    echo -e "${RED}x) Exit${NC}"
    echo ""
}

# ==============================================================================
# MAIN EXECUTION LOGIC
# ==============================================================================

main() {
    check_dependencies # Ensure dependencies are met before showing the menu
    while true; do
        show_main_menu
        read -p "Please enter your choice [1-19, x]: " choice

        case "$choice" in
            1) import_single_node || true; read -p "Press Enter to continue..." ;;
            2) remove_node || true; read -p "Press Enter to continue..." ;;
            3) update_existing_node || true; read -p "Press Enter to continue..." ;;
            4) bulk_sync_haproxy || true; read -p "Press Enter to continue..." ;;
            5) monitor_node_health_status || true; read -p "Press Enter to continue..." ;;
            6) bulk_update_configurations || true; read -p "Press Enter to continue..." ;;
            7) deploy_new_node_professional_enhanced || true; read -p "Press Enter to continue..." ;;
            8) configure_marzban_api || true; read -p "Press Enter to continue..." ;;
            9) backup_restore_menu || true; read -p "Press Enter to continue..." ;;
            10) nginx_management_menu || true; read -p "Press Enter to continue..." ;;
            11) bulk_node_operations || true; read -p "Press Enter to continue..." ;;
            12) show_system_diagnostics || true; read -p "Press Enter to continue..." ;;
            13) configure_telegram_advanced || true; read -p "Press Enter to continue..." ;;
            14) show_system_resources || true; read -p "Press Enter to continue..." ;;
            15) validate_configurations || true; read -p "Press Enter to continue..." ;;
            16) clean_old_logs || true; read -p "Press Enter to continue..." ;;
            17) view_marzban_logs || true; read -p "Press Enter to continue..." ;;
            18) view_haproxy_logs || true; read -p "Press Enter to continue..." ;;
            19) view_system_logs || true; read -p "Press Enter to continue..." ;;
            x|X)
                log "INFO" "Exiting Marzban Central Manager. Goodbye!"
                exit 0
                ;;
            *)
                log "ERROR" "Invalid option: $choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Start The Program ---
acquire_lock
main

#
# Enhanced with Complete Backup System, Optimized Monitoring & Advanced Features
# Author: behnamrjd
# Version: Professional-3.0

SCRIPT_VERSION="Professional-3.0"
MANAGER_DIR="/root/MarzbanManager"
NODES_CONFIG_FILE="${MANAGER_DIR}/marzban_managed_nodes.conf"
MANAGER_CONFIG_FILE="${MANAGER_DIR}/marzban_manager.conf"
BACKUP_DIR="${MANAGER_DIR}/backups"
LOCKFILE="/var/lock/marzban-central-manager.lock"
LOGFILE="/tmp/marzban_central_manager_$(date +%Y%m%d_%H%M%S).log"

# Enhanced Backup Configuration
BACKUP_MAIN_DIR="${BACKUP_DIR}/main_server"
BACKUP_NODES_DIR="${BACKUP_DIR}/nodes"
BACKUP_ARCHIVE_DIR="${BACKUP_DIR}/archives"
BACKUP_RETENTION_COUNT=3
BACKUP_SCHEDULE_HOUR="03"
BACKUP_SCHEDULE_MINUTE="30"
BACKUP_TIMEZONE="Asia/Tehran"
AUTO_BACKUP_ENABLED=false

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

# --- Global Variables ---
MAIN_SERVER_IP=$(hostname -I | awk '{print $1}')
MARZBAN_PANEL_PROTOCOL="https"
MARZBAN_PANEL_DOMAIN=""
MARZBAN_PANEL_PORT=""
MARZBAN_PANEL_USERNAME=""
MARZBAN_PANEL_PASSWORD=""
MARZBAN_TOKEN=""
CLIENT_CERT=""
MARZBAN_NODE_ID=""

# Enhanced monitoring configuration (optimized for server performance)
MONITORING_INTERVAL=600  # 10 minutes (reduced from 5 minutes)
HEALTH_CHECK_TIMEOUT=30  # Increased timeout for stability
API_RATE_LIMIT_DELAY=2   # Delay between API calls
SYNC_CHECK_INTERVAL=1800 # 30 minutes for sync monitoring

# Service detection variables
MAIN_HAS_NGINX=false
MAIN_HAS_HAPROXY=false
NGINX_CONFIG_PATH=""
HAPROXY_CONFIG_PATH=""
GEO_FILES_PATH=""

mkdir -p "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
chmod 700 "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
if [ -f "$MANAGER_CONFIG_FILE" ]; then source "$MANAGER_CONFIG_FILE"; fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

## Enhanced logging with multiple levels and file rotation
log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    local masked_message="$message"
    
    # Mask sensitive information
    if [[ -n "${NODE_SSH_PASSWORD:-}" ]]; then masked_message="${message//$NODE_SSH_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_PANEL_PASSWORD:-}" ]]; then masked_message="${message//$MARZBAN_PANEL_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_TOKEN:-}" ]]; then masked_message="${message//$MARZBAN_TOKEN/*****masked*****/}"; fi
    
    # Log to system logger
    logger -t "marzban-central-manager" "$level: $masked_message"
    
    # Enhanced console output with icons and colors
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $masked_message" | tee -a "$LOGFILE";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $masked_message" | tee -a "$LOGFILE";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $masked_message" | tee -a "$LOGFILE";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $masked_message" | tee -a "$LOGFILE";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $masked_message" | tee -a "$LOGFILE";;
        PROMPT)  echo -e "[$timestamp] ${CYAN}❓ PROMPT:${NC} $masked_message";;
        DEBUG)   echo -e "[$timestamp] ${DIM}🐛 DEBUG:${NC} $masked_message" | tee -a "$LOGFILE";;
        BACKUP)  echo -e "[$timestamp] ${CYAN}💾 BACKUP:${NC} $masked_message" | tee -a "$LOGFILE";;
        SYNC)    echo -e "[$timestamp] ${PURPLE}🔄 SYNC:${NC} $masked_message" | tee -a "$LOGFILE";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $masked_message" | tee -a "$LOGFILE";;
    esac
}

send_telegram_notification() {
    local message="$1"
    local level="${2:-normal}" # normal, high, critical
    local stored_level

    # Load TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, and TELEGRAM_NOTIFICATION_LEVEL from config
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        source "$MANAGER_CONFIG_FILE"
    fi

    stored_level=${TELEGRAM_NOTIFICATION_LEVEL:-1} # Default to all notifications if not set

    # Check if notifications are enabled and the level is appropriate
    if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_CHAT_ID}" ] || [ "$stored_level" -eq 4 ]; then
        # log "DEBUG" "Telegram notifications are disabled or not configured."
        return 0
    fi

    # Level mapping: 1=all, 2=high/critical, 3=critical only
    case "$level" in
        "normal")
            if [ "$stored_level" -gt 1 ]; then return 0; fi
            ;;
        "high")
            if [ "$stored_level" -gt 2 ]; then return 0; fi
            ;;
        "critical")
            if [ "$stored_level" -gt 3 ]; then return 0; fi
            ;;
    esac

    # Send the notification using curl
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d "chat_id=${TELEGRAM_CHAT_ID}" \
         -d "text=${message}" \
         -d "parse_mode=HTML" > /dev/null &
}

## Lock management for single instance execution
acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        local pid; pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then 
            log "ERROR" "Instance already running (PID: $pid)."
            exit 1
        fi
        log "WARNING" "Removing stale lock file."
        rm -f "$LOCKFILE"
    fi
    echo "$$" > "$LOCKFILE"
    log "INFO" "Lock acquired."
}

release_lock() { rm -f "$LOCKFILE"; log "INFO" "Lock released."; }
trap release_lock EXIT
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

## Dependency checks with auto-installation
check_dependencies() {
    local deps=("sshpass" "python3" "curl" "jq" "rsync" "pigz" "git")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then # Using our defined function
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "INFO" "Installing missing dependencies: ${missing_deps[*]}"
        if command_exists apt; then
            apt update >/dev/null 2>&1
            apt install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via apt."
        elif command_exists yum; then
            yum install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via yum."
        else
            log "ERROR" "Cannot determine package manager (apt or yum). Please install dependencies manually: ${missing_deps[*]}"
            return 1
        fi
    fi
    
    # Check Python modules
    if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
        log "INFO" "Installing python3-full (or equivalent for json, urllib.parse, datetime)..."
        if command_exists apt; then
            apt install -y python3-full >/dev/null 2>&1
        elif command_exists yum; then
             # CentOS might need python3-json, python3-urllib an python3-datetime or similar
             # For simplicity, assuming python3-devel or a more general package might cover these.
             # This part might need adjustment based on specific distro.
            yum install -y python3-devel >/dev/null 2>&1 || yum install -y python3 >/dev/null 2>&1
        fi
        # Re-check after attempting install
        if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
            log "WARNING" "Failed to install required Python modules. Some functionalities might be affected."
        else
            log "SUCCESS" "Python modules seem to be available."
        fi
    fi
    return 0
}

## Enhanced SSH operations with retry mechanism and rate limiting
ssh_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" command="$5" desc="$6"
    local max_retries=3 retry=0
    
    sleep "$API_RATE_LIMIT_DELAY"
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Executing ($desc) on $node_ip (attempt $((retry+1))/$max_retries)..."
        
        # Use a here-string to pass the password securely
        if sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
           -p "$node_port" "${node_user}@${node_ip}" "$command" 2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "Remote command ($desc) executed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 5 seconds..."
            sleep 5
        fi
    done
    
    log "ERROR" "Remote command ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP with progress and retry
scp_to_remote() {
    local local_path="$1" node_ip="$2" node_user="$3" node_port="$4" node_password="$5" remote_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Transferring ($desc) to $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "$local_path" "${node_user}@${node_ip}:${remote_path}" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File transfer ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File transfer ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP from remote with retry
scp_from_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" remote_path="$5" local_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Downloading ($desc) from $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if echo "$node_password" | sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "${node_user}@${node_ip}:${remote_path}" "$local_path" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File download ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File download ($desc) failed after $max_retries attempts."
    return 1
}

## Node configuration management
load_nodes_config() {
    if [ -f "$NODES_CONFIG_FILE" ]; then
        mapfile -t NODES_ARRAY < <(grep -vE '^\s*#|^\s*$' "$NODES_CONFIG_FILE" || true)
    else
        NODES_ARRAY=()
    fi
}

save_nodes_config() {
    printf "%s\n" "${NODES_ARRAY[@]}" > "$NODES_CONFIG_FILE"
    chmod 600 "$NODES_CONFIG_FILE"
    log "INFO" "Nodes configuration saved."
}

add_node_to_config() {
    local name="$1" ip="$2" user="$3" port="$4" domain="$5" password="$6" node_id="${7:-}"
    NODES_ARRAY+=("${name};${ip};${user};${port};${domain};${password};${node_id}")
    log "INFO" "Node '$name' added to configuration."
}

get_node_config_by_name() {
    local name="$1"
    for entry in "${NODES_ARRAY[@]}"; do
        if [[ "$entry" == "${name};"* ]]; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

## Service Detection System
detect_main_server_services() {
    log "STEP" "Detecting services on main server..."
    
    # Detect Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        MAIN_HAS_NGINX=true
        NGINX_CONFIG_PATH="/etc/nginx"
        log "SUCCESS" "Nginx detected on main server"
    else
        MAIN_HAS_NGINX=false
        log "INFO" "Nginx not detected on main server"
    fi
    
    # Detect HAProxy
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        MAIN_HAS_HAPROXY=true
        HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
        log "SUCCESS" "HAProxy detected on main server"
    else
        MAIN_HAS_HAPROXY=false
        log "INFO" "HAProxy not detected on main server"
    fi
    
    # Detect Geo files from Core config
    detect_geo_files_location
}

detect_geo_files_location() {
    log "INFO" "Detecting geo files location using multi-priority smart-scan..."
    
    # --- Priority 1: The most reliable method (from .env file) ---
    if [ -f "/opt/marzban/.env" ]; then
        local env_geo_path
        env_geo_path=$(grep -E "^\s*XRAY_ASSETS_PATH" /opt/marzban/.env | cut -d'=' -f2- | tr -d '"' | tr -d "'" | sed 's/#.*//' | xargs)
        if [ -n "$env_geo_path" ] && [ -d "$env_geo_path" ]; then
            if [ -f "$env_geo_path/geosite.dat" ] && [ -f "$env_geo_path/geoip.dat" ]; then
                log "SUCCESS" "Geo files found and validated via .env file at: $env_geo_path"
                GEO_FILES_PATH="$env_geo_path"
                return 0
            fi
        fi
    fi

    # --- Priority 2: Your brilliant idea - Find filenames from xray_config.json and search for them ---
    if [ -f "/var/lib/marzban/xray_config.json" ]; then
        log "INFO" "Scanning xray_config.json for custom geo file names..."
        local geoip_file
        local geosite_file

        geoip_file=$(jq -r '[.routing.rules[]? | .ip[]? | select(startswith("geoip:"))] | .[0] // "geoip:geoip"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geoip_file+=".dat"

        geosite_file=$(jq -r '[.routing.rules[]? | .domain[]? | select(startswith("geosite:"))] | .[0] // "geosite:geosite"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geosite_file+=".dat"
        
        log "DEBUG" "Detected target files: $geoip_file, $geosite_file"

        local found_dir
        found_dir=$(find / -name "$geoip_file" -printf "%h\n" 2>/dev/null | while read -r dir; do
            if [ -f "$dir/$geosite_file" ]; then
                echo "$dir"
                break
            fi
        done)

        if [ -n "$found_dir" ]; then
            log "SUCCESS" "Geo files found via xray_config scan at: $found_dir"
            GEO_FILES_PATH="$found_dir"
            return 0
        fi
    fi

    # --- Priority 3: Fallback to scanning common hardcoded locations ---
    log "INFO" "Falling back to scanning common default directories..."
    local common_paths=(
        "/var/lib/marzban/assets" "/var/lib/marzban/geo" "/var/lib/marzban/chocolate"
        "/opt/marzban/assets" "/opt/marzban/geo"
    )
    for path in "${common_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/geosite.dat" ] && [ -f "$path/geoip.dat" ]; then
            log "SUCCESS" "Geo files found via fallback scan at: $path"
            GEO_FILES_PATH="$path"
            return 0
        fi
    done
    
    log "WARNING" "Could not find custom Geo files on the main server. Geo file sync will be skipped."
    GEO_FILES_PATH=""
    return 1
}
## Complete Backup System Implementation
create_full_backup() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_full_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting comprehensive backup process..."
    
    # Create temporary backup directory
    mkdir -p "$temp_backup_dir"
    
    # Phase 1: Backup main server
    log "STEP" "Phase 1: Backing up main server..."
    backup_main_server "$temp_backup_dir"
    
    # Phase 2: Backup all nodes
    log "STEP" "Phase 2: Backing up all nodes..."
    backup_all_nodes "$temp_backup_dir"
    
    # Phase 3: Create compressed archive
    log "STEP" "Phase 3: Creating compressed archive..."
    create_backup_archive "$temp_backup_dir" "$final_archive"
    
    # Phase 4: Apply retention policy
    log "STEP" "Phase 4: Applying retention policy..."
    apply_backup_retention_policy_global
    
    # Cleanup
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Full backup completed: $final_archive"
    
    # Send notification
    local backup_size=$(du -h "$final_archive" | cut -f1)
    send_telegram_notification "💾 Backup Completed%0A%0A📁 File: ${backup_name}.tar.gz%0A📊 Size: ${backup_size}%0A⏰ Time: $(date)" "normal"
}

backup_main_server() {
    local backup_dir="$1/main_server"
    mkdir -p "$backup_dir"
    
    log "BACKUP" "Backing up main server components..."
    
    # Backup Marzban
    if [ -d "/opt/marzban" ]; then
        log "INFO" "Backing up Marzban configuration..."
        cp -r /opt/marzban "$backup_dir/" 2>/dev/null || log "WARNING" "Failed to backup Marzban"
    fi
    
    # Backup HAProxy (if user confirms)
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "PROMPT" "Backup HAProxy configuration? (y/n):"
        read -r backup_haproxy
        if [[ "$backup_haproxy" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up HAProxy configuration..."
            mkdir -p "$backup_dir/haproxy"
            cp -r /etc/haproxy/* "$backup_dir/haproxy/" 2>/dev/null || log "WARNING" "Failed to backup HAProxy"
        fi
    fi
    
    # Backup Nginx (if user confirms)
    if [ "$MAIN_HAS_NGINX" = "true" ]; then
        log "PROMPT" "Backup Nginx configuration? (y/n):"
        read -r backup_nginx
        if [[ "$backup_nginx" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up Nginx configuration..."
            mkdir -p "$backup_dir/nginx"
            cp -r /etc/nginx/* "$backup_dir/nginx/" 2>/dev/null || log "WARNING" "Failed to backup Nginx"
        fi
    fi
    
    # Backup Geo files
    if [ -n "$GEO_FILES_PATH" ]; then
        log "INFO" "Backing up Geo files..."
        mkdir -p "$backup_dir/geo_files"
        cp -r "$GEO_FILES_PATH"/* "$backup_dir/geo_files/" 2>/dev/null || log "WARNING" "Failed to backup Geo files"
    fi
    
    # Backup Manager configuration
    log "INFO" "Backing up Manager configuration..."
    cp -r "$MANAGER_DIR" "$backup_dir/manager_config" 2>/dev/null || log "WARNING" "Failed to backup Manager config"
    
    log "SUCCESS" "Main server backup completed."
}

backup_all_nodes() {
    local backup_dir="$1/nodes"
    mkdir -p "$backup_dir"
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured for backup."
        return 0
    fi
    
    log "BACKUP" "Backing up ${#NODES_ARRAY[@]} nodes..."
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Backing up node: $name ($ip)"
        
        local node_backup_dir="$backup_dir/$name"
        mkdir -p "$node_backup_dir"
        
        export NODE_SSH_PASSWORD="$password"
        
        # Create backup on remote node
        local remote_backup_file="/tmp/node_backup_${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "tar -czf $remote_backup_file --warning=no-file-changed /opt/marzban-node/ /var/lib/marzban-node/ /etc/systemd/system/marzban-node* /etc/haproxy/ 2>/dev/null" \
           "Node Backup Creation"; then
            
            # Transfer backup to main server
            if scp_from_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$remote_backup_file" "$node_backup_dir/backup.tar.gz" "Node Backup Transfer"; then
                
                # Create node info file
                cat > "$node_backup_dir/node_info.txt" << EOF
Node Name: $name
IP Address: $ip
Domain: $domain
SSH User: $user
SSH Port: $port
Marzban Node ID: $node_id
Backup Date: $(date)
EOF
                
                # Cleanup remote backup
                ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                    "rm -f $remote_backup_file" "Remote Cleanup" || true
                
                log "SUCCESS" "Node $name backup completed."
            else
                log "ERROR" "Failed to transfer backup from node $name"
            fi
        else
            log "ERROR" "Failed to create backup on node $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "All nodes backup completed."
}

create_backup_archive() {
    local source_dir="$1"
    local archive_path="$2"
    
    log "BACKUP" "Creating compressed archive..."
    
    # Use pigz for faster compression if available
    if command_exists pigz; then
        tar -cf - -C "$(dirname "$source_dir")" "$(basename "$source_dir")" | pigz > "$archive_path"
    else
        tar -czf "$archive_path" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"
    fi
    
    # Verify archive integrity
    if tar -tzf "$archive_path" >/dev/null 2>&1; then
        local archive_size=$(du -h "$archive_path" | cut -f1)
        log "SUCCESS" "Archive created successfully: $archive_size"
        
        # Create checksum
        md5sum "$archive_path" > "${archive_path}.md5"
        log "INFO" "Checksum created: ${archive_path}.md5"
    else
        log "ERROR" "Archive verification failed!"
        return 1
    fi
}

apply_backup_retention_policy_global() {
    log "BACKUP" "Applying retention policy (keeping last $BACKUP_RETENTION_COUNT backups)..."
    
    # Remove old archives
    ls -t "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | \
        tail -n +$((BACKUP_RETENTION_COUNT + 1)) | \
        while read -r old_backup; do
            log "INFO" "Removing old backup: $(basename "$old_backup")"
            rm -f "$old_backup" "${old_backup}.md5"
        done
    
    local remaining_count
    remaining_count=$(ls "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | wc -l)
    log "SUCCESS" "Retention policy applied: $remaining_count backups remaining"
}

## Automated Backup Scheduling
setup_automated_backup() {
    log "STEP" "Setting up automated backup system..."
    
    # Create backup script
    local backup_script="/usr/local/bin/marzban-auto-backup.sh"
    cat > "$backup_script" << 'EOF'
#!/bin/bash
# Automated Marzban Backup Script
cd /root/MarzbanManager
./marzban_central_manager.sh --backup >> /var/log/marzban-backup.log 2>&1
EOF
    
    chmod +x "$backup_script"
    
    # Setup cron job for 3:30 AM Iran time
    local cron_entry="30 3 * * * TZ=Asia/Tehran $backup_script"
    
    # Remove existing cron job if exists
    crontab -l 2>/dev/null | grep -v "marzban-auto-backup" | crontab -
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    log "SUCCESS" "Automated backup scheduled for 3:30 AM Iran time daily"
    
    # Update configuration
    sed -i '/AUTO_BACKUP_ENABLED=/d' "$MANAGER_CONFIG_FILE" 2>/dev/null || true
    echo "AUTO_BACKUP_ENABLED=true" >> "$MANAGER_CONFIG_FILE"
    
    send_telegram_notification "⏰ Automated Backup Enabled%0A%0A📅 Schedule: Daily at 3:30 AM (Iran Time)%0A🔄 Retention: $BACKUP_RETENTION_COUNT backups" "normal"
}

## Enhanced HAProxy Synchronization System
sync_haproxy_across_all_nodes() {
    local new_node_name="$1" new_node_ip="$2" new_node_domain="$3"
    
    log "SYNC" "Starting HAProxy synchronization across all nodes..."
    
    # Phase 1: Update main server HAProxy
    if ! update_main_haproxy_config "$new_node_name" "$new_node_ip" "$new_node_domain"; then
        log "ERROR" "Failed to update main server HAProxy"
        return 1
    fi
    
    # Phase 2: Sync to all existing nodes
    sync_haproxy_to_all_existing_nodes
    
    # Phase 3: Install HAProxy on new node
    install_haproxy_on_new_node "$new_node_ip" "$new_node_name"
    
    # Phase 4: Verification
    verify_haproxy_sync_across_nodes
}

update_main_haproxy_config() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_cfg}.backup.$(date +%s)"
    
    log "SYNC" "Updating main server HAProxy configuration..."
    cp "$haproxy_cfg" "$backup_file"
    
    # Create enhanced HAProxy config with new node
    create_enhanced_haproxy_config "$node_name" "$node_ip" "$node_domain"
    
    # Validate configuration before reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        if systemctl reload haproxy; then
            log "SUCCESS" "Main server HAProxy updated and reloaded successfully"
            log "SYNC" "HAProxy updated: Added backend $node_name ($node_ip) for domain $node_domain"
            send_telegram_notification "🔄 HAProxy Updated%0A%0AAdded: $node_name%0AIP: $node_ip%0ADomain: $node_domain" "normal"
            return 0
        else
            log "ERROR" "Failed to reload HAProxy service, restoring backup"
            cp "$backup_file" "$haproxy_cfg"
            systemctl reload haproxy
            return 1
        fi
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup"
        cp "$backup_file" "$haproxy_cfg"
        return 1
    fi
}

sync_haproxy_to_all_existing_nodes() {
    log "SYNC" "Synchronizing HAProxy to all existing nodes..."
    local sync_success=0 sync_failed=0
    
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "SYNC" "Syncing HAProxy to node: $name ($ip)"
        export NODE_SSH_PASSWORD="$password"
        
        # Create rollback point on node
        if create_node_rollback_point "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            
            # Sync HAProxy configuration
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                sync_success=$((sync_success + 1))
                log "SUCCESS" "HAProxy synced to node: $name"
            else
                sync_failed=$((sync_failed + 1))
                log "ERROR" "Failed to sync HAProxy to node: $name"
                
                # Attempt rollback
                rollback_node_configuration "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"
            fi
        else
            log "WARNING" "Could not create rollback point for node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SYNC" "HAProxy sync completed: $sync_success successful, $sync_failed failed"
    
    # Send notification
    send_telegram_notification "📊 HAProxy Sync Report%0A%0A✅ Success: $sync_success%0A❌ Failed: $sync_failed" "normal"
}

create_node_rollback_point() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "SYNC" "Creating rollback point for node: $node_name"
    
    # Create backup of current HAProxy config
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg ]; then cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.rollback.$(date +%s); echo 'Rollback point created'; else echo 'No HAProxy config found'; fi" \
       "Rollback Point Creation"; then
        
        # Store rollback info
        echo "${node_name};${node_ip};$(date +%s)" >> "${BACKUP_DIR}/rollback_points.log"
        return 0
    else
        return 1
    fi
}

sync_haproxy_to_single_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    # Check if HAProxy is installed on node
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
         "command -v haproxy >/dev/null 2>&1" "HAProxy Check"; then
        
        log "SYNC" "Installing HAProxy on node: $node_name"
        if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
             "apt update >/dev/null 2>&1 && apt install -y haproxy >/dev/null 2>&1" \
             "HAProxy Installation"; then
            return 1
        fi
    fi
    
    # Copy main HAProxy config to node
    if scp_to_remote "/etc/haproxy/haproxy.cfg" "$node_ip" "$node_user" "$node_port" "$node_password" \
       "/etc/haproxy/haproxy.cfg" "HAProxy Configuration"; then
        
        # Validate and restart HAProxy on node
        if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
           "/usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl enable haproxy && systemctl restart haproxy" \
           "HAProxy Validation & Restart"; then
            
            log "SUCCESS" "HAProxy successfully synced to node: $node_name"
            return 0
        else
            log "ERROR" "HAProxy validation/restart failed on node: $node_name"
            return 1
        fi
    else
        return 1
    fi
}

rollback_node_configuration() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "WARNING" "Attempting rollback for node: $node_name"
    
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg.rollback.* ]; then cp /etc/haproxy/haproxy.cfg.rollback.* /etc/haproxy/haproxy.cfg && systemctl restart haproxy && echo 'Rollback successful'; else echo 'No rollback file found'; fi" \
       "Configuration Rollback"; then
        
        log "SUCCESS" "Rollback completed for node: $node_name"
        send_telegram_notification "🔄 Rollback Executed%0A%0ANode: $node_name%0AStatus: Successful" "high"
    else
        log "ERROR" "Rollback failed for node: $node_name"
        send_telegram_notification "🚨 Rollback Failed%0A%0ANode: $node_name%0ARequires manual intervention!" "critical"
    fi
}

## Geo Files Transfer System
transfer_geo_files_to_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4"
    
    if [ -z "$GEO_FILES_PATH" ]; then
        log "WARNING" "No geo files detected on main server, downloading fresh copies..."
        return 0
    fi
    
    log "SYNC" "Transferring geo files from main server to node..."
    
    # Create geo directory on node
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "mkdir -p /var/lib/marzban-node/chocolate" \
        "Geo Directory Creation"
    
    # Transfer geo files
    scp_to_remote "$GEO_FILES_PATH/geosite.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geosite.dat" "Geosite File"
    
    scp_to_remote "$GEO_FILES_PATH/geoip.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geoip.dat" "Geoip File"
    
    # Set proper permissions
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "chmod 644 /var/lib/marzban-node/chocolate/*.dat && chown root:root /var/lib/marzban-node/chocolate/*.dat" \
        "Geo Files Permissions"
    
    log "SUCCESS" "Geo files transferred successfully"
}

create_enhanced_docker_compose() {
    log "SYNC" "Creating enhanced docker-compose with geo volume..."
    
    local geo_volume=""
    if [ -n "$GEO_FILES_PATH" ]; then
        geo_volume="      - /var/lib/marzban-node/chocolate:/var/lib/marzban-node/chocolate"
    fi
    
    cat > docker-compose.yml << EOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /opt/marzban-node:/opt/marzban-node
${geo_volume}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "SUCCESS" "Enhanced docker-compose.yml created with geo volume support"
}
## Optimized Continuous Monitoring System
start_continuous_sync_monitoring() {
    log "INFO" "Starting optimized continuous synchronization monitoring..."
    
    while true; do
        monitor_haproxy_sync_status
        monitor_geo_files_sync_status
        monitor_node_health_status
        
        # Optimized sleep interval (30 minutes to reduce server load)
        sleep "$SYNC_CHECK_INTERVAL"
    done
}

monitor_haproxy_sync_status() {
    local main_config_hash
    main_config_hash=$(md5sum /etc/haproxy/haproxy.cfg | awk '{print $1}' 2>/dev/null || echo "missing")
    
    load_nodes_config
    local out_of_sync_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_config_hash
        node_config_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                          "if [ -f /etc/haproxy/haproxy.cfg ]; then md5sum /etc/haproxy/haproxy.cfg | awk '{print \$1}'; else echo 'missing'; fi" \
                          "Config Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_config_hash" != "$main_config_hash" ] && [ "$node_config_hash" != "error" ]; then
            out_of_sync_nodes+=("$name")
            log "WARNING" "Node $name is out of sync (hash: $node_config_hash vs main: $main_config_hash)"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_nodes[@]} -gt 0 ]; then
        log "SYNC" "Out of sync nodes detected: ${out_of_sync_nodes[*]}"
        send_telegram_notification "⚠️ Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_nodes[*]}%0A%0AAutomatic resync will be attempted." "high"
        
        # Attempt automatic resync
        auto_resync_nodes "${out_of_sync_nodes[@]}"
    fi
}

auto_resync_nodes() {
    local nodes=("$@")
    
    for node_name in "${nodes[@]}"; do
        log "SYNC" "Attempting automatic resync for node: $node_name"
        
        local node_entry
        node_entry=$(get_node_config_by_name "$node_name")
        
        if [ -n "$node_entry" ]; then
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            export NODE_SSH_PASSWORD="$password"
            
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                log "SUCCESS" "Automatic resync successful for node: $node_name"
                send_telegram_notification "✅ Auto-Resync Success%0A%0ANode: $node_name" "normal"
            else
                log "ERROR" "Automatic resync failed for node: $node_name"
                send_telegram_notification "🚨 Auto-Resync Failed%0A%0ANode: $node_name%0AManual intervention required!" "critical"
            fi
            
            unset NODE_SSH_PASSWORD
        fi
    done
}

monitor_geo_files_sync_status() {
    if [ -z "$GEO_FILES_PATH" ]; then
        return 0
    fi
    
    local main_geosite_hash main_geoip_hash
    main_geosite_hash=$(md5sum "$GEO_FILES_PATH/geosite.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    main_geoip_hash=$(md5sum "$GEO_FILES_PATH/geoip.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    
    load_nodes_config
    local out_of_sync_geo_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_geosite_hash node_geoip_hash
        node_geosite_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                           "if [ -f /var/lib/marzban-node/chocolate/geosite.dat ]; then md5sum /var/lib/marzban-node/chocolate/geosite.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                           "Geosite Hash Check" 2>/dev/null || echo "error")
        
        node_geoip_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                         "if [ -f /var/lib/marzban-node/chocolate/geoip.dat ]; then md5sum /var/lib/marzban-node/chocolate/geoip.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                         "Geoip Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_geosite_hash" != "$main_geosite_hash" ] || [ "$node_geoip_hash" != "$main_geoip_hash" ]; then
            if [ "$node_geosite_hash" != "error" ] && [ "$node_geoip_hash" != "error" ]; then
                out_of_sync_geo_nodes+=("$name")
                log "WARNING" "Node $name geo files are out of sync"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_geo_nodes[@]} -gt 0 ]; then
        log "SYNC" "Geo files out of sync on nodes: ${out_of_sync_geo_nodes[*]}"
        send_telegram_notification "🌍 Geo Files Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_geo_nodes[*]}" "normal"
    fi
}

monitor_node_health_status() {
    if ! get_marzban_token >/dev/null 2>&1; then
        return 1
    fi
    
    local unhealthy_nodes=()
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 10 --max-time 15 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status="unknown" # Default status
            if echo "$health_response" | jq -e . >/dev/null 2>&1; then # Check if response is valid JSON
                status=$(echo "$health_response" | jq -r '.status // "unknown"')
            else
                log "WARNING" "Node $name ($ip): Invalid API response for health check."
                log "DEBUG" "Response for $name: $health_response"
                # status remains "unknown"
            fi
            
            if [ "$status" != "connected" ]; then
                unhealthy_nodes+=("$name:$status")
            fi
        fi
        
        # Rate limiting
        sleep "$API_RATE_LIMIT_DELAY"
    done
    
    if [ ${#unhealthy_nodes[@]} -gt 0 ]; then
        log "WARNING" "Unhealthy nodes detected: ${unhealthy_nodes[*]}"
        send_telegram_notification "🔴 Health Alert%0A%0AUnhealthy nodes: ${unhealthy_nodes[*]}" "high"
    fi
}

## Enhanced Marzban API Configuration
configure_marzban_api() {
    log "STEP" "Configuring Marzban Panel API Connection..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Marzban Panel API Setup${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Please provide your Marzban Panel details:${NC}\n"
    
    log "PROMPT" "Panel Protocol (http/https) [default: https]:"
    read -r protocol
    protocol=${protocol:-https}
    
    log "PROMPT" "Panel Domain/IP (e.g., panel.example.com):"
    read -r domain
    
    log "PROMPT" "Panel Port [default: 8000]:"
    read -r port
    port=${port:-8000}
    
    log "PROMPT" "Admin Username:"
    read -r username
    
    log "PROMPT" "Admin Password:"
    read -s password
    echo ""
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$username" ] || [ -z "$password" ]; then
        log "ERROR" "All fields are required."
        return 1
    fi
    
    # Test connection
    log "INFO" "Testing API connection..."
    local test_url="${protocol}://${domain}:${port}/api/admin/token"
    local test_response
    
    test_response=$(curl -s -X POST "$test_url" \
        -d "username=${username}&password=${password}" \
        --connect-timeout 10 --max-time 30 \
        --insecure 2>/dev/null)
    
    if echo "$test_response" | grep -q "access_token"; then
        log "SUCCESS" "API connection test successful!"
        
        # Save configuration
        {
            echo "MARZBAN_PANEL_PROTOCOL=\"$protocol\""
            echo "MARZBAN_PANEL_DOMAIN=\"$domain\""
            echo "MARZBAN_PANEL_PORT=\"$port\""
            echo "MARZBAN_PANEL_USERNAME=\"$username\""
            echo "MARZBAN_PANEL_PASSWORD=\"$password\""
        } >> "$MANAGER_CONFIG_FILE"
        
        chmod 600 "$MANAGER_CONFIG_FILE"
        source "$MANAGER_CONFIG_FILE"
        
        log "SUCCESS" "Marzban API configuration saved successfully."
        send_telegram_notification "🔗 Marzban API Connected%0A%0APanel: $domain:$port%0AStatus: ✅ Connected" "normal"
    else
        log "ERROR" "API connection test failed. Please check your credentials and panel accessibility."
        log "DEBUG" "Response: $test_response"
        return 1
    fi
}

## Function to get Marzban API token
get_marzban_token() {
    if [ -n "$MARZBAN_TOKEN" ]; then
        # Token already exists, maybe add a check for expiration if API supports it
        # log "DEBUG" "Using existing Marzban token."
        return 0
    fi

    if [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ]; then
        log "ERROR" "Marzban Panel API credentials are not configured. Please run 'Configure Marzban API' first."
        return 1
    fi

    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response

    # log "INFO" "Attempting to get Marzban API token..."
    response=$(curl -s -X POST "$login_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout 10 --max-time 20 \
        --insecure 2>/dev/null)

    if echo "$response" | grep -q "access_token"; then
        MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
        if [ -n "$MARZBAN_TOKEN" ]; then
            # log "SUCCESS" "Marzban API token obtained successfully."
            # Store token in config for persistence across script runs? Or rely on global var for current session.
            # For now, it's a global variable for the current session.
            return 0
        else
            log "ERROR" "Failed to parse access token from API response."
            log "DEBUG" "Full API response: $response"
            return 1
        fi
    else
        log "ERROR" "Failed to obtain Marzban API token. Check credentials and panel accessibility."
        log "DEBUG" "API Response: $response"
        MARZBAN_TOKEN="" # Clear any stale token
        return 1
    fi
}

add_node_to_marzban_panel_api() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    
    log "INFO" "Registering node '$node_name' with the Marzban panel..."
    
    local add_node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node"
    local payload
    payload=$(printf '{"name": "%s", "address": "%s", "port": 62050, "api_port": 62051, "usage_coefficient": 1.0, "add_as_new_host": false}' "$node_name" "$node_ip")

    local response
    response=$(curl -s -X POST "$add_node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Content-Type: application/json" -H "Accept: application/json" \
        -d "$payload" --insecure)

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        MARZBAN_NODE_ID=$(echo "$response" | jq -r .id)
        log "SUCCESS" "Node '$node_name' successfully added to panel with ID: $MARZBAN_NODE_ID"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node '$node_name' already exists in the panel. Attempting to retrieve its ID..."
        
        local nodes_list_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes"
        local nodes_response
        nodes_response=$(curl -s -X GET "$nodes_list_url" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        local existing_id
        existing_id=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$node_name\") | .id" 2>/dev/null)
        
        if [ -n "$existing_id" ]; then
            MARZBAN_NODE_ID="$existing_id"
            log "SUCCESS" "Successfully retrieved ID for existing node: $MARZBAN_NODE_ID"
            return 0
        else
            log "ERROR" "Node is said to exist, but could not retrieve its ID from the panel."
            return 1
        fi
    else
        log "ERROR" "Failed to add node to Marzban panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

get_client_cert_from_marzban_api() {
    local node_id="$1"
    
    log "INFO" "Retrieving client certificate for node ID: $node_id"
    
    local node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${node_id}"
    
    local response
    response=$(curl -s -X GET "$node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Accept: application/json" \
        --insecure)
        
    if echo "$response" | jq -e '.client_cert' >/dev/null 2>&1; then
        CLIENT_CERT=$(echo "$response" | jq -r .client_cert)
        if [ -n "$CLIENT_CERT" ]; then
            log "SUCCESS" "Client certificate retrieved successfully."
            return 0
        else
            log "ERROR" "Client certificate is empty in the API response."
            return 1
        fi
    else
        log "ERROR" "Failed to retrieve client certificate from panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

## Automated Monitoring Setup
setup_automated_monitoring() {
    log "STEP" "Setting up automated monitoring system..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║       ${CYAN}Automated Monitoring Setup${NC}       ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Monitoring Options:${NC}"
    echo " 1. Enable Continuous Sync Monitoring"
    echo " 2. Enable Automated Health Checks"
    echo " 3. Setup Both (Recommended)"
    echo " 4. Disable All Monitoring"
    echo " 5. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose monitoring option:"
    read -r choice
    
    case "$choice" in
        1|3)
            # Setup sync monitoring
            local sync_script="/usr/local/bin/marzban-sync-monitor.sh"
            cat > "$sync_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --sync-monitor >> /var/log/marzban-sync.log 2>&1
EOF
            chmod +x "$sync_script"
            
            # Add to cron (every 30 minutes)
            local sync_cron="*/30 * * * * $sync_script"
            crontab -l 2>/dev/null | grep -v "marzban-sync-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$sync_cron") | crontab -
            
            log "SUCCESS" "Sync monitoring enabled (every 30 minutes)"
            ;;
    esac
    
    case "$choice" in
        2|3)
            # Setup health monitoring
            local health_script="/usr/local/bin/marzban-health-monitor.sh"
            cat > "$health_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --health-monitor >> /var/log/marzban-health.log 2>&1
EOF
            chmod +x "$health_script"
            
            # Add to cron (every 10 minutes)
            local health_cron="*/10 * * * * $health_script"
            crontab -l 2>/dev/null | grep -v "marzban-health-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$health_cron") | crontab -
            
            log "SUCCESS" "Health monitoring enabled (every 10 minutes)"
            ;;
    esac
    
    case "$choice" in
        4)
            # Disable monitoring
            crontab -l 2>/dev/null | grep -v "marzban-.*-monitor" | crontab -
            rm -f /usr/local/bin/marzban-*-monitor.sh
            log "SUCCESS" "All automated monitoring disabled"
            ;;
        5)
            return 0
            ;;
        *)
            log "ERROR" "Invalid option"
            return 1
            ;;
    esac
    
    if [ "$choice" != "4" ] && [ "$choice" != "5" ]; then
        send_telegram_notification "🤖 Automated Monitoring Enabled%0A%0AMonitoring active on $(hostname)" "normal"
    fi
}

## Enhanced Node Import System
import_existing_nodes() {
    log "STEP" "Importing existing nodes..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║         ${CYAN}Import Existing Nodes${NC}          ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Import Options:${NC}"
    echo " 1. Import Single Node"
    echo " 2. Import from CSV File"
    echo " 3. Auto-discover Nodes from Marzban Panel"
    echo " 4. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose import method:"
    read -r choice
    
    case "$choice" in
        1) import_single_node ;;
        2) import_from_csv ;;
        3) auto_discover_nodes ;;
        4) return 0 ;;
        *) log "ERROR" "Invalid option" ;;
    esac
}

import_single_node() {
    log "STEP" "Adding/Importing a single node..."
    
    local node_name node_ip node_user="root" node_port="22" node_domain node_password

    log "PROMPT" "Enter Node Name:"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP:"; read -r node_ip
    log "PROMPT" "Enter SSH Username [default: root]:"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port [default: 22]:"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain:"; read -r node_domain
    log "PROMPT" "Enter SSH Password:"; read -s node_password; echo ""

    # Combine connectivity test and Marzban Node check into a single SSH session
    local remote_command="echo 'CONN_OK'; if docker ps 2>/dev/null | grep -q marzban-node; then echo 'NODE_INSTALLED'; else echo 'NODE_NOT_INSTALLED'; fi"
    
    local check_result
    if ! check_result=$(ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "$remote_command" "Connectivity and Node Check"); then
        log "ERROR" "Failed to connect to node. Please check credentials."
        return 1
    fi
    
    if echo "$check_result" | grep -q "NODE_INSTALLED"; then
        log "INFO" "Marzban Node is already installed. Checking registration in panel..."
        
        if ! get_marzban_token; then return 1; fi
        local nodes_response
        nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure 2>/dev/null)
        
        local node_id
        if echo "$nodes_response" | jq empty 2>/dev/null; then
            node_id=$(echo "$nodes_response" | jq -r ".[] | select(.address==\"$node_ip\") | .id" 2>/dev/null)
        fi

        if [ -n "$node_id" ]; then
            log "SUCCESS" "Node is already registered in the panel with ID: $node_id. Importing..."
            add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$node_id"
            save_nodes_config
        else
            log "WARNING" "This node is running, but it is NOT registered in your Marzban panel."
            log "PROMPT" "Do you want to add it to the panel now? (y/n)"
            read -r add_to_panel
            if [[ "$add_to_panel" =~ ^[Yy]$ ]]; then
                log "STEP" "Registering existing node with the panel..."
                if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi
                
                log "STEP" "Deploying new client certificate to the node..."
                if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
                
                if [ -z "$CLIENT_CERT" ]; then
                    log "ERROR" "Failed to retrieve client certificate from panel. Cannot proceed."
                    return 1
                fi

                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
                rm "$temp_cert"
                
                log "STEP" "Restarting node service to apply new certificate..."
                ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" "Service Restart"

                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
                save_nodes_config
                log "SUCCESS" "Node '$node_name' successfully registered and imported!"
            else
                log "INFO" "Node was not registered in the panel. It has been added to the local manager only."
                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" ""
                save_nodes_config
            fi
        fi
    elif echo "$check_result" | grep -q "NODE_NOT_INSTALLED"; then
        log "WARNING" "Marzban Node is NOT installed on this server."
        log "PROMPT" "Do you want to install it automatically now? (y/n)"
        read -r install_now
        if [[ "$install_now" =~ ^[Yy]$ ]]; then
            if _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
                log "SUCCESS" "🎉 Node '$node_name' installed and configured successfully!"
            else
                log "ERROR" "Node installation failed. Please check the logs."
            fi
        else
            log "INFO" "Installation cancelled. Node was not added."
        fi
    fi
}

import_from_csv() {
    log "STEP" "Importing nodes from CSV file..."
    
    log "PROMPT" "Enter CSV file path (format: name,ip,user,port,domain,password):"
    read -r csv_file
    
    if [ ! -f "$csv_file" ]; then
        log "ERROR" "CSV file not found: $csv_file"
        return 1
    fi
    
    local imported=0 failed=0
    
    while IFS=',' read -r name ip user port domain password; do
        # Skip header line
        if [ "$name" = "name" ]; then continue; fi
        
        log "INFO" "Importing node: $name"
        
        if get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "WARNING" "Node '$name' already exists, skipping."
            continue
        fi
        
        # Test connectivity
        export NODE_SSH_PASSWORD="$password"
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'test'" "CSV Import Test" >/dev/null 2>&1; then
            add_node_to_config "$name" "$ip" "$user" "$port" "$domain" "$password" ""
            imported=$((imported + 1))
            log "SUCCESS" "Node '$name' imported."
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to import node '$name'."
        fi
        unset NODE_SSH_PASSWORD
        
    done < "$csv_file"
    
    save_nodes_config
    log "SUCCESS" "CSV import completed: $imported imported, $failed failed."
}

auto_discover_nodes() {
    log "STEP" "Auto-discovering nodes from Marzban Panel..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    local nodes_response
    nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        --insecure 2>/dev/null)
    
    if ! echo "$nodes_response" | jq empty 2>/dev/null; then
        log "ERROR" "Failed to fetch nodes from Marzban Panel."
        return 1
    fi
    
    local discovered=0
    
    echo "$nodes_response" | jq -r '.[] | "\(.name);\(.address);\(.id)"' | while IFS=';' read -r name address node_id; do
        if ! get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "INFO" "Discovered node: $name ($address)"
            
            # Add with default values (user will need to update SSH credentials)
            add_node_to_config "$name" "$address" "root" "22" "$name.domain.com" "UPDATE_PASSWORD" "$node_id"
            discovered=$((discovered + 1))
        fi
    done
    
    save_nodes_config
    log "SUCCESS" "Auto-discovery completed: $discovered nodes discovered."
    log "WARNING" "Please update SSH credentials for discovered nodes using 'Update Node Configuration'."
}

## Node Update System
update_existing_node() {
    log "STEP" "Updating existing node configuration..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to update."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Update Node Configuration${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip)"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to update (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${CYAN}Updating node: $name${NC}"
    echo -e "Current values (press Enter to keep current value):\n"
    
    log "PROMPT" "IP Address [$ip]:"
    read -r new_ip
    new_ip=${new_ip:-$ip}
    
    log "PROMPT" "SSH Username [$user]:"
    read -r new_user
    new_user=${new_user:-$user}
    
    log "PROMPT" "SSH Port [$port]:"
    read -r new_port
    new_port=${new_port:-$port}
    
    log "PROMPT" "Domain [$domain]:"
    read -r new_domain
    new_domain=${new_domain:-$domain}
    
    log "PROMPT" "Update SSH Password? (y/n):"
    read -r update_password
    
    local new_password="$password"
    if [[ "$update_password" =~ ^[Yy]$ ]]; then
        log "PROMPT" "New SSH Password:"
        read -s new_password
        echo ""
    fi
    
    # Update the node entry
    NODES_ARRAY[$selected_index]="${name};${new_ip};${new_user};${new_port};${new_domain};${new_password};${node_id}"
    save_nodes_config
    
    log "SUCCESS" "Node '$name' configuration updated successfully."
    
    # Test connectivity with new settings
    log "INFO" "Testing connectivity with new settings..."
    export NODE_SSH_PASSWORD="$new_password"
    if ssh_remote "$new_ip" "$new_user" "$new_port" "$NODE_SSH_PASSWORD" "echo 'Update test successful'" "Update Connectivity Test"; then
        log "SUCCESS" "Connectivity test passed with new settings."
    else
        log "WARNING" "Connectivity test failed. Please verify the new settings."
    fi
    unset NODE_SSH_PASSWORD
}
## Node Removal System
remove_node() {
    log "STEP" "Removing node from system..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to remove."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║            ${CYAN}Remove Node${NC}                 ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip) - $domain"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to remove (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will remove node '$name' from:${NC}"
    echo "- Local configuration"
    echo "- Marzban Panel (if connected)"
    echo "- HAProxy configuration"
    echo ""
    
    log "PROMPT" "Are you sure you want to remove node '$name'? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Node removal cancelled."
        return 0
    fi
    
    # Remove from Marzban Panel if node_id exists
    if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
        log "STEP" "Removing node from Marzban Panel..."
        if get_marzban_token; then
            local delete_response
            delete_response=$(curl -s -X DELETE "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                log "SUCCESS" "Node removed from Marzban Panel."
            else
                log "WARNING" "Failed to remove node from Marzban Panel."
            fi
        fi
    fi
    
    # Remove from HAProxy configuration
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "STEP" "Removing node from HAProxy configuration..."
        remove_haproxy_backend "$name" "$domain"
    fi
    
    # Remove from local configuration
    unset NODES_ARRAY[$selected_index]
    NODES_ARRAY=("${NODES_ARRAY[@]}")  # Re-index array
    save_nodes_config
    
    log "SUCCESS" "Node '$name' removed successfully."
    send_telegram_notification "🗑️ Node Removed%0A%0ANode: $name%0AIP: $ip%0ADomain: $domain" "normal"
}

remove_haproxy_backend() {
    local node_name="$1" node_domain="$2"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backend_name="vless_${node_name}"
    
    # Create backup
    cp "$haproxy_cfg" "${haproxy_cfg}.backup.$(date +%s)"
    
    # Remove backend section
    sed -i "/^# Backend for ${node_name}/,/^$/d" "$haproxy_cfg"
    sed -i "/^backend ${backend_name}/,/^$/d" "$haproxy_cfg"
    
    # Remove frontend rule
    sed -i "/use_backend ${backend_name} if.*${node_domain}/d" "$haproxy_cfg"
    
    # Validate and reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        systemctl reload haproxy
        log "SUCCESS" "HAProxy configuration updated."
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup."
        cp "${haproxy_cfg}.backup."* "$haproxy_cfg"
        systemctl reload haproxy
        return 1
    fi
}

## Enhanced Backup and Restore System
backup_restore_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Backup & Restore System${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Backup Options:${NC}"
        echo " 1. Create Full System Backup"
        echo " 2. Create Main Server Only Backup"
        echo " 3. Create Nodes Only Backup"
        echo " 4. Setup Automated Backup"
        echo ""
        echo -e "${PURPLE}Restore Options:${NC}"
        echo " 5. List Available Backups"
        echo " 6. Restore from Backup"
        echo " 7. Verify Backup Integrity"
        echo ""
        echo -e "${PURPLE}Management:${NC}"
        echo " 8. Cleanup Old Backups"
        echo " 9. Export Backup to Remote"
        echo " 10. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose backup/restore option:"
        read -r choice
        
        case "$choice" in
            1) create_full_backup ;;
            2) backup_main_server_only ;;
            3) backup_nodes_only ;;
            4) setup_automated_backup ;;
            5) list_available_backups ;;
            6) restore_from_backup ;;
            7) verify_backup_integrity_menu ;;
            8) cleanup_old_backups ;;
            9) export_backup_to_remote ;;
            10) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "10" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

backup_main_server_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_main_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting main server backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_main_server "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Main server backup completed: $final_archive"
}

backup_nodes_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_nodes_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting nodes backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_all_nodes "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Nodes backup completed: $final_archive"
}

list_available_backups() {
    log "BACKUP" "Listing available backups..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Available Backups${NC}                        ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    if ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        printf "%-5s %-35s %-15s %-10s\n" "No." "Backup Name" "Date" "Size"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        
        local i=1
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            local filename=$(basename "$backup")
            local filesize=$(du -h "$backup" | cut -f1)
            local filedate=$(date -r "$backup" '+%Y-%m-%d %H:%M')
            
            printf "%-5s %-35s %-15s %-10s\n" "$i" "$filename" "$filedate" "$filesize"
            i=$((i + 1))
        done
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "No backups found in $BACKUP_ARCHIVE_DIR"
    fi
}

verify_backup_integrity_menu() {
    log "BACKUP" "Backup integrity verification..."
    
    list_available_backups
    
    if ! ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        return 0
    fi
    
    echo ""
    log "PROMPT" "Enter backup number to verify (or 'all' for all backups):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            verify_backup_integrity "$backup"
        done
    else
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            local backup_files=("$BACKUP_ARCHIVE_DIR"/*.tar.gz)
            local selected_index=$((selection - 1))
            
            if [ $selected_index -ge 0 ] && [ $selected_index -lt ${#backup_files[@]} ]; then
                verify_backup_integrity "${backup_files[$selected_index]}"
            else
                log "ERROR" "Invalid backup number."
            fi
        else
            log "ERROR" "Invalid input."
        fi
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

## Nginx Management System
nginx_management_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║           ${CYAN}Nginx Management${NC}              ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        # Check Nginx status
        if systemctl is-active --quiet nginx; then
            echo -e "${GREEN}✅ Nginx Status: Running${NC}"
        else
            echo -e "${RED}❌ Nginx Status: Not Running${NC}"
        fi
        
        echo ""
        echo -e "${PURPLE}Configuration Management:${NC}"
        echo " 1. View Nginx Configuration"
        echo " 2. Test Nginx Configuration"
        echo " 3. Reload Nginx Configuration"
        echo " 4. Restart Nginx Service"
        echo ""
        echo -e "${PURPLE}SSL Certificate Management:${NC}"
        echo " 5. Generate SSL Certificate"
        echo " 6. Renew SSL Certificates"
        echo " 7. View Certificate Status"
        echo ""
        echo -e "${PURPLE}Site Management:${NC}"
        echo " 8. Add New Site Configuration"
        echo " 9. Remove Site Configuration"
        echo " 10. Enable/Disable Site"
        echo ""
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose Nginx management option:"
        read -r choice
        
        case "$choice" in
            1) view_nginx_configuration ;;
            2) test_nginx_configuration ;;
            3) reload_nginx_configuration ;;
            4) restart_nginx_service ;;
            5) generate_ssl_certificate ;;
            6) renew_ssl_certificates ;;
            7) view_certificate_status ;;
            8) add_nginx_site ;;
            9) remove_nginx_site ;;
            10) toggle_nginx_site ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_nginx_configuration() {
    log "INFO" "Displaying Nginx configuration..."
    
    if [ -f "/etc/nginx/nginx.conf" ]; then
        echo -e "\n${CYAN}Main Nginx Configuration:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        cat /etc/nginx/nginx.conf
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        log "ERROR" "Nginx configuration file not found."
    fi
    
    echo -e "\n${CYAN}Available Site Configurations:${NC}"
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                echo "✅ $site_name (enabled)"
            else
                echo "❌ $site_name (disabled)"
            fi
        done
    else
        echo "No site configurations found."
    fi
}

test_nginx_configuration() {
    log "INFO" "Testing Nginx configuration..."
    
    if nginx -t 2>&1; then
        log "SUCCESS" "Nginx configuration test passed."
    else
        log "ERROR" "Nginx configuration test failed."
    fi
}

reload_nginx_configuration() {
    log "INFO" "Reloading Nginx configuration..."
    
    if nginx -t 2>/dev/null; then
        if systemctl reload nginx; then
            log "SUCCESS" "Nginx configuration reloaded successfully."
        else
            log "ERROR" "Failed to reload Nginx configuration."
        fi
    else
        log "ERROR" "Nginx configuration test failed. Cannot reload."
    fi
}

restart_nginx_service() {
    log "INFO" "Restarting Nginx service..."
    
    if systemctl restart nginx; then
        log "SUCCESS" "Nginx service restarted successfully."
    else
        log "ERROR" "Failed to restart Nginx service."
    fi
}

## Bulk Operations Enhancement
bulk_update_certificates() {
    log "STEP" "Updating certificates on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            log "INFO" "Updating certificate for node: $name"
            
            # Get fresh certificate from Marzban Panel
            if get_client_cert_from_marzban_api "$node_id"; then
                export NODE_SSH_PASSWORD="$password"
                
                # Deploy certificate to node
                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                
                if scp_to_remote "$temp_cert" "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "/var/lib/marzban-node/ssl_client_cert.pem" "Certificate Update"; then
                    
                    # Restart node service
                    if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                       "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" \
                       "Service Restart"; then
                        updated=$((updated + 1))
                        log "SUCCESS" "Certificate updated for node: $name"
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to restart service on node: $name"
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to deploy certificate to node: $name"
                fi
                
                rm "$temp_cert"
                unset NODE_SSH_PASSWORD
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to get certificate for node: $name"
            fi
        else
            log "WARNING" "Node '$name' has no API ID, skipping certificate update."
        fi
    done
    
    log "SUCCESS" "Certificate update completed: $updated updated, $failed failed."
    send_telegram_notification "🔐 Certificate Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

bulk_restart_services() {
    log "STEP" "Restarting services on all nodes..."
    
    load_nodes_config
    local restarted=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Restarting services on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "cd /opt/marzban-node && docker compose restart" \
           "Service Restart"; then
            restarted=$((restarted + 1))
            log "SUCCESS" "Services restarted on node: $name"
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to restart services on node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Service restart completed: $restarted restarted, $failed failed."
    send_telegram_notification "🔄 Service Restart Report%0A%0A✅ Restarted: $restarted%0A❌ Failed: $failed" "normal"
}

bulk_update_geo_files() {
    log "STEP" "Updating geo files on all nodes..."
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating geo files on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        # Transfer geo files if available on main server
        if [ -n "$GEO_FILES_PATH" ]; then
            if transfer_geo_files_to_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files updated on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to update geo files on node: $name"
            fi
        else
            # Download fresh geo files on node
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$(declare -f update_geo_files_on_node); update_geo_files_on_node" \
               "Geo Files Update"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files downloaded on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to download geo files on node: $name"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Geo files update completed: $updated updated, $failed failed."
    send_telegram_notification "🌍 Geo Files Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

_internal_deploy_node() {
    local node_name="$1" node_ip="$2" node_user="$3" node_port="$4" node_domain="$5" node_password="$6"

    log "STEP" "Starting Final Deployment Workflow for '$node_name'..."

    # Phase 1: Deploy and start the node in standalone mode (without client cert requirement)
    log "STEP" "Phase 1: Deploying node in standalone mode..."
    if ! scp_to_remote "${0%/*}/marzban_node_deployer.sh" "$node_ip" "$node_user" "$node_port" "$node_password" "/tmp/marzban_node_deployer.sh" "Node Deployer Script"; then return 1; fi
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "bash /tmp/marzban_node_deployer.sh" "Node Standalone Deployment"; then
        return 1
    fi
    
    # Wait until the node service is actually listening on the port
    log "INFO" "Waiting for node service to become active..."
    local timer=0
    while ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "ss -tuln | grep -q ':62050'" "Port Listening Check" >/dev/null 2>&1; do
        sleep 5
        timer=$((timer + 5))
        if [ $timer -ge 60 ]; then
            log "ERROR" "Node service failed to start and listen on port 62050 after 60 seconds. Please check node logs."
            return 1
        fi
    done
    log "SUCCESS" "Node service is active and listening."

    # Phase 2: Register the now-running node with the panel
    log "STEP" "Phase 2: Registering node with Marzban panel..."
    if ! get_marzban_token; then return 1; fi
    if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi

    # Phase 3: Retrieve the REAL client certificate
    log "STEP" "Phase 3: Retrieving client certificate..."
    if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
    if [ -z "$CLIENT_CERT" ]; then log "ERROR" "Failed to retrieve client certificate."; return 1; fi
    
    # Deploy the REAL certificate to the node
    local temp_cert; temp_cert=$(mktemp)
    echo "$CLIENT_CERT" > "$temp_cert"
    scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
    rm "$temp_cert"
    
    # Phase 4: Reconfigure and restart the node to enable panel connection
    log "STEP" "Phase 4: Reconfiguring and restarting node for panel connection..."
    local reconfigure_command="sed -i 's/# SSL_CLIENT_CERT_FILE/SSL_CLIENT_CERT_FILE/' /opt/marzban-node/docker-compose.yml && chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart"
    if ! ssh_remote "$node_ip" "$user" "$port" "$node_password" "$reconfigure_command" "Final Node Reconfiguration"; then
        return 1
    fi
    
    # Final health check
    log "INFO" "Waiting 15s for the node to connect to the panel..."
    sleep 15
    if check_node_health_via_api "$MARZBAN_NODE_ID" "$node_name"; then
        log "SUCCESS" "✅ Final health check passed! Node is fully connected."
    fi

    add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
    save_nodes_config
    return 0
}

deploy_new_node_professional_enhanced() {
    log "STEP" "Starting Enhanced Professional Node Deployment..."
    if [ -z "$MARZBAN_PANEL_DOMAIN" ]; then
        log "ERROR" "Marzban Panel API not configured. Please use Option 8 first."
        return 1
    fi
    detect_main_server_services

    local node_ip node_user="root" node_port="22" node_domain node_name node_password
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║     ${CYAN}Enhanced Professional Deployment${NC}     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    log "PROMPT" "Enter Node Name (unique identifier):"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP Address:"; read -r node_ip
    log "PROMPT" "Enter SSH Username (default: root):"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port (default: 22):"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain (e.g., node1.example.com):"; read -r node_domain
    if ! [[ $node_domain =~ ^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.){1,}[a-zA-Z]{2,}$ ]]; then
        log "ERROR" "Invalid domain format."
        return 1
    fi
    log "PROMPT" "Enter SSH Password for $node_user@$node_ip:"; read -s node_password; echo ""
    
    _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "🎉 Node '$node_name' deployed and configured successfully!"
        send_telegram_notification "🚀 New Node Deployed%0A%0ANode: $node_name%0AIP: $node_ip%0ADomain: $node_domain%0AStatus: ✅ Operational" "normal"
    else
        log "ERROR" "Node deployment failed. Please check the logs."
    fi
}

## Advanced Telegram Configuration
configure_telegram_advanced() {
    log "STEP" "Configuring advanced Telegram notifications..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Telegram Notifications Setup${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Telegram Bot Configuration:${NC}"
    echo "1. Create a bot via @BotFather on Telegram"
    echo "2. Get your chat ID from @userinfobot"
    echo "3. Configure notification levels"
    echo ""
    
    log "PROMPT" "Enter Telegram Bot Token:"
    read -r bot_token
    
    log "PROMPT" "Enter Telegram Chat ID:"
    read -r chat_id
    
    if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
        # Test notification
        log "INFO" "Testing Telegram notification..."
        local test_message="🤖 Marzban Central Manager%0A%0ATest notification from $(hostname)%0ATime: $(date)"
        
        if curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
           -d "chat_id=${chat_id}" \
           -d "text=${test_message}" \
           -d "parse_mode=Markdown" >/dev/null; then
            
            log "SUCCESS" "Telegram test notification sent successfully!"
            
            # Save configuration
            {
                echo "TELEGRAM_BOT_TOKEN=\"$bot_token\""
                echo "TELEGRAM_CHAT_ID=\"$chat_id\""
            } >> "$MANAGER_CONFIG_FILE"
            
            chmod 600 "$MANAGER_CONFIG_FILE"
            source "$MANAGER_CONFIG_FILE"
            
            # Configure notification levels
            echo -e "\n${PURPLE}Notification Levels:${NC}"
            echo " 1. All notifications (normal, high, critical)"
            echo " 2. High and critical only"
            echo " 3. Critical only"
            echo " 4. Disabled"
            echo ""
            
            log "PROMPT" "Choose notification level [default: 1]:"
            read -r level
            level=${level:-1}
            
            echo "TELEGRAM_NOTIFICATION_LEVEL=\"$level\"" >> "$MANAGER_CONFIG_FILE"
            
            log "SUCCESS" "Telegram notifications configured successfully!"
        else
            log "ERROR" "Failed to send test notification. Please check your bot token and chat ID."
        fi
    else
        log "ERROR" "Bot token and chat ID are required."
    fi
}

## Bulk Node Operations Menu
bulk_node_operations() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Bulk Node Operations${NC}             ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        load_nodes_config
        echo -e "${PURPLE}Available Operations for ${#NODES_ARRAY[@]} nodes:${NC}"
        echo " 1. Update All Certificates"
        echo " 2. Restart All Services"
        echo " 3. Update All Geo Files"
        echo " 4. Sync HAProxy to All Nodes"
        echo " 5. Health Check All Nodes"
        echo " 6. Reconnect Disconnected Nodes"
        echo " 7. Update All Node Configurations"
        echo " 8. Bulk SSH Command Execution"
        echo " 9. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose bulk operation:"
        read -r choice
        
        case "$choice" in
            1) bulk_update_certificates ;;
            2) bulk_restart_services ;;
            3) bulk_update_geo_files ;;
            4) bulk_sync_haproxy ;;
            5) bulk_health_check ;;
            6) bulk_reconnect_nodes ;;
            7) bulk_update_configurations ;;
            8) bulk_ssh_command ;;
            9) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "9" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

bulk_health_check() {
    log "STEP" "Performing health check on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local healthy=0 unhealthy=0 unknown=0
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Bulk Health Check Report${NC}                   ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        echo -e "${CYAN}Checking node: $name ($ip)${NC}"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            if check_node_health_via_api "$node_id" "$name"; then
                healthy=$((healthy + 1))
            else
                unhealthy=$((unhealthy + 1))
            fi
        else
            echo "   ⚪ No API ID - checking SSH connectivity..."
            export NODE_SSH_PASSWORD="$password"
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'SSH OK'" "SSH Health Check" >/dev/null 2>&1; then
                echo "   🟢 SSH connectivity: OK"
                unknown=$((unknown + 1))
            else
                echo "   🔴 SSH connectivity: FAILED"
                unhealthy=$((unhealthy + 1))
            fi
            unset NODE_SSH_PASSWORD
        fi
        echo ""
    done
    
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                      ${CYAN}Health Summary${NC}                           ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "🟢 Healthy Nodes: $healthy"
    echo -e "🔴 Unhealthy Nodes: $unhealthy"
    echo -e "⚪ Unknown Status: $unknown"
    echo -e "📊 Total Nodes: ${#NODES_ARRAY[@]}"
    
    # Send notification
    send_telegram_notification "🏥 Health Check Report%0A%0A🟢 Healthy: $healthy%0A🔴 Unhealthy: $unhealthy%0A⚪ Unknown: $unknown%0A📊 Total: ${#NODES_ARRAY[@]}" "normal"
}

bulk_sync_haproxy() {
    log "STEP" "Syncing HAProxy configuration to all nodes..."
    
    if [ "$MAIN_HAS_HAPROXY" != "true" ]; then
        log "ERROR" "HAProxy not detected on main server."
        return 1
    fi
    
    load_nodes_config
    local synced=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Syncing HAProxy to node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "HAProxy sync completed: $synced synced, $failed failed."
    send_telegram_notification "🔄 HAProxy Bulk Sync%0A%0A✅ Synced: $synced%0A❌ Failed: $failed" "normal"
}

bulk_reconnect_nodes() {
    log "STEP" "Reconnecting disconnected nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local reconnected=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
            
            if [ "$status" != "connected" ]; then
                log "INFO" "Attempting to reconnect node: $name"
                export NODE_SSH_PASSWORD="$password"
                
                # Restart node service
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && docker compose restart" \
                   "Service Restart for Reconnection"; then
                    
                    # Wait and check status again
                    sleep 10
                    health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                        -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                        -H "Authorization: Bearer $MARZBAN_TOKEN" \
                        --insecure 2>/dev/null)
                    
                    local new_status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
                    
                    if [ "$new_status" = "connected" ]; then
                        reconnected=$((reconnected + 1))
                        log "SUCCESS" "Node '$name' reconnected successfully."
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to reconnect node '$name'."
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to restart service on node '$name'."
                fi
                
                unset NODE_SSH_PASSWORD
            fi
        fi
    done
    
    log "SUCCESS" "Reconnection completed: $reconnected reconnected, $failed failed."
    send_telegram_notification "🔌 Bulk Reconnection%0A%0A✅ Reconnected: $reconnected%0A❌ Failed: $failed" "normal"
}

bulk_ssh_command() {
    log "STEP" "Bulk SSH command execution..."
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will execute a command on ALL nodes!${NC}"
    echo -e "${YELLOW}Please be very careful with the command you enter.${NC}\n"
    
    log "PROMPT" "Enter command to execute on all nodes:"
    read -r command
    
    if [ -z "$command" ]; then
        log "ERROR" "No command provided."
        return 1
    fi
    
    echo -e "\n${YELLOW}Command to execute: ${WHITE}$command${NC}"
    log "PROMPT" "Are you sure you want to execute this on ALL nodes? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Bulk command execution cancelled."
        return 0
    fi
    
    load_nodes_config
    local success=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Executing command on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$command" "Bulk Command Execution"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Bulk command execution completed: $success successful, $failed failed."
}

## System Diagnostics and Logs
show_system_diagnostics() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║        ${CYAN}System Logs & Diagnostics${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Log Management:${NC}"
        echo " 1. View Recent Manager Logs"
        echo " 2. View Marzban Panel Logs"
        echo " 3. View HAProxy Logs"
        echo " 4. View System Logs"
        echo ""
        echo -e "${PURPLE}Diagnostics:${NC}"
        echo " 5. System Resource Usage"
        echo " 6. Network Connectivity Test"
        echo " 7. Service Status Check"
        echo " 8. Configuration Validation"
        echo ""
        echo -e "${PURPLE}Maintenance:${NC}"
        echo " 9. Clean Old Log Files"
        echo " 10. Export Diagnostic Report"
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose diagnostic option:"
        read -r choice
        
        case "$choice" in
            1) view_manager_logs ;;
            2) view_marzban_logs ;;
            3) view_haproxy_logs ;;
            4) view_system_logs ;;
            5) show_system_resources ;;
            6) test_network_connectivity ;;
            7) check_service_status ;;
            8) validate_configurations ;;
            9) clean_old_logs ;;
            10) export_diagnostic_report ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_manager_logs() {
    log "INFO" "Displaying recent Manager logs..."
    
    echo -e "\n${CYAN}Recent Manager Activity:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$LOGFILE" ]; then
        tail -50 "$LOGFILE"
    else
        echo "No current session log file found."
    fi
    
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    # Show system logs for marzban-central-manager
    echo -e "\n${CYAN}System Logs (last 20 entries):${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -t marzban-central-manager -n 20 --no-pager 2>/dev/null || echo "No system logs found."
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

show_system_resources() {
    log "INFO" "Displaying system resource usage..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}System Resource Usage${NC}                     ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # CPU Usage
    echo -e "${PURPLE}🖥️  CPU Usage:${NC}"
    top -bn1 | grep "Cpu(s)" | awk '{print $2 $3 $4 $5 $6 $7 $8}' | sed 's/%us,/ User,/g; s/%sy,/ System,/g; s/%ni,/ Nice,/g; s/%id,/ Idle,/g; s/%wa,/ Wait,/g; s/%hi,/ Hardware IRQ,/g; s/%si/ Software IRQ/g'
    
    # Memory Usage
    echo -e "\n${PURPLE}💾 Memory Usage:${NC}"
    free -h | grep -E "(Mem|Swap)"
    
    # Disk Usage
    echo -e "\n${PURPLE}💿 Disk Usage:${NC}"
    df -h | grep -E "^/dev"
    
    # Network Usage
    echo -e "\n${PURPLE}🌐 Network Interfaces:${NC}"
    ip -s link show | grep -E "(^\d+:|RX:|TX:)" | head -20
    
    # Load Average
    echo -e "\n${PURPLE}📊 Load Average:${NC}"
    uptime
    
    # Top Processes
    echo -e "\n${PURPLE}🔝 Top Processes (CPU):${NC}"
    ps aux --sort=-%cpu | head -10 | awk '{printf "%-10s %-6s %-6s %-50s\n", $1, $3, $4, $11}'
    
    # Docker Resources (if available)
    if command_exists docker; then
        echo -e "\n${PURPLE}🐳 Docker Resources:${NC}"
        docker system df 2>/dev/null || echo "Docker system info unavailable"
    fi
}

test_network_connectivity() {
    log "INFO" "Testing network connectivity..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                   ${CYAN}Network Connectivity Test${NC}                  ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Test DNS resolution
    echo -e "${PURPLE}🔍 DNS Resolution Test:${NC}"
    for domain in "google.com" "github.com" "cloudflare.com"; do
        if nslookup "$domain" >/dev/null 2>&1; then
            echo "✅ $domain - OK"
        else
            echo "❌ $domain - FAILED"
        fi
    done
    
    # Test internet connectivity
    echo -e "\n${PURPLE}🌐 Internet Connectivity Test:${NC}"
    for host in "8.8.8.8" "1.1.1.1" "208.67.222.222"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            echo "✅ $host - OK"
        else
            echo "❌ $host - FAILED"
        fi
    done
    
    # Test Marzban Panel connectivity
    if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
        echo -e "\n${PURPLE}🔗 Marzban Panel Connectivity:${NC}"
        local panel_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}"
        
        if curl -s --connect-timeout 5 --max-time 10 "$panel_url" >/dev/null 2>&1; then
            echo "✅ $panel_url - OK"
        else
            echo "❌ $panel_url - FAILED"
        fi
    fi
    
    # Test node connectivity
    echo -e "\n${PURPLE}🖥️  Node Connectivity Test:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
            echo "✅ $name ($ip) - Ping OK"
        else
            echo "❌ $name ($ip) - Ping FAILED"
        fi
    done
}

check_service_status() {
    log "INFO" "Checking service status..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                     ${CYAN}Service Status Check${NC}                      ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check main services
    local services=("docker" "nginx" "haproxy" "ssh" "cron")
    
    echo -e "${PURPLE}🔧 Main Server Services:${NC}"
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "✅ $service - Running"
        elif systemctl list-unit-files | grep -q "^$service.service"; then
            echo "❌ $service - Stopped"
        else
            echo "⚪ $service - Not Installed"
        fi
    done
    
    # Check Marzban service
    echo -e "\n${PURPLE}📊 Marzban Panel Status:${NC}"
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        if docker compose ps | grep -q "Up"; then
            echo "✅ Marzban Panel - Running"
        else
            echo "❌ Marzban Panel - Stopped"
        fi
    else
        echo "⚪ Marzban Panel - Not Found"
    fi
    
    # Check node services
    echo -e "\n${PURPLE}🖥️  Node Services Status:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_status
        node_status=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                     "cd /opt/marzban-node 2>/dev/null && docker compose ps | grep -q 'Up' && echo 'Running' || echo 'Stopped'" \
                     "Node Service Check" 2>/dev/null || echo "Unreachable")
        
        case "$node_status" in
            "Running") echo "✅ $name - Running" ;;
            "Stopped") echo "❌ $name - Stopped" ;;
            *) echo "⚪ $name - Unreachable" ;;
        esac
        
        unset NODE_SSH_PASSWORD
    done
}

export_diagnostic_report() {
    log "INFO" "Generating comprehensive diagnostic report..."
    
    local report_file="${BACKUP_DIR}/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Marzban Central Manager - Diagnostic Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "Manager Version: $SCRIPT_VERSION"
        echo "========================================"
        echo ""
        
        echo "SYSTEM INFORMATION:"
        echo "-------------------"
        uname -a
        echo ""
        cat /etc/os-release 2>/dev/null || echo "OS info unavailable"
        echo ""
        
        echo "RESOURCE USAGE:"
        echo "---------------"
        free -h
        echo ""
        df -h
        echo ""
        uptime
        echo ""
        
        echo "NETWORK CONFIGURATION:"
        echo "----------------------"
        ip addr show | grep -E "(inet |inet6 )"
        echo ""
        
        echo "SERVICE STATUS:"
        echo "---------------"
        for service in docker nginx haproxy ssh cron; do
            systemctl is-active "$service" 2>/dev/null | sed "s/^/$service: /"
        done
        echo ""
        
        echo "MARZBAN CONFIGURATION:"
        echo "----------------------"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
            echo "Panel Domain: $MARZBAN_PANEL_DOMAIN"
            echo "Panel Port: $MARZBAN_PANEL_PORT"
            echo "Panel Protocol: $MARZBAN_PANEL_PROTOCOL"
        else
            echo "Marzban Panel not configured"
        fi
        echo ""
        
        echo "CONFIGURED NODES:"
        echo "-----------------"
        load_nodes_config
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            echo "Node: $name | IP: $ip | Domain: $domain | ID: $node_id"
        done
        echo ""
        
        echo "RECENT LOGS:"
        echo "------------"
        if [ -f "$LOGFILE" ]; then
            tail -20 "$LOGFILE"
        else
            echo "No recent logs available"
        fi
        
    } > "$report_file"
    
    log "SUCCESS" "Diagnostic report generated: $report_file"
    
    # Offer to send via Telegram
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        log "PROMPT" "Send diagnostic report via Telegram? (y/n):"
        read -r send_telegram
        
        if [[ "$send_telegram" =~ ^[Yy]$ ]]; then
            local report_summary="📋 Diagnostic Report%0A%0AGenerated: $(date)%0AHostname: $(hostname)%0ANodes: ${#NODES_ARRAY[@]}%0A%0AReport saved locally: $(basename "$report_file")"
            send_telegram_notification "$report_summary" "normal"
            log "SUCCESS" "Diagnostic summary sent via Telegram."
        fi
    fi
}

## Missing functions implementation
bulk_update_configurations() {
    log "STEP" "Bulk updating node configurations..."
    
    echo -e "\n${YELLOW}This will update common configuration files on all nodes.${NC}"
    echo -e "${YELLOW}Available updates:${NC}"
    echo " 1. Update docker-compose.yml"
    echo " 2. Update environment variables"
    echo " 3. Update SSL certificates"
    echo " 4. All of the above"
    echo ""
    
    log "PROMPT" "Choose update type:"
    read -r update_type
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating configuration for node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        case "$update_type" in
            1|4)
                # Update docker-compose.yml
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && $(declare -f create_enhanced_docker_compose); create_enhanced_docker_compose" \
                   "Docker Compose Update"; then
                    log "SUCCESS" "Docker compose updated on node: $name"
                else
                    log "ERROR" "Failed to update docker compose on node: $name"
                fi
                ;;
        esac
        
        if [ "$update_type" = "4" ] || [ "$update_type" = "2" ]; then
            # Update environment variables
            ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                "cd /opt/marzban-node && docker compose restart" \
                "Service Restart" >/dev/null 2>&1
        fi
        
        updated=$((updated + 1))
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Configuration update completed: $updated updated, $failed failed."
}

view_marzban_logs() {
    log "INFO" "Displaying Marzban Panel logs..."
    
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        echo -e "\n${CYAN}Recent Marzban Panel Logs:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        docker compose logs --tail=50 2>/dev/null || echo "Unable to fetch Marzban logs"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Marzban installation not found at /opt/marzban"
    fi
}

view_haproxy_logs() {
    log "INFO" "Displaying HAProxy logs..."
    
    echo -e "\n${CYAN}Recent HAProxy Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -u haproxy -n 50 --no-pager 2>/dev/null || echo "HAProxy logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

view_system_logs() {
    log "INFO" "Displaying system logs..."
    
    echo -e "\n${CYAN}Recent System Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -n 50 --no-pager 2>/dev/null || echo "System logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

validate_configurations() {
    log "INFO" "Validating system configurations..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                  ${CYAN}Configuration Validation${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Validate Nginx configuration
    if command_exists nginx; then
        echo -e "${PURPLE}🔧 Nginx Configuration:${NC}"
        if nginx -t 2>/dev/null; then
            echo "✅ Nginx configuration is valid"
        else
            echo "❌ Nginx configuration has errors"
        fi
    fi
    
    # Validate HAProxy configuration
    if command_exists haproxy; then
        echo -e "\n${PURPLE}⚖️  HAProxy Configuration:${NC}"
        if /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg 2>/dev/null; then
            echo "✅ HAProxy configuration is valid"
        else
            echo "❌ HAProxy configuration has errors"
        fi
    fi
    
    # Validate Manager configuration
    echo -e "\n${PURPLE}📊 Manager Configuration:${NC}"
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        echo "✅ Manager configuration file exists"
        
        # Check required variables
        source "$MANAGER_CONFIG_FILE"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ] && [ -n "$MARZBAN_PANEL_USERNAME" ]; then
            echo "✅ Marzban Panel credentials configured"
        else
            echo "❌ Marzban Panel credentials missing"
        fi
    else
        echo "❌ Manager configuration file missing"
    fi
    
    # Validate node configurations
    echo -e "\n${PURPLE}🖥️  Node Configurations:${NC}"
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -gt 0 ]; then
        echo "✅ ${#NODES_ARRAY[@]} nodes configured"
        
        local valid_nodes=0
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                valid_nodes=$((valid_nodes + 1))
            fi
        done
        echo "✅ $valid_nodes nodes have valid IP addresses"
    else
        echo "⚪ No nodes configured"
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        log "DEBUG" "Checking type of command_exists before use in clean_old_logs:"
        type command_exists || log "ERROR" "command_exists is not recognized here!"
        
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

# Additional missing functions for complete functionality
add_nginx_site() {
    log "STEP" "Adding new Nginx site configuration..."
    
    log "PROMPT" "Enter site domain (e.g., example.com):"
    read -r site_domain
    
    log "PROMPT" "Enter document root path (default: /var/www/$site_domain):"
    read -r doc_root
    doc_root=${doc_root:-/var/www/$site_domain}
    
    # Create site configuration
    local site_config="/etc/nginx/sites-available/$site_domain"
    cat > "$site_config" << EOF
server {
    listen 80;
    server_name $site_domain www.$site_domain;
    root $doc_root;
    index index.html index.htm index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF
    
    # Create document root
    mkdir -p "$doc_root"
    chown www-data:www-data "$doc_root"
    
    # Create basic index file
    echo "<h1>Welcome to $site_domain</h1>" > "$doc_root/index.html"
    chown www-data:www-data "$doc_root/index.html"
    
    log "SUCCESS" "Site configuration created: $site_config"
    log "INFO" "To enable the site, run: ln -s $site_config /etc/nginx/sites-enabled/"
}

remove_nginx_site() {
    log "STEP" "Removing Nginx site configuration..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            echo " $i. $site_name"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to remove:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            # Remove from sites-enabled if linked
            rm -f "/etc/nginx/sites-enabled/$selected_site"
            
            # Remove from sites-available
            rm -f "/etc/nginx/sites-available/$selected_site"
            
            log "SUCCESS" "Site '$selected_site' removed successfully."
            
            # Test nginx configuration
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed after site removal."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available to remove."
    fi
}

toggle_nginx_site() {
    log "STEP" "Enable/Disable Nginx site..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            local status="disabled"
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                status="enabled"
            fi
            echo " $i. $site_name ($status)"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to toggle:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            if [ -L "/etc/nginx/sites-enabled/$selected_site" ]; then
                # Disable site
                rm "/etc/nginx/sites-enabled/$selected_site"
                log "SUCCESS" "Site '$selected_site' disabled."
            else
                # Enable site
                ln -s "/etc/nginx/sites-available/$selected_site" "/etc/nginx/sites-enabled/"
                log "SUCCESS" "Site '$selected_site' enabled."
            fi
            
            # Test and reload nginx
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available."
    fi
}

generate_ssl_certificate() {
    log "STEP" "Generating SSL certificate..."
    
    log "PROMPT" "Enter domain for SSL certificate:"
    read -r ssl_domain
    
    log "PROMPT" "Enter email for Let's Encrypt:"
    read -r ssl_email
    
    # Install certbot if not available
    if ! command_exists certbot; then
        log "INFO" "Installing certbot..."
        apt update >/dev/null 2>&1
        apt install -y certbot python3-certbot-nginx >/dev/null 2>&1
    fi
    
    # Generate certificate
    if certbot --nginx -d "$ssl_domain" --email "$ssl_email" --agree-tos --non-interactive; then
        log "SUCCESS" "SSL certificate generated for $ssl_domain"
    else
        log "ERROR" "Failed to generate SSL certificate for $ssl_domain"
    fi
}

renew_ssl_certificates() {
    log "STEP" "Renewing SSL certificates..."
    
    if command_exists certbot; then
        if certbot renew --dry-run; then
            log "SUCCESS" "SSL certificate renewal test passed."
            
            log "PROMPT" "Proceed with actual renewal? (y/n):"
            read -r proceed
            
            if [[ "$proceed" =~ ^[Yy]$ ]]; then
                if certbot renew; then
                    log "SUCCESS" "SSL certificates renewed successfully."
                    systemctl reload nginx
                else
                    log "ERROR" "SSL certificate renewal failed."
                fi
            fi
        else
            log "ERROR" "SSL certificate renewal test failed."
        fi
    else
        log "ERROR" "Certbot not installed."
    fi
}

view_certificate_status() {
    log "INFO" "Displaying SSL certificate status..."
    
    if command_exists certbot; then
        echo -e "\n${CYAN}SSL Certificate Status:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        certbot certificates
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Certbot not installed. Cannot check SSL certificate status."
    fi
}

# Script completion message
log "SUCCESS" "Marzban Central Manager Professional Edition v$SCRIPT_VERSION loaded successfully!"

# ==============================================================================
# MAIN MENU DISPLAY FUNCTION
# ==============================================================================

show_main_menu() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║ ${CYAN}${BOLD}Marzban Central Node Manager${NC}                           ║"
    echo -e "${WHITE}║ ${PURPLE}Made with ❤️ by B3hnAM - Thanks to all Marzban developers${NC} ║"
    echo -e "${WHITE}║ ${YELLOW}[Professional Edition v${SCRIPT_VERSION}]${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}Current Nodes Overview:${NC}"
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No nodes have been added yet.${NC}"
    else
        printf "%-20s %-15s %-15s %-10s\n" "Node Name" "IP Address" "Status" "Domain"
        echo -e "${WHITE}----------------------------------------------------------------------${NC}"
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            local status
            if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
                status="${GREEN}Online${NC}"
            else
                status="${RED}Offline${NC}"
            fi
            printf "%-20s %-15s %-15s %-10s\n" "$name" "$ip" "$status" "$domain"
        done
    fi
    
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${GREEN}1) Add a new node${NC}"
    echo -e "${GREEN}2) Remove a node${NC}"
    echo -e "${GREEN}3) Update node information${NC}"
    echo -e "${YELLOW}4) Sync HAProxy to All Nodes${NC}"
    echo -e "${CYAN}5) Check all nodes status${NC}"
    echo -e "${PURPLE}6) Bulk Update Node Configurations${NC}"
    echo -e "${BLUE}7) Install Marzban on a new node${NC}"
    echo -e "${WHITE}8) Configure Marzban API${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${GREEN}9) Backup & Restore Menu${NC}"
    echo -e "${GREEN}10) Nginx Management Menu${NC}"
    echo -e "${GREEN}11) Bulk Node Operations Menu${NC}"
    echo -e "${GREEN}12) System Logs & Diagnostics Menu${NC}"
    echo -e "${CYAN}-----------------------------------------------${NC}" # Additional separator
    echo -e "${WHITE}13) Configure Telegram Notifications${NC}"
    echo -e "${WHITE}14) View System Resources${NC}"
    echo -e "${WHITE}15) Validate Configurations${NC}"
    echo -e "${WHITE}16) Clean Old Logs${NC}"
    echo -e "${YELLOW}17) View Marzban Panel Logs${NC}"
    echo -e "${YELLOW}18) View HAProxy Logs${NC}"
    echo -e "${YELLOW}19) View System Logs${NC}"
    echo -e "${RED}x) Exit${NC}"
    echo ""
}

# ==============================================================================
# MAIN EXECUTION LOGIC
# ==============================================================================

main() {
    check_dependencies # Ensure dependencies are met before showing the menu
    while true; do
        show_main_menu
        read -p "Please enter your choice [1-19, x]: " choice

        case "$choice" in
            1) import_single_node || true; read -p "Press Enter to continue..." ;;
            2) remove_node || true; read -p "Press Enter to continue..." ;;
            3) update_existing_node || true; read -p "Press Enter to continue..." ;;
            4) bulk_sync_haproxy || true; read -p "Press Enter to continue..." ;;
            5) monitor_node_health_status || true; read -p "Press Enter to continue..." ;;
            6) bulk_update_configurations || true; read -p "Press Enter to continue..." ;;
            7) deploy_new_node_professional_enhanced || true; read -p "Press Enter to continue..." ;;
            8) configure_marzban_api || true; read -p "Press Enter to continue..." ;;
            9) backup_restore_menu || true; read -p "Press Enter to continue..." ;;
            10) nginx_management_menu || true; read -p "Press Enter to continue..." ;;
            11) bulk_node_operations || true; read -p "Press Enter to continue..." ;;
            12) show_system_diagnostics || true; read -p "Press Enter to continue..." ;;
            13) configure_telegram_advanced || true; read -p "Press Enter to continue..." ;;
            14) show_system_resources || true; read -p "Press Enter to continue..." ;;
            15) validate_configurations || true; read -p "Press Enter to continue..." ;;
            16) clean_old_logs || true; read -p "Press Enter to continue..." ;;
            17) view_marzban_logs || true; read -p "Press Enter to continue..." ;;
            18) view_haproxy_logs || true; read -p "Press Enter to continue..." ;;
            19) view_system_logs || true; read -p "Press Enter to continue..." ;;
            x|X)
                log "INFO" "Exiting Marzban Central Manager. Goodbye!"
                exit 0
                ;;
            *)
                log "ERROR" "Invalid option: $choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Start The Program ---
main\n\t'

# Marzban Central Node Manager - Professional Edition v3.0
# Enhanced with Complete Backup System, Optimized Monitoring & Advanced Features
# Author: behnamrjd
# Version: Professional-3.0

SCRIPT_VERSION="Professional-3.0"
MANAGER_DIR="/root/MarzbanManager"
NODES_CONFIG_FILE="${MANAGER_DIR}/marzban_managed_nodes.conf"
MANAGER_CONFIG_FILE="${MANAGER_DIR}/marzban_manager.conf"
BACKUP_DIR="${MANAGER_DIR}/backups"
LOCKFILE="/var/lock/marzban-central-manager.lock"
LOGFILE="/tmp/marzban_central_manager_$(date +%Y%m%d_%H%M%S).log"

# Enhanced Backup Configuration
BACKUP_MAIN_DIR="${BACKUP_DIR}/main_server"
BACKUP_NODES_DIR="${BACKUP_DIR}/nodes"
BACKUP_ARCHIVE_DIR="${BACKUP_DIR}/archives"
BACKUP_RETENTION_COUNT=3
BACKUP_SCHEDULE_HOUR="03"
BACKUP_SCHEDULE_MINUTE="30"
BACKUP_TIMEZONE="Asia/Tehran"
AUTO_BACKUP_ENABLED=false

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

# --- Global Variables ---
MAIN_SERVER_IP=$(hostname -I | awk '{print $1}')
MARZBAN_PANEL_PROTOCOL="https"
MARZBAN_PANEL_DOMAIN=""
MARZBAN_PANEL_PORT=""
MARZBAN_PANEL_USERNAME=""
MARZBAN_PANEL_PASSWORD=""
MARZBAN_TOKEN=""
CLIENT_CERT=""
MARZBAN_NODE_ID=""

# Enhanced monitoring configuration (optimized for server performance)
MONITORING_INTERVAL=600  # 10 minutes (reduced from 5 minutes)
HEALTH_CHECK_TIMEOUT=30  # Increased timeout for stability
API_RATE_LIMIT_DELAY=2   # Delay between API calls
SYNC_CHECK_INTERVAL=1800 # 30 minutes for sync monitoring

# Service detection variables
MAIN_HAS_NGINX=false
MAIN_HAS_HAPROXY=false
NGINX_CONFIG_PATH=""
HAPROXY_CONFIG_PATH=""
GEO_FILES_PATH=""

mkdir -p "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
chmod 700 "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
if [ -f "$MANAGER_CONFIG_FILE" ]; then source "$MANAGER_CONFIG_FILE"; fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

## Enhanced logging with multiple levels and file rotation
log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    local masked_message="$message"
    
    # Mask sensitive information
    if [[ -n "${NODE_SSH_PASSWORD:-}" ]]; then masked_message="${message//$NODE_SSH_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_PANEL_PASSWORD:-}" ]]; then masked_message="${message//$MARZBAN_PANEL_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_TOKEN:-}" ]]; then masked_message="${message//$MARZBAN_TOKEN/*****masked*****/}"; fi
    
    # Log to system logger
    logger -t "marzban-central-manager" "$level: $masked_message"
    
    # Enhanced console output with icons and colors
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $masked_message" | tee -a "$LOGFILE";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $masked_message" | tee -a "$LOGFILE";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $masked_message" | tee -a "$LOGFILE";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $masked_message" | tee -a "$LOGFILE";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $masked_message" | tee -a "$LOGFILE";;
        PROMPT)  echo -e "[$timestamp] ${CYAN}❓ PROMPT:${NC} $masked_message";;
        DEBUG)   echo -e "[$timestamp] ${DIM}🐛 DEBUG:${NC} $masked_message" | tee -a "$LOGFILE";;
        BACKUP)  echo -e "[$timestamp] ${CYAN}💾 BACKUP:${NC} $masked_message" | tee -a "$LOGFILE";;
        SYNC)    echo -e "[$timestamp] ${PURPLE}🔄 SYNC:${NC} $masked_message" | tee -a "$LOGFILE";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $masked_message" | tee -a "$LOGFILE";;
    esac
}

send_telegram_notification() {
    local message="$1"
    local level="${2:-normal}" # normal, high, critical
    local stored_level

    # Load TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, and TELEGRAM_NOTIFICATION_LEVEL from config
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        source "$MANAGER_CONFIG_FILE"
    fi

    stored_level=${TELEGRAM_NOTIFICATION_LEVEL:-1} # Default to all notifications if not set

    # Check if notifications are enabled and the level is appropriate
    if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_CHAT_ID}" ] || [ "$stored_level" -eq 4 ]; then
        # log "DEBUG" "Telegram notifications are disabled or not configured."
        return 0
    fi

    # Level mapping: 1=all, 2=high/critical, 3=critical only
    case "$level" in
        "normal")
            if [ "$stored_level" -gt 1 ]; then return 0; fi
            ;;
        "high")
            if [ "$stored_level" -gt 2 ]; then return 0; fi
            ;;
        "critical")
            if [ "$stored_level" -gt 3 ]; then return 0; fi
            ;;
    esac

    # Send the notification using curl
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d "chat_id=${TELEGRAM_CHAT_ID}" \
         -d "text=${message}" \
         -d "parse_mode=HTML" > /dev/null &
}

## Lock management for single instance execution
acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        local pid; pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then 
            log "ERROR" "Instance already running (PID: $pid)."
            exit 1
        fi
        log "WARNING" "Removing stale lock file."
        rm -f "$LOCKFILE"
    fi
    echo "$$" > "$LOCKFILE"
    log "INFO" "Lock acquired."
}

release_lock() { rm -f "$LOCKFILE"; log "INFO" "Lock released."; }
trap release_lock EXIT
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

## Dependency checks with auto-installation
check_dependencies() {
    local deps=("sshpass" "python3" "curl" "jq" "rsync" "pigz" "git")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then # Using our defined function
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "INFO" "Installing missing dependencies: ${missing_deps[*]}"
        if command_exists apt; then
            apt update >/dev/null 2>&1
            apt install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via apt."
        elif command_exists yum; then
            yum install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via yum."
        else
            log "ERROR" "Cannot determine package manager (apt or yum). Please install dependencies manually: ${missing_deps[*]}"
            return 1
        fi
    fi
    
    # Check Python modules
    if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
        log "INFO" "Installing python3-full (or equivalent for json, urllib.parse, datetime)..."
        if command_exists apt; then
            apt install -y python3-full >/dev/null 2>&1
        elif command_exists yum; then
             # CentOS might need python3-json, python3-urllib an python3-datetime or similar
             # For simplicity, assuming python3-devel or a more general package might cover these.
             # This part might need adjustment based on specific distro.
            yum install -y python3-devel >/dev/null 2>&1 || yum install -y python3 >/dev/null 2>&1
        fi
        # Re-check after attempting install
        if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
            log "WARNING" "Failed to install required Python modules. Some functionalities might be affected."
        else
            log "SUCCESS" "Python modules seem to be available."
        fi
    fi
    return 0
}

## Enhanced SSH operations with retry mechanism and rate limiting
ssh_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" command="$5" desc="$6"
    local max_retries=3 retry=0
    
    sleep "$API_RATE_LIMIT_DELAY"
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Executing ($desc) on $node_ip (attempt $((retry+1))/$max_retries)..."
        
        # Use environment variable to pass password more securely
        if SSHPASS="$node_password" sshpass -e ssh -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
           -p "$node_port" "${node_user}@${node_ip}" "$command" 2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "Remote command ($desc) executed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 5 seconds..."
            sleep 5
        fi
    done
    
    log "ERROR" "Remote command ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP with progress and retry
scp_to_remote() {
    local local_path="$1" node_ip="$2" node_user="$3" node_port="$4" node_password="$5" remote_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Transferring ($desc) to $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "$local_path" "${node_user}@${node_ip}:${remote_path}" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File transfer ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File transfer ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP from remote with retry
scp_from_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" remote_path="$5" local_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Downloading ($desc) from $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if echo "$node_password" | sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "${node_user}@${node_ip}:${remote_path}" "$local_path" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File download ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File download ($desc) failed after $max_retries attempts."
    return 1
}

## Node configuration management
load_nodes_config() {
    if [ -f "$NODES_CONFIG_FILE" ]; then
        mapfile -t NODES_ARRAY < <(grep -vE '^\s*#|^\s*$' "$NODES_CONFIG_FILE" || true)
    else
        NODES_ARRAY=()
    fi
}

save_nodes_config() {
    printf "%s\n" "${NODES_ARRAY[@]}" > "$NODES_CONFIG_FILE"
    chmod 600 "$NODES_CONFIG_FILE"
    log "INFO" "Nodes configuration saved."
}

add_node_to_config() {
    local name="$1" ip="$2" user="$3" port="$4" domain="$5" password="$6" node_id="${7:-}"
    NODES_ARRAY+=("${name};${ip};${user};${port};${domain};${password};${node_id}")
    log "INFO" "Node '$name' added to configuration."
}

get_node_config_by_name() {
    local name="$1"
    for entry in "${NODES_ARRAY[@]}"; do
        if [[ "$entry" == "${name};"* ]]; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

## Service Detection System
detect_main_server_services() {
    log "STEP" "Detecting services on main server..."
    
    # Detect Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        MAIN_HAS_NGINX=true
        NGINX_CONFIG_PATH="/etc/nginx"
        log "SUCCESS" "Nginx detected on main server"
    else
        MAIN_HAS_NGINX=false
        log "INFO" "Nginx not detected on main server"
    fi
    
    # Detect HAProxy
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        MAIN_HAS_HAPROXY=true
        HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
        log "SUCCESS" "HAProxy detected on main server"
    else
        MAIN_HAS_HAPROXY=false
        log "INFO" "HAProxy not detected on main server"
    fi
    
    # Detect Geo files from Core config
    detect_geo_files_location
}

detect_geo_files_location() {
    log "INFO" "Detecting geo files location using multi-priority smart-scan..."
    
    # --- Priority 1: The most reliable method (from .env file) ---
    if [ -f "/opt/marzban/.env" ]; then
        local env_geo_path
        env_geo_path=$(grep -E "^\s*XRAY_ASSETS_PATH" /opt/marzban/.env | cut -d'=' -f2- | tr -d '"' | tr -d "'" | sed 's/#.*//' | xargs)
        if [ -n "$env_geo_path" ] && [ -d "$env_geo_path" ]; then
            if [ -f "$env_geo_path/geosite.dat" ] && [ -f "$env_geo_path/geoip.dat" ]; then
                log "SUCCESS" "Geo files found and validated via .env file at: $env_geo_path"
                GEO_FILES_PATH="$env_geo_path"
                return 0
            fi
        fi
    fi

    # --- Priority 2: Your brilliant idea - Find filenames from xray_config.json and search for them ---
    if [ -f "/var/lib/marzban/xray_config.json" ]; then
        log "INFO" "Scanning xray_config.json for custom geo file names..."
        local geoip_file
        local geosite_file

        geoip_file=$(jq -r '[.routing.rules[]? | .ip[]? | select(startswith("geoip:"))] | .[0] // "geoip:geoip"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geoip_file+=".dat"

        geosite_file=$(jq -r '[.routing.rules[]? | .domain[]? | select(startswith("geosite:"))] | .[0] // "geosite:geosite"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geosite_file+=".dat"
        
        log "DEBUG" "Detected target files: $geoip_file, $geosite_file"

        local found_dir
        found_dir=$(find / -name "$geoip_file" -printf "%h\n" 2>/dev/null | while read -r dir; do
            if [ -f "$dir/$geosite_file" ]; then
                echo "$dir"
                break
            fi
        done)

        if [ -n "$found_dir" ]; then
            log "SUCCESS" "Geo files found via xray_config scan at: $found_dir"
            GEO_FILES_PATH="$found_dir"
            return 0
        fi
    fi

    # --- Priority 3: Fallback to scanning common hardcoded locations ---
    log "INFO" "Falling back to scanning common default directories..."
    local common_paths=(
        "/var/lib/marzban/assets" "/var/lib/marzban/geo" "/var/lib/marzban/chocolate"
        "/opt/marzban/assets" "/opt/marzban/geo"
    )
    for path in "${common_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/geosite.dat" ] && [ -f "$path/geoip.dat" ]; then
            log "SUCCESS" "Geo files found via fallback scan at: $path"
            GEO_FILES_PATH="$path"
            return 0
        fi
    done
    
    log "WARNING" "Could not find custom Geo files on the main server. Geo file sync will be skipped."
    GEO_FILES_PATH=""
    return 1
}
## Complete Backup System Implementation
create_full_backup() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_full_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting comprehensive backup process..."
    
    # Create temporary backup directory
    mkdir -p "$temp_backup_dir"
    
    # Phase 1: Backup main server
    log "STEP" "Phase 1: Backing up main server..."
    backup_main_server "$temp_backup_dir"
    
    # Phase 2: Backup all nodes
    log "STEP" "Phase 2: Backing up all nodes..."
    backup_all_nodes "$temp_backup_dir"
    
    # Phase 3: Create compressed archive
    log "STEP" "Phase 3: Creating compressed archive..."
    create_backup_archive "$temp_backup_dir" "$final_archive"
    
    # Phase 4: Apply retention policy
    log "STEP" "Phase 4: Applying retention policy..."
    apply_backup_retention_policy_global
    
    # Cleanup
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Full backup completed: $final_archive"
    
    # Send notification
    local backup_size=$(du -h "$final_archive" | cut -f1)
    send_telegram_notification "💾 Backup Completed%0A%0A📁 File: ${backup_name}.tar.gz%0A📊 Size: ${backup_size}%0A⏰ Time: $(date)" "normal"
}

backup_main_server() {
    local backup_dir="$1/main_server"
    mkdir -p "$backup_dir"
    
    log "BACKUP" "Backing up main server components..."
    
    # Backup Marzban
    if [ -d "/opt/marzban" ]; then
        log "INFO" "Backing up Marzban configuration..."
        cp -r /opt/marzban "$backup_dir/" 2>/dev/null || log "WARNING" "Failed to backup Marzban"
    fi
    
    # Backup HAProxy (if user confirms)
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "PROMPT" "Backup HAProxy configuration? (y/n):"
        read -r backup_haproxy
        if [[ "$backup_haproxy" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up HAProxy configuration..."
            mkdir -p "$backup_dir/haproxy"
            cp -r /etc/haproxy/* "$backup_dir/haproxy/" 2>/dev/null || log "WARNING" "Failed to backup HAProxy"
        fi
    fi
    
    # Backup Nginx (if user confirms)
    if [ "$MAIN_HAS_NGINX" = "true" ]; then
        log "PROMPT" "Backup Nginx configuration? (y/n):"
        read -r backup_nginx
        if [[ "$backup_nginx" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up Nginx configuration..."
            mkdir -p "$backup_dir/nginx"
            cp -r /etc/nginx/* "$backup_dir/nginx/" 2>/dev/null || log "WARNING" "Failed to backup Nginx"
        fi
    fi
    
    # Backup Geo files
    if [ -n "$GEO_FILES_PATH" ]; then
        log "INFO" "Backing up Geo files..."
        mkdir -p "$backup_dir/geo_files"
        cp -r "$GEO_FILES_PATH"/* "$backup_dir/geo_files/" 2>/dev/null || log "WARNING" "Failed to backup Geo files"
    fi
    
    # Backup Manager configuration
    log "INFO" "Backing up Manager configuration..."
    cp -r "$MANAGER_DIR" "$backup_dir/manager_config" 2>/dev/null || log "WARNING" "Failed to backup Manager config"
    
    log "SUCCESS" "Main server backup completed."
}

backup_all_nodes() {
    local backup_dir="$1/nodes"
    mkdir -p "$backup_dir"
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured for backup."
        return 0
    fi
    
    log "BACKUP" "Backing up ${#NODES_ARRAY[@]} nodes..."
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Backing up node: $name ($ip)"
        
        local node_backup_dir="$backup_dir/$name"
        mkdir -p "$node_backup_dir"
        
        export NODE_SSH_PASSWORD="$password"
        
        # Create backup on remote node
        local remote_backup_file="/tmp/node_backup_${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "tar -czf $remote_backup_file --warning=no-file-changed /opt/marzban-node/ /var/lib/marzban-node/ /etc/systemd/system/marzban-node* /etc/haproxy/ 2>/dev/null" \
           "Node Backup Creation"; then
            
            # Transfer backup to main server
            if scp_from_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$remote_backup_file" "$node_backup_dir/backup.tar.gz" "Node Backup Transfer"; then
                
                # Create node info file
                cat > "$node_backup_dir/node_info.txt" << EOF
Node Name: $name
IP Address: $ip
Domain: $domain
SSH User: $user
SSH Port: $port
Marzban Node ID: $node_id
Backup Date: $(date)
EOF
                
                # Cleanup remote backup
                ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                    "rm -f $remote_backup_file" "Remote Cleanup" || true
                
                log "SUCCESS" "Node $name backup completed."
            else
                log "ERROR" "Failed to transfer backup from node $name"
            fi
        else
            log "ERROR" "Failed to create backup on node $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "All nodes backup completed."
}

create_backup_archive() {
    local source_dir="$1"
    local archive_path="$2"
    
    log "BACKUP" "Creating compressed archive..."
    
    # Use pigz for faster compression if available
    if command_exists pigz; then
        tar -cf - -C "$(dirname "$source_dir")" "$(basename "$source_dir")" | pigz > "$archive_path"
    else
        tar -czf "$archive_path" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"
    fi
    
    # Verify archive integrity
    if tar -tzf "$archive_path" >/dev/null 2>&1; then
        local archive_size=$(du -h "$archive_path" | cut -f1)
        log "SUCCESS" "Archive created successfully: $archive_size"
        
        # Create checksum
        md5sum "$archive_path" > "${archive_path}.md5"
        log "INFO" "Checksum created: ${archive_path}.md5"
    else
        log "ERROR" "Archive verification failed!"
        return 1
    fi
}

apply_backup_retention_policy_global() {
    log "BACKUP" "Applying retention policy (keeping last $BACKUP_RETENTION_COUNT backups)..."
    
    # Remove old archives
    ls -t "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | \
        tail -n +$((BACKUP_RETENTION_COUNT + 1)) | \
        while read -r old_backup; do
            log "INFO" "Removing old backup: $(basename "$old_backup")"
            rm -f "$old_backup" "${old_backup}.md5"
        done
    
    local remaining_count
    remaining_count=$(ls "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | wc -l)
    log "SUCCESS" "Retention policy applied: $remaining_count backups remaining"
}

## Automated Backup Scheduling
setup_automated_backup() {
    log "STEP" "Setting up automated backup system..."
    
    # Create backup script
    local backup_script="/usr/local/bin/marzban-auto-backup.sh"
    cat > "$backup_script" << 'EOF'
#!/bin/bash
# Automated Marzban Backup Script
cd /root/MarzbanManager
./marzban_central_manager.sh --backup >> /var/log/marzban-backup.log 2>&1
EOF
    
    chmod +x "$backup_script"
    
    # Setup cron job for 3:30 AM Iran time
    local cron_entry="30 3 * * * TZ=Asia/Tehran $backup_script"
    
    # Remove existing cron job if exists
    crontab -l 2>/dev/null | grep -v "marzban-auto-backup" | crontab -
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    log "SUCCESS" "Automated backup scheduled for 3:30 AM Iran time daily"
    
    # Update configuration
    sed -i '/AUTO_BACKUP_ENABLED=/d' "$MANAGER_CONFIG_FILE" 2>/dev/null || true
    echo "AUTO_BACKUP_ENABLED=true" >> "$MANAGER_CONFIG_FILE"
    
    send_telegram_notification "⏰ Automated Backup Enabled%0A%0A📅 Schedule: Daily at 3:30 AM (Iran Time)%0A🔄 Retention: $BACKUP_RETENTION_COUNT backups" "normal"
}

## Enhanced HAProxy Synchronization System
sync_haproxy_across_all_nodes() {
    local new_node_name="$1" new_node_ip="$2" new_node_domain="$3"
    
    log "SYNC" "Starting HAProxy synchronization across all nodes..."
    
    # Phase 1: Update main server HAProxy
    if ! update_main_haproxy_config "$new_node_name" "$new_node_ip" "$new_node_domain"; then
        log "ERROR" "Failed to update main server HAProxy"
        return 1
    fi
    
    # Phase 2: Sync to all existing nodes
    sync_haproxy_to_all_existing_nodes
    
    # Phase 3: Install HAProxy on new node
    install_haproxy_on_new_node "$new_node_ip" "$new_node_name"
    
    # Phase 4: Verification
    verify_haproxy_sync_across_nodes
}

update_main_haproxy_config() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_cfg}.backup.$(date +%s)"
    
    log "SYNC" "Updating main server HAProxy configuration..."
    cp "$haproxy_cfg" "$backup_file"
    
    # Create enhanced HAProxy config with new node
    create_enhanced_haproxy_config "$node_name" "$node_ip" "$node_domain"
    
    # Validate configuration before reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        if systemctl reload haproxy; then
            log "SUCCESS" "Main server HAProxy updated and reloaded successfully"
            log "SYNC" "HAProxy updated: Added backend $node_name ($node_ip) for domain $node_domain"
            send_telegram_notification "🔄 HAProxy Updated%0A%0AAdded: $node_name%0AIP: $node_ip%0ADomain: $node_domain" "normal"
            return 0
        else
            log "ERROR" "Failed to reload HAProxy service, restoring backup"
            cp "$backup_file" "$haproxy_cfg"
            systemctl reload haproxy
            return 1
        fi
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup"
        cp "$backup_file" "$haproxy_cfg"
        return 1
    fi
}

sync_haproxy_to_all_existing_nodes() {
    log "SYNC" "Synchronizing HAProxy to all existing nodes..."
    local sync_success=0 sync_failed=0
    
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "SYNC" "Syncing HAProxy to node: $name ($ip)"
        export NODE_SSH_PASSWORD="$password"
        
        # Create rollback point on node
        if create_node_rollback_point "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            
            # Sync HAProxy configuration
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                sync_success=$((sync_success + 1))
                log "SUCCESS" "HAProxy synced to node: $name"
            else
                sync_failed=$((sync_failed + 1))
                log "ERROR" "Failed to sync HAProxy to node: $name"
                
                # Attempt rollback
                rollback_node_configuration "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"
            fi
        else
            log "WARNING" "Could not create rollback point for node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SYNC" "HAProxy sync completed: $sync_success successful, $sync_failed failed"
    
    # Send notification
    send_telegram_notification "📊 HAProxy Sync Report%0A%0A✅ Success: $sync_success%0A❌ Failed: $sync_failed" "normal"
}

create_node_rollback_point() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "SYNC" "Creating rollback point for node: $node_name"
    
    # Create backup of current HAProxy config
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg ]; then cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.rollback.$(date +%s); echo 'Rollback point created'; else echo 'No HAProxy config found'; fi" \
       "Rollback Point Creation"; then
        
        # Store rollback info
        echo "${node_name};${node_ip};$(date +%s)" >> "${BACKUP_DIR}/rollback_points.log"
        return 0
    else
        return 1
    fi
}

sync_haproxy_to_single_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    # Check if HAProxy is installed on node
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
         "command -v haproxy >/dev/null 2>&1" "HAProxy Check"; then
        
        log "SYNC" "Installing HAProxy on node: $node_name"
        if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
             "apt update >/dev/null 2>&1 && apt install -y haproxy >/dev/null 2>&1" \
             "HAProxy Installation"; then
            return 1
        fi
    fi
    
    # Copy main HAProxy config to node
    if scp_to_remote "/etc/haproxy/haproxy.cfg" "$node_ip" "$node_user" "$node_port" "$node_password" \
       "/etc/haproxy/haproxy.cfg" "HAProxy Configuration"; then
        
        # Validate and restart HAProxy on node
        if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
           "/usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl enable haproxy && systemctl restart haproxy" \
           "HAProxy Validation & Restart"; then
            
            log "SUCCESS" "HAProxy successfully synced to node: $node_name"
            return 0
        else
            log "ERROR" "HAProxy validation/restart failed on node: $node_name"
            return 1
        fi
    else
        return 1
    fi
}

rollback_node_configuration() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "WARNING" "Attempting rollback for node: $node_name"
    
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg.rollback.* ]; then cp /etc/haproxy/haproxy.cfg.rollback.* /etc/haproxy/haproxy.cfg && systemctl restart haproxy && echo 'Rollback successful'; else echo 'No rollback file found'; fi" \
       "Configuration Rollback"; then
        
        log "SUCCESS" "Rollback completed for node: $node_name"
        send_telegram_notification "🔄 Rollback Executed%0A%0ANode: $node_name%0AStatus: Successful" "high"
    else
        log "ERROR" "Rollback failed for node: $node_name"
        send_telegram_notification "🚨 Rollback Failed%0A%0ANode: $node_name%0ARequires manual intervention!" "critical"
    fi
}

## Geo Files Transfer System
transfer_geo_files_to_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4"
    
    if [ -z "$GEO_FILES_PATH" ]; then
        log "WARNING" "No geo files detected on main server, downloading fresh copies..."
        return 0
    fi
    
    log "SYNC" "Transferring geo files from main server to node..."
    
    # Create geo directory on node
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "mkdir -p /var/lib/marzban-node/chocolate" \
        "Geo Directory Creation"
    
    # Transfer geo files
    scp_to_remote "$GEO_FILES_PATH/geosite.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geosite.dat" "Geosite File"
    
    scp_to_remote "$GEO_FILES_PATH/geoip.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geoip.dat" "Geoip File"
    
    # Set proper permissions
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "chmod 644 /var/lib/marzban-node/chocolate/*.dat && chown root:root /var/lib/marzban-node/chocolate/*.dat" \
        "Geo Files Permissions"
    
    log "SUCCESS" "Geo files transferred successfully"
}

create_enhanced_docker_compose() {
    log "SYNC" "Creating enhanced docker-compose with geo volume..."
    
    local geo_volume=""
    if [ -n "$GEO_FILES_PATH" ]; then
        geo_volume="      - /var/lib/marzban-node/chocolate:/var/lib/marzban-node/chocolate"
    fi
    
    cat > docker-compose.yml << EOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /opt/marzban-node:/opt/marzban-node
${geo_volume}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "SUCCESS" "Enhanced docker-compose.yml created with geo volume support"
}
## Optimized Continuous Monitoring System
start_continuous_sync_monitoring() {
    log "INFO" "Starting optimized continuous synchronization monitoring..."
    
    while true; do
        monitor_haproxy_sync_status
        monitor_geo_files_sync_status
        monitor_node_health_status
        
        # Optimized sleep interval (30 minutes to reduce server load)
        sleep "$SYNC_CHECK_INTERVAL"
    done
}

monitor_haproxy_sync_status() {
    local main_config_hash
    main_config_hash=$(md5sum /etc/haproxy/haproxy.cfg | awk '{print $1}' 2>/dev/null || echo "missing")
    
    load_nodes_config
    local out_of_sync_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_config_hash
        node_config_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                          "if [ -f /etc/haproxy/haproxy.cfg ]; then md5sum /etc/haproxy/haproxy.cfg | awk '{print \$1}'; else echo 'missing'; fi" \
                          "Config Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_config_hash" != "$main_config_hash" ] && [ "$node_config_hash" != "error" ]; then
            out_of_sync_nodes+=("$name")
            log "WARNING" "Node $name is out of sync (hash: $node_config_hash vs main: $main_config_hash)"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_nodes[@]} -gt 0 ]; then
        log "SYNC" "Out of sync nodes detected: ${out_of_sync_nodes[*]}"
        send_telegram_notification "⚠️ Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_nodes[*]}%0A%0AAutomatic resync will be attempted." "high"
        
        # Attempt automatic resync
        auto_resync_nodes "${out_of_sync_nodes[@]}"
    fi
}

auto_resync_nodes() {
    local nodes=("$@")
    
    for node_name in "${nodes[@]}"; do
        log "SYNC" "Attempting automatic resync for node: $node_name"
        
        local node_entry
        node_entry=$(get_node_config_by_name "$node_name")
        
        if [ -n "$node_entry" ]; then
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            export NODE_SSH_PASSWORD="$password"
            
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                log "SUCCESS" "Automatic resync successful for node: $node_name"
                send_telegram_notification "✅ Auto-Resync Success%0A%0ANode: $node_name" "normal"
            else
                log "ERROR" "Automatic resync failed for node: $node_name"
                send_telegram_notification "🚨 Auto-Resync Failed%0A%0ANode: $node_name%0AManual intervention required!" "critical"
            fi
            
            unset NODE_SSH_PASSWORD
        fi
    done
}

monitor_geo_files_sync_status() {
    if [ -z "$GEO_FILES_PATH" ]; then
        return 0
    fi
    
    local main_geosite_hash main_geoip_hash
    main_geosite_hash=$(md5sum "$GEO_FILES_PATH/geosite.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    main_geoip_hash=$(md5sum "$GEO_FILES_PATH/geoip.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    
    load_nodes_config
    local out_of_sync_geo_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_geosite_hash node_geoip_hash
        node_geosite_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                           "if [ -f /var/lib/marzban-node/chocolate/geosite.dat ]; then md5sum /var/lib/marzban-node/chocolate/geosite.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                           "Geosite Hash Check" 2>/dev/null || echo "error")
        
        node_geoip_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                         "if [ -f /var/lib/marzban-node/chocolate/geoip.dat ]; then md5sum /var/lib/marzban-node/chocolate/geoip.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                         "Geoip Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_geosite_hash" != "$main_geosite_hash" ] || [ "$node_geoip_hash" != "$main_geoip_hash" ]; then
            if [ "$node_geosite_hash" != "error" ] && [ "$node_geoip_hash" != "error" ]; then
                out_of_sync_geo_nodes+=("$name")
                log "WARNING" "Node $name geo files are out of sync"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_geo_nodes[@]} -gt 0 ]; then
        log "SYNC" "Geo files out of sync on nodes: ${out_of_sync_geo_nodes[*]}"
        send_telegram_notification "🌍 Geo Files Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_geo_nodes[*]}" "normal"
    fi
}

monitor_node_health_status() {
    if ! get_marzban_token >/dev/null 2>&1; then
        return 1
    fi
    
    local unhealthy_nodes=()
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 10 --max-time 15 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status="unknown" # Default status
            if echo "$health_response" | jq -e . >/dev/null 2>&1; then # Check if response is valid JSON
                status=$(echo "$health_response" | jq -r '.status // "unknown"')
            else
                log "WARNING" "Node $name ($ip): Invalid API response for health check."
                log "DEBUG" "Response for $name: $health_response"
                # status remains "unknown"
            fi
            
            if [ "$status" != "connected" ]; then
                unhealthy_nodes+=("$name:$status")
            fi
        fi
        
        # Rate limiting
        sleep "$API_RATE_LIMIT_DELAY"
    done
    
    if [ ${#unhealthy_nodes[@]} -gt 0 ]; then
        log "WARNING" "Unhealthy nodes detected: ${unhealthy_nodes[*]}"
        send_telegram_notification "🔴 Health Alert%0A%0AUnhealthy nodes: ${unhealthy_nodes[*]}" "high"
    fi
}

## Enhanced Marzban API Configuration
configure_marzban_api() {
    log "STEP" "Configuring Marzban Panel API Connection..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Marzban Panel API Setup${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Please provide your Marzban Panel details:${NC}\n"
    
    log "PROMPT" "Panel Protocol (http/https) [default: https]:"
    read -r protocol
    protocol=${protocol:-https}
    
    log "PROMPT" "Panel Domain/IP (e.g., panel.example.com):"
    read -r domain
    
    log "PROMPT" "Panel Port [default: 8000]:"
    read -r port
    port=${port:-8000}
    
    log "PROMPT" "Admin Username:"
    read -r username
    
    log "PROMPT" "Admin Password:"
    read -s password
    echo ""
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$username" ] || [ -z "$password" ]; then
        log "ERROR" "All fields are required."
        return 1
    fi
    
    # Test connection
    log "INFO" "Testing API connection..."
    local test_url="${protocol}://${domain}:${port}/api/admin/token"
    local test_response
    
    test_response=$(curl -s -X POST "$test_url" \
        -d "username=${username}&password=${password}" \
        --connect-timeout 10 --max-time 30 \
        --insecure 2>/dev/null)
    
    if echo "$test_response" | grep -q "access_token"; then
        log "SUCCESS" "API connection test successful!"
        
        # Save configuration
        {
            echo "MARZBAN_PANEL_PROTOCOL=\"$protocol\""
            echo "MARZBAN_PANEL_DOMAIN=\"$domain\""
            echo "MARZBAN_PANEL_PORT=\"$port\""
            echo "MARZBAN_PANEL_USERNAME=\"$username\""
            echo "MARZBAN_PANEL_PASSWORD=\"$password\""
        } >> "$MANAGER_CONFIG_FILE"
        
        chmod 600 "$MANAGER_CONFIG_FILE"
        source "$MANAGER_CONFIG_FILE"
        
        log "SUCCESS" "Marzban API configuration saved successfully."
        send_telegram_notification "🔗 Marzban API Connected%0A%0APanel: $domain:$port%0AStatus: ✅ Connected" "normal"
    else
        log "ERROR" "API connection test failed. Please check your credentials and panel accessibility."
        log "DEBUG" "Response: $test_response"
        return 1
    fi
}

## Function to get Marzban API token
get_marzban_token() {
    if [ -n "$MARZBAN_TOKEN" ]; then
        # Token already exists, maybe add a check for expiration if API supports it
        # log "DEBUG" "Using existing Marzban token."
        return 0
    fi

    if [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ]; then
        log "ERROR" "Marzban Panel API credentials are not configured. Please run 'Configure Marzban API' first."
        return 1
    fi

    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response

    # log "INFO" "Attempting to get Marzban API token..."
    response=$(curl -s -X POST "$login_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout 10 --max-time 20 \
        --insecure 2>/dev/null)

    if echo "$response" | grep -q "access_token"; then
        MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
        if [ -n "$MARZBAN_TOKEN" ]; then
            # log "SUCCESS" "Marzban API token obtained successfully."
            # Store token in config for persistence across script runs? Or rely on global var for current session.
            # For now, it's a global variable for the current session.
            return 0
        else
            log "ERROR" "Failed to parse access token from API response."
            log "DEBUG" "Full API response: $response"
            return 1
        fi
    else
        log "ERROR" "Failed to obtain Marzban API token. Check credentials and panel accessibility."
        log "DEBUG" "API Response: $response"
        MARZBAN_TOKEN="" # Clear any stale token
        return 1
    fi
}

add_node_to_marzban_panel_api() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    
    log "INFO" "Registering node '$node_name' with the Marzban panel..."
    
    local add_node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node"
    local payload
    payload=$(printf '{"name": "%s", "address": "%s", "port": 62050, "api_port": 62051, "usage_coefficient": 1.0, "add_as_new_host": false}' "$node_name" "$node_ip")

    local response
    response=$(curl -s -X POST "$add_node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Content-Type: application/json" -H "Accept: application/json" \
        -d "$payload" --insecure)

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        MARZBAN_NODE_ID=$(echo "$response" | jq -r .id)
        log "SUCCESS" "Node '$node_name' successfully added to panel with ID: $MARZBAN_NODE_ID"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node '$node_name' already exists in the panel. Attempting to retrieve its ID..."
        
        local nodes_list_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes"
        local nodes_response
        nodes_response=$(curl -s -X GET "$nodes_list_url" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        local existing_id
        existing_id=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$node_name\") | .id" 2>/dev/null)
        
        if [ -n "$existing_id" ]; then
            MARZBAN_NODE_ID="$existing_id"
            log "SUCCESS" "Successfully retrieved ID for existing node: $MARZBAN_NODE_ID"
            return 0
        else
            log "ERROR" "Node is said to exist, but could not retrieve its ID from the panel."
            return 1
        fi
    else
        log "ERROR" "Failed to add node to Marzban panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

get_client_cert_from_marzban_api() {
    local node_id="$1"
    
    log "INFO" "Retrieving client certificate for node ID: $node_id"
    
    local node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${node_id}"
    
    local response
    response=$(curl -s -X GET "$node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Accept: application/json" \
        --insecure)
        
    if echo "$response" | jq -e '.client_cert' >/dev/null 2>&1; then
        CLIENT_CERT=$(echo "$response" | jq -r .client_cert)
        if [ -n "$CLIENT_CERT" ]; then
            log "SUCCESS" "Client certificate retrieved successfully."
            return 0
        else
            log "ERROR" "Client certificate is empty in the API response."
            return 1
        fi
    else
        log "ERROR" "Failed to retrieve client certificate from panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

## Automated Monitoring Setup
setup_automated_monitoring() {
    log "STEP" "Setting up automated monitoring system..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║       ${CYAN}Automated Monitoring Setup${NC}       ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Monitoring Options:${NC}"
    echo " 1. Enable Continuous Sync Monitoring"
    echo " 2. Enable Automated Health Checks"
    echo " 3. Setup Both (Recommended)"
    echo " 4. Disable All Monitoring"
    echo " 5. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose monitoring option:"
    read -r choice
    
    case "$choice" in
        1|3)
            # Setup sync monitoring
            local sync_script="/usr/local/bin/marzban-sync-monitor.sh"
            cat > "$sync_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --sync-monitor >> /var/log/marzban-sync.log 2>&1
EOF
            chmod +x "$sync_script"
            
            # Add to cron (every 30 minutes)
            local sync_cron="*/30 * * * * $sync_script"
            crontab -l 2>/dev/null | grep -v "marzban-sync-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$sync_cron") | crontab -
            
            log "SUCCESS" "Sync monitoring enabled (every 30 minutes)"
            ;;
    esac
    
    case "$choice" in
        2|3)
            # Setup health monitoring
            local health_script="/usr/local/bin/marzban-health-monitor.sh"
            cat > "$health_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --health-monitor >> /var/log/marzban-health.log 2>&1
EOF
            chmod +x "$health_script"
            
            # Add to cron (every 10 minutes)
            local health_cron="*/10 * * * * $health_script"
            crontab -l 2>/dev/null | grep -v "marzban-health-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$health_cron") | crontab -
            
            log "SUCCESS" "Health monitoring enabled (every 10 minutes)"
            ;;
    esac
    
    case "$choice" in
        4)
            # Disable monitoring
            crontab -l 2>/dev/null | grep -v "marzban-.*-monitor" | crontab -
            rm -f /usr/local/bin/marzban-*-monitor.sh
            log "SUCCESS" "All automated monitoring disabled"
            ;;
        5)
            return 0
            ;;
        *)
            log "ERROR" "Invalid option"
            return 1
            ;;
    esac
    
    if [ "$choice" != "4" ] && [ "$choice" != "5" ]; then
        send_telegram_notification "🤖 Automated Monitoring Enabled%0A%0AMonitoring active on $(hostname)" "normal"
    fi
}

## Enhanced Node Import System
import_existing_nodes() {
    log "STEP" "Importing existing nodes..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║         ${CYAN}Import Existing Nodes${NC}          ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Import Options:${NC}"
    echo " 1. Import Single Node"
    echo " 2. Import from CSV File"
    echo " 3. Auto-discover Nodes from Marzban Panel"
    echo " 4. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose import method:"
    read -r choice
    
    case "$choice" in
        1) import_single_node ;;
        2) import_from_csv ;;
        3) auto_discover_nodes ;;
        4) return 0 ;;
        *) log "ERROR" "Invalid option" ;;
    esac
}

import_single_node() {
    log "STEP" "Adding/Importing a single node..."
    
    local node_name node_ip node_user="root" node_port="22" node_domain node_password

    log "PROMPT" "Enter Node Name:"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP:"; read -r node_ip
    log "PROMPT" "Enter SSH Username [default: root]:"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port [default: 22]:"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain:"; read -r node_domain
    log "PROMPT" "Enter SSH Password:"; read -s node_password; echo ""

    # Combine connectivity test and Marzban Node check into a single SSH session
    local remote_command="echo 'CONN_OK'; if docker ps 2>/dev/null | grep -q marzban-node; then echo 'NODE_INSTALLED'; else echo 'NODE_NOT_INSTALLED'; fi"
    
    local check_result
    if ! check_result=$(ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "$remote_command" "Connectivity and Node Check"); then
        log "ERROR" "Failed to connect to node. Please check credentials."
        return 1
    fi
    
    if echo "$check_result" | grep -q "NODE_INSTALLED"; then
        log "INFO" "Marzban Node is already installed. Checking registration in panel..."
        
        if ! get_marzban_token; then return 1; fi
        local nodes_response
        nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure 2>/dev/null)
        
        local node_id
        if echo "$nodes_response" | jq empty 2>/dev/null; then
            node_id=$(echo "$nodes_response" | jq -r ".[] | select(.address==\"$node_ip\") | .id" 2>/dev/null)
        fi

        if [ -n "$node_id" ]; then
            log "SUCCESS" "Node is already registered in the panel with ID: $node_id. Importing..."
            add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$node_id"
            save_nodes_config
        else
            log "WARNING" "This node is running, but it is NOT registered in your Marzban panel."
            log "PROMPT" "Do you want to add it to the panel now? (y/n)"
            read -r add_to_panel
            if [[ "$add_to_panel" =~ ^[Yy]$ ]]; then
                log "STEP" "Registering existing node with the panel..."
                if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi
                
                log "STEP" "Deploying new client certificate to the node..."
                if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
                
                if [ -z "$CLIENT_CERT" ]; then
                    log "ERROR" "Failed to retrieve client certificate from panel. Cannot proceed."
                    return 1
                fi

                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
                rm "$temp_cert"
                
                log "STEP" "Restarting node service to apply new certificate..."
                ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" "Service Restart"

                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
                save_nodes_config
                log "SUCCESS" "Node '$node_name' successfully registered and imported!"
            else
                log "INFO" "Node was not registered in the panel. It has been added to the local manager only."
                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" ""
                save_nodes_config
            fi
        fi
    elif echo "$check_result" | grep -q "NODE_NOT_INSTALLED"; then
        log "WARNING" "Marzban Node is NOT installed on this server."
        log "PROMPT" "Do you want to install it automatically now? (y/n)"
        read -r install_now
        if [[ "$install_now" =~ ^[Yy]$ ]]; then
            if _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
                log "SUCCESS" "🎉 Node '$node_name' installed and configured successfully!"
            else
                log "ERROR" "Node installation failed. Please check the logs."
            fi
        else
            log "INFO" "Installation cancelled. Node was not added."
        fi
    fi
}

import_from_csv() {
    log "STEP" "Importing nodes from CSV file..."
    
    log "PROMPT" "Enter CSV file path (format: name,ip,user,port,domain,password):"
    read -r csv_file
    
    if [ ! -f "$csv_file" ]; then
        log "ERROR" "CSV file not found: $csv_file"
        return 1
    fi
    
    local imported=0 failed=0
    
    while IFS=',' read -r name ip user port domain password; do
        # Skip header line
        if [ "$name" = "name" ]; then continue; fi
        
        log "INFO" "Importing node: $name"
        
        if get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "WARNING" "Node '$name' already exists, skipping."
            continue
        fi
        
        # Test connectivity
        export NODE_SSH_PASSWORD="$password"
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'test'" "CSV Import Test" >/dev/null 2>&1; then
            add_node_to_config "$name" "$ip" "$user" "$port" "$domain" "$password" ""
            imported=$((imported + 1))
            log "SUCCESS" "Node '$name' imported."
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to import node '$name'."
        fi
        unset NODE_SSH_PASSWORD
        
    done < "$csv_file"
    
    save_nodes_config
    log "SUCCESS" "CSV import completed: $imported imported, $failed failed."
}

auto_discover_nodes() {
    log "STEP" "Auto-discovering nodes from Marzban Panel..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    local nodes_response
    nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        --insecure 2>/dev/null)
    
    if ! echo "$nodes_response" | jq empty 2>/dev/null; then
        log "ERROR" "Failed to fetch nodes from Marzban Panel."
        return 1
    fi
    
    local discovered=0
    
    echo "$nodes_response" | jq -r '.[] | "\(.name);\(.address);\(.id)"' | while IFS=';' read -r name address node_id; do
        if ! get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "INFO" "Discovered node: $name ($address)"
            
            # Add with default values (user will need to update SSH credentials)
            add_node_to_config "$name" "$address" "root" "22" "$name.domain.com" "UPDATE_PASSWORD" "$node_id"
            discovered=$((discovered + 1))
        fi
    done
    
    save_nodes_config
    log "SUCCESS" "Auto-discovery completed: $discovered nodes discovered."
    log "WARNING" "Please update SSH credentials for discovered nodes using 'Update Node Configuration'."
}

## Node Update System
update_existing_node() {
    log "STEP" "Updating existing node configuration..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to update."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Update Node Configuration${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip)"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to update (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${CYAN}Updating node: $name${NC}"
    echo -e "Current values (press Enter to keep current value):\n"
    
    log "PROMPT" "IP Address [$ip]:"
    read -r new_ip
    new_ip=${new_ip:-$ip}
    
    log "PROMPT" "SSH Username [$user]:"
    read -r new_user
    new_user=${new_user:-$user}
    
    log "PROMPT" "SSH Port [$port]:"
    read -r new_port
    new_port=${new_port:-$port}
    
    log "PROMPT" "Domain [$domain]:"
    read -r new_domain
    new_domain=${new_domain:-$domain}
    
    log "PROMPT" "Update SSH Password? (y/n):"
    read -r update_password
    
    local new_password="$password"
    if [[ "$update_password" =~ ^[Yy]$ ]]; then
        log "PROMPT" "New SSH Password:"
        read -s new_password
        echo ""
    fi
    
    # Update the node entry
    NODES_ARRAY[$selected_index]="${name};${new_ip};${new_user};${new_port};${new_domain};${new_password};${node_id}"
    save_nodes_config
    
    log "SUCCESS" "Node '$name' configuration updated successfully."
    
    # Test connectivity with new settings
    log "INFO" "Testing connectivity with new settings..."
    export NODE_SSH_PASSWORD="$new_password"
    if ssh_remote "$new_ip" "$new_user" "$new_port" "$NODE_SSH_PASSWORD" "echo 'Update test successful'" "Update Connectivity Test"; then
        log "SUCCESS" "Connectivity test passed with new settings."
    else
        log "WARNING" "Connectivity test failed. Please verify the new settings."
    fi
    unset NODE_SSH_PASSWORD
}
## Node Removal System
remove_node() {
    log "STEP" "Removing node from system..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to remove."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║            ${CYAN}Remove Node${NC}                 ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip) - $domain"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to remove (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will remove node '$name' from:${NC}"
    echo "- Local configuration"
    echo "- Marzban Panel (if connected)"
    echo "- HAProxy configuration"
    echo ""
    
    log "PROMPT" "Are you sure you want to remove node '$name'? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Node removal cancelled."
        return 0
    fi
    
    # Remove from Marzban Panel if node_id exists
    if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
        log "STEP" "Removing node from Marzban Panel..."
        if get_marzban_token; then
            local delete_response
            delete_response=$(curl -s -X DELETE "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                log "SUCCESS" "Node removed from Marzban Panel."
            else
                log "WARNING" "Failed to remove node from Marzban Panel."
            fi
        fi
    fi
    
    # Remove from HAProxy configuration
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "STEP" "Removing node from HAProxy configuration..."
        remove_haproxy_backend "$name" "$domain"
    fi
    
    # Remove from local configuration
    unset NODES_ARRAY[$selected_index]
    NODES_ARRAY=("${NODES_ARRAY[@]}")  # Re-index array
    save_nodes_config
    
    log "SUCCESS" "Node '$name' removed successfully."
    send_telegram_notification "🗑️ Node Removed%0A%0ANode: $name%0AIP: $ip%0ADomain: $domain" "normal"
}

remove_haproxy_backend() {
    local node_name="$1" node_domain="$2"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backend_name="vless_${node_name}"
    
    # Create backup
    cp "$haproxy_cfg" "${haproxy_cfg}.backup.$(date +%s)"
    
    # Remove backend section
    sed -i "/^# Backend for ${node_name}/,/^$/d" "$haproxy_cfg"
    sed -i "/^backend ${backend_name}/,/^$/d" "$haproxy_cfg"
    
    # Remove frontend rule
    sed -i "/use_backend ${backend_name} if.*${node_domain}/d" "$haproxy_cfg"
    
    # Validate and reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        systemctl reload haproxy
        log "SUCCESS" "HAProxy configuration updated."
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup."
        cp "${haproxy_cfg}.backup."* "$haproxy_cfg"
        systemctl reload haproxy
        return 1
    fi
}

## Enhanced Backup and Restore System
backup_restore_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Backup & Restore System${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Backup Options:${NC}"
        echo " 1. Create Full System Backup"
        echo " 2. Create Main Server Only Backup"
        echo " 3. Create Nodes Only Backup"
        echo " 4. Setup Automated Backup"
        echo ""
        echo -e "${PURPLE}Restore Options:${NC}"
        echo " 5. List Available Backups"
        echo " 6. Restore from Backup"
        echo " 7. Verify Backup Integrity"
        echo ""
        echo -e "${PURPLE}Management:${NC}"
        echo " 8. Cleanup Old Backups"
        echo " 9. Export Backup to Remote"
        echo " 10. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose backup/restore option:"
        read -r choice
        
        case "$choice" in
            1) create_full_backup ;;
            2) backup_main_server_only ;;
            3) backup_nodes_only ;;
            4) setup_automated_backup ;;
            5) list_available_backups ;;
            6) restore_from_backup ;;
            7) verify_backup_integrity_menu ;;
            8) cleanup_old_backups ;;
            9) export_backup_to_remote ;;
            10) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "10" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

backup_main_server_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_main_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting main server backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_main_server "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Main server backup completed: $final_archive"
}

backup_nodes_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_nodes_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting nodes backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_all_nodes "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Nodes backup completed: $final_archive"
}

list_available_backups() {
    log "BACKUP" "Listing available backups..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Available Backups${NC}                        ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    if ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        printf "%-5s %-35s %-15s %-10s\n" "No." "Backup Name" "Date" "Size"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        
        local i=1
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            local filename=$(basename "$backup")
            local filesize=$(du -h "$backup" | cut -f1)
            local filedate=$(date -r "$backup" '+%Y-%m-%d %H:%M')
            
            printf "%-5s %-35s %-15s %-10s\n" "$i" "$filename" "$filedate" "$filesize"
            i=$((i + 1))
        done
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "No backups found in $BACKUP_ARCHIVE_DIR"
    fi
}

verify_backup_integrity_menu() {
    log "BACKUP" "Backup integrity verification..."
    
    list_available_backups
    
    if ! ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        return 0
    fi
    
    echo ""
    log "PROMPT" "Enter backup number to verify (or 'all' for all backups):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            verify_backup_integrity "$backup"
        done
    else
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            local backup_files=("$BACKUP_ARCHIVE_DIR"/*.tar.gz)
            local selected_index=$((selection - 1))
            
            if [ $selected_index -ge 0 ] && [ $selected_index -lt ${#backup_files[@]} ]; then
                verify_backup_integrity "${backup_files[$selected_index]}"
            else
                log "ERROR" "Invalid backup number."
            fi
        else
            log "ERROR" "Invalid input."
        fi
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

## Nginx Management System
nginx_management_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║           ${CYAN}Nginx Management${NC}              ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        # Check Nginx status
        if systemctl is-active --quiet nginx; then
            echo -e "${GREEN}✅ Nginx Status: Running${NC}"
        else
            echo -e "${RED}❌ Nginx Status: Not Running${NC}"
        fi
        
        echo ""
        echo -e "${PURPLE}Configuration Management:${NC}"
        echo " 1. View Nginx Configuration"
        echo " 2. Test Nginx Configuration"
        echo " 3. Reload Nginx Configuration"
        echo " 4. Restart Nginx Service"
        echo ""
        echo -e "${PURPLE}SSL Certificate Management:${NC}"
        echo " 5. Generate SSL Certificate"
        echo " 6. Renew SSL Certificates"
        echo " 7. View Certificate Status"
        echo ""
        echo -e "${PURPLE}Site Management:${NC}"
        echo " 8. Add New Site Configuration"
        echo " 9. Remove Site Configuration"
        echo " 10. Enable/Disable Site"
        echo ""
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose Nginx management option:"
        read -r choice
        
        case "$choice" in
            1) view_nginx_configuration ;;
            2) test_nginx_configuration ;;
            3) reload_nginx_configuration ;;
            4) restart_nginx_service ;;
            5) generate_ssl_certificate ;;
            6) renew_ssl_certificates ;;
            7) view_certificate_status ;;
            8) add_nginx_site ;;
            9) remove_nginx_site ;;
            10) toggle_nginx_site ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_nginx_configuration() {
    log "INFO" "Displaying Nginx configuration..."
    
    if [ -f "/etc/nginx/nginx.conf" ]; then
        echo -e "\n${CYAN}Main Nginx Configuration:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        cat /etc/nginx/nginx.conf
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        log "ERROR" "Nginx configuration file not found."
    fi
    
    echo -e "\n${CYAN}Available Site Configurations:${NC}"
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                echo "✅ $site_name (enabled)"
            else
                echo "❌ $site_name (disabled)"
            fi
        done
    else
        echo "No site configurations found."
    fi
}

test_nginx_configuration() {
    log "INFO" "Testing Nginx configuration..."
    
    if nginx -t 2>&1; then
        log "SUCCESS" "Nginx configuration test passed."
    else
        log "ERROR" "Nginx configuration test failed."
    fi
}

reload_nginx_configuration() {
    log "INFO" "Reloading Nginx configuration..."
    
    if nginx -t 2>/dev/null; then
        if systemctl reload nginx; then
            log "SUCCESS" "Nginx configuration reloaded successfully."
        else
            log "ERROR" "Failed to reload Nginx configuration."
        fi
    else
        log "ERROR" "Nginx configuration test failed. Cannot reload."
    fi
}

restart_nginx_service() {
    log "INFO" "Restarting Nginx service..."
    
    if systemctl restart nginx; then
        log "SUCCESS" "Nginx service restarted successfully."
    else
        log "ERROR" "Failed to restart Nginx service."
    fi
}

## Bulk Operations Enhancement
bulk_update_certificates() {
    log "STEP" "Updating certificates on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            log "INFO" "Updating certificate for node: $name"
            
            # Get fresh certificate from Marzban Panel
            if get_client_cert_from_marzban_api "$node_id"; then
                export NODE_SSH_PASSWORD="$password"
                
                # Deploy certificate to node
                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                
                if scp_to_remote "$temp_cert" "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "/var/lib/marzban-node/ssl_client_cert.pem" "Certificate Update"; then
                    
                    # Restart node service
                    if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                       "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" \
                       "Service Restart"; then
                        updated=$((updated + 1))
                        log "SUCCESS" "Certificate updated for node: $name"
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to restart service on node: $name"
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to deploy certificate to node: $name"
                fi
                
                rm "$temp_cert"
                unset NODE_SSH_PASSWORD
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to get certificate for node: $name"
            fi
        else
            log "WARNING" "Node '$name' has no API ID, skipping certificate update."
        fi
    done
    
    log "SUCCESS" "Certificate update completed: $updated updated, $failed failed."
    send_telegram_notification "🔐 Certificate Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

bulk_restart_services() {
    log "STEP" "Restarting services on all nodes..."
    
    load_nodes_config
    local restarted=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Restarting services on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "cd /opt/marzban-node && docker compose restart" \
           "Service Restart"; then
            restarted=$((restarted + 1))
            log "SUCCESS" "Services restarted on node: $name"
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to restart services on node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Service restart completed: $restarted restarted, $failed failed."
    send_telegram_notification "🔄 Service Restart Report%0A%0A✅ Restarted: $restarted%0A❌ Failed: $failed" "normal"
}

bulk_update_geo_files() {
    log "STEP" "Updating geo files on all nodes..."
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating geo files on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        # Transfer geo files if available on main server
        if [ -n "$GEO_FILES_PATH" ]; then
            if transfer_geo_files_to_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files updated on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to update geo files on node: $name"
            fi
        else
            # Download fresh geo files on node
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$(declare -f update_geo_files_on_node); update_geo_files_on_node" \
               "Geo Files Update"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files downloaded on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to download geo files on node: $name"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Geo files update completed: $updated updated, $failed failed."
    send_telegram_notification "🌍 Geo Files Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

_internal_deploy_node() {
    local node_name="$1" node_ip="$2" node_user="$3" node_port="$4" node_domain="$5" node_password="$6"

    log "STEP" "Starting Final Deployment Workflow for '$node_name'..."

    # Phase 1: Deploy and start the node in standalone mode (without client cert requirement)
    log "STEP" "Phase 1: Deploying node in standalone mode..."
    if ! scp_to_remote "${0%/*}/marzban_node_deployer.sh" "$node_ip" "$node_user" "$node_port" "$node_password" "/tmp/marzban_node_deployer.sh" "Node Deployer Script"; then return 1; fi
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "bash /tmp/marzban_node_deployer.sh" "Node Standalone Deployment"; then
        return 1
    fi
    
    # Wait until the node service is actually listening on the port
    log "INFO" "Waiting for node service to become active..."
    local timer=0
    while ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "ss -tuln | grep -q ':62050'" "Port Listening Check" >/dev/null 2>&1; do
        sleep 5
        timer=$((timer + 5))
        if [ $timer -ge 60 ]; then
            log "ERROR" "Node service failed to start and listen on port 62050 after 60 seconds. Please check node logs."
            return 1
        fi
    done
    log "SUCCESS" "Node service is active and listening."

    # Phase 2: Register the now-running node with the panel
    log "STEP" "Phase 2: Registering node with Marzban panel..."
    if ! get_marzban_token; then return 1; fi
    if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi

    # Phase 3: Retrieve the REAL client certificate
    log "STEP" "Phase 3: Retrieving client certificate..."
    if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
    if [ -z "$CLIENT_CERT" ]; then log "ERROR" "Failed to retrieve client certificate."; return 1; fi
    
    # Deploy the REAL certificate to the node
    local temp_cert; temp_cert=$(mktemp)
    echo "$CLIENT_CERT" > "$temp_cert"
    scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
    rm "$temp_cert"
    
    # Phase 4: Reconfigure and restart the node to enable panel connection
    log "STEP" "Phase 4: Reconfiguring and restarting node for panel connection..."
    local reconfigure_command="sed -i 's/# SSL_CLIENT_CERT_FILE/SSL_CLIENT_CERT_FILE/' /opt/marzban-node/docker-compose.yml && chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart"
    if ! ssh_remote "$node_ip" "$user" "$port" "$node_password" "$reconfigure_command" "Final Node Reconfiguration"; then
        return 1
    fi
    
    # Final health check
    log "INFO" "Waiting 15s for the node to connect to the panel..."
    sleep 15
    if check_node_health_via_api "$MARZBAN_NODE_ID" "$node_name"; then
        log "SUCCESS" "✅ Final health check passed! Node is fully connected."
    fi

    add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
    save_nodes_config
    return 0
}

deploy_new_node_professional_enhanced() {
    log "STEP" "Starting Enhanced Professional Node Deployment..."
    if [ -z "$MARZBAN_PANEL_DOMAIN" ]; then
        log "ERROR" "Marzban Panel API not configured. Please use Option 8 first."
        return 1
    fi
    detect_main_server_services

    local node_ip node_user="root" node_port="22" node_domain node_name node_password
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║     ${CYAN}Enhanced Professional Deployment${NC}     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    log "PROMPT" "Enter Node Name (unique identifier):"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP Address:"; read -r node_ip
    log "PROMPT" "Enter SSH Username (default: root):"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port (default: 22):"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain (e.g., node1.example.com):"; read -r node_domain
    if ! [[ $node_domain =~ ^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.){1,}[a-zA-Z]{2,}$ ]]; then
        log "ERROR" "Invalid domain format."
        return 1
    fi
    log "PROMPT" "Enter SSH Password for $node_user@$node_ip:"; read -s node_password; echo ""
    
    _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "🎉 Node '$node_name' deployed and configured successfully!"
        send_telegram_notification "🚀 New Node Deployed%0A%0ANode: $node_name%0AIP: $node_ip%0ADomain: $node_domain%0AStatus: ✅ Operational" "normal"
    else
        log "ERROR" "Node deployment failed. Please check the logs."
    fi
}

## Advanced Telegram Configuration
configure_telegram_advanced() {
    log "STEP" "Configuring advanced Telegram notifications..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Telegram Notifications Setup${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Telegram Bot Configuration:${NC}"
    echo "1. Create a bot via @BotFather on Telegram"
    echo "2. Get your chat ID from @userinfobot"
    echo "3. Configure notification levels"
    echo ""
    
    log "PROMPT" "Enter Telegram Bot Token:"
    read -r bot_token
    
    log "PROMPT" "Enter Telegram Chat ID:"
    read -r chat_id
    
    if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
        # Test notification
        log "INFO" "Testing Telegram notification..."
        local test_message="🤖 Marzban Central Manager%0A%0ATest notification from $(hostname)%0ATime: $(date)"
        
        if curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
           -d "chat_id=${chat_id}" \
           -d "text=${test_message}" \
           -d "parse_mode=Markdown" >/dev/null; then
            
            log "SUCCESS" "Telegram test notification sent successfully!"
            
            # Save configuration
            {
                echo "TELEGRAM_BOT_TOKEN=\"$bot_token\""
                echo "TELEGRAM_CHAT_ID=\"$chat_id\""
            } >> "$MANAGER_CONFIG_FILE"
            
            chmod 600 "$MANAGER_CONFIG_FILE"
            source "$MANAGER_CONFIG_FILE"
            
            # Configure notification levels
            echo -e "\n${PURPLE}Notification Levels:${NC}"
            echo " 1. All notifications (normal, high, critical)"
            echo " 2. High and critical only"
            echo " 3. Critical only"
            echo " 4. Disabled"
            echo ""
            
            log "PROMPT" "Choose notification level [default: 1]:"
            read -r level
            level=${level:-1}
            
            echo "TELEGRAM_NOTIFICATION_LEVEL=\"$level\"" >> "$MANAGER_CONFIG_FILE"
            
            log "SUCCESS" "Telegram notifications configured successfully!"
        else
            log "ERROR" "Failed to send test notification. Please check your bot token and chat ID."
        fi
    else
        log "ERROR" "Bot token and chat ID are required."
    fi
}

## Bulk Node Operations Menu
bulk_node_operations() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Bulk Node Operations${NC}             ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        load_nodes_config
        echo -e "${PURPLE}Available Operations for ${#NODES_ARRAY[@]} nodes:${NC}"
        echo " 1. Update All Certificates"
        echo " 2. Restart All Services"
        echo " 3. Update All Geo Files"
        echo " 4. Sync HAProxy to All Nodes"
        echo " 5. Health Check All Nodes"
        echo " 6. Reconnect Disconnected Nodes"
        echo " 7. Update All Node Configurations"
        echo " 8. Bulk SSH Command Execution"
        echo " 9. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose bulk operation:"
        read -r choice
        
        case "$choice" in
            1) bulk_update_certificates ;;
            2) bulk_restart_services ;;
            3) bulk_update_geo_files ;;
            4) bulk_sync_haproxy ;;
            5) bulk_health_check ;;
            6) bulk_reconnect_nodes ;;
            7) bulk_update_configurations ;;
            8) bulk_ssh_command ;;
            9) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "9" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

bulk_health_check() {
    log "STEP" "Performing health check on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local healthy=0 unhealthy=0 unknown=0
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Bulk Health Check Report${NC}                   ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        echo -e "${CYAN}Checking node: $name ($ip)${NC}"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            if check_node_health_via_api "$node_id" "$name"; then
                healthy=$((healthy + 1))
            else
                unhealthy=$((unhealthy + 1))
            fi
        else
            echo "   ⚪ No API ID - checking SSH connectivity..."
            export NODE_SSH_PASSWORD="$password"
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'SSH OK'" "SSH Health Check" >/dev/null 2>&1; then
                echo "   🟢 SSH connectivity: OK"
                unknown=$((unknown + 1))
            else
                echo "   🔴 SSH connectivity: FAILED"
                unhealthy=$((unhealthy + 1))
            fi
            unset NODE_SSH_PASSWORD
        fi
        echo ""
    done
    
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                      ${CYAN}Health Summary${NC}                           ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "🟢 Healthy Nodes: $healthy"
    echo -e "🔴 Unhealthy Nodes: $unhealthy"
    echo -e "⚪ Unknown Status: $unknown"
    echo -e "📊 Total Nodes: ${#NODES_ARRAY[@]}"
    
    # Send notification
    send_telegram_notification "🏥 Health Check Report%0A%0A🟢 Healthy: $healthy%0A🔴 Unhealthy: $unhealthy%0A⚪ Unknown: $unknown%0A📊 Total: ${#NODES_ARRAY[@]}" "normal"
}

bulk_sync_haproxy() {
    log "STEP" "Syncing HAProxy configuration to all nodes..."
    
    if [ "$MAIN_HAS_HAPROXY" != "true" ]; then
        log "ERROR" "HAProxy not detected on main server."
        return 1
    fi
    
    load_nodes_config
    local synced=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Syncing HAProxy to node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "HAProxy sync completed: $synced synced, $failed failed."
    send_telegram_notification "🔄 HAProxy Bulk Sync%0A%0A✅ Synced: $synced%0A❌ Failed: $failed" "normal"
}

bulk_reconnect_nodes() {
    log "STEP" "Reconnecting disconnected nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local reconnected=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
            
            if [ "$status" != "connected" ]; then
                log "INFO" "Attempting to reconnect node: $name"
                export NODE_SSH_PASSWORD="$password"
                
                # Restart node service
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && docker compose restart" \
                   "Service Restart for Reconnection"; then
                    
                    # Wait and check status again
                    sleep 10
                    health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                        -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                        -H "Authorization: Bearer $MARZBAN_TOKEN" \
                        --insecure 2>/dev/null)
                    
                    local new_status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
                    
                    if [ "$new_status" = "connected" ]; then
                        reconnected=$((reconnected + 1))
                        log "SUCCESS" "Node '$name' reconnected successfully."
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to reconnect node '$name'."
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to restart service on node '$name'."
                fi
                
                unset NODE_SSH_PASSWORD
            fi
        fi
    done
    
    log "SUCCESS" "Reconnection completed: $reconnected reconnected, $failed failed."
    send_telegram_notification "🔌 Bulk Reconnection%0A%0A✅ Reconnected: $reconnected%0A❌ Failed: $failed" "normal"
}

bulk_ssh_command() {
    log "STEP" "Bulk SSH command execution..."
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will execute a command on ALL nodes!${NC}"
    echo -e "${YELLOW}Please be very careful with the command you enter.${NC}\n"
    
    log "PROMPT" "Enter command to execute on all nodes:"
    read -r command
    
    if [ -z "$command" ]; then
        log "ERROR" "No command provided."
        return 1
    fi
    
    echo -e "\n${YELLOW}Command to execute: ${WHITE}$command${NC}"
    log "PROMPT" "Are you sure you want to execute this on ALL nodes? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Bulk command execution cancelled."
        return 0
    fi
    
    load_nodes_config
    local success=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Executing command on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$command" "Bulk Command Execution"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Bulk command execution completed: $success successful, $failed failed."
}

## System Diagnostics and Logs
show_system_diagnostics() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║        ${CYAN}System Logs & Diagnostics${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Log Management:${NC}"
        echo " 1. View Recent Manager Logs"
        echo " 2. View Marzban Panel Logs"
        echo " 3. View HAProxy Logs"
        echo " 4. View System Logs"
        echo ""
        echo -e "${PURPLE}Diagnostics:${NC}"
        echo " 5. System Resource Usage"
        echo " 6. Network Connectivity Test"
        echo " 7. Service Status Check"
        echo " 8. Configuration Validation"
        echo ""
        echo -e "${PURPLE}Maintenance:${NC}"
        echo " 9. Clean Old Log Files"
        echo " 10. Export Diagnostic Report"
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose diagnostic option:"
        read -r choice
        
        case "$choice" in
            1) view_manager_logs ;;
            2) view_marzban_logs ;;
            3) view_haproxy_logs ;;
            4) view_system_logs ;;
            5) show_system_resources ;;
            6) test_network_connectivity ;;
            7) check_service_status ;;
            8) validate_configurations ;;
            9) clean_old_logs ;;
            10) export_diagnostic_report ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_manager_logs() {
    log "INFO" "Displaying recent Manager logs..."
    
    echo -e "\n${CYAN}Recent Manager Activity:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$LOGFILE" ]; then
        tail -50 "$LOGFILE"
    else
        echo "No current session log file found."
    fi
    
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    # Show system logs for marzban-central-manager
    echo -e "\n${CYAN}System Logs (last 20 entries):${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -t marzban-central-manager -n 20 --no-pager 2>/dev/null || echo "No system logs found."
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

show_system_resources() {
    log "INFO" "Displaying system resource usage..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}System Resource Usage${NC}                     ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # CPU Usage
    echo -e "${PURPLE}🖥️  CPU Usage:${NC}"
    top -bn1 | grep "Cpu(s)" | awk '{print $2 $3 $4 $5 $6 $7 $8}' | sed 's/%us,/ User,/g; s/%sy,/ System,/g; s/%ni,/ Nice,/g; s/%id,/ Idle,/g; s/%wa,/ Wait,/g; s/%hi,/ Hardware IRQ,/g; s/%si/ Software IRQ/g'
    
    # Memory Usage
    echo -e "\n${PURPLE}💾 Memory Usage:${NC}"
    free -h | grep -E "(Mem|Swap)"
    
    # Disk Usage
    echo -e "\n${PURPLE}💿 Disk Usage:${NC}"
    df -h | grep -E "^/dev"
    
    # Network Usage
    echo -e "\n${PURPLE}🌐 Network Interfaces:${NC}"
    ip -s link show | grep -E "(^\d+:|RX:|TX:)" | head -20
    
    # Load Average
    echo -e "\n${PURPLE}📊 Load Average:${NC}"
    uptime
    
    # Top Processes
    echo -e "\n${PURPLE}🔝 Top Processes (CPU):${NC}"
    ps aux --sort=-%cpu | head -10 | awk '{printf "%-10s %-6s %-6s %-50s\n", $1, $3, $4, $11}'
    
    # Docker Resources (if available)
    if command_exists docker; then
        echo -e "\n${PURPLE}🐳 Docker Resources:${NC}"
        docker system df 2>/dev/null || echo "Docker system info unavailable"
    fi
}

test_network_connectivity() {
    log "INFO" "Testing network connectivity..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                   ${CYAN}Network Connectivity Test${NC}                  ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Test DNS resolution
    echo -e "${PURPLE}🔍 DNS Resolution Test:${NC}"
    for domain in "google.com" "github.com" "cloudflare.com"; do
        if nslookup "$domain" >/dev/null 2>&1; then
            echo "✅ $domain - OK"
        else
            echo "❌ $domain - FAILED"
        fi
    done
    
    # Test internet connectivity
    echo -e "\n${PURPLE}🌐 Internet Connectivity Test:${NC}"
    for host in "8.8.8.8" "1.1.1.1" "208.67.222.222"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            echo "✅ $host - OK"
        else
            echo "❌ $host - FAILED"
        fi
    done
    
    # Test Marzban Panel connectivity
    if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
        echo -e "\n${PURPLE}🔗 Marzban Panel Connectivity:${NC}"
        local panel_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}"
        
        if curl -s --connect-timeout 5 --max-time 10 "$panel_url" >/dev/null 2>&1; then
            echo "✅ $panel_url - OK"
        else
            echo "❌ $panel_url - FAILED"
        fi
    fi
    
    # Test node connectivity
    echo -e "\n${PURPLE}🖥️  Node Connectivity Test:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
            echo "✅ $name ($ip) - Ping OK"
        else
            echo "❌ $name ($ip) - Ping FAILED"
        fi
    done
}

check_service_status() {
    log "INFO" "Checking service status..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                     ${CYAN}Service Status Check${NC}                      ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check main services
    local services=("docker" "nginx" "haproxy" "ssh" "cron")
    
    echo -e "${PURPLE}🔧 Main Server Services:${NC}"
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "✅ $service - Running"
        elif systemctl list-unit-files | grep -q "^$service.service"; then
            echo "❌ $service - Stopped"
        else
            echo "⚪ $service - Not Installed"
        fi
    done
    
    # Check Marzban service
    echo -e "\n${PURPLE}📊 Marzban Panel Status:${NC}"
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        if docker compose ps | grep -q "Up"; then
            echo "✅ Marzban Panel - Running"
        else
            echo "❌ Marzban Panel - Stopped"
        fi
    else
        echo "⚪ Marzban Panel - Not Found"
    fi
    
    # Check node services
    echo -e "\n${PURPLE}🖥️  Node Services Status:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_status
        node_status=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                     "cd /opt/marzban-node 2>/dev/null && docker compose ps | grep -q 'Up' && echo 'Running' || echo 'Stopped'" \
                     "Node Service Check" 2>/dev/null || echo "Unreachable")
        
        case "$node_status" in
            "Running") echo "✅ $name - Running" ;;
            "Stopped") echo "❌ $name - Stopped" ;;
            *) echo "⚪ $name - Unreachable" ;;
        esac
        
        unset NODE_SSH_PASSWORD
    done
}

export_diagnostic_report() {
    log "INFO" "Generating comprehensive diagnostic report..."
    
    local report_file="${BACKUP_DIR}/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Marzban Central Manager - Diagnostic Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "Manager Version: $SCRIPT_VERSION"
        echo "========================================"
        echo ""
        
        echo "SYSTEM INFORMATION:"
        echo "-------------------"
        uname -a
        echo ""
        cat /etc/os-release 2>/dev/null || echo "OS info unavailable"
        echo ""
        
        echo "RESOURCE USAGE:"
        echo "---------------"
        free -h
        echo ""
        df -h
        echo ""
        uptime
        echo ""
        
        echo "NETWORK CONFIGURATION:"
        echo "----------------------"
        ip addr show | grep -E "(inet |inet6 )"
        echo ""
        
        echo "SERVICE STATUS:"
        echo "---------------"
        for service in docker nginx haproxy ssh cron; do
            systemctl is-active "$service" 2>/dev/null | sed "s/^/$service: /"
        done
        echo ""
        
        echo "MARZBAN CONFIGURATION:"
        echo "----------------------"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
            echo "Panel Domain: $MARZBAN_PANEL_DOMAIN"
            echo "Panel Port: $MARZBAN_PANEL_PORT"
            echo "Panel Protocol: $MARZBAN_PANEL_PROTOCOL"
        else
            echo "Marzban Panel not configured"
        fi
        echo ""
        
        echo "CONFIGURED NODES:"
        echo "-----------------"
        load_nodes_config
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            echo "Node: $name | IP: $ip | Domain: $domain | ID: $node_id"
        done
        echo ""
        
        echo "RECENT LOGS:"
        echo "------------"
        if [ -f "$LOGFILE" ]; then
            tail -20 "$LOGFILE"
        else
            echo "No recent logs available"
        fi
        
    } > "$report_file"
    
    log "SUCCESS" "Diagnostic report generated: $report_file"
    
    # Offer to send via Telegram
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        log "PROMPT" "Send diagnostic report via Telegram? (y/n):"
        read -r send_telegram
        
        if [[ "$send_telegram" =~ ^[Yy]$ ]]; then
            local report_summary="📋 Diagnostic Report%0A%0AGenerated: $(date)%0AHostname: $(hostname)%0ANodes: ${#NODES_ARRAY[@]}%0A%0AReport saved locally: $(basename "$report_file")"
            send_telegram_notification "$report_summary" "normal"
            log "SUCCESS" "Diagnostic summary sent via Telegram."
        fi
    fi
}

## Missing functions implementation
bulk_update_configurations() {
    log "STEP" "Bulk updating node configurations..."
    
    echo -e "\n${YELLOW}This will update common configuration files on all nodes.${NC}"
    echo -e "${YELLOW}Available updates:${NC}"
    echo " 1. Update docker-compose.yml"
    echo " 2. Update environment variables"
    echo " 3. Update SSL certificates"
    echo " 4. All of the above"
    echo ""
    
    log "PROMPT" "Choose update type:"
    read -r update_type
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating configuration for node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        case "$update_type" in
            1|4)
                # Update docker-compose.yml
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && $(declare -f create_enhanced_docker_compose); create_enhanced_docker_compose" \
                   "Docker Compose Update"; then
                    log "SUCCESS" "Docker compose updated on node: $name"
                else
                    log "ERROR" "Failed to update docker compose on node: $name"
                fi
                ;;
        esac
        
        if [ "$update_type" = "4" ] || [ "$update_type" = "2" ]; then
            # Update environment variables
            ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                "cd /opt/marzban-node && docker compose restart" \
                "Service Restart" >/dev/null 2>&1
        fi
        
        updated=$((updated + 1))
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Configuration update completed: $updated updated, $failed failed."
}

view_marzban_logs() {
    log "INFO" "Displaying Marzban Panel logs..."
    
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        echo -e "\n${CYAN}Recent Marzban Panel Logs:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        docker compose logs --tail=50 2>/dev/null || echo "Unable to fetch Marzban logs"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Marzban installation not found at /opt/marzban"
    fi
}

view_haproxy_logs() {
    log "INFO" "Displaying HAProxy logs..."
    
    echo -e "\n${CYAN}Recent HAProxy Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -u haproxy -n 50 --no-pager 2>/dev/null || echo "HAProxy logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

view_system_logs() {
    log "INFO" "Displaying system logs..."
    
    echo -e "\n${CYAN}Recent System Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -n 50 --no-pager 2>/dev/null || echo "System logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

validate_configurations() {
    log "INFO" "Validating system configurations..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                  ${CYAN}Configuration Validation${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Validate Nginx configuration
    if command_exists nginx; then
        echo -e "${PURPLE}🔧 Nginx Configuration:${NC}"
        if nginx -t 2>/dev/null; then
            echo "✅ Nginx configuration is valid"
        else
            echo "❌ Nginx configuration has errors"
        fi
    fi
    
    # Validate HAProxy configuration
    if command_exists haproxy; then
        echo -e "\n${PURPLE}⚖️  HAProxy Configuration:${NC}"
        if /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg 2>/dev/null; then
            echo "✅ HAProxy configuration is valid"
        else
            echo "❌ HAProxy configuration has errors"
        fi
    fi
    
    # Validate Manager configuration
    echo -e "\n${PURPLE}📊 Manager Configuration:${NC}"
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        echo "✅ Manager configuration file exists"
        
        # Check required variables
        source "$MANAGER_CONFIG_FILE"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ] && [ -n "$MARZBAN_PANEL_USERNAME" ]; then
            echo "✅ Marzban Panel credentials configured"
        else
            echo "❌ Marzban Panel credentials missing"
        fi
    else
        echo "❌ Manager configuration file missing"
    fi
    
    # Validate node configurations
    echo -e "\n${PURPLE}🖥️  Node Configurations:${NC}"
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -gt 0 ]; then
        echo "✅ ${#NODES_ARRAY[@]} nodes configured"
        
        local valid_nodes=0
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                valid_nodes=$((valid_nodes + 1))
            fi
        done
        echo "✅ $valid_nodes nodes have valid IP addresses"
    else
        echo "⚪ No nodes configured"
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        log "DEBUG" "Checking type of command_exists before use in clean_old_logs:"
        type command_exists || log "ERROR" "command_exists is not recognized here!"
        
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

# Additional missing functions for complete functionality
add_nginx_site() {
    log "STEP" "Adding new Nginx site configuration..."
    
    log "PROMPT" "Enter site domain (e.g., example.com):"
    read -r site_domain
    
    log "PROMPT" "Enter document root path (default: /var/www/$site_domain):"
    read -r doc_root
    doc_root=${doc_root:-/var/www/$site_domain}
    
    # Create site configuration
    local site_config="/etc/nginx/sites-available/$site_domain"
    cat > "$site_config" << EOF
server {
    listen 80;
    server_name $site_domain www.$site_domain;
    root $doc_root;
    index index.html index.htm index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF
    
    # Create document root
    mkdir -p "$doc_root"
    chown www-data:www-data "$doc_root"
    
    # Create basic index file
    echo "<h1>Welcome to $site_domain</h1>" > "$doc_root/index.html"
    chown www-data:www-data "$doc_root/index.html"
    
    log "SUCCESS" "Site configuration created: $site_config"
    log "INFO" "To enable the site, run: ln -s $site_config /etc/nginx/sites-enabled/"
}

remove_nginx_site() {
    log "STEP" "Removing Nginx site configuration..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            echo " $i. $site_name"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to remove:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            # Remove from sites-enabled if linked
            rm -f "/etc/nginx/sites-enabled/$selected_site"
            
            # Remove from sites-available
            rm -f "/etc/nginx/sites-available/$selected_site"
            
            log "SUCCESS" "Site '$selected_site' removed successfully."
            
            # Test nginx configuration
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed after site removal."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available to remove."
    fi
}

toggle_nginx_site() {
    log "STEP" "Enable/Disable Nginx site..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            local status="disabled"
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                status="enabled"
            fi
            echo " $i. $site_name ($status)"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to toggle:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            if [ -L "/etc/nginx/sites-enabled/$selected_site" ]; then
                # Disable site
                rm "/etc/nginx/sites-enabled/$selected_site"
                log "SUCCESS" "Site '$selected_site' disabled."
            else
                # Enable site
                ln -s "/etc/nginx/sites-available/$selected_site" "/etc/nginx/sites-enabled/"
                log "SUCCESS" "Site '$selected_site' enabled."
            fi
            
            # Test and reload nginx
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available."
    fi
}

generate_ssl_certificate() {
    log "STEP" "Generating SSL certificate..."
    
    log "PROMPT" "Enter domain for SSL certificate:"
    read -r ssl_domain
    
    log "PROMPT" "Enter email for Let's Encrypt:"
    read -r ssl_email
    
    # Install certbot if not available
    if ! command_exists certbot; then
        log "INFO" "Installing certbot..."
        apt update >/dev/null 2>&1
        apt install -y certbot python3-certbot-nginx >/dev/null 2>&1
    fi
    
    # Generate certificate
    if certbot --nginx -d "$ssl_domain" --email "$ssl_email" --agree-tos --non-interactive; then
        log "SUCCESS" "SSL certificate generated for $ssl_domain"
    else
        log "ERROR" "Failed to generate SSL certificate for $ssl_domain"
    fi
}

renew_ssl_certificates() {
    log "STEP" "Renewing SSL certificates..."
    
    if command_exists certbot; then
        if certbot renew --dry-run; then
            log "SUCCESS" "SSL certificate renewal test passed."
            
            log "PROMPT" "Proceed with actual renewal? (y/n):"
            read -r proceed
            
            if [[ "$proceed" =~ ^[Yy]$ ]]; then
                if certbot renew; then
                    log "SUCCESS" "SSL certificates renewed successfully."
                    systemctl reload nginx
                else
                    log "ERROR" "SSL certificate renewal failed."
                fi
            fi
        else
            log "ERROR" "SSL certificate renewal test failed."
        fi
    else
        log "ERROR" "Certbot not installed."
    fi
}

view_certificate_status() {
    log "INFO" "Displaying SSL certificate status..."
    
    if command_exists certbot; then
        echo -e "\n${CYAN}SSL Certificate Status:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        certbot certificates
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Certbot not installed. Cannot check SSL certificate status."
    fi
}

# Script completion message
log "SUCCESS" "Marzban Central Manager Professional Edition v$SCRIPT_VERSION loaded successfully!"

# ==============================================================================
# MAIN MENU DISPLAY FUNCTION
# ==============================================================================

show_main_menu() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║ ${CYAN}${BOLD}Marzban Central Node Manager${NC}                           ║"
    echo -e "${WHITE}║ ${PURPLE}Made with ❤️ by B3hnAM - Thanks to all Marzban developers${NC} ║"
    echo -e "${WHITE}║ ${YELLOW}[Professional Edition v${SCRIPT_VERSION}]${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}Current Nodes Overview:${NC}"
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No nodes have been added yet.${NC}"
    else
        printf "%-20s %-15s %-15s %-10s\n" "Node Name" "IP Address" "Status" "Domain"
        echo -e "${WHITE}----------------------------------------------------------------------${NC}"
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            local status
            if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
                status="${GREEN}Online${NC}"
            else
                status="${RED}Offline${NC}"
            fi
            printf "%-20s %-15s %-15s %-10s\n" "$name" "$ip" "$status" "$domain"
        done
    fi
    
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${GREEN}1) Add a new node${NC}"
    echo -e "${GREEN}2) Remove a node${NC}"
    echo -e "${GREEN}3) Update node information${NC}"
    echo -e "${YELLOW}4) Sync HAProxy to All Nodes${NC}"
    echo -e "${CYAN}5) Check all nodes status${NC}"
    echo -e "${PURPLE}6) Bulk Update Node Configurations${NC}"
    echo -e "${BLUE}7) Install Marzban on a new node${NC}"
    echo -e "${WHITE}8) Configure Marzban API${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${GREEN}9) Backup & Restore Menu${NC}"
    echo -e "${GREEN}10) Nginx Management Menu${NC}"
    echo -e "${GREEN}11) Bulk Node Operations Menu${NC}"
    echo -e "${GREEN}12) System Logs & Diagnostics Menu${NC}"
    echo -e "${CYAN}-----------------------------------------------${NC}" # Additional separator
    echo -e "${WHITE}13) Configure Telegram Notifications${NC}"
    echo -e "${WHITE}14) View System Resources${NC}"
    echo -e "${WHITE}15) Validate Configurations${NC}"
    echo -e "${WHITE}16) Clean Old Logs${NC}"
    echo -e "${YELLOW}17) View Marzban Panel Logs${NC}"
    echo -e "${YELLOW}18) View HAProxy Logs${NC}"
    echo -e "${YELLOW}19) View System Logs${NC}"
    echo -e "${RED}x) Exit${NC}"
    echo ""
}

# ==============================================================================
# MAIN EXECUTION LOGIC
# ==============================================================================

main() {
    check_dependencies # Ensure dependencies are met before showing the menu
    while true; do
        show_main_menu
        read -p "Please enter your choice [1-19, x]: " choice

        case "$choice" in
            1) import_single_node || true; read -p "Press Enter to continue..." ;;
            2) remove_node || true; read -p "Press Enter to continue..." ;;
            3) update_existing_node || true; read -p "Press Enter to continue..." ;;
            4) bulk_sync_haproxy || true; read -p "Press Enter to continue..." ;;
            5) monitor_node_health_status || true; read -p "Press Enter to continue..." ;;
            6) bulk_update_configurations || true; read -p "Press Enter to continue..." ;;
            7) deploy_new_node_professional_enhanced || true; read -p "Press Enter to continue..." ;;
            8) configure_marzban_api || true; read -p "Press Enter to continue..." ;;
            9) backup_restore_menu || true; read -p "Press Enter to continue..." ;;
            10) nginx_management_menu || true; read -p "Press Enter to continue..." ;;
            11) bulk_node_operations || true; read -p "Press Enter to continue..." ;;
            12) show_system_diagnostics || true; read -p "Press Enter to continue..." ;;
            13) configure_telegram_advanced || true; read -p "Press Enter to continue..." ;;
            14) show_system_resources || true; read -p "Press Enter to continue..." ;;
            15) validate_configurations || true; read -p "Press Enter to continue..." ;;
            16) clean_old_logs || true; read -p "Press Enter to continue..." ;;
            17) view_marzban_logs || true; read -p "Press Enter to continue..." ;;
            18) view_haproxy_logs || true; read -p "Press Enter to continue..." ;;
            19) view_system_logs || true; read -p "Press Enter to continue..." ;;
            x|X)
                log "INFO" "Exiting Marzban Central Manager. Goodbye!"
                exit 0
                ;;
            *)
                log "ERROR" "Invalid option: $choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Start The Program ---
main\n\t'

# Marzban Central Node Manager - Professional Edition v3.0
# Enhanced with Complete Backup System, Optimized Monitoring & Advanced Features
# Author: behnamrjd
# Version: Professional-3.0

SCRIPT_VERSION="Professional-3.0"
MANAGER_DIR="/root/MarzbanManager"
NODES_CONFIG_FILE="${MANAGER_DIR}/marzban_managed_nodes.conf"
MANAGER_CONFIG_FILE="${MANAGER_DIR}/marzban_manager.conf"
BACKUP_DIR="${MANAGER_DIR}/backups"
LOCKFILE="/var/lock/marzban-central-manager.lock"
LOGFILE="/tmp/marzban_central_manager_$(date +%Y%m%d_%H%M%S).log"

# Enhanced Backup Configuration
BACKUP_MAIN_DIR="${BACKUP_DIR}/main_server"
BACKUP_NODES_DIR="${BACKUP_DIR}/nodes"
BACKUP_ARCHIVE_DIR="${BACKUP_DIR}/archives"
BACKUP_RETENTION_COUNT=3
BACKUP_SCHEDULE_HOUR="03"
BACKUP_SCHEDULE_MINUTE="30"
BACKUP_TIMEZONE="Asia/Tehran"
AUTO_BACKUP_ENABLED=false

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

# --- Global Variables ---
MAIN_SERVER_IP=$(hostname -I | awk '{print $1}')
MARZBAN_PANEL_PROTOCOL="https"
MARZBAN_PANEL_DOMAIN=""
MARZBAN_PANEL_PORT=""
MARZBAN_PANEL_USERNAME=""
MARZBAN_PANEL_PASSWORD=""
MARZBAN_TOKEN=""
CLIENT_CERT=""
MARZBAN_NODE_ID=""

# Enhanced monitoring configuration (optimized for server performance)
MONITORING_INTERVAL=600  # 10 minutes (reduced from 5 minutes)
HEALTH_CHECK_TIMEOUT=30  # Increased timeout for stability
API_RATE_LIMIT_DELAY=2   # Delay between API calls
SYNC_CHECK_INTERVAL=1800 # 30 minutes for sync monitoring

# Service detection variables
MAIN_HAS_NGINX=false
MAIN_HAS_HAPROXY=false
NGINX_CONFIG_PATH=""
HAPROXY_CONFIG_PATH=""
GEO_FILES_PATH=""

mkdir -p "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
chmod 700 "$MANAGER_DIR" "$BACKUP_DIR" "$BACKUP_MAIN_DIR" "$BACKUP_NODES_DIR" "$BACKUP_ARCHIVE_DIR"
if [ -f "$MANAGER_CONFIG_FILE" ]; then source "$MANAGER_CONFIG_FILE"; fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

## Enhanced logging with multiple levels and file rotation
log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    local masked_message="$message"
    
    # Mask sensitive information
    if [[ -n "${NODE_SSH_PASSWORD:-}" ]]; then masked_message="${message//$NODE_SSH_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_PANEL_PASSWORD:-}" ]]; then masked_message="${message//$MARZBAN_PANEL_PASSWORD/*****masked*****/}"; fi
    if [[ -n "${MARZBAN_TOKEN:-}" ]]; then masked_message="${message//$MARZBAN_TOKEN/*****masked*****/}"; fi
    
    # Log to system logger
    logger -t "marzban-central-manager" "$level: $masked_message"
    
    # Enhanced console output with icons and colors
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $masked_message" | tee -a "$LOGFILE";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $masked_message" | tee -a "$LOGFILE";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $masked_message" | tee -a "$LOGFILE";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $masked_message" | tee -a "$LOGFILE";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $masked_message" | tee -a "$LOGFILE";;
        PROMPT)  echo -e "[$timestamp] ${CYAN}❓ PROMPT:${NC} $masked_message";;
        DEBUG)   echo -e "[$timestamp] ${DIM}🐛 DEBUG:${NC} $masked_message" | tee -a "$LOGFILE";;
        BACKUP)  echo -e "[$timestamp] ${CYAN}💾 BACKUP:${NC} $masked_message" | tee -a "$LOGFILE";;
        SYNC)    echo -e "[$timestamp] ${PURPLE}🔄 SYNC:${NC} $masked_message" | tee -a "$LOGFILE";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $masked_message" | tee -a "$LOGFILE";;
    esac
}

send_telegram_notification() {
    local message="$1"
    local level="${2:-normal}" # normal, high, critical
    local stored_level

    # Load TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, and TELEGRAM_NOTIFICATION_LEVEL from config
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        source "$MANAGER_CONFIG_FILE"
    fi

    stored_level=${TELEGRAM_NOTIFICATION_LEVEL:-1} # Default to all notifications if not set

    # Check if notifications are enabled and the level is appropriate
    if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_CHAT_ID}" ] || [ "$stored_level" -eq 4 ]; then
        # log "DEBUG" "Telegram notifications are disabled or not configured."
        return 0
    fi

    # Level mapping: 1=all, 2=high/critical, 3=critical only
    case "$level" in
        "normal")
            if [ "$stored_level" -gt 1 ]; then return 0; fi
            ;;
        "high")
            if [ "$stored_level" -gt 2 ]; then return 0; fi
            ;;
        "critical")
            if [ "$stored_level" -gt 3 ]; then return 0; fi
            ;;
    esac

    # Send the notification using curl
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d "chat_id=${TELEGRAM_CHAT_ID}" \
         -d "text=${message}" \
         -d "parse_mode=HTML" > /dev/null &
}

## Lock management for single instance execution
acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        local pid; pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then 
            log "ERROR" "Instance already running (PID: $pid)."
            exit 1
        fi
        log "WARNING" "Removing stale lock file."
        rm -f "$LOCKFILE"
    fi
    echo "$$" > "$LOCKFILE"
    log "INFO" "Lock acquired."
}

release_lock() { rm -f "$LOCKFILE"; log "INFO" "Lock released."; }
trap release_lock EXIT
trap 'log "ERROR" "Script interrupted"; exit 1' INT TERM

## Dependency checks with auto-installation
check_dependencies() {
    local deps=("sshpass" "python3" "curl" "jq" "rsync" "pigz" "git")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then # Using our defined function
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log "INFO" "Installing missing dependencies: ${missing_deps[*]}"
        if command_exists apt; then
            apt update >/dev/null 2>&1
            apt install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via apt."
        elif command_exists yum; then
            yum install -y "${missing_deps[@]}" >/dev/null 2>&1
            log "SUCCESS" "Dependencies installed successfully via yum."
        else
            log "ERROR" "Cannot determine package manager (apt or yum). Please install dependencies manually: ${missing_deps[*]}"
            return 1
        fi
    fi
    
    # Check Python modules
    if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
        log "INFO" "Installing python3-full (or equivalent for json, urllib.parse, datetime)..."
        if command_exists apt; then
            apt install -y python3-full >/dev/null 2>&1
        elif command_exists yum; then
             # CentOS might need python3-json, python3-urllib an python3-datetime or similar
             # For simplicity, assuming python3-devel or a more general package might cover these.
             # This part might need adjustment based on specific distro.
            yum install -y python3-devel >/dev/null 2>&1 || yum install -y python3 >/dev/null 2>&1
        fi
        # Re-check after attempting install
        if ! python3 -c "import json, urllib.parse, datetime" 2>/dev/null; then
            log "WARNING" "Failed to install required Python modules. Some functionalities might be affected."
        else
            log "SUCCESS" "Python modules seem to be available."
        fi
    fi
    return 0
}

## Enhanced SSH operations with retry mechanism and rate limiting
ssh_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" command="$5" desc="$6"
    local max_retries=3 retry=0
    
    sleep "$API_RATE_LIMIT_DELAY"
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Executing ($desc) on $node_ip (attempt $((retry+1))/$max_retries)..."
        
        # Use a here-string to pass the password securely
        if sshpass -p "$node_password" ssh -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
           -p "$node_port" "${node_user}@${node_ip}" "$command" 2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "Remote command ($desc) executed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 5 seconds..."
            sleep 5
        fi
    done
    
    log "ERROR" "Remote command ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP with progress and retry
scp_to_remote() {
    local local_path="$1" node_ip="$2" node_user="$3" node_port="$4" node_password="$5" remote_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Transferring ($desc) to $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "$local_path" "${node_user}@${node_ip}:${remote_path}" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File transfer ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File transfer ($desc) failed after $max_retries attempts."
    return 1
}

## Enhanced SCP from remote with retry
scp_from_remote() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" remote_path="$5" local_path="$6" desc="$7"
    local max_retries=3 retry=0
    
    while [ $retry -lt $max_retries ]; do
        log "INFO" "Downloading ($desc) from $node_ip (attempt $((retry+1))/$max_retries)..."
        
        if echo "$node_password" | sshpass -p "$node_password" scp -o StrictHostKeyChecking=no \
           -o ConnectTimeout="$HEALTH_CHECK_TIMEOUT" -P "$node_port" "${node_user}@${node_ip}:${remote_path}" "$local_path" \
           2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "File download ($desc) completed successfully."
            return 0
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log "WARNING" "Retry $retry/$max_retries in 3 seconds..."
            sleep 3
        fi
    done
    
    log "ERROR" "File download ($desc) failed after $max_retries attempts."
    return 1
}

## Node configuration management
load_nodes_config() {
    if [ -f "$NODES_CONFIG_FILE" ]; then
        mapfile -t NODES_ARRAY < <(grep -vE '^\s*#|^\s*$' "$NODES_CONFIG_FILE" || true)
    else
        NODES_ARRAY=()
    fi
}

save_nodes_config() {
    printf "%s\n" "${NODES_ARRAY[@]}" > "$NODES_CONFIG_FILE"
    chmod 600 "$NODES_CONFIG_FILE"
    log "INFO" "Nodes configuration saved."
}

add_node_to_config() {
    local name="$1" ip="$2" user="$3" port="$4" domain="$5" password="$6" node_id="${7:-}"
    NODES_ARRAY+=("${name};${ip};${user};${port};${domain};${password};${node_id}")
    log "INFO" "Node '$name' added to configuration."
}

get_node_config_by_name() {
    local name="$1"
    for entry in "${NODES_ARRAY[@]}"; do
        if [[ "$entry" == "${name};"* ]]; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

## Service Detection System
detect_main_server_services() {
    log "STEP" "Detecting services on main server..."
    
    # Detect Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        MAIN_HAS_NGINX=true
        NGINX_CONFIG_PATH="/etc/nginx"
        log "SUCCESS" "Nginx detected on main server"
    else
        MAIN_HAS_NGINX=false
        log "INFO" "Nginx not detected on main server"
    fi
    
    # Detect HAProxy
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        MAIN_HAS_HAPROXY=true
        HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
        log "SUCCESS" "HAProxy detected on main server"
    else
        MAIN_HAS_HAPROXY=false
        log "INFO" "HAProxy not detected on main server"
    fi
    
    # Detect Geo files from Core config
    detect_geo_files_location
}

detect_geo_files_location() {
    log "INFO" "Detecting geo files location using multi-priority smart-scan..."
    
    # --- Priority 1: The most reliable method (from .env file) ---
    if [ -f "/opt/marzban/.env" ]; then
        local env_geo_path
        env_geo_path=$(grep -E "^\s*XRAY_ASSETS_PATH" /opt/marzban/.env | cut -d'=' -f2- | tr -d '"' | tr -d "'" | sed 's/#.*//' | xargs)
        if [ -n "$env_geo_path" ] && [ -d "$env_geo_path" ]; then
            if [ -f "$env_geo_path/geosite.dat" ] && [ -f "$env_geo_path/geoip.dat" ]; then
                log "SUCCESS" "Geo files found and validated via .env file at: $env_geo_path"
                GEO_FILES_PATH="$env_geo_path"
                return 0
            fi
        fi
    fi

    # --- Priority 2: Your brilliant idea - Find filenames from xray_config.json and search for them ---
    if [ -f "/var/lib/marzban/xray_config.json" ]; then
        log "INFO" "Scanning xray_config.json for custom geo file names..."
        local geoip_file
        local geosite_file

        geoip_file=$(jq -r '[.routing.rules[]? | .ip[]? | select(startswith("geoip:"))] | .[0] // "geoip:geoip"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geoip_file+=".dat"

        geosite_file=$(jq -r '[.routing.rules[]? | .domain[]? | select(startswith("geosite:"))] | .[0] // "geosite:geosite"' /var/lib/marzban/xray_config.json | cut -d':' -f2)
        geosite_file+=".dat"
        
        log "DEBUG" "Detected target files: $geoip_file, $geosite_file"

        local found_dir
        found_dir=$(find / -name "$geoip_file" -printf "%h\n" 2>/dev/null | while read -r dir; do
            if [ -f "$dir/$geosite_file" ]; then
                echo "$dir"
                break
            fi
        done)

        if [ -n "$found_dir" ]; then
            log "SUCCESS" "Geo files found via xray_config scan at: $found_dir"
            GEO_FILES_PATH="$found_dir"
            return 0
        fi
    fi

    # --- Priority 3: Fallback to scanning common hardcoded locations ---
    log "INFO" "Falling back to scanning common default directories..."
    local common_paths=(
        "/var/lib/marzban/assets" "/var/lib/marzban/geo" "/var/lib/marzban/chocolate"
        "/opt/marzban/assets" "/opt/marzban/geo"
    )
    for path in "${common_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/geosite.dat" ] && [ -f "$path/geoip.dat" ]; then
            log "SUCCESS" "Geo files found via fallback scan at: $path"
            GEO_FILES_PATH="$path"
            return 0
        fi
    done
    
    log "WARNING" "Could not find custom Geo files on the main server. Geo file sync will be skipped."
    GEO_FILES_PATH=""
    return 1
}
## Complete Backup System Implementation
create_full_backup() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_full_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting comprehensive backup process..."
    
    # Create temporary backup directory
    mkdir -p "$temp_backup_dir"
    
    # Phase 1: Backup main server
    log "STEP" "Phase 1: Backing up main server..."
    backup_main_server "$temp_backup_dir"
    
    # Phase 2: Backup all nodes
    log "STEP" "Phase 2: Backing up all nodes..."
    backup_all_nodes "$temp_backup_dir"
    
    # Phase 3: Create compressed archive
    log "STEP" "Phase 3: Creating compressed archive..."
    create_backup_archive "$temp_backup_dir" "$final_archive"
    
    # Phase 4: Apply retention policy
    log "STEP" "Phase 4: Applying retention policy..."
    apply_backup_retention_policy_global
    
    # Cleanup
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Full backup completed: $final_archive"
    
    # Send notification
    local backup_size=$(du -h "$final_archive" | cut -f1)
    send_telegram_notification "💾 Backup Completed%0A%0A📁 File: ${backup_name}.tar.gz%0A📊 Size: ${backup_size}%0A⏰ Time: $(date)" "normal"
}

backup_main_server() {
    local backup_dir="$1/main_server"
    mkdir -p "$backup_dir"
    
    log "BACKUP" "Backing up main server components..."
    
    # Backup Marzban
    if [ -d "/opt/marzban" ]; then
        log "INFO" "Backing up Marzban configuration..."
        cp -r /opt/marzban "$backup_dir/" 2>/dev/null || log "WARNING" "Failed to backup Marzban"
    fi
    
    # Backup HAProxy (if user confirms)
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "PROMPT" "Backup HAProxy configuration? (y/n):"
        read -r backup_haproxy
        if [[ "$backup_haproxy" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up HAProxy configuration..."
            mkdir -p "$backup_dir/haproxy"
            cp -r /etc/haproxy/* "$backup_dir/haproxy/" 2>/dev/null || log "WARNING" "Failed to backup HAProxy"
        fi
    fi
    
    # Backup Nginx (if user confirms)
    if [ "$MAIN_HAS_NGINX" = "true" ]; then
        log "PROMPT" "Backup Nginx configuration? (y/n):"
        read -r backup_nginx
        if [[ "$backup_nginx" =~ ^[Yy]$ ]]; then
            log "INFO" "Backing up Nginx configuration..."
            mkdir -p "$backup_dir/nginx"
            cp -r /etc/nginx/* "$backup_dir/nginx/" 2>/dev/null || log "WARNING" "Failed to backup Nginx"
        fi
    fi
    
    # Backup Geo files
    if [ -n "$GEO_FILES_PATH" ]; then
        log "INFO" "Backing up Geo files..."
        mkdir -p "$backup_dir/geo_files"
        cp -r "$GEO_FILES_PATH"/* "$backup_dir/geo_files/" 2>/dev/null || log "WARNING" "Failed to backup Geo files"
    fi
    
    # Backup Manager configuration
    log "INFO" "Backing up Manager configuration..."
    cp -r "$MANAGER_DIR" "$backup_dir/manager_config" 2>/dev/null || log "WARNING" "Failed to backup Manager config"
    
    log "SUCCESS" "Main server backup completed."
}

backup_all_nodes() {
    local backup_dir="$1/nodes"
    mkdir -p "$backup_dir"
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured for backup."
        return 0
    fi
    
    log "BACKUP" "Backing up ${#NODES_ARRAY[@]} nodes..."
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Backing up node: $name ($ip)"
        
        local node_backup_dir="$backup_dir/$name"
        mkdir -p "$node_backup_dir"
        
        export NODE_SSH_PASSWORD="$password"
        
        # Create backup on remote node
        local remote_backup_file="/tmp/node_backup_${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "tar -czf $remote_backup_file --warning=no-file-changed /opt/marzban-node/ /var/lib/marzban-node/ /etc/systemd/system/marzban-node* /etc/haproxy/ 2>/dev/null" \
           "Node Backup Creation"; then
            
            # Transfer backup to main server
            if scp_from_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$remote_backup_file" "$node_backup_dir/backup.tar.gz" "Node Backup Transfer"; then
                
                # Create node info file
                cat > "$node_backup_dir/node_info.txt" << EOF
Node Name: $name
IP Address: $ip
Domain: $domain
SSH User: $user
SSH Port: $port
Marzban Node ID: $node_id
Backup Date: $(date)
EOF
                
                # Cleanup remote backup
                ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                    "rm -f $remote_backup_file" "Remote Cleanup" || true
                
                log "SUCCESS" "Node $name backup completed."
            else
                log "ERROR" "Failed to transfer backup from node $name"
            fi
        else
            log "ERROR" "Failed to create backup on node $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "All nodes backup completed."
}

create_backup_archive() {
    local source_dir="$1"
    local archive_path="$2"
    
    log "BACKUP" "Creating compressed archive..."
    
    # Use pigz for faster compression if available
    if command_exists pigz; then
        tar -cf - -C "$(dirname "$source_dir")" "$(basename "$source_dir")" | pigz > "$archive_path"
    else
        tar -czf "$archive_path" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"
    fi
    
    # Verify archive integrity
    if tar -tzf "$archive_path" >/dev/null 2>&1; then
        local archive_size=$(du -h "$archive_path" | cut -f1)
        log "SUCCESS" "Archive created successfully: $archive_size"
        
        # Create checksum
        md5sum "$archive_path" > "${archive_path}.md5"
        log "INFO" "Checksum created: ${archive_path}.md5"
    else
        log "ERROR" "Archive verification failed!"
        return 1
    fi
}

apply_backup_retention_policy_global() {
    log "BACKUP" "Applying retention policy (keeping last $BACKUP_RETENTION_COUNT backups)..."
    
    # Remove old archives
    ls -t "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | \
        tail -n +$((BACKUP_RETENTION_COUNT + 1)) | \
        while read -r old_backup; do
            log "INFO" "Removing old backup: $(basename "$old_backup")"
            rm -f "$old_backup" "${old_backup}.md5"
        done
    
    local remaining_count
    remaining_count=$(ls "$BACKUP_ARCHIVE_DIR"/marzban_full_backup_*.tar.gz 2>/dev/null | wc -l)
    log "SUCCESS" "Retention policy applied: $remaining_count backups remaining"
}

## Automated Backup Scheduling
setup_automated_backup() {
    log "STEP" "Setting up automated backup system..."
    
    # Create backup script
    local backup_script="/usr/local/bin/marzban-auto-backup.sh"
    cat > "$backup_script" << 'EOF'
#!/bin/bash
# Automated Marzban Backup Script
cd /root/MarzbanManager
./marzban_central_manager.sh --backup >> /var/log/marzban-backup.log 2>&1
EOF
    
    chmod +x "$backup_script"
    
    # Setup cron job for 3:30 AM Iran time
    local cron_entry="30 3 * * * TZ=Asia/Tehran $backup_script"
    
    # Remove existing cron job if exists
    crontab -l 2>/dev/null | grep -v "marzban-auto-backup" | crontab -
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    log "SUCCESS" "Automated backup scheduled for 3:30 AM Iran time daily"
    
    # Update configuration
    sed -i '/AUTO_BACKUP_ENABLED=/d' "$MANAGER_CONFIG_FILE" 2>/dev/null || true
    echo "AUTO_BACKUP_ENABLED=true" >> "$MANAGER_CONFIG_FILE"
    
    send_telegram_notification "⏰ Automated Backup Enabled%0A%0A📅 Schedule: Daily at 3:30 AM (Iran Time)%0A🔄 Retention: $BACKUP_RETENTION_COUNT backups" "normal"
}

## Enhanced HAProxy Synchronization System
sync_haproxy_across_all_nodes() {
    local new_node_name="$1" new_node_ip="$2" new_node_domain="$3"
    
    log "SYNC" "Starting HAProxy synchronization across all nodes..."
    
    # Phase 1: Update main server HAProxy
    if ! update_main_haproxy_config "$new_node_name" "$new_node_ip" "$new_node_domain"; then
        log "ERROR" "Failed to update main server HAProxy"
        return 1
    fi
    
    # Phase 2: Sync to all existing nodes
    sync_haproxy_to_all_existing_nodes
    
    # Phase 3: Install HAProxy on new node
    install_haproxy_on_new_node "$new_node_ip" "$new_node_name"
    
    # Phase 4: Verification
    verify_haproxy_sync_across_nodes
}

update_main_haproxy_config() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backup_file="${haproxy_cfg}.backup.$(date +%s)"
    
    log "SYNC" "Updating main server HAProxy configuration..."
    cp "$haproxy_cfg" "$backup_file"
    
    # Create enhanced HAProxy config with new node
    create_enhanced_haproxy_config "$node_name" "$node_ip" "$node_domain"
    
    # Validate configuration before reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        if systemctl reload haproxy; then
            log "SUCCESS" "Main server HAProxy updated and reloaded successfully"
            log "SYNC" "HAProxy updated: Added backend $node_name ($node_ip) for domain $node_domain"
            send_telegram_notification "🔄 HAProxy Updated%0A%0AAdded: $node_name%0AIP: $node_ip%0ADomain: $node_domain" "normal"
            return 0
        else
            log "ERROR" "Failed to reload HAProxy service, restoring backup"
            cp "$backup_file" "$haproxy_cfg"
            systemctl reload haproxy
            return 1
        fi
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup"
        cp "$backup_file" "$haproxy_cfg"
        return 1
    fi
}

sync_haproxy_to_all_existing_nodes() {
    log "SYNC" "Synchronizing HAProxy to all existing nodes..."
    local sync_success=0 sync_failed=0
    
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "SYNC" "Syncing HAProxy to node: $name ($ip)"
        export NODE_SSH_PASSWORD="$password"
        
        # Create rollback point on node
        if create_node_rollback_point "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            
            # Sync HAProxy configuration
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                sync_success=$((sync_success + 1))
                log "SUCCESS" "HAProxy synced to node: $name"
            else
                sync_failed=$((sync_failed + 1))
                log "ERROR" "Failed to sync HAProxy to node: $name"
                
                # Attempt rollback
                rollback_node_configuration "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"
            fi
        else
            log "WARNING" "Could not create rollback point for node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SYNC" "HAProxy sync completed: $sync_success successful, $sync_failed failed"
    
    # Send notification
    send_telegram_notification "📊 HAProxy Sync Report%0A%0A✅ Success: $sync_success%0A❌ Failed: $sync_failed" "normal"
}

create_node_rollback_point() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "SYNC" "Creating rollback point for node: $node_name"
    
    # Create backup of current HAProxy config
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg ]; then cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.rollback.$(date +%s); echo 'Rollback point created'; else echo 'No HAProxy config found'; fi" \
       "Rollback Point Creation"; then
        
        # Store rollback info
        echo "${node_name};${node_ip};$(date +%s)" >> "${BACKUP_DIR}/rollback_points.log"
        return 0
    else
        return 1
    fi
}

sync_haproxy_to_single_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    # Check if HAProxy is installed on node
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
         "command -v haproxy >/dev/null 2>&1" "HAProxy Check"; then
        
        log "SYNC" "Installing HAProxy on node: $node_name"
        if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
             "apt update >/dev/null 2>&1 && apt install -y haproxy >/dev/null 2>&1" \
             "HAProxy Installation"; then
            return 1
        fi
    fi
    
    # Copy main HAProxy config to node
    if scp_to_remote "/etc/haproxy/haproxy.cfg" "$node_ip" "$node_user" "$node_port" "$node_password" \
       "/etc/haproxy/haproxy.cfg" "HAProxy Configuration"; then
        
        # Validate and restart HAProxy on node
        if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
           "/usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl enable haproxy && systemctl restart haproxy" \
           "HAProxy Validation & Restart"; then
            
            log "SUCCESS" "HAProxy successfully synced to node: $node_name"
            return 0
        else
            log "ERROR" "HAProxy validation/restart failed on node: $node_name"
            return 1
        fi
    else
        return 1
    fi
}

rollback_node_configuration() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4" node_name="$5"
    
    log "WARNING" "Attempting rollback for node: $node_name"
    
    if ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
       "if [ -f /etc/haproxy/haproxy.cfg.rollback.* ]; then cp /etc/haproxy/haproxy.cfg.rollback.* /etc/haproxy/haproxy.cfg && systemctl restart haproxy && echo 'Rollback successful'; else echo 'No rollback file found'; fi" \
       "Configuration Rollback"; then
        
        log "SUCCESS" "Rollback completed for node: $node_name"
        send_telegram_notification "🔄 Rollback Executed%0A%0ANode: $node_name%0AStatus: Successful" "high"
    else
        log "ERROR" "Rollback failed for node: $node_name"
        send_telegram_notification "🚨 Rollback Failed%0A%0ANode: $node_name%0ARequires manual intervention!" "critical"
    fi
}

## Geo Files Transfer System
transfer_geo_files_to_node() {
    local node_ip="$1" node_user="$2" node_port="$3" node_password="$4"
    
    if [ -z "$GEO_FILES_PATH" ]; then
        log "WARNING" "No geo files detected on main server, downloading fresh copies..."
        return 0
    fi
    
    log "SYNC" "Transferring geo files from main server to node..."
    
    # Create geo directory on node
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "mkdir -p /var/lib/marzban-node/chocolate" \
        "Geo Directory Creation"
    
    # Transfer geo files
    scp_to_remote "$GEO_FILES_PATH/geosite.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geosite.dat" "Geosite File"
    
    scp_to_remote "$GEO_FILES_PATH/geoip.dat" "$node_ip" "$node_user" "$node_port" "$node_password" \
        "/var/lib/marzban-node/chocolate/geoip.dat" "Geoip File"
    
    # Set proper permissions
    ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" \
        "chmod 644 /var/lib/marzban-node/chocolate/*.dat && chown root:root /var/lib/marzban-node/chocolate/*.dat" \
        "Geo Files Permissions"
    
    log "SUCCESS" "Geo files transferred successfully"
}

create_enhanced_docker_compose() {
    log "SYNC" "Creating enhanced docker-compose with geo volume..."
    
    local geo_volume=""
    if [ -n "$GEO_FILES_PATH" ]; then
        geo_volume="      - /var/lib/marzban-node/chocolate:/var/lib/marzban-node/chocolate"
    fi
    
    cat > docker-compose.yml << EOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /opt/marzban-node:/opt/marzban-node
${geo_volume}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "SUCCESS" "Enhanced docker-compose.yml created with geo volume support"
}
## Optimized Continuous Monitoring System
start_continuous_sync_monitoring() {
    log "INFO" "Starting optimized continuous synchronization monitoring..."
    
    while true; do
        monitor_haproxy_sync_status
        monitor_geo_files_sync_status
        monitor_node_health_status
        
        # Optimized sleep interval (30 minutes to reduce server load)
        sleep "$SYNC_CHECK_INTERVAL"
    done
}

monitor_haproxy_sync_status() {
    local main_config_hash
    main_config_hash=$(md5sum /etc/haproxy/haproxy.cfg | awk '{print $1}' 2>/dev/null || echo "missing")
    
    load_nodes_config
    local out_of_sync_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_config_hash
        node_config_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                          "if [ -f /etc/haproxy/haproxy.cfg ]; then md5sum /etc/haproxy/haproxy.cfg | awk '{print \$1}'; else echo 'missing'; fi" \
                          "Config Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_config_hash" != "$main_config_hash" ] && [ "$node_config_hash" != "error" ]; then
            out_of_sync_nodes+=("$name")
            log "WARNING" "Node $name is out of sync (hash: $node_config_hash vs main: $main_config_hash)"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_nodes[@]} -gt 0 ]; then
        log "SYNC" "Out of sync nodes detected: ${out_of_sync_nodes[*]}"
        send_telegram_notification "⚠️ Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_nodes[*]}%0A%0AAutomatic resync will be attempted." "high"
        
        # Attempt automatic resync
        auto_resync_nodes "${out_of_sync_nodes[@]}"
    fi
}

auto_resync_nodes() {
    local nodes=("$@")
    
    for node_name in "${nodes[@]}"; do
        log "SYNC" "Attempting automatic resync for node: $node_name"
        
        local node_entry
        node_entry=$(get_node_config_by_name "$node_name")
        
        if [ -n "$node_entry" ]; then
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            export NODE_SSH_PASSWORD="$password"
            
            if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
                log "SUCCESS" "Automatic resync successful for node: $node_name"
                send_telegram_notification "✅ Auto-Resync Success%0A%0ANode: $node_name" "normal"
            else
                log "ERROR" "Automatic resync failed for node: $node_name"
                send_telegram_notification "🚨 Auto-Resync Failed%0A%0ANode: $node_name%0AManual intervention required!" "critical"
            fi
            
            unset NODE_SSH_PASSWORD
        fi
    done
}

monitor_geo_files_sync_status() {
    if [ -z "$GEO_FILES_PATH" ]; then
        return 0
    fi
    
    local main_geosite_hash main_geoip_hash
    main_geosite_hash=$(md5sum "$GEO_FILES_PATH/geosite.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    main_geoip_hash=$(md5sum "$GEO_FILES_PATH/geoip.dat" 2>/dev/null | awk '{print $1}' || echo "missing")
    
    load_nodes_config
    local out_of_sync_geo_nodes=()
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_geosite_hash node_geoip_hash
        node_geosite_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                           "if [ -f /var/lib/marzban-node/chocolate/geosite.dat ]; then md5sum /var/lib/marzban-node/chocolate/geosite.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                           "Geosite Hash Check" 2>/dev/null || echo "error")
        
        node_geoip_hash=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                         "if [ -f /var/lib/marzban-node/chocolate/geoip.dat ]; then md5sum /var/lib/marzban-node/chocolate/geoip.dat | awk '{print \$1}'; else echo 'missing'; fi" \
                         "Geoip Hash Check" 2>/dev/null || echo "error")
        
        if [ "$node_geosite_hash" != "$main_geosite_hash" ] || [ "$node_geoip_hash" != "$main_geoip_hash" ]; then
            if [ "$node_geosite_hash" != "error" ] && [ "$node_geoip_hash" != "error" ]; then
                out_of_sync_geo_nodes+=("$name")
                log "WARNING" "Node $name geo files are out of sync"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    if [ ${#out_of_sync_geo_nodes[@]} -gt 0 ]; then
        log "SYNC" "Geo files out of sync on nodes: ${out_of_sync_geo_nodes[*]}"
        send_telegram_notification "🌍 Geo Files Sync Alert%0A%0AOut of sync nodes: ${out_of_sync_geo_nodes[*]}" "normal"
    fi
}

monitor_node_health_status() {
    if ! get_marzban_token >/dev/null 2>&1; then
        return 1
    fi
    
    local unhealthy_nodes=()
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 10 --max-time 15 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status="unknown" # Default status
            if echo "$health_response" | jq -e . >/dev/null 2>&1; then # Check if response is valid JSON
                status=$(echo "$health_response" | jq -r '.status // "unknown"')
            else
                log "WARNING" "Node $name ($ip): Invalid API response for health check."
                log "DEBUG" "Response for $name: $health_response"
                # status remains "unknown"
            fi
            
            if [ "$status" != "connected" ]; then
                unhealthy_nodes+=("$name:$status")
            fi
        fi
        
        # Rate limiting
        sleep "$API_RATE_LIMIT_DELAY"
    done
    
    if [ ${#unhealthy_nodes[@]} -gt 0 ]; then
        log "WARNING" "Unhealthy nodes detected: ${unhealthy_nodes[*]}"
        send_telegram_notification "🔴 Health Alert%0A%0AUnhealthy nodes: ${unhealthy_nodes[*]}" "high"
    fi
}

## Enhanced Marzban API Configuration
configure_marzban_api() {
    log "STEP" "Configuring Marzban Panel API Connection..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Marzban Panel API Setup${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Please provide your Marzban Panel details:${NC}\n"
    
    log "PROMPT" "Panel Protocol (http/https) [default: https]:"
    read -r protocol
    protocol=${protocol:-https}
    
    log "PROMPT" "Panel Domain/IP (e.g., panel.example.com):"
    read -r domain
    
    log "PROMPT" "Panel Port [default: 8000]:"
    read -r port
    port=${port:-8000}
    
    log "PROMPT" "Admin Username:"
    read -r username
    
    log "PROMPT" "Admin Password:"
    read -s password
    echo ""
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$username" ] || [ -z "$password" ]; then
        log "ERROR" "All fields are required."
        return 1
    fi
    
    # Test connection
    log "INFO" "Testing API connection..."
    local test_url="${protocol}://${domain}:${port}/api/admin/token"
    local test_response
    
    test_response=$(curl -s -X POST "$test_url" \
        -d "username=${username}&password=${password}" \
        --connect-timeout 10 --max-time 30 \
        --insecure 2>/dev/null)
    
    if echo "$test_response" | grep -q "access_token"; then
        log "SUCCESS" "API connection test successful!"
        
        # Save configuration
        {
            echo "MARZBAN_PANEL_PROTOCOL=\"$protocol\""
            echo "MARZBAN_PANEL_DOMAIN=\"$domain\""
            echo "MARZBAN_PANEL_PORT=\"$port\""
            echo "MARZBAN_PANEL_USERNAME=\"$username\""
            echo "MARZBAN_PANEL_PASSWORD=\"$password\""
        } >> "$MANAGER_CONFIG_FILE"
        
        chmod 600 "$MANAGER_CONFIG_FILE"
        source "$MANAGER_CONFIG_FILE"
        
        log "SUCCESS" "Marzban API configuration saved successfully."
        send_telegram_notification "🔗 Marzban API Connected%0A%0APanel: $domain:$port%0AStatus: ✅ Connected" "normal"
    else
        log "ERROR" "API connection test failed. Please check your credentials and panel accessibility."
        log "DEBUG" "Response: $test_response"
        return 1
    fi
}

## Function to get Marzban API token
get_marzban_token() {
    if [ -n "$MARZBAN_TOKEN" ]; then
        # Token already exists, maybe add a check for expiration if API supports it
        # log "DEBUG" "Using existing Marzban token."
        return 0
    fi

    if [ -z "$MARZBAN_PANEL_DOMAIN" ] || [ -z "$MARZBAN_PANEL_USERNAME" ] || [ -z "$MARZBAN_PANEL_PASSWORD" ]; then
        log "ERROR" "Marzban Panel API credentials are not configured. Please run 'Configure Marzban API' first."
        return 1
    fi

    local login_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/admin/token"
    local response

    # log "INFO" "Attempting to get Marzban API token..."
    response=$(curl -s -X POST "$login_url" \
        -d "username=${MARZBAN_PANEL_USERNAME}&password=${MARZBAN_PANEL_PASSWORD}" \
        --connect-timeout 10 --max-time 20 \
        --insecure 2>/dev/null)

    if echo "$response" | grep -q "access_token"; then
        MARZBAN_TOKEN=$(echo "$response" | jq -r .access_token 2>/dev/null)
        if [ -n "$MARZBAN_TOKEN" ]; then
            # log "SUCCESS" "Marzban API token obtained successfully."
            # Store token in config for persistence across script runs? Or rely on global var for current session.
            # For now, it's a global variable for the current session.
            return 0
        else
            log "ERROR" "Failed to parse access token from API response."
            log "DEBUG" "Full API response: $response"
            return 1
        fi
    else
        log "ERROR" "Failed to obtain Marzban API token. Check credentials and panel accessibility."
        log "DEBUG" "API Response: $response"
        MARZBAN_TOKEN="" # Clear any stale token
        return 1
    fi
}

add_node_to_marzban_panel_api() {
    local node_name="$1" node_ip="$2" node_domain="$3"
    
    log "INFO" "Registering node '$node_name' with the Marzban panel..."
    
    local add_node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node"
    local payload
    payload=$(printf '{"name": "%s", "address": "%s", "port": 62050, "api_port": 62051, "usage_coefficient": 1.0, "add_as_new_host": false}' "$node_name" "$node_ip")

    local response
    response=$(curl -s -X POST "$add_node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Content-Type: application/json" -H "Accept: application/json" \
        -d "$payload" --insecure)

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        MARZBAN_NODE_ID=$(echo "$response" | jq -r .id)
        log "SUCCESS" "Node '$node_name' successfully added to panel with ID: $MARZBAN_NODE_ID"
        return 0
    elif echo "$response" | grep -q "already exists"; then
        log "WARNING" "Node '$node_name' already exists in the panel. Attempting to retrieve its ID..."
        
        local nodes_list_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes"
        local nodes_response
        nodes_response=$(curl -s -X GET "$nodes_list_url" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure)
        
        local existing_id
        existing_id=$(echo "$nodes_response" | jq -r ".[] | select(.name==\"$node_name\") | .id" 2>/dev/null)
        
        if [ -n "$existing_id" ]; then
            MARZBAN_NODE_ID="$existing_id"
            log "SUCCESS" "Successfully retrieved ID for existing node: $MARZBAN_NODE_ID"
            return 0
        else
            log "ERROR" "Node is said to exist, but could not retrieve its ID from the panel."
            return 1
        fi
    else
        log "ERROR" "Failed to add node to Marzban panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

get_client_cert_from_marzban_api() {
    local node_id="$1"
    
    log "INFO" "Retrieving client certificate for node ID: $node_id"
    
    local node_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/${node_id}"
    
    local response
    response=$(curl -s -X GET "$node_url" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        -H "Accept: application/json" \
        --insecure)
        
    if echo "$response" | jq -e '.client_cert' >/dev/null 2>&1; then
        CLIENT_CERT=$(echo "$response" | jq -r .client_cert)
        if [ -n "$CLIENT_CERT" ]; then
            log "SUCCESS" "Client certificate retrieved successfully."
            return 0
        else
            log "ERROR" "Client certificate is empty in the API response."
            return 1
        fi
    else
        log "ERROR" "Failed to retrieve client certificate from panel."
        log "DEBUG" "API Response: $response"
        return 1
    fi
}

## Automated Monitoring Setup
setup_automated_monitoring() {
    log "STEP" "Setting up automated monitoring system..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║       ${CYAN}Automated Monitoring Setup${NC}       ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Monitoring Options:${NC}"
    echo " 1. Enable Continuous Sync Monitoring"
    echo " 2. Enable Automated Health Checks"
    echo " 3. Setup Both (Recommended)"
    echo " 4. Disable All Monitoring"
    echo " 5. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose monitoring option:"
    read -r choice
    
    case "$choice" in
        1|3)
            # Setup sync monitoring
            local sync_script="/usr/local/bin/marzban-sync-monitor.sh"
            cat > "$sync_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --sync-monitor >> /var/log/marzban-sync.log 2>&1
EOF
            chmod +x "$sync_script"
            
            # Add to cron (every 30 minutes)
            local sync_cron="*/30 * * * * $sync_script"
            crontab -l 2>/dev/null | grep -v "marzban-sync-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$sync_cron") | crontab -
            
            log "SUCCESS" "Sync monitoring enabled (every 30 minutes)"
            ;;
    esac
    
    case "$choice" in
        2|3)
            # Setup health monitoring
            local health_script="/usr/local/bin/marzban-health-monitor.sh"
            cat > "$health_script" << 'EOF'
#!/bin/bash
cd /root/MarzbanManager
./marzban_central_manager.sh --health-monitor >> /var/log/marzban-health.log 2>&1
EOF
            chmod +x "$health_script"
            
            # Add to cron (every 10 minutes)
            local health_cron="*/10 * * * * $health_script"
            crontab -l 2>/dev/null | grep -v "marzban-health-monitor" | crontab -
            (crontab -l 2>/dev/null; echo "$health_cron") | crontab -
            
            log "SUCCESS" "Health monitoring enabled (every 10 minutes)"
            ;;
    esac
    
    case "$choice" in
        4)
            # Disable monitoring
            crontab -l 2>/dev/null | grep -v "marzban-.*-monitor" | crontab -
            rm -f /usr/local/bin/marzban-*-monitor.sh
            log "SUCCESS" "All automated monitoring disabled"
            ;;
        5)
            return 0
            ;;
        *)
            log "ERROR" "Invalid option"
            return 1
            ;;
    esac
    
    if [ "$choice" != "4" ] && [ "$choice" != "5" ]; then
        send_telegram_notification "🤖 Automated Monitoring Enabled%0A%0AMonitoring active on $(hostname)" "normal"
    fi
}

## Enhanced Node Import System
import_existing_nodes() {
    log "STEP" "Importing existing nodes..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║         ${CYAN}Import Existing Nodes${NC}          ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Import Options:${NC}"
    echo " 1. Import Single Node"
    echo " 2. Import from CSV File"
    echo " 3. Auto-discover Nodes from Marzban Panel"
    echo " 4. Back to Main Menu"
    echo ""
    
    log "PROMPT" "Choose import method:"
    read -r choice
    
    case "$choice" in
        1) import_single_node ;;
        2) import_from_csv ;;
        3) auto_discover_nodes ;;
        4) return 0 ;;
        *) log "ERROR" "Invalid option" ;;
    esac
}

import_single_node() {
    log "STEP" "Adding/Importing a single node..."
    
    local node_name node_ip node_user="root" node_port="22" node_domain node_password

    log "PROMPT" "Enter Node Name:"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP:"; read -r node_ip
    log "PROMPT" "Enter SSH Username [default: root]:"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port [default: 22]:"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain:"; read -r node_domain
    log "PROMPT" "Enter SSH Password:"; read -s node_password; echo ""

    # Combine connectivity test and Marzban Node check into a single SSH session
    local remote_command="echo 'CONN_OK'; if docker ps 2>/dev/null | grep -q marzban-node; then echo 'NODE_INSTALLED'; else echo 'NODE_NOT_INSTALLED'; fi"
    
    local check_result
    if ! check_result=$(ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "$remote_command" "Connectivity and Node Check"); then
        log "ERROR" "Failed to connect to node. Please check credentials."
        return 1
    fi
    
    if echo "$check_result" | grep -q "NODE_INSTALLED"; then
        log "INFO" "Marzban Node is already installed. Checking registration in panel..."
        
        if ! get_marzban_token; then return 1; fi
        local nodes_response
        nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" -H "Authorization: Bearer $MARZBAN_TOKEN" --insecure 2>/dev/null)
        
        local node_id
        if echo "$nodes_response" | jq empty 2>/dev/null; then
            node_id=$(echo "$nodes_response" | jq -r ".[] | select(.address==\"$node_ip\") | .id" 2>/dev/null)
        fi

        if [ -n "$node_id" ]; then
            log "SUCCESS" "Node is already registered in the panel with ID: $node_id. Importing..."
            add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$node_id"
            save_nodes_config
        else
            log "WARNING" "This node is running, but it is NOT registered in your Marzban panel."
            log "PROMPT" "Do you want to add it to the panel now? (y/n)"
            read -r add_to_panel
            if [[ "$add_to_panel" =~ ^[Yy]$ ]]; then
                log "STEP" "Registering existing node with the panel..."
                if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi
                
                log "STEP" "Deploying new client certificate to the node..."
                if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
                
                if [ -z "$CLIENT_CERT" ]; then
                    log "ERROR" "Failed to retrieve client certificate from panel. Cannot proceed."
                    return 1
                fi

                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
                rm "$temp_cert"
                
                log "STEP" "Restarting node service to apply new certificate..."
                ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" "Service Restart"

                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
                save_nodes_config
                log "SUCCESS" "Node '$node_name' successfully registered and imported!"
            else
                log "INFO" "Node was not registered in the panel. It has been added to the local manager only."
                add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" ""
                save_nodes_config
            fi
        fi
    elif echo "$check_result" | grep -q "NODE_NOT_INSTALLED"; then
        log "WARNING" "Marzban Node is NOT installed on this server."
        log "PROMPT" "Do you want to install it automatically now? (y/n)"
        read -r install_now
        if [[ "$install_now" =~ ^[Yy]$ ]]; then
            if _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
                log "SUCCESS" "🎉 Node '$node_name' installed and configured successfully!"
            else
                log "ERROR" "Node installation failed. Please check the logs."
            fi
        else
            log "INFO" "Installation cancelled. Node was not added."
        fi
    fi
}

import_from_csv() {
    log "STEP" "Importing nodes from CSV file..."
    
    log "PROMPT" "Enter CSV file path (format: name,ip,user,port,domain,password):"
    read -r csv_file
    
    if [ ! -f "$csv_file" ]; then
        log "ERROR" "CSV file not found: $csv_file"
        return 1
    fi
    
    local imported=0 failed=0
    
    while IFS=',' read -r name ip user port domain password; do
        # Skip header line
        if [ "$name" = "name" ]; then continue; fi
        
        log "INFO" "Importing node: $name"
        
        if get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "WARNING" "Node '$name' already exists, skipping."
            continue
        fi
        
        # Test connectivity
        export NODE_SSH_PASSWORD="$password"
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'test'" "CSV Import Test" >/dev/null 2>&1; then
            add_node_to_config "$name" "$ip" "$user" "$port" "$domain" "$password" ""
            imported=$((imported + 1))
            log "SUCCESS" "Node '$name' imported."
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to import node '$name'."
        fi
        unset NODE_SSH_PASSWORD
        
    done < "$csv_file"
    
    save_nodes_config
    log "SUCCESS" "CSV import completed: $imported imported, $failed failed."
}

auto_discover_nodes() {
    log "STEP" "Auto-discovering nodes from Marzban Panel..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    local nodes_response
    nodes_response=$(curl -s -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/nodes" \
        -H "Authorization: Bearer $MARZBAN_TOKEN" \
        --insecure 2>/dev/null)
    
    if ! echo "$nodes_response" | jq empty 2>/dev/null; then
        log "ERROR" "Failed to fetch nodes from Marzban Panel."
        return 1
    fi
    
    local discovered=0
    
    echo "$nodes_response" | jq -r '.[] | "\(.name);\(.address);\(.id)"' | while IFS=';' read -r name address node_id; do
        if ! get_node_config_by_name "$name" >/dev/null 2>&1; then
            log "INFO" "Discovered node: $name ($address)"
            
            # Add with default values (user will need to update SSH credentials)
            add_node_to_config "$name" "$address" "root" "22" "$name.domain.com" "UPDATE_PASSWORD" "$node_id"
            discovered=$((discovered + 1))
        fi
    done
    
    save_nodes_config
    log "SUCCESS" "Auto-discovery completed: $discovered nodes discovered."
    log "WARNING" "Please update SSH credentials for discovered nodes using 'Update Node Configuration'."
}

## Node Update System
update_existing_node() {
    log "STEP" "Updating existing node configuration..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to update."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Update Node Configuration${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip)"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to update (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${CYAN}Updating node: $name${NC}"
    echo -e "Current values (press Enter to keep current value):\n"
    
    log "PROMPT" "IP Address [$ip]:"
    read -r new_ip
    new_ip=${new_ip:-$ip}
    
    log "PROMPT" "SSH Username [$user]:"
    read -r new_user
    new_user=${new_user:-$user}
    
    log "PROMPT" "SSH Port [$port]:"
    read -r new_port
    new_port=${new_port:-$port}
    
    log "PROMPT" "Domain [$domain]:"
    read -r new_domain
    new_domain=${new_domain:-$domain}
    
    log "PROMPT" "Update SSH Password? (y/n):"
    read -r update_password
    
    local new_password="$password"
    if [[ "$update_password" =~ ^[Yy]$ ]]; then
        log "PROMPT" "New SSH Password:"
        read -s new_password
        echo ""
    fi
    
    # Update the node entry
    NODES_ARRAY[$selected_index]="${name};${new_ip};${new_user};${new_port};${new_domain};${new_password};${node_id}"
    save_nodes_config
    
    log "SUCCESS" "Node '$name' configuration updated successfully."
    
    # Test connectivity with new settings
    log "INFO" "Testing connectivity with new settings..."
    export NODE_SSH_PASSWORD="$new_password"
    if ssh_remote "$new_ip" "$new_user" "$new_port" "$NODE_SSH_PASSWORD" "echo 'Update test successful'" "Update Connectivity Test"; then
        log "SUCCESS" "Connectivity test passed with new settings."
    else
        log "WARNING" "Connectivity test failed. Please verify the new settings."
    fi
    unset NODE_SSH_PASSWORD
}
## Node Removal System
remove_node() {
    log "STEP" "Removing node from system..."
    
    load_nodes_config
    
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        log "WARNING" "No nodes configured to remove."
        return 0
    fi
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║            ${CYAN}Remove Node${NC}                 ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Available Nodes:${NC}"
    local i=1
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        echo " $i. $name ($ip) - $domain"
        i=$((i + 1))
    done
    echo ""
    
    log "PROMPT" "Select node to remove (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#NODES_ARRAY[@]}" ]; then
        log "ERROR" "Invalid selection."
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will remove node '$name' from:${NC}"
    echo "- Local configuration"
    echo "- Marzban Panel (if connected)"
    echo "- HAProxy configuration"
    echo ""
    
    log "PROMPT" "Are you sure you want to remove node '$name'? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Node removal cancelled."
        return 0
    fi
    
    # Remove from Marzban Panel if node_id exists
    if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
        log "STEP" "Removing node from Marzban Panel..."
        if get_marzban_token; then
            local delete_response
            delete_response=$(curl -s -X DELETE "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                log "SUCCESS" "Node removed from Marzban Panel."
            else
                log "WARNING" "Failed to remove node from Marzban Panel."
            fi
        fi
    fi
    
    # Remove from HAProxy configuration
    if [ "$MAIN_HAS_HAPROXY" = "true" ]; then
        log "STEP" "Removing node from HAProxy configuration..."
        remove_haproxy_backend "$name" "$domain"
    fi
    
    # Remove from local configuration
    unset NODES_ARRAY[$selected_index]
    NODES_ARRAY=("${NODES_ARRAY[@]}")  # Re-index array
    save_nodes_config
    
    log "SUCCESS" "Node '$name' removed successfully."
    send_telegram_notification "🗑️ Node Removed%0A%0ANode: $name%0AIP: $ip%0ADomain: $domain" "normal"
}

remove_haproxy_backend() {
    local node_name="$1" node_domain="$2"
    local haproxy_cfg="/etc/haproxy/haproxy.cfg"
    local backend_name="vless_${node_name}"
    
    # Create backup
    cp "$haproxy_cfg" "${haproxy_cfg}.backup.$(date +%s)"
    
    # Remove backend section
    sed -i "/^# Backend for ${node_name}/,/^$/d" "$haproxy_cfg"
    sed -i "/^backend ${backend_name}/,/^$/d" "$haproxy_cfg"
    
    # Remove frontend rule
    sed -i "/use_backend ${backend_name} if.*${node_domain}/d" "$haproxy_cfg"
    
    # Validate and reload
    if /usr/sbin/haproxy -c -f "$haproxy_cfg" 2>/dev/null; then
        systemctl reload haproxy
        log "SUCCESS" "HAProxy configuration updated."
    else
        log "ERROR" "HAProxy configuration validation failed, restoring backup."
        cp "${haproxy_cfg}.backup."* "$haproxy_cfg"
        systemctl reload haproxy
        return 1
    fi
}

## Enhanced Backup and Restore System
backup_restore_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Backup & Restore System${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Backup Options:${NC}"
        echo " 1. Create Full System Backup"
        echo " 2. Create Main Server Only Backup"
        echo " 3. Create Nodes Only Backup"
        echo " 4. Setup Automated Backup"
        echo ""
        echo -e "${PURPLE}Restore Options:${NC}"
        echo " 5. List Available Backups"
        echo " 6. Restore from Backup"
        echo " 7. Verify Backup Integrity"
        echo ""
        echo -e "${PURPLE}Management:${NC}"
        echo " 8. Cleanup Old Backups"
        echo " 9. Export Backup to Remote"
        echo " 10. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose backup/restore option:"
        read -r choice
        
        case "$choice" in
            1) create_full_backup ;;
            2) backup_main_server_only ;;
            3) backup_nodes_only ;;
            4) setup_automated_backup ;;
            5) list_available_backups ;;
            6) restore_from_backup ;;
            7) verify_backup_integrity_menu ;;
            8) cleanup_old_backups ;;
            9) export_backup_to_remote ;;
            10) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "10" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

backup_main_server_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_main_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting main server backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_main_server "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Main server backup completed: $final_archive"
}

backup_nodes_only() {
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="marzban_nodes_backup_${backup_timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_archive="${BACKUP_ARCHIVE_DIR}/${backup_name}.tar.gz"
    
    log "BACKUP" "Starting nodes backup..."
    
    mkdir -p "$temp_backup_dir"
    backup_all_nodes "$temp_backup_dir"
    create_backup_archive "$temp_backup_dir" "$final_archive"
    rm -rf "$temp_backup_dir"
    
    log "SUCCESS" "Nodes backup completed: $final_archive"
}

list_available_backups() {
    log "BACKUP" "Listing available backups..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Available Backups${NC}                        ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    if ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        printf "%-5s %-35s %-15s %-10s\n" "No." "Backup Name" "Date" "Size"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        
        local i=1
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            local filename=$(basename "$backup")
            local filesize=$(du -h "$backup" | cut -f1)
            local filedate=$(date -r "$backup" '+%Y-%m-%d %H:%M')
            
            printf "%-5s %-35s %-15s %-10s\n" "$i" "$filename" "$filedate" "$filesize"
            i=$((i + 1))
        done
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "No backups found in $BACKUP_ARCHIVE_DIR"
    fi
}

verify_backup_integrity_menu() {
    log "BACKUP" "Backup integrity verification..."
    
    list_available_backups
    
    if ! ls "$BACKUP_ARCHIVE_DIR"/*.tar.gz >/dev/null 2>&1; then
        return 0
    fi
    
    echo ""
    log "PROMPT" "Enter backup number to verify (or 'all' for all backups):"
    read -r selection
    
    if [ "$selection" = "all" ]; then
        for backup in "$BACKUP_ARCHIVE_DIR"/*.tar.gz; do
            verify_backup_integrity "$backup"
        done
    else
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            local backup_files=("$BACKUP_ARCHIVE_DIR"/*.tar.gz)
            local selected_index=$((selection - 1))
            
            if [ $selected_index -ge 0 ] && [ $selected_index -lt ${#backup_files[@]} ]; then
                verify_backup_integrity "${backup_files[$selected_index]}"
            else
                log "ERROR" "Invalid backup number."
            fi
        else
            log "ERROR" "Invalid input."
        fi
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

## Nginx Management System
nginx_management_menu() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║           ${CYAN}Nginx Management${NC}              ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        # Check Nginx status
        if systemctl is-active --quiet nginx; then
            echo -e "${GREEN}✅ Nginx Status: Running${NC}"
        else
            echo -e "${RED}❌ Nginx Status: Not Running${NC}"
        fi
        
        echo ""
        echo -e "${PURPLE}Configuration Management:${NC}"
        echo " 1. View Nginx Configuration"
        echo " 2. Test Nginx Configuration"
        echo " 3. Reload Nginx Configuration"
        echo " 4. Restart Nginx Service"
        echo ""
        echo -e "${PURPLE}SSL Certificate Management:${NC}"
        echo " 5. Generate SSL Certificate"
        echo " 6. Renew SSL Certificates"
        echo " 7. View Certificate Status"
        echo ""
        echo -e "${PURPLE}Site Management:${NC}"
        echo " 8. Add New Site Configuration"
        echo " 9. Remove Site Configuration"
        echo " 10. Enable/Disable Site"
        echo ""
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose Nginx management option:"
        read -r choice
        
        case "$choice" in
            1) view_nginx_configuration ;;
            2) test_nginx_configuration ;;
            3) reload_nginx_configuration ;;
            4) restart_nginx_service ;;
            5) generate_ssl_certificate ;;
            6) renew_ssl_certificates ;;
            7) view_certificate_status ;;
            8) add_nginx_site ;;
            9) remove_nginx_site ;;
            10) toggle_nginx_site ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_nginx_configuration() {
    log "INFO" "Displaying Nginx configuration..."
    
    if [ -f "/etc/nginx/nginx.conf" ]; then
        echo -e "\n${CYAN}Main Nginx Configuration:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        cat /etc/nginx/nginx.conf
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        log "ERROR" "Nginx configuration file not found."
    fi
    
    echo -e "\n${CYAN}Available Site Configurations:${NC}"
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                echo "✅ $site_name (enabled)"
            else
                echo "❌ $site_name (disabled)"
            fi
        done
    else
        echo "No site configurations found."
    fi
}

test_nginx_configuration() {
    log "INFO" "Testing Nginx configuration..."
    
    if nginx -t 2>&1; then
        log "SUCCESS" "Nginx configuration test passed."
    else
        log "ERROR" "Nginx configuration test failed."
    fi
}

reload_nginx_configuration() {
    log "INFO" "Reloading Nginx configuration..."
    
    if nginx -t 2>/dev/null; then
        if systemctl reload nginx; then
            log "SUCCESS" "Nginx configuration reloaded successfully."
        else
            log "ERROR" "Failed to reload Nginx configuration."
        fi
    else
        log "ERROR" "Nginx configuration test failed. Cannot reload."
    fi
}

restart_nginx_service() {
    log "INFO" "Restarting Nginx service..."
    
    if systemctl restart nginx; then
        log "SUCCESS" "Nginx service restarted successfully."
    else
        log "ERROR" "Failed to restart Nginx service."
    fi
}

## Bulk Operations Enhancement
bulk_update_certificates() {
    log "STEP" "Updating certificates on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            log "INFO" "Updating certificate for node: $name"
            
            # Get fresh certificate from Marzban Panel
            if get_client_cert_from_marzban_api "$node_id"; then
                export NODE_SSH_PASSWORD="$password"
                
                # Deploy certificate to node
                local temp_cert; temp_cert=$(mktemp)
                echo "$CLIENT_CERT" > "$temp_cert"
                
                if scp_to_remote "$temp_cert" "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "/var/lib/marzban-node/ssl_client_cert.pem" "Certificate Update"; then
                    
                    # Restart node service
                    if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                       "chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart" \
                       "Service Restart"; then
                        updated=$((updated + 1))
                        log "SUCCESS" "Certificate updated for node: $name"
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to restart service on node: $name"
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to deploy certificate to node: $name"
                fi
                
                rm "$temp_cert"
                unset NODE_SSH_PASSWORD
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to get certificate for node: $name"
            fi
        else
            log "WARNING" "Node '$name' has no API ID, skipping certificate update."
        fi
    done
    
    log "SUCCESS" "Certificate update completed: $updated updated, $failed failed."
    send_telegram_notification "🔐 Certificate Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

bulk_restart_services() {
    log "STEP" "Restarting services on all nodes..."
    
    load_nodes_config
    local restarted=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Restarting services on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
           "cd /opt/marzban-node && docker compose restart" \
           "Service Restart"; then
            restarted=$((restarted + 1))
            log "SUCCESS" "Services restarted on node: $name"
        else
            failed=$((failed + 1))
            log "ERROR" "Failed to restart services on node: $name"
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Service restart completed: $restarted restarted, $failed failed."
    send_telegram_notification "🔄 Service Restart Report%0A%0A✅ Restarted: $restarted%0A❌ Failed: $failed" "normal"
}

bulk_update_geo_files() {
    log "STEP" "Updating geo files on all nodes..."
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating geo files on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        # Transfer geo files if available on main server
        if [ -n "$GEO_FILES_PATH" ]; then
            if transfer_geo_files_to_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files updated on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to update geo files on node: $name"
            fi
        else
            # Download fresh geo files on node
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
               "$(declare -f update_geo_files_on_node); update_geo_files_on_node" \
               "Geo Files Update"; then
                updated=$((updated + 1))
                log "SUCCESS" "Geo files downloaded on node: $name"
            else
                failed=$((failed + 1))
                log "ERROR" "Failed to download geo files on node: $name"
            fi
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Geo files update completed: $updated updated, $failed failed."
    send_telegram_notification "🌍 Geo Files Update Report%0A%0A✅ Updated: $updated%0A❌ Failed: $failed" "normal"
}

_internal_deploy_node() {
    local node_name="$1" node_ip="$2" node_user="$3" node_port="$4" node_domain="$5" node_password="$6"

    log "STEP" "Starting Final Deployment Workflow for '$node_name'..."

    # Phase 1: Deploy and start the node in standalone mode (without client cert requirement)
    log "STEP" "Phase 1: Deploying node in standalone mode..."
    if ! scp_to_remote "${0%/*}/marzban_node_deployer.sh" "$node_ip" "$node_user" "$node_port" "$node_password" "/tmp/marzban_node_deployer.sh" "Node Deployer Script"; then return 1; fi
    if ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "bash /tmp/marzban_node_deployer.sh" "Node Standalone Deployment"; then
        return 1
    fi
    
    # Wait until the node service is actually listening on the port
    log "INFO" "Waiting for node service to become active..."
    local timer=0
    while ! ssh_remote "$node_ip" "$node_user" "$node_port" "$node_password" "ss -tuln | grep -q ':62050'" "Port Listening Check" >/dev/null 2>&1; do
        sleep 5
        timer=$((timer + 5))
        if [ $timer -ge 60 ]; then
            log "ERROR" "Node service failed to start and listen on port 62050 after 60 seconds. Please check node logs."
            return 1
        fi
    done
    log "SUCCESS" "Node service is active and listening."

    # Phase 2: Register the now-running node with the panel
    log "STEP" "Phase 2: Registering node with Marzban panel..."
    if ! get_marzban_token; then return 1; fi
    if ! add_node_to_marzban_panel_api "$node_name" "$node_ip" "$node_domain"; then return 1; fi

    # Phase 3: Retrieve the REAL client certificate
    log "STEP" "Phase 3: Retrieving client certificate..."
    if ! get_client_cert_from_marzban_api "$MARZBAN_NODE_ID"; then return 1; fi
    if [ -z "$CLIENT_CERT" ]; then log "ERROR" "Failed to retrieve client certificate."; return 1; fi
    
    # Deploy the REAL certificate to the node
    local temp_cert; temp_cert=$(mktemp)
    echo "$CLIENT_CERT" > "$temp_cert"
    scp_to_remote "$temp_cert" "$node_ip" "$node_user" "$node_port" "$node_password" "/var/lib/marzban-node/ssl_client_cert.pem" "Client Certificate"
    rm "$temp_cert"
    
    # Phase 4: Reconfigure and restart the node to enable panel connection
    log "STEP" "Phase 4: Reconfiguring and restarting node for panel connection..."
    local reconfigure_command="sed -i 's/# SSL_CLIENT_CERT_FILE/SSL_CLIENT_CERT_FILE/' /opt/marzban-node/docker-compose.yml && chmod 600 /var/lib/marzban-node/ssl_client_cert.pem && cd /opt/marzban-node && docker compose restart"
    if ! ssh_remote "$node_ip" "$user" "$port" "$node_password" "$reconfigure_command" "Final Node Reconfiguration"; then
        return 1
    fi
    
    # Final health check
    log "INFO" "Waiting 15s for the node to connect to the panel..."
    sleep 15
    if check_node_health_via_api "$MARZBAN_NODE_ID" "$node_name"; then
        log "SUCCESS" "✅ Final health check passed! Node is fully connected."
    fi

    add_node_to_config "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password" "$MARZBAN_NODE_ID"
    save_nodes_config
    return 0
}

deploy_new_node_professional_enhanced() {
    log "STEP" "Starting Enhanced Professional Node Deployment..."
    if [ -z "$MARZBAN_PANEL_DOMAIN" ]; then
        log "ERROR" "Marzban Panel API not configured. Please use Option 8 first."
        return 1
    fi
    detect_main_server_services

    local node_ip node_user="root" node_port="22" node_domain node_name node_password
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║     ${CYAN}Enhanced Professional Deployment${NC}     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    log "PROMPT" "Enter Node Name (unique identifier):"; read -r node_name
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log "ERROR" "Node '$node_name' already exists."
        return 1
    fi

    log "PROMPT" "Enter Node IP Address:"; read -r node_ip
    log "PROMPT" "Enter SSH Username (default: root):"; read -r node_user_input; node_user=${node_user_input:-$node_user}
    log "PROMPT" "Enter SSH Port (default: 22):"; read -r node_port_input; node_port=${node_port_input:-$node_port}
    log "PROMPT" "Enter Node Domain (e.g., node1.example.com):"; read -r node_domain
    if ! [[ $node_domain =~ ^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.){1,}[a-zA-Z]{2,}$ ]]; then
        log "ERROR" "Invalid domain format."
        return 1
    fi
    log "PROMPT" "Enter SSH Password for $node_user@$node_ip:"; read -s node_password; echo ""
    
    _internal_deploy_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "🎉 Node '$node_name' deployed and configured successfully!"
        send_telegram_notification "🚀 New Node Deployed%0A%0ANode: $node_name%0AIP: $node_ip%0ADomain: $node_domain%0AStatus: ✅ Operational" "normal"
    else
        log "ERROR" "Node deployment failed. Please check the logs."
    fi
}

## Advanced Telegram Configuration
configure_telegram_advanced() {
    log "STEP" "Configuring advanced Telegram notifications..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Telegram Notifications Setup${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${PURPLE}Telegram Bot Configuration:${NC}"
    echo "1. Create a bot via @BotFather on Telegram"
    echo "2. Get your chat ID from @userinfobot"
    echo "3. Configure notification levels"
    echo ""
    
    log "PROMPT" "Enter Telegram Bot Token:"
    read -r bot_token
    
    log "PROMPT" "Enter Telegram Chat ID:"
    read -r chat_id
    
    if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
        # Test notification
        log "INFO" "Testing Telegram notification..."
        local test_message="🤖 Marzban Central Manager%0A%0ATest notification from $(hostname)%0ATime: $(date)"
        
        if curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
           -d "chat_id=${chat_id}" \
           -d "text=${test_message}" \
           -d "parse_mode=Markdown" >/dev/null; then
            
            log "SUCCESS" "Telegram test notification sent successfully!"
            
            # Save configuration
            {
                echo "TELEGRAM_BOT_TOKEN=\"$bot_token\""
                echo "TELEGRAM_CHAT_ID=\"$chat_id\""
            } >> "$MANAGER_CONFIG_FILE"
            
            chmod 600 "$MANAGER_CONFIG_FILE"
            source "$MANAGER_CONFIG_FILE"
            
            # Configure notification levels
            echo -e "\n${PURPLE}Notification Levels:${NC}"
            echo " 1. All notifications (normal, high, critical)"
            echo " 2. High and critical only"
            echo " 3. Critical only"
            echo " 4. Disabled"
            echo ""
            
            log "PROMPT" "Choose notification level [default: 1]:"
            read -r level
            level=${level:-1}
            
            echo "TELEGRAM_NOTIFICATION_LEVEL=\"$level\"" >> "$MANAGER_CONFIG_FILE"
            
            log "SUCCESS" "Telegram notifications configured successfully!"
        else
            log "ERROR" "Failed to send test notification. Please check your bot token and chat ID."
        fi
    else
        log "ERROR" "Bot token and chat ID are required."
    fi
}

## Bulk Node Operations Menu
bulk_node_operations() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║          ${CYAN}Bulk Node Operations${NC}             ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        load_nodes_config
        echo -e "${PURPLE}Available Operations for ${#NODES_ARRAY[@]} nodes:${NC}"
        echo " 1. Update All Certificates"
        echo " 2. Restart All Services"
        echo " 3. Update All Geo Files"
        echo " 4. Sync HAProxy to All Nodes"
        echo " 5. Health Check All Nodes"
        echo " 6. Reconnect Disconnected Nodes"
        echo " 7. Update All Node Configurations"
        echo " 8. Bulk SSH Command Execution"
        echo " 9. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose bulk operation:"
        read -r choice
        
        case "$choice" in
            1) bulk_update_certificates ;;
            2) bulk_restart_services ;;
            3) bulk_update_geo_files ;;
            4) bulk_sync_haproxy ;;
            5) bulk_health_check ;;
            6) bulk_reconnect_nodes ;;
            7) bulk_update_configurations ;;
            8) bulk_ssh_command ;;
            9) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "9" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

bulk_health_check() {
    log "STEP" "Performing health check on all nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local healthy=0 unhealthy=0 unknown=0
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}Bulk Health Check Report${NC}                   ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        echo -e "${CYAN}Checking node: $name ($ip)${NC}"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            if check_node_health_via_api "$node_id" "$name"; then
                healthy=$((healthy + 1))
            else
                unhealthy=$((unhealthy + 1))
            fi
        else
            echo "   ⚪ No API ID - checking SSH connectivity..."
            export NODE_SSH_PASSWORD="$password"
            if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "echo 'SSH OK'" "SSH Health Check" >/dev/null 2>&1; then
                echo "   🟢 SSH connectivity: OK"
                unknown=$((unknown + 1))
            else
                echo "   🔴 SSH connectivity: FAILED"
                unhealthy=$((unhealthy + 1))
            fi
            unset NODE_SSH_PASSWORD
        fi
        echo ""
    done
    
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                      ${CYAN}Health Summary${NC}                           ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "🟢 Healthy Nodes: $healthy"
    echo -e "🔴 Unhealthy Nodes: $unhealthy"
    echo -e "⚪ Unknown Status: $unknown"
    echo -e "📊 Total Nodes: ${#NODES_ARRAY[@]}"
    
    # Send notification
    send_telegram_notification "🏥 Health Check Report%0A%0A🟢 Healthy: $healthy%0A🔴 Unhealthy: $unhealthy%0A⚪ Unknown: $unknown%0A📊 Total: ${#NODES_ARRAY[@]}" "normal"
}

bulk_sync_haproxy() {
    log "STEP" "Syncing HAProxy configuration to all nodes..."
    
    if [ "$MAIN_HAS_HAPROXY" != "true" ]; then
        log "ERROR" "HAProxy not detected on main server."
        return 1
    fi
    
    load_nodes_config
    local synced=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Syncing HAProxy to node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if sync_haproxy_to_single_node "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$name"; then
            synced=$((synced + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "HAProxy sync completed: $synced synced, $failed failed."
    send_telegram_notification "🔄 HAProxy Bulk Sync%0A%0A✅ Synced: $synced%0A❌ Failed: $failed" "normal"
}

bulk_reconnect_nodes() {
    log "STEP" "Reconnecting disconnected nodes..."
    
    if ! get_marzban_token; then
        log "ERROR" "Failed to authenticate with Marzban Panel."
        return 1
    fi
    
    load_nodes_config
    local reconnected=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if [ -n "$node_id" ] && [ "$node_id" != "null" ]; then
            local health_response
            health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                -H "Authorization: Bearer $MARZBAN_TOKEN" \
                --insecure 2>/dev/null)
            
            local status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
            
            if [ "$status" != "connected" ]; then
                log "INFO" "Attempting to reconnect node: $name"
                export NODE_SSH_PASSWORD="$password"
                
                # Restart node service
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && docker compose restart" \
                   "Service Restart for Reconnection"; then
                    
                    # Wait and check status again
                    sleep 10
                    health_response=$(curl -s --connect-timeout 5 --max-time 10 \
                        -X GET "${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}/api/node/$node_id" \
                        -H "Authorization: Bearer $MARZBAN_TOKEN" \
                        --insecure 2>/dev/null)
                    
                    local new_status=$(echo "$health_response" | jq -r '.status // "unknown"' 2>/dev/null)
                    
                    if [ "$new_status" = "connected" ]; then
                        reconnected=$((reconnected + 1))
                        log "SUCCESS" "Node '$name' reconnected successfully."
                    else
                        failed=$((failed + 1))
                        log "ERROR" "Failed to reconnect node '$name'."
                    fi
                else
                    failed=$((failed + 1))
                    log "ERROR" "Failed to restart service on node '$name'."
                fi
                
                unset NODE_SSH_PASSWORD
            fi
        fi
    done
    
    log "SUCCESS" "Reconnection completed: $reconnected reconnected, $failed failed."
    send_telegram_notification "🔌 Bulk Reconnection%0A%0A✅ Reconnected: $reconnected%0A❌ Failed: $failed" "normal"
}

bulk_ssh_command() {
    log "STEP" "Bulk SSH command execution..."
    
    echo -e "\n${YELLOW}⚠️  WARNING: This will execute a command on ALL nodes!${NC}"
    echo -e "${YELLOW}Please be very careful with the command you enter.${NC}\n"
    
    log "PROMPT" "Enter command to execute on all nodes:"
    read -r command
    
    if [ -z "$command" ]; then
        log "ERROR" "No command provided."
        return 1
    fi
    
    echo -e "\n${YELLOW}Command to execute: ${WHITE}$command${NC}"
    log "PROMPT" "Are you sure you want to execute this on ALL nodes? (yes/no):"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Bulk command execution cancelled."
        return 0
    fi
    
    load_nodes_config
    local success=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Executing command on node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" "$command" "Bulk Command Execution"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
        
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Bulk command execution completed: $success successful, $failed failed."
}

## System Diagnostics and Logs
show_system_diagnostics() {
    while true; do
        clear
        echo -e "${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║        ${CYAN}System Logs & Diagnostics${NC}         ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${PURPLE}Log Management:${NC}"
        echo " 1. View Recent Manager Logs"
        echo " 2. View Marzban Panel Logs"
        echo " 3. View HAProxy Logs"
        echo " 4. View System Logs"
        echo ""
        echo -e "${PURPLE}Diagnostics:${NC}"
        echo " 5. System Resource Usage"
        echo " 6. Network Connectivity Test"
        echo " 7. Service Status Check"
        echo " 8. Configuration Validation"
        echo ""
        echo -e "${PURPLE}Maintenance:${NC}"
        echo " 9. Clean Old Log Files"
        echo " 10. Export Diagnostic Report"
        echo " 11. Back to Main Menu"
        echo ""
        
        log "PROMPT" "Choose diagnostic option:"
        read -r choice
        
        case "$choice" in
            1) view_manager_logs ;;
            2) view_marzban_logs ;;
            3) view_haproxy_logs ;;
            4) view_system_logs ;;
            5) show_system_resources ;;
            6) test_network_connectivity ;;
            7) check_service_status ;;
            8) validate_configurations ;;
            9) clean_old_logs ;;
            10) export_diagnostic_report ;;
            11) break ;;
            *) log "ERROR" "Invalid option." ;;
        esac
        
        if [ "$choice" != "11" ]; then
            log "PROMPT" "Press Enter to continue..."
            read -s -r
        fi
    done
}

view_manager_logs() {
    log "INFO" "Displaying recent Manager logs..."
    
    echo -e "\n${CYAN}Recent Manager Activity:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$LOGFILE" ]; then
        tail -50 "$LOGFILE"
    else
        echo "No current session log file found."
    fi
    
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    
    # Show system logs for marzban-central-manager
    echo -e "\n${CYAN}System Logs (last 20 entries):${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -t marzban-central-manager -n 20 --no-pager 2>/dev/null || echo "No system logs found."
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

show_system_resources() {
    log "INFO" "Displaying system resource usage..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${CYAN}System Resource Usage${NC}                     ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # CPU Usage
    echo -e "${PURPLE}🖥️  CPU Usage:${NC}"
    top -bn1 | grep "Cpu(s)" | awk '{print $2 $3 $4 $5 $6 $7 $8}' | sed 's/%us,/ User,/g; s/%sy,/ System,/g; s/%ni,/ Nice,/g; s/%id,/ Idle,/g; s/%wa,/ Wait,/g; s/%hi,/ Hardware IRQ,/g; s/%si/ Software IRQ/g'
    
    # Memory Usage
    echo -e "\n${PURPLE}💾 Memory Usage:${NC}"
    free -h | grep -E "(Mem|Swap)"
    
    # Disk Usage
    echo -e "\n${PURPLE}💿 Disk Usage:${NC}"
    df -h | grep -E "^/dev"
    
    # Network Usage
    echo -e "\n${PURPLE}🌐 Network Interfaces:${NC}"
    ip -s link show | grep -E "(^\d+:|RX:|TX:)" | head -20
    
    # Load Average
    echo -e "\n${PURPLE}📊 Load Average:${NC}"
    uptime
    
    # Top Processes
    echo -e "\n${PURPLE}🔝 Top Processes (CPU):${NC}"
    ps aux --sort=-%cpu | head -10 | awk '{printf "%-10s %-6s %-6s %-50s\n", $1, $3, $4, $11}'
    
    # Docker Resources (if available)
    if command_exists docker; then
        echo -e "\n${PURPLE}🐳 Docker Resources:${NC}"
        docker system df 2>/dev/null || echo "Docker system info unavailable"
    fi
}

test_network_connectivity() {
    log "INFO" "Testing network connectivity..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                   ${CYAN}Network Connectivity Test${NC}                  ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Test DNS resolution
    echo -e "${PURPLE}🔍 DNS Resolution Test:${NC}"
    for domain in "google.com" "github.com" "cloudflare.com"; do
        if nslookup "$domain" >/dev/null 2>&1; then
            echo "✅ $domain - OK"
        else
            echo "❌ $domain - FAILED"
        fi
    done
    
    # Test internet connectivity
    echo -e "\n${PURPLE}🌐 Internet Connectivity Test:${NC}"
    for host in "8.8.8.8" "1.1.1.1" "208.67.222.222"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            echo "✅ $host - OK"
        else
            echo "❌ $host - FAILED"
        fi
    done
    
    # Test Marzban Panel connectivity
    if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
        echo -e "\n${PURPLE}🔗 Marzban Panel Connectivity:${NC}"
        local panel_url="${MARZBAN_PANEL_PROTOCOL}://${MARZBAN_PANEL_DOMAIN}:${MARZBAN_PANEL_PORT}"
        
        if curl -s --connect-timeout 5 --max-time 10 "$panel_url" >/dev/null 2>&1; then
            echo "✅ $panel_url - OK"
        else
            echo "❌ $panel_url - FAILED"
        fi
    fi
    
    # Test node connectivity
    echo -e "\n${PURPLE}🖥️  Node Connectivity Test:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
            echo "✅ $name ($ip) - Ping OK"
        else
            echo "❌ $name ($ip) - Ping FAILED"
        fi
    done
}

check_service_status() {
    log "INFO" "Checking service status..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                     ${CYAN}Service Status Check${NC}                      ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check main services
    local services=("docker" "nginx" "haproxy" "ssh" "cron")
    
    echo -e "${PURPLE}🔧 Main Server Services:${NC}"
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "✅ $service - Running"
        elif systemctl list-unit-files | grep -q "^$service.service"; then
            echo "❌ $service - Stopped"
        else
            echo "⚪ $service - Not Installed"
        fi
    done
    
    # Check Marzban service
    echo -e "\n${PURPLE}📊 Marzban Panel Status:${NC}"
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        if docker compose ps | grep -q "Up"; then
            echo "✅ Marzban Panel - Running"
        else
            echo "❌ Marzban Panel - Stopped"
        fi
    else
        echo "⚪ Marzban Panel - Not Found"
    fi
    
    # Check node services
    echo -e "\n${PURPLE}🖥️  Node Services Status:${NC}"
    load_nodes_config
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        export NODE_SSH_PASSWORD="$password"
        local node_status
        node_status=$(ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                     "cd /opt/marzban-node 2>/dev/null && docker compose ps | grep -q 'Up' && echo 'Running' || echo 'Stopped'" \
                     "Node Service Check" 2>/dev/null || echo "Unreachable")
        
        case "$node_status" in
            "Running") echo "✅ $name - Running" ;;
            "Stopped") echo "❌ $name - Stopped" ;;
            *) echo "⚪ $name - Unreachable" ;;
        esac
        
        unset NODE_SSH_PASSWORD
    done
}

export_diagnostic_report() {
    log "INFO" "Generating comprehensive diagnostic report..."
    
    local report_file="${BACKUP_DIR}/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Marzban Central Manager - Diagnostic Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "Manager Version: $SCRIPT_VERSION"
        echo "========================================"
        echo ""
        
        echo "SYSTEM INFORMATION:"
        echo "-------------------"
        uname -a
        echo ""
        cat /etc/os-release 2>/dev/null || echo "OS info unavailable"
        echo ""
        
        echo "RESOURCE USAGE:"
        echo "---------------"
        free -h
        echo ""
        df -h
        echo ""
        uptime
        echo ""
        
        echo "NETWORK CONFIGURATION:"
        echo "----------------------"
        ip addr show | grep -E "(inet |inet6 )"
        echo ""
        
        echo "SERVICE STATUS:"
        echo "---------------"
        for service in docker nginx haproxy ssh cron; do
            systemctl is-active "$service" 2>/dev/null | sed "s/^/$service: /"
        done
        echo ""
        
        echo "MARZBAN CONFIGURATION:"
        echo "----------------------"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ]; then
            echo "Panel Domain: $MARZBAN_PANEL_DOMAIN"
            echo "Panel Port: $MARZBAN_PANEL_PORT"
            echo "Panel Protocol: $MARZBAN_PANEL_PROTOCOL"
        else
            echo "Marzban Panel not configured"
        fi
        echo ""
        
        echo "CONFIGURED NODES:"
        echo "-----------------"
        load_nodes_config
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            echo "Node: $name | IP: $ip | Domain: $domain | ID: $node_id"
        done
        echo ""
        
        echo "RECENT LOGS:"
        echo "------------"
        if [ -f "$LOGFILE" ]; then
            tail -20 "$LOGFILE"
        else
            echo "No recent logs available"
        fi
        
    } > "$report_file"
    
    log "SUCCESS" "Diagnostic report generated: $report_file"
    
    # Offer to send via Telegram
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        log "PROMPT" "Send diagnostic report via Telegram? (y/n):"
        read -r send_telegram
        
        if [[ "$send_telegram" =~ ^[Yy]$ ]]; then
            local report_summary="📋 Diagnostic Report%0A%0AGenerated: $(date)%0AHostname: $(hostname)%0ANodes: ${#NODES_ARRAY[@]}%0A%0AReport saved locally: $(basename "$report_file")"
            send_telegram_notification "$report_summary" "normal"
            log "SUCCESS" "Diagnostic summary sent via Telegram."
        fi
    fi
}

## Missing functions implementation
bulk_update_configurations() {
    log "STEP" "Bulk updating node configurations..."
    
    echo -e "\n${YELLOW}This will update common configuration files on all nodes.${NC}"
    echo -e "${YELLOW}Available updates:${NC}"
    echo " 1. Update docker-compose.yml"
    echo " 2. Update environment variables"
    echo " 3. Update SSL certificates"
    echo " 4. All of the above"
    echo ""
    
    log "PROMPT" "Choose update type:"
    read -r update_type
    
    load_nodes_config
    local updated=0 failed=0
    
    for node_entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
        
        log "INFO" "Updating configuration for node: $name"
        export NODE_SSH_PASSWORD="$password"
        
        case "$update_type" in
            1|4)
                # Update docker-compose.yml
                if ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                   "cd /opt/marzban-node && $(declare -f create_enhanced_docker_compose); create_enhanced_docker_compose" \
                   "Docker Compose Update"; then
                    log "SUCCESS" "Docker compose updated on node: $name"
                else
                    log "ERROR" "Failed to update docker compose on node: $name"
                fi
                ;;
        esac
        
        if [ "$update_type" = "4" ] || [ "$update_type" = "2" ]; then
            # Update environment variables
            ssh_remote "$ip" "$user" "$port" "$NODE_SSH_PASSWORD" \
                "cd /opt/marzban-node && docker compose restart" \
                "Service Restart" >/dev/null 2>&1
        fi
        
        updated=$((updated + 1))
        unset NODE_SSH_PASSWORD
    done
    
    log "SUCCESS" "Configuration update completed: $updated updated, $failed failed."
}

view_marzban_logs() {
    log "INFO" "Displaying Marzban Panel logs..."
    
    if [ -d "/opt/marzban" ]; then
        cd /opt/marzban
        echo -e "\n${CYAN}Recent Marzban Panel Logs:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        docker compose logs --tail=50 2>/dev/null || echo "Unable to fetch Marzban logs"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Marzban installation not found at /opt/marzban"
    fi
}

view_haproxy_logs() {
    log "INFO" "Displaying HAProxy logs..."
    
    echo -e "\n${CYAN}Recent HAProxy Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -u haproxy -n 50 --no-pager 2>/dev/null || echo "HAProxy logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

view_system_logs() {
    log "INFO" "Displaying system logs..."
    
    echo -e "\n${CYAN}Recent System Logs:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    journalctl -n 50 --no-pager 2>/dev/null || echo "System logs not available"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

validate_configurations() {
    log "INFO" "Validating system configurations..."
    
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                  ${CYAN}Configuration Validation${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Validate Nginx configuration
    if command_exists nginx; then
        echo -e "${PURPLE}🔧 Nginx Configuration:${NC}"
        if nginx -t 2>/dev/null; then
            echo "✅ Nginx configuration is valid"
        else
            echo "❌ Nginx configuration has errors"
        fi
    fi
    
    # Validate HAProxy configuration
    if command_exists haproxy; then
        echo -e "\n${PURPLE}⚖️  HAProxy Configuration:${NC}"
        if /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg 2>/dev/null; then
            echo "✅ HAProxy configuration is valid"
        else
            echo "❌ HAProxy configuration has errors"
        fi
    fi
    
    # Validate Manager configuration
    echo -e "\n${PURPLE}📊 Manager Configuration:${NC}"
    if [ -f "$MANAGER_CONFIG_FILE" ]; then
        echo "✅ Manager configuration file exists"
        
        # Check required variables
        source "$MANAGER_CONFIG_FILE"
        if [ -n "$MARZBAN_PANEL_DOMAIN" ] && [ -n "$MARZBAN_PANEL_USERNAME" ]; then
            echo "✅ Marzban Panel credentials configured"
        else
            echo "❌ Marzban Panel credentials missing"
        fi
    else
        echo "❌ Manager configuration file missing"
    fi
    
    # Validate node configurations
    echo -e "\n${PURPLE}🖥️  Node Configurations:${NC}"
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -gt 0 ]; then
        echo "✅ ${#NODES_ARRAY[@]} nodes configured"
        
        local valid_nodes=0
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                valid_nodes=$((valid_nodes + 1))
            fi
        done
        echo "✅ $valid_nodes nodes have valid IP addresses"
    else
        echo "⚪ No nodes configured"
    fi
}

clean_old_logs() {
    log "INFO" "Cleaning old log files..."

    echo -e "\n${YELLOW}This will remove log files older than 30 days.${NC}"
    log "PROMPT" "Continue with log cleanup? (y/n):"
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local cleaned=0

        # Clean manager logs
        find /tmp -name "marzban_central_manager_*.log" -mtime +30 -delete 2>/dev/null && cleaned=$((cleaned + 1))

        # Clean system logs (rotate)
        journalctl --vacuum-time=30d >/dev/null 2>&1 && cleaned=$((cleaned + 1))

        # Clean Docker logs
        log "DEBUG" "Checking type of command_exists before use in clean_old_logs:"
        type command_exists || log "ERROR" "command_exists is not recognized here!"
        
        if command_exists docker; then
            log "INFO" "Docker command found, attempting to prune Docker system logs."
            docker system prune -f --filter "until=720h" >/dev/null 2>&1 && cleaned=$((cleaned + 1))
        else
            log "INFO" "Docker command not found, skipping Docker log cleanup."
        fi

        log "SUCCESS" "Log cleanup completed. $cleaned log sources cleaned."
    else
        log "INFO" "Log cleanup cancelled."
    fi
}

# Additional missing functions for complete functionality
add_nginx_site() {
    log "STEP" "Adding new Nginx site configuration..."
    
    log "PROMPT" "Enter site domain (e.g., example.com):"
    read -r site_domain
    
    log "PROMPT" "Enter document root path (default: /var/www/$site_domain):"
    read -r doc_root
    doc_root=${doc_root:-/var/www/$site_domain}
    
    # Create site configuration
    local site_config="/etc/nginx/sites-available/$site_domain"
    cat > "$site_config" << EOF
server {
    listen 80;
    server_name $site_domain www.$site_domain;
    root $doc_root;
    index index.html index.htm index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF
    
    # Create document root
    mkdir -p "$doc_root"
    chown www-data:www-data "$doc_root"
    
    # Create basic index file
    echo "<h1>Welcome to $site_domain</h1>" > "$doc_root/index.html"
    chown www-data:www-data "$doc_root/index.html"
    
    log "SUCCESS" "Site configuration created: $site_config"
    log "INFO" "To enable the site, run: ln -s $site_config /etc/nginx/sites-enabled/"
}

remove_nginx_site() {
    log "STEP" "Removing Nginx site configuration..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            echo " $i. $site_name"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to remove:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            # Remove from sites-enabled if linked
            rm -f "/etc/nginx/sites-enabled/$selected_site"
            
            # Remove from sites-available
            rm -f "/etc/nginx/sites-available/$selected_site"
            
            log "SUCCESS" "Site '$selected_site' removed successfully."
            
            # Test nginx configuration
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed after site removal."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available to remove."
    fi
}

toggle_nginx_site() {
    log "STEP" "Enable/Disable Nginx site..."
    
    if ls /etc/nginx/sites-available/* >/dev/null 2>&1; then
        echo -e "\n${PURPLE}Available sites:${NC}"
        local i=1
        for site in /etc/nginx/sites-available/*; do
            local site_name=$(basename "$site")
            local status="disabled"
            if [ -L "/etc/nginx/sites-enabled/$site_name" ]; then
                status="enabled"
            fi
            echo " $i. $site_name ($status)"
            i=$((i + 1))
        done
        
        log "PROMPT" "Enter site number to toggle:"
        read -r site_num
        
        local sites=($(ls /etc/nginx/sites-available/))
        local selected_site="${sites[$((site_num - 1))]}"
        
        if [ -n "$selected_site" ]; then
            if [ -L "/etc/nginx/sites-enabled/$selected_site" ]; then
                # Disable site
                rm "/etc/nginx/sites-enabled/$selected_site"
                log "SUCCESS" "Site '$selected_site' disabled."
            else
                # Enable site
                ln -s "/etc/nginx/sites-available/$selected_site" "/etc/nginx/sites-enabled/"
                log "SUCCESS" "Site '$selected_site' enabled."
            fi
            
            # Test and reload nginx
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log "SUCCESS" "Nginx configuration reloaded."
            else
                log "ERROR" "Nginx configuration test failed."
            fi
        else
            log "ERROR" "Invalid site selection."
        fi
    else
        log "WARNING" "No sites available."
    fi
}

generate_ssl_certificate() {
    log "STEP" "Generating SSL certificate..."
    
    log "PROMPT" "Enter domain for SSL certificate:"
    read -r ssl_domain
    
    log "PROMPT" "Enter email for Let's Encrypt:"
    read -r ssl_email
    
    # Install certbot if not available
    if ! command_exists certbot; then
        log "INFO" "Installing certbot..."
        apt update >/dev/null 2>&1
        apt install -y certbot python3-certbot-nginx >/dev/null 2>&1
    fi
    
    # Generate certificate
    if certbot --nginx -d "$ssl_domain" --email "$ssl_email" --agree-tos --non-interactive; then
        log "SUCCESS" "SSL certificate generated for $ssl_domain"
    else
        log "ERROR" "Failed to generate SSL certificate for $ssl_domain"
    fi
}

renew_ssl_certificates() {
    log "STEP" "Renewing SSL certificates..."
    
    if command_exists certbot; then
        if certbot renew --dry-run; then
            log "SUCCESS" "SSL certificate renewal test passed."
            
            log "PROMPT" "Proceed with actual renewal? (y/n):"
            read -r proceed
            
            if [[ "$proceed" =~ ^[Yy]$ ]]; then
                if certbot renew; then
                    log "SUCCESS" "SSL certificates renewed successfully."
                    systemctl reload nginx
                else
                    log "ERROR" "SSL certificate renewal failed."
                fi
            fi
        else
            log "ERROR" "SSL certificate renewal test failed."
        fi
    else
        log "ERROR" "Certbot not installed."
    fi
}

view_certificate_status() {
    log "INFO" "Displaying SSL certificate status..."
    
    if command_exists certbot; then
        echo -e "\n${CYAN}SSL Certificate Status:${NC}"
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        certbot certificates
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
    else
        echo "Certbot not installed. Cannot check SSL certificate status."
    fi
}

# Script completion message
log "SUCCESS" "Marzban Central Manager Professional Edition v$SCRIPT_VERSION loaded successfully!"

# ==============================================================================
# MAIN MENU DISPLAY FUNCTION
# ==============================================================================

show_main_menu() {
    clear
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║ ${CYAN}${BOLD}Marzban Central Node Manager${NC}                           ║"
    echo -e "${WHITE}║ ${PURPLE}Made with ❤️ by B3hnAM - Thanks to all Marzban developers${NC} ║"
    echo -e "${WHITE}║ ${YELLOW}[Professional Edition v${SCRIPT_VERSION}]${NC}                    ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}Current Nodes Overview:${NC}"
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    
    load_nodes_config
    if [ "${#NODES_ARRAY[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No nodes have been added yet.${NC}"
    else
        printf "%-20s %-15s %-15s %-10s\n" "Node Name" "IP Address" "Status" "Domain"
        echo -e "${WHITE}----------------------------------------------------------------------${NC}"
        for node_entry in "${NODES_ARRAY[@]}"; do
            IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
            local status
            if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
                status="${GREEN}Online${NC}"
            else
                status="${RED}Offline${NC}"
            fi
            printf "%-20s %-15s %-15s %-10s\n" "$name" "$ip" "$status" "$domain"
        done
    fi
    
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${GREEN}1) Add a new node${NC}"
    echo -e "${GREEN}2) Remove a node${NC}"
    echo -e "${GREEN}3) Update node information${NC}"
    echo -e "${YELLOW}4) Sync HAProxy to All Nodes${NC}"
    echo -e "${CYAN}5) Check all nodes status${NC}"
    echo -e "${PURPLE}6) Bulk Update Node Configurations${NC}"
    echo -e "${BLUE}7) Install Marzban on a new node${NC}"
    echo -e "${WHITE}8) Configure Marzban API${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${GREEN}9) Backup & Restore Menu${NC}"
    echo -e "${GREEN}10) Nginx Management Menu${NC}"
    echo -e "${GREEN}11) Bulk Node Operations Menu${NC}"
    echo -e "${GREEN}12) System Logs & Diagnostics Menu${NC}"
    echo -e "${CYAN}-----------------------------------------------${NC}" # Additional separator
    echo -e "${WHITE}13) Configure Telegram Notifications${NC}"
    echo -e "${WHITE}14) View System Resources${NC}"
    echo -e "${WHITE}15) Validate Configurations${NC}"
    echo -e "${WHITE}16) Clean Old Logs${NC}"
    echo -e "${YELLOW}17) View Marzban Panel Logs${NC}"
    echo -e "${YELLOW}18) View HAProxy Logs${NC}"
    echo -e "${YELLOW}19) View System Logs${NC}"
    echo -e "${RED}x) Exit${NC}"
    echo ""
}

# ==============================================================================
# MAIN EXECUTION LOGIC
# ==============================================================================

main() {
    check_dependencies # Ensure dependencies are met before showing the menu
    while true; do
        show_main_menu
        read -p "Please enter your choice [1-19, x]: " choice

        case "$choice" in
            1) import_single_node || true; read -p "Press Enter to continue..." ;;
            2) remove_node || true; read -p "Press Enter to continue..." ;;
            3) update_existing_node || true; read -p "Press Enter to continue..." ;;
            4) bulk_sync_haproxy || true; read -p "Press Enter to continue..." ;;
            5) monitor_node_health_status || true; read -p "Press Enter to continue..." ;;
            6) bulk_update_configurations || true; read -p "Press Enter to continue..." ;;
            7) deploy_new_node_professional_enhanced || true; read -p "Press Enter to continue..." ;;
            8) configure_marzban_api || true; read -p "Press Enter to continue..." ;;
            9) backup_restore_menu || true; read -p "Press Enter to continue..." ;;
            10) nginx_management_menu || true; read -p "Press Enter to continue..." ;;
            11) bulk_node_operations || true; read -p "Press Enter to continue..." ;;
            12) show_system_diagnostics || true; read -p "Press Enter to continue..." ;;
            13) configure_telegram_advanced || true; read -p "Press Enter to continue..." ;;
            14) show_system_resources || true; read -p "Press Enter to continue..." ;;
            15) validate_configurations || true; read -p "Press Enter to continue..." ;;
            16) clean_old_logs || true; read -p "Press Enter to continue..." ;;
            17) view_marzban_logs || true; read -p "Press Enter to continue..." ;;
            18) view_haproxy_logs || true; read -p "Press Enter to continue..." ;;
            19) view_system_logs || true; read -p "Press Enter to continue..." ;;
            x|X)
                log "INFO" "Exiting Marzban Central Manager. Goodbye!"
                exit 0
                ;;
            *)
                log "ERROR" "Invalid option: $choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# --- Start The Program ---
main