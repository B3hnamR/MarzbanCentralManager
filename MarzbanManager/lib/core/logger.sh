#!/bin/bash
# Marzban Central Manager - Logging System Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_SUCCESS=4

# Current log level (can be overridden)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Log file rotation settings
readonly MAX_LOG_SIZE=10485760  # 10MB
readonly MAX_LOG_FILES=5

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get short timestamp for console
get_short_timestamp() {
    date '+%H:%M:%S'
}

# Mask sensitive information in log messages
mask_sensitive_data() {
    local message="$1"
    
    # Mask common sensitive patterns (only if variables are set)
    [[ -n "${NODE_SSH_PASSWORD:-}" ]] && message="${message//$NODE_SSH_PASSWORD/*****masked*****}"
    [[ -n "${MARZBAN_PANEL_PASSWORD:-}" ]] && message="${message//$MARZBAN_PANEL_PASSWORD/*****masked*****}"
    [[ -n "${MARZBAN_TOKEN:-}" ]] && message="${message//$MARZBAN_TOKEN/*****masked*****}"
    [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && message="${message//$TELEGRAM_BOT_TOKEN/*****masked*****}"
    
    # Mask password patterns
    message=$(echo "$message" | sed -E 's/password=[^[:space:]]+/password=*****masked*****/gi')
    message=$(echo "$message" | sed -E 's/token=[^[:space:]]+/token=*****masked*****/gi')
    
    echo "$message"
}

# Rotate log file if needed
rotate_log_file() {
    local log_file="$1"
    
    if [[ -f "$log_file" ]] && [[ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null) -gt $MAX_LOG_SIZE ]]; then
        # Rotate existing log files
        for ((i=MAX_LOG_FILES-1; i>=1; i--)); do
            if [[ -f "${log_file}.${i}" ]]; then
                mv "${log_file}.${i}" "${log_file}.$((i+1))"
            fi
        done
        
        # Move current log to .1
        mv "$log_file" "${log_file}.1"
        
        # Create new log file
        touch "$log_file"
        chmod 644 "$log_file"
    fi
}

# Core logging function
write_log() {
    local level="$1"
    local message="$2"
    local log_to_file="${3:-true}"
    local log_to_console="${4:-true}"
    local log_to_syslog="${5:-true}"
    
    local timestamp
    local short_timestamp
    local masked_message
    local level_name
    local level_icon
    local level_color
    
    timestamp=$(get_timestamp)
    short_timestamp=$(get_short_timestamp)
    masked_message=$(mask_sensitive_data "$message")
    
    # Set level properties
    case "$level" in
        $LOG_LEVEL_SUCCESS)
            level_name="SUCCESS"
            level_icon="✅"
            level_color="$GREEN"
            ;;
        $LOG_LEVEL_ERROR)
            level_name="ERROR"
            level_icon="❌"
            level_color="$RED"
            ;;
        $LOG_LEVEL_WARNING)
            level_name="WARNING"
            level_icon="⚠️ "
            level_color="$YELLOW"
            ;;
        $LOG_LEVEL_INFO)
            level_name="INFO"
            level_icon="ℹ️ "
            level_color="$BLUE"
            ;;
        $LOG_LEVEL_DEBUG)
            level_name="DEBUG"
            level_icon="🐛"
            level_color="$DIM"
            ;;
        *)
            level_name="LOG"
            level_icon="📝"
            level_color="$WHITE"
            ;;
    esac
    
    # Log to console
    if [[ "$log_to_console" == "true" ]] && [[ $level -ge $LOG_LEVEL ]]; then
        echo -e "[$short_timestamp] ${level_color}${level_icon} ${level_name}:${NC} $masked_message"
    fi
    
    # Log to file
    if [[ "$log_to_file" == "true" ]] && [[ -n "${LOGFILE:-}" ]]; then
        rotate_log_file "$LOGFILE"
        echo "[$timestamp] $level_name: $masked_message" >> "$LOGFILE"
    fi
    
    # Log to syslog
    if [[ "$log_to_syslog" == "true" ]]; then
        logger -t "marzban-central-manager" "$level_name: $masked_message"
    fi
}

# ============================================================================
# PUBLIC LOGGING FUNCTIONS
# ============================================================================

# Success log
log_success() {
    write_log $LOG_LEVEL_SUCCESS "$1" "${2:-true}" "${3:-true}" "${4:-true}"
}

# Error log
log_error() {
    write_log $LOG_LEVEL_ERROR "$1" "${2:-true}" "${3:-true}" "${4:-true}"
}

# Warning log
log_warning() {
    write_log $LOG_LEVEL_WARNING "$1" "${2:-true}" "${3:-true}" "${4:-true}"
}

# Info log
log_info() {
    write_log $LOG_LEVEL_INFO "$1" "${2:-true}" "${3:-true}" "${4:-true}"
}

# Debug log
log_debug() {
    write_log $LOG_LEVEL_DEBUG "$1" "${2:-true}" "${3:-true}" "${4:-false}"
}

# Step log (special info with different icon)
log_step() {
    local message="$1"
    local timestamp=$(get_short_timestamp)
    local masked_message=$(mask_sensitive_data "$message")
    
    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $masked_message"
    
    if [[ -n "${LOGFILE:-}" ]]; then
        rotate_log_file "$LOGFILE"
        echo "[$(get_timestamp)] STEP: $masked_message" >> "$LOGFILE"
    fi
    
    logger -t "marzban-central-manager" "STEP: $masked_message"
}

# Prompt log (special log for user prompts)
log_prompt() {
    local message="$1"
    local timestamp=$(get_short_timestamp)
    
    echo -e "[$timestamp] ${CYAN}❓ PROMPT:${NC} $message"
}

# Backup log (special log for backup operations)
log_backup() {
    local message="$1"
    local timestamp=$(get_short_timestamp)
    local masked_message=$(mask_sensitive_data "$message")
    
    echo -e "[$timestamp] ${CYAN}💾 BACKUP:${NC} $masked_message"
    
    if [[ -n "${LOGFILE:-}" ]]; then
        rotate_log_file "$LOGFILE"
        echo "[$(get_timestamp)] BACKUP: $masked_message" >> "$LOGFILE"
    fi
    
    logger -t "marzban-central-manager" "BACKUP: $masked_message"
}

# Sync log (special log for sync operations)
log_sync() {
    local message="$1"
    local timestamp=$(get_short_timestamp)
    local masked_message=$(mask_sensitive_data "$message")
    
    echo -e "[$timestamp] ${PURPLE}🔄 SYNC:${NC} $masked_message"
    
    if [[ -n "${LOGFILE:-}" ]]; then
        rotate_log_file "$LOGFILE"
        echo "[$(get_timestamp)] SYNC: $masked_message" >> "$LOGFILE"
    fi
    
    logger -t "marzban-central-manager" "SYNC: $masked_message"
}

# ============================================================================
# LEGACY COMPATIBILITY FUNCTION
# ============================================================================

# Main log function for backward compatibility
log() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        "SUCCESS") log_success "$message" ;;
        "ERROR") log_error "$message" ;;
        "WARNING") log_warning "$message" ;;
        "INFO") log_info "$message" ;;
        "DEBUG") log_debug "$message" ;;
        "STEP") log_step "$message" ;;
        "PROMPT") log_prompt "$message" ;;
        "BACKUP") log_backup "$message" ;;
        "SYNC") log_sync "$message" ;;
        *) log_info "$message" ;;
    esac
}

# ============================================================================
# LOG MANAGEMENT FUNCTIONS
# ============================================================================

# Set log level
set_log_level() {
    local level="$1"
    
    case "$level" in
        "DEBUG"|"debug"|0) LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        "INFO"|"info"|1) LOG_LEVEL=$LOG_LEVEL_INFO ;;
        "WARNING"|"warning"|2) LOG_LEVEL=$LOG_LEVEL_WARNING ;;
        "ERROR"|"error"|3) LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        *) 
            log_error "Invalid log level: $level"
            return 1
            ;;
    esac
    
    log_info "Log level set to: $level"
}

# Clean old log files
clean_old_logs() {
    local days="${1:-30}"
    local cleaned=0
    
    log_info "Cleaning log files older than $days days..."
    
    # Clean manager logs
    if find /tmp -name "marzban_central_manager_*.log" -mtime +$days -delete 2>/dev/null; then
        cleaned=$((cleaned + 1))
    fi
    
    # Clean rotated logs
    if [[ -n "${LOGFILE:-}" ]]; then
        local log_dir=$(dirname "$LOGFILE")
        local log_base=$(basename "$LOGFILE")
        
        find "$log_dir" -name "${log_base}.*" -mtime +$days -delete 2>/dev/null && cleaned=$((cleaned + 1))
    fi
    
    log_success "Log cleanup completed. $cleaned log sources cleaned."
}

# Get log statistics
get_log_stats() {
    if [[ -z "${LOGFILE:-}" ]] || [[ ! -f "$LOGFILE" ]]; then
        echo "No active log file"
        return 1
    fi
    
    local file_size
    local line_count
    local error_count
    local warning_count
    local success_count
    
    file_size=$(du -h "$LOGFILE" | cut -f1)
    line_count=$(wc -l < "$LOGFILE")
    error_count=$(grep -c "ERROR:" "$LOGFILE" 2>/dev/null || echo "0")
    warning_count=$(grep -c "WARNING:" "$LOGFILE" 2>/dev/null || echo "0")
    success_count=$(grep -c "SUCCESS:" "$LOGFILE" 2>/dev/null || echo "0")
    
    echo "Log File Statistics:"
    echo "  File: $LOGFILE"
    echo "  Size: $file_size"
    echo "  Lines: $line_count"
    echo "  Errors: $error_count"
    echo "  Warnings: $warning_count"
    echo "  Success: $success_count"
}

# Initialize logging system
init_logging() {
    # Create log file if it doesn't exist
    if [[ -n "${LOGFILE:-}" ]]; then
        touch "$LOGFILE" 2>/dev/null || {
            echo "Warning: Cannot create log file: $LOGFILE" >&2
            return 1
        }
        chmod 644 "$LOGFILE"
    fi
    
    log_info "Logging system initialized"
    return 0
}