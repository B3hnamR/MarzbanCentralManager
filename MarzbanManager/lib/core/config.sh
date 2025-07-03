#!/bin/bash
# Marzban Central Manager - Configuration Management Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# GLOBAL CONFIGURATION VARIABLES
# ============================================================================

# Script Information
readonly SCRIPT_VERSION="Professional-3.1"
readonly SCRIPT_NAME="Marzban Central Manager"
readonly SCRIPT_AUTHOR="B3hnamR"

# Directory Structure
readonly MANAGER_DIR="/root/MarzbanManager"
readonly NODES_CONFIG_FILE="${MANAGER_DIR}/marzban_managed_nodes.conf"
readonly MANAGER_CONFIG_FILE="${MANAGER_DIR}/marzban_manager.conf"
readonly BACKUP_DIR="${MANAGER_DIR}/backups"
readonly LOCKFILE="/var/lock/marzban-central-manager.lock"
readonly LOGFILE="/tmp/marzban_central_manager_$(date +%Y%m%d_%H%M%S).log"

# Backup Configuration
readonly BACKUP_MAIN_DIR="${BACKUP_DIR}/main_server"
readonly BACKUP_NODES_DIR="${BACKUP_DIR}/nodes"
readonly BACKUP_ARCHIVE_DIR="${BACKUP_DIR}/archives"
readonly BACKUP_RETENTION_COUNT=3
readonly BACKUP_SCHEDULE_HOUR="03"
readonly BACKUP_SCHEDULE_MINUTE="30"
readonly BACKUP_TIMEZONE="Asia/Tehran"

# Network Configuration
MAIN_SERVER_IP=$(hostname -I | awk '{print $1}')
MARZBAN_PANEL_PROTOCOL="https"
MARZBAN_PANEL_DOMAIN=""
MARZBAN_PANEL_PORT=""
MARZBAN_PANEL_USERNAME=""
MARZBAN_PANEL_PASSWORD=""
MARZBAN_TOKEN=""
CLIENT_CERT=""
MARZBAN_NODE_ID=""

# SSH Configuration
NODE_SSH_PASSWORD=""

# Telegram Configuration
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_NOTIFICATION_LEVEL="1"

# Monitoring Configuration
readonly MONITORING_INTERVAL=600        # 10 minutes
readonly HEALTH_CHECK_TIMEOUT=30        # 30 seconds
readonly API_RATE_LIMIT_DELAY=2         # 2 seconds between API calls
readonly SYNC_CHECK_INTERVAL=1800       # 30 minutes for sync monitoring

# Service Detection Variables
MAIN_HAS_NGINX=false
MAIN_HAS_HAPROXY=false
NGINX_CONFIG_PATH=""
HAPROXY_CONFIG_PATH=""
GEO_FILES_PATH=""

# Feature Flags
AUTO_BACKUP_ENABLED=false

# ============================================================================
# CONFIGURATION MANAGEMENT FUNCTIONS
# ============================================================================

# Initialize configuration directories
init_config_directories() {
    local dirs=(
        "$MANAGER_DIR"
        "$BACKUP_DIR"
        "$BACKUP_MAIN_DIR"
        "$BACKUP_NODES_DIR"
        "$BACKUP_ARCHIVE_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            echo "ERROR: Failed to create directory: $dir" >&2
            return 1
        fi
        chmod 700 "$dir"
    done
    
    return 0
}

# Load manager configuration
load_manager_config() {
    if [[ -f "$MANAGER_CONFIG_FILE" ]]; then
        # Source the config file safely
        set -a  # Export all variables
        source "$MANAGER_CONFIG_FILE"
        set +a  # Stop exporting
        return 0
    fi
    return 1
}

# Save configuration to file
save_manager_config() {
    local config_content=""
    
    # Build configuration content
    config_content+="# Marzban Central Manager Configuration\n"
    config_content+="# Generated on: $(date)\n\n"
    
    # Panel Configuration
    config_content+="# Panel Configuration\n"
    config_content+="MARZBAN_PANEL_PROTOCOL=\"${MARZBAN_PANEL_PROTOCOL}\"\n"
    config_content+="MARZBAN_PANEL_DOMAIN=\"${MARZBAN_PANEL_DOMAIN}\"\n"
    config_content+="MARZBAN_PANEL_PORT=\"${MARZBAN_PANEL_PORT}\"\n"
    config_content+="MARZBAN_PANEL_USERNAME=\"${MARZBAN_PANEL_USERNAME}\"\n"
    config_content+="MARZBAN_PANEL_PASSWORD=\"${MARZBAN_PANEL_PASSWORD}\"\n\n"
    
    # Telegram Configuration
    config_content+="# Telegram Configuration\n"
    config_content+="TELEGRAM_BOT_TOKEN=\"${TELEGRAM_BOT_TOKEN:-}\"\n"
    config_content+="TELEGRAM_CHAT_ID=\"${TELEGRAM_CHAT_ID:-}\"\n"
    config_content+="TELEGRAM_NOTIFICATION_LEVEL=\"${TELEGRAM_NOTIFICATION_LEVEL:-1}\"\n\n"
    
    # Feature Flags
    config_content+="# Feature Flags\n"
    config_content+="AUTO_BACKUP_ENABLED=${AUTO_BACKUP_ENABLED}\n"
    
    # Write to file
    echo -e "$config_content" > "$MANAGER_CONFIG_FILE"
    chmod 600 "$MANAGER_CONFIG_FILE"
    
    return 0
}

# Validate configuration
validate_config() {
    local errors=()
    
    # Check required directories
    for dir in "$MANAGER_DIR" "$BACKUP_DIR"; do
        if [[ ! -d "$dir" ]]; then
            errors+=("Missing directory: $dir")
        fi
    done
    
    # Check panel configuration if set
    if [[ -n "$MARZBAN_PANEL_DOMAIN" ]]; then
        if [[ -z "$MARZBAN_PANEL_USERNAME" || -z "$MARZBAN_PANEL_PASSWORD" ]]; then
            errors+=("Incomplete panel configuration")
        fi
    fi
    
    # Return validation result
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf "Configuration validation errors:\n"
        printf " - %s\n" "${errors[@]}"
        return 1
    fi
    
    return 0
}

# Get configuration value
get_config_value() {
    local key="$1"
    local default_value="${2:-}"
    
    if [[ -f "$MANAGER_CONFIG_FILE" ]]; then
        local value
        value=$(grep "^${key}=" "$MANAGER_CONFIG_FILE" | cut -d'=' -f2- | tr -d '"')
        echo "${value:-$default_value}"
    else
        echo "$default_value"
    fi
}

# Set configuration value
set_config_value() {
    local key="$1"
    local value="$2"
    
    # Remove existing key
    if [[ -f "$MANAGER_CONFIG_FILE" ]]; then
        sed -i "/^${key}=/d" "$MANAGER_CONFIG_FILE"
    fi
    
    # Add new value
    echo "${key}=\"${value}\"" >> "$MANAGER_CONFIG_FILE"
    chmod 600 "$MANAGER_CONFIG_FILE"
}

# Check if API is configured
is_api_configured() {
    [[ -n "${MARZBAN_PANEL_DOMAIN:-}" && -n "${MARZBAN_PANEL_USERNAME:-}" && -n "${MARZBAN_PANEL_PASSWORD:-}" ]]
}

# Check if Telegram is configured
is_telegram_configured() {
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]
}

# Export configuration for other modules
export_config() {
    # Export all configuration variables
    export SCRIPT_VERSION SCRIPT_NAME SCRIPT_AUTHOR
    export MANAGER_DIR NODES_CONFIG_FILE MANAGER_CONFIG_FILE BACKUP_DIR LOCKFILE LOGFILE
    export BACKUP_MAIN_DIR BACKUP_NODES_DIR BACKUP_ARCHIVE_DIR BACKUP_RETENTION_COUNT
    export BACKUP_SCHEDULE_HOUR BACKUP_SCHEDULE_MINUTE BACKUP_TIMEZONE
    export MAIN_SERVER_IP MARZBAN_PANEL_PROTOCOL MARZBAN_PANEL_DOMAIN MARZBAN_PANEL_PORT
    export MARZBAN_PANEL_USERNAME MARZBAN_PANEL_PASSWORD MARZBAN_TOKEN CLIENT_CERT MARZBAN_NODE_ID
    export NODE_SSH_PASSWORD TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID TELEGRAM_NOTIFICATION_LEVEL
    export MONITORING_INTERVAL HEALTH_CHECK_TIMEOUT API_RATE_LIMIT_DELAY SYNC_CHECK_INTERVAL
    export MAIN_HAS_NGINX MAIN_HAS_HAPROXY NGINX_CONFIG_PATH HAPROXY_CONFIG_PATH GEO_FILES_PATH
    export AUTO_BACKUP_ENABLED
}

# Initialize configuration system
init_config() {
    # Create directories
    if ! init_config_directories; then
        return 1
    fi
    
    # Load existing configuration
    load_manager_config
    
    # Initialize service detection variables
    MAIN_HAS_NGINX=false
    MAIN_HAS_HAPROXY=false
    NGINX_CONFIG_PATH=""
    HAPROXY_CONFIG_PATH=""
    GEO_FILES_PATH=""
    
    # Export configuration
    export_config
    
    return 0
}