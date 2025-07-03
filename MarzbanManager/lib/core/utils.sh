#!/bin/bash
# Marzban Central Manager - Utility Functions Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# SYSTEM UTILITIES
# ============================================================================

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if script is running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Get system information
get_system_info() {
    local info=""
    
    # OS Information
    if [[ -f /etc/os-release ]]; then
        local os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        info+="OS: $os_name\n"
    fi
    
    # Kernel version
    info+="Kernel: $(uname -r)\n"
    
    # Architecture
    info+="Architecture: $(uname -m)\n"
    
    # Memory
    if command_exists free; then
        local memory=$(free -h | awk '/^Mem:/ {print $2}')
        info+="Memory: $memory\n"
    fi
    
    # Disk space
    if command_exists df; then
        local disk=$(df -h / | awk 'NR==2 {print $2}')
        info+="Disk: $disk\n"
    fi
    
    # CPU cores
    local cores=$(nproc 2>/dev/null || echo "Unknown")
    info+="CPU Cores: $cores\n"
    
    echo -e "$info"
}

# Get network interface IP
get_primary_ip() {
    # Try multiple methods to get primary IP
    local ip=""
    
    # Method 1: hostname -I
    if command_exists hostname; then
        ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    fi
    
    # Method 2: ip route
    if [[ -z "$ip" ]] && command_exists ip; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
    fi
    
    # Method 3: ifconfig
    if [[ -z "$ip" ]] && command_exists ifconfig; then
        ip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
    
    # Method 4: curl external service
    if [[ -z "$ip" ]] && command_exists curl; then
        ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
    fi
    
    echo "${ip:-127.0.0.1}"
}

# Check internet connectivity
check_internet() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
            return 0
        fi
    done
    
    return 1
}

# Get available disk space in bytes
get_available_space() {
    local path="${1:-/}"
    df "$path" | awk 'NR==2 {print $4}'
}

# Check if port is in use
is_port_in_use() {
    local port="$1"
    
    if command_exists ss; then
        ss -tuln | grep -q ":$port "
    elif command_exists netstat; then
        netstat -tuln | grep -q ":$port "
    else
        return 1
    fi
}

# ============================================================================
# STRING UTILITIES
# ============================================================================

# Trim whitespace from string
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace
    echo "$var"
}

# Convert string to lowercase
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Check if string is empty
is_empty() {
    [[ -z "$(trim "$1")" ]]
}

# Check if string is a valid IP address
is_valid_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $regex ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Check if string is a valid domain
is_valid_domain() {
    local domain="$1"
    local regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
    
    [[ $domain =~ $regex ]] && [[ ${#domain} -le 253 ]]
}

# Check if string is a valid port number
is_valid_port() {
    local port="$1"
    [[ $port =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

# Generate random string
generate_random_string() {
    local length="${1:-16}"
    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    
    for ((i=0; i<length; i++)); do
        echo -n "${chars:RANDOM%${#chars}:1}"
    done
    echo
}

# ============================================================================
# FILE UTILITIES
# ============================================================================

# Create directory with proper permissions
create_secure_dir() {
    local dir="$1"
    local mode="${2:-700}"
    
    if mkdir -p "$dir" 2>/dev/null; then
        chmod "$mode" "$dir"
        return 0
    fi
    return 1
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    local backup_dir="${2:-$(dirname "$file")}"
    
    if [[ -f "$file" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_name="$(basename "$file").backup.$timestamp"
        local backup_path="$backup_dir/$backup_name"
        
        if cp "$file" "$backup_path" 2>/dev/null; then
            echo "$backup_path"
            return 0
        fi
    fi
    return 1
}

# Check file permissions
check_file_permissions() {
    local file="$1"
    local expected_mode="$2"
    
    if [[ -f "$file" ]]; then
        local actual_mode=$(stat -c %a "$file" 2>/dev/null || stat -f %A "$file" 2>/dev/null)
        [[ "$actual_mode" == "$expected_mode" ]]
    else
        return 1
    fi
}

# Get file size in human readable format
get_file_size() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        if command_exists du; then
            du -h "$file" | cut -f1
        else
            ls -lh "$file" | awk '{print $5}'
        fi
    fi
}

# Calculate file checksum
calculate_checksum() {
    local file="$1"
    local algorithm="${2:-md5}"
    
    if [[ -f "$file" ]]; then
        case "$algorithm" in
            md5)
                if command_exists md5sum; then
                    md5sum "$file" | cut -d' ' -f1
                elif command_exists md5; then
                    md5 -q "$file"
                fi
                ;;
            sha256)
                if command_exists sha256sum; then
                    sha256sum "$file" | cut -d' ' -f1
                elif command_exists shasum; then
                    shasum -a 256 "$file" | cut -d' ' -f1
                fi
                ;;
        esac
    fi
}

# ============================================================================
# PROCESS UTILITIES
# ============================================================================

# Check if process is running
is_process_running() {
    local process_name="$1"
    pgrep -f "$process_name" >/dev/null 2>&1
}

# Get process PID
get_process_pid() {
    local process_name="$1"
    pgrep -f "$process_name" | head -1
}

# Kill process gracefully
kill_process_gracefully() {
    local process_name="$1"
    local timeout="${2:-30}"
    
    local pid=$(get_process_pid "$process_name")
    if [[ -n "$pid" ]]; then
        # Send TERM signal
        kill -TERM "$pid" 2>/dev/null
        
        # Wait for process to exit
        local count=0
        while [[ $count -lt $timeout ]] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# DATE/TIME UTILITIES
# ============================================================================

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get current timestamp for filenames
get_timestamp_filename() {
    date '+%Y%m%d_%H%M%S'
}

# Convert seconds to human readable format
seconds_to_human() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    local result=""
    [[ $days -gt 0 ]] && result+="${days}d "
    [[ $hours -gt 0 ]] && result+="${hours}h "
    [[ $minutes -gt 0 ]] && result+="${minutes}m "
    [[ $secs -gt 0 ]] && result+="${secs}s"
    
    echo "${result:-0s}"
}

# ============================================================================
# VALIDATION UTILITIES
# ============================================================================

# Validate email address
is_valid_email() {
    local email="$1"
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    [[ $email =~ $regex ]]
}

# Validate URL
is_valid_url() {
    local url="$1"
    local regex='^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$'
    [[ $url =~ $regex ]]
}

# Validate phone number (basic)
is_valid_phone() {
    local phone="$1"
    local regex='^[+]?[0-9]{10,15}$'
    [[ $phone =~ $regex ]]
}

# ============================================================================
# ARRAY UTILITIES
# ============================================================================

# Check if array contains element
array_contains() {
    local element="$1"
    shift
    local array=("$@")
    
    for item in "${array[@]}"; do
        [[ "$item" == "$element" ]] && return 0
    done
    return 1
}

# Remove element from array
array_remove() {
    local element="$1"
    shift
    local array=("$@")
    local result=()
    
    for item in "${array[@]}"; do
        [[ "$item" != "$element" ]] && result+=("$item")
    done
    
    printf '%s\n' "${result[@]}"
}

# Get unique elements from array
array_unique() {
    local array=("$@")
    printf '%s\n' "${array[@]}" | sort -u
}

# ============================================================================
# RETRY UTILITIES
# ============================================================================

# Retry command with exponential backoff
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    local max_delay="${3:-300}"
    shift 3
    local command=("$@")
    
    local attempt=1
    local current_delay="$delay"
    
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}"; then
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            return 1
        fi
        
        sleep "$current_delay"
        current_delay=$((current_delay * 2))
        [[ $current_delay -gt $max_delay ]] && current_delay="$max_delay"
        
        ((attempt++))
    done
    
    return 1
}

# Simple retry function
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")
    
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    return 1
}

# ============================================================================
# LOCK UTILITIES
# ============================================================================

# Acquire lock with timeout
acquire_lock_with_timeout() {
    local lockfile="$1"
    local timeout="${2:-60}"
    local wait_interval="${3:-1}"
    
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if (set -C; echo $$ > "$lockfile") 2>/dev/null; then
            return 0
        fi
        
        # Check if lock is stale
        if [[ -f "$lockfile" ]]; then
            local lock_pid=$(cat "$lockfile" 2>/dev/null)
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -f "$lockfile"
                continue
            fi
        fi
        
        sleep "$wait_interval"
        elapsed=$((elapsed + wait_interval))
    done
    
    return 1
}

# Release lock
release_lock() {
    local lockfile="$1"
    rm -f "$lockfile"
}

# ============================================================================
# SERVICE DETECTION UTILITIES
# ============================================================================

# Detect main server services
detect_main_server_services() {
    log_info "Detecting main server services..."
    
    # Detect Nginx
    if command_exists nginx; then
        MAIN_HAS_NGINX=true
        log_info "Nginx detected"
        
        # Find Nginx config path
        if [[ -f "/etc/nginx/nginx.conf" ]]; then
            NGINX_CONFIG_PATH="/etc/nginx/nginx.conf"
        elif [[ -f "/usr/local/nginx/conf/nginx.conf" ]]; then
            NGINX_CONFIG_PATH="/usr/local/nginx/conf/nginx.conf"
        else
            NGINX_CONFIG_PATH=$(nginx -t 2>&1 | grep "configuration file" | awk '{print $5}' | head -1)
        fi
        
        if [[ -n "$NGINX_CONFIG_PATH" ]]; then
            log_info "Nginx config found at: $NGINX_CONFIG_PATH"
        fi
    else
        MAIN_HAS_NGINX=false
        log_info "Nginx not detected"
    fi
    
    # Detect HAProxy
    if command_exists haproxy; then
        MAIN_HAS_HAPROXY=true
        log_info "HAProxy detected"
        
        # Find HAProxy config path
        if [[ -f "/etc/haproxy/haproxy.cfg" ]]; then
            HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
        elif [[ -f "/usr/local/etc/haproxy/haproxy.cfg" ]]; then
            HAPROXY_CONFIG_PATH="/usr/local/etc/haproxy/haproxy.cfg"
        else
            # Try to find from process
            local haproxy_proc=$(ps aux | grep haproxy | grep -v grep | head -1)
            if [[ -n "$haproxy_proc" ]]; then
                HAPROXY_CONFIG_PATH=$(echo "$haproxy_proc" | grep -o '\-f [^ ]*' | cut -d' ' -f2)
            fi
        fi
        
        if [[ -n "$HAPROXY_CONFIG_PATH" ]]; then
            log_info "HAProxy config found at: $HAPROXY_CONFIG_PATH"
        fi
    else
        MAIN_HAS_HAPROXY=false
        log_info "HAProxy not detected"
    fi
    
    # Detect Geo files
    detect_geo_files
    
    # Export detected services
    export MAIN_HAS_NGINX MAIN_HAS_HAPROXY NGINX_CONFIG_PATH HAPROXY_CONFIG_PATH GEO_FILES_PATH
    
    log_success "Service detection completed"
    return 0
}

# Detect geo files location
detect_geo_files() {
    log_debug "Detecting geo files location..."
    
    local possible_paths=(
        "/var/lib/marzban/xray_config"
        "/opt/marzban/xray_config"
        "/usr/local/share/xray"
        "/var/lib/xray"
        "/opt/xray"
        "/etc/xray"
    )
    
    # Method 1: Check .env file
    if [[ -f "/opt/marzban/.env" ]]; then
        local xray_assets=$(grep "XRAY_ASSETS_PATH" /opt/marzban/.env | cut -d'=' -f2 | tr -d '"')
        if [[ -n "$xray_assets" && -d "$xray_assets" ]]; then
            possible_paths=("$xray_assets" "${possible_paths[@]}")
        fi
    fi
    
    # Method 2: Check xray_config.json
    if [[ -f "/var/lib/marzban/xray_config.json" ]]; then
        local geo_path=$(grep -o '"geoip":[[:space:]]*"[^"]*"' /var/lib/marzban/xray_config.json | cut -d'"' -f4 | head -1)
        if [[ -n "$geo_path" ]]; then
            local geo_dir=$(dirname "$geo_path")
            possible_paths=("$geo_dir" "${possible_paths[@]}")
        fi
    fi
    
    # Find the first existing path with geo files
    for path in "${possible_paths[@]}"; do
        if [[ -d "$path" ]] && ([[ -f "$path/geoip.dat" ]] || [[ -f "$path/geosite.dat" ]]); then
            GEO_FILES_PATH="$path"
            log_info "Geo files found at: $GEO_FILES_PATH"
            return 0
        fi
    done
    
    log_warning "Geo files location not found"
    return 1
}

# Check service status
check_service_status() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl is-active --quiet "$service"
    elif command_exists service; then
        service "$service" status >/dev/null 2>&1
    else
        return 1
    fi
}

# Get service status info
get_service_status_info() {
    local service="$1"
    
    if check_service_status "$service"; then
        echo "running"
    else
        echo "stopped"
    fi
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize utilities module
init_utils() {
    # Set up any required environment
    return 0
}