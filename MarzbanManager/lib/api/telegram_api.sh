#!/bin/bash
# Marzban Central Manager - Telegram API Module
# Professional Edition v3.0
# Author: behnamrjd

# ============================================================================
# TELEGRAM CONFIGURATION
# ============================================================================

# Notification levels
readonly TELEGRAM_LEVEL_ALL=1
readonly TELEGRAM_LEVEL_HIGH=2
readonly TELEGRAM_LEVEL_CRITICAL=3
readonly TELEGRAM_LEVEL_OFF=4

# API settings
readonly TELEGRAM_API_TIMEOUT=10
readonly TELEGRAM_API_RETRY_COUNT=3
readonly TELEGRAM_API_RETRY_DELAY=2

# Message formatting
readonly TELEGRAM_MAX_MESSAGE_LENGTH=4096

# ============================================================================
# TELEGRAM API FUNCTIONS
# ============================================================================

# Send message to Telegram
send_telegram_message() {
    local message="$1"
    local parse_mode="${2:-HTML}"
    local disable_preview="${3:-true}"
    
    # Check if Telegram is configured
    if ! is_telegram_configured; then
        log_debug "Telegram notifications are not configured"
        return 0
    fi
    
    # Validate message length
    if [[ ${#message} -gt $TELEGRAM_MAX_MESSAGE_LENGTH ]]; then
        log_warning "Telegram message too long, truncating..."
        message="${message:0:$((TELEGRAM_MAX_MESSAGE_LENGTH-50))}...\n\n[Message truncated]"
    fi
    
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local payload
    
    # Create JSON payload
    payload=$(jq -n \
        --arg chat_id "$TELEGRAM_CHAT_ID" \
        --arg text "$message" \
        --arg parse_mode "$parse_mode" \
        --argjson disable_web_page_preview "$disable_preview" \
        '{
            chat_id: $chat_id,
            text: $text,
            parse_mode: $parse_mode,
            disable_web_page_preview: $disable_web_page_preview
        }')
    
    local attempt=1
    local response
    
    while [[ $attempt -le $TELEGRAM_API_RETRY_COUNT ]]; do
        response=$(curl -s -X POST "$api_url" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --connect-timeout "$TELEGRAM_API_TIMEOUT" \
            --max-time "$TELEGRAM_API_TIMEOUT" \
            2>/dev/null)
        
        if [[ $? -eq 0 ]] && echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
            local ok_status
            ok_status=$(echo "$response" | jq -r .ok)
            if [[ "$ok_status" == "true" ]]; then
                log_debug "Telegram message sent successfully"
                return 0
            fi
        fi
        
        log_warning "Telegram message send failed (attempt $attempt/$TELEGRAM_API_RETRY_COUNT)"
        
        if [[ $attempt -lt $TELEGRAM_API_RETRY_COUNT ]]; then
            sleep "$TELEGRAM_API_RETRY_DELAY"
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to send Telegram message after $TELEGRAM_API_RETRY_COUNT attempts"
    log_debug "Last response: $response"
    return 1
}

# Send notification with level filtering
send_telegram_notification() {
    local message="$1"
    local level="${2:-normal}"
    local stored_level
    
    # Load notification level from config
    stored_level=${TELEGRAM_NOTIFICATION_LEVEL:-$TELEGRAM_LEVEL_ALL}
    
    # Check if notifications are enabled and level is appropriate
    if ! is_telegram_configured || [[ $stored_level -eq $TELEGRAM_LEVEL_OFF ]]; then
        log_debug "Telegram notifications are disabled"
        return 0
    fi
    
    # Level filtering
    case "$level" in
        "normal")
            if [[ $stored_level -gt $TELEGRAM_LEVEL_ALL ]]; then
                log_debug "Normal notification filtered out by level setting"
                return 0
            fi
            ;;
        "high")
            if [[ $stored_level -gt $TELEGRAM_LEVEL_HIGH ]]; then
                log_debug "High notification filtered out by level setting"
                return 0
            fi
            ;;
        "critical")
            if [[ $stored_level -gt $TELEGRAM_LEVEL_CRITICAL ]]; then
                log_debug "Critical notification filtered out by level setting"
                return 0
            fi
            ;;
    esac
    
    # Add timestamp and hostname to message
    local hostname=$(hostname 2>/dev/null || echo "Unknown")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local formatted_message="🤖 <b>Marzban Central Manager</b>%0A%0A${message}%0A%0A📅 ${timestamp}%0A🖥️ ${hostname}"
    
    # Send the message in background to avoid blocking
    send_telegram_message "$formatted_message" &
}

# ============================================================================
# TELEGRAM CONFIGURATION FUNCTIONS
# ============================================================================

# Configure Telegram notifications
configure_telegram_notifications() {
    log_step "Configuring Telegram Notifications..."
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║       ${CYAN}Telegram Notifications Setup${NC}       ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}To set up Telegram notifications, you need:${NC}"
    echo "1. A Telegram bot token (from @BotFather)"
    echo "2. Your chat ID (from @userinfobot or API)"
    echo ""
    
    # Get bot token
    log_prompt "Enter Telegram Bot Token:"
    read -r bot_token
    
    if [[ -z "$bot_token" ]]; then
        log_error "Bot token is required"
        return 1
    fi
    
    # Get chat ID
    log_prompt "Enter Telegram Chat ID:"
    read -r chat_id
    
    if [[ -z "$chat_id" ]]; then
        log_error "Chat ID is required"
        return 1
    fi
    
    # Test the configuration
    log_info "Testing Telegram configuration..."
    
    # Temporarily set variables for testing
    local old_token="$TELEGRAM_BOT_TOKEN"
    local old_chat_id="$TELEGRAM_CHAT_ID"
    
    TELEGRAM_BOT_TOKEN="$bot_token"
    TELEGRAM_CHAT_ID="$chat_id"
    
    if send_telegram_message "🎉 Telegram notifications configured successfully!%0A%0AThis is a test message from Marzban Central Manager."; then
        log_success "Telegram test message sent successfully!"
        
        # Configure notification level
        configure_notification_level
        
        # Save configuration
        set_config_value "TELEGRAM_BOT_TOKEN" "$bot_token"
        set_config_value "TELEGRAM_CHAT_ID" "$chat_id"
        
        log_success "Telegram notifications configured and saved"
        return 0
    else
        log_error "Failed to send test message. Please check your bot token and chat ID"
        
        # Restore old values
        TELEGRAM_BOT_TOKEN="$old_token"
        TELEGRAM_CHAT_ID="$old_chat_id"
        return 1
    fi
}

# Configure notification level
configure_notification_level() {
    echo -e "\n${PURPLE}Notification Level Configuration:${NC}"
    echo " 1. All notifications (normal, high, critical)"
    echo " 2. High and critical only"
    echo " 3. Critical only"
    echo " 4. Disable notifications"
    echo ""
    
    log_prompt "Choose notification level [1-4]:"
    read -r level_choice
    
    case "$level_choice" in
        1)
            TELEGRAM_NOTIFICATION_LEVEL=$TELEGRAM_LEVEL_ALL
            set_config_value "TELEGRAM_NOTIFICATION_LEVEL" "$TELEGRAM_LEVEL_ALL"
            log_info "Notification level set to: All notifications"
            ;;
        2)
            TELEGRAM_NOTIFICATION_LEVEL=$TELEGRAM_LEVEL_HIGH
            set_config_value "TELEGRAM_NOTIFICATION_LEVEL" "$TELEGRAM_LEVEL_HIGH"
            log_info "Notification level set to: High and critical only"
            ;;
        3)
            TELEGRAM_NOTIFICATION_LEVEL=$TELEGRAM_LEVEL_CRITICAL
            set_config_value "TELEGRAM_NOTIFICATION_LEVEL" "$TELEGRAM_LEVEL_CRITICAL"
            log_info "Notification level set to: Critical only"
            ;;
        4)
            TELEGRAM_NOTIFICATION_LEVEL=$TELEGRAM_LEVEL_OFF
            set_config_value "TELEGRAM_NOTIFICATION_LEVEL" "$TELEGRAM_LEVEL_OFF"
            log_info "Notification level set to: Disabled"
            ;;
        *)
            log_warning "Invalid choice, defaulting to all notifications"
            TELEGRAM_NOTIFICATION_LEVEL=$TELEGRAM_LEVEL_ALL
            set_config_value "TELEGRAM_NOTIFICATION_LEVEL" "$TELEGRAM_LEVEL_ALL"
            ;;
    esac
}

# Show Telegram status
show_telegram_status() {
    echo -e "\n${WHITE}╔═════════════════════════════════��══════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Telegram Notifications Status${NC}      ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    if is_telegram_configured; then
        echo -e "${GREEN}✅ Telegram Status: Configured${NC}"
        echo -e "${BLUE}🤖 Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}...${NC}"
        echo -e "${BLUE}💬 Chat ID: ${TELEGRAM_CHAT_ID}${NC}"
        
        # Show notification level
        local level_text
        case "${TELEGRAM_NOTIFICATION_LEVEL:-$TELEGRAM_LEVEL_ALL}" in
            $TELEGRAM_LEVEL_ALL) level_text="All notifications" ;;
            $TELEGRAM_LEVEL_HIGH) level_text="High and critical only" ;;
            $TELEGRAM_LEVEL_CRITICAL) level_text="Critical only" ;;
            $TELEGRAM_LEVEL_OFF) level_text="Disabled" ;;
            *) level_text="Unknown" ;;
        esac
        echo -e "${BLUE}📊 Level: $level_text${NC}"
        
        # Test connection
        echo -e "${BLUE}🔗 Testing connection...${NC}"
        if send_telegram_message "🔍 Connection test from Marzban Central Manager"; then
            echo -e "${GREEN}✅ Connection: Active${NC}"
        else
            echo -e "${RED}❌ Connection: Failed${NC}"
        fi
    else
        echo -e "${RED}❌ Telegram Status: Not Configured${NC}"
        echo -e "${YELLOW}⚠️  Configure Telegram to receive notifications${NC}"
    fi
    echo ""
}

# ============================================================================
# TELEGRAM UTILITY FUNCTIONS
# ============================================================================

# Get bot information
get_bot_info() {
    if ! is_telegram_configured; then
        log_error "Telegram is not configured"
        return 1
    fi
    
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
    local response
    
    response=$(curl -s -X GET "$api_url" \
        --connect-timeout "$TELEGRAM_API_TIMEOUT" \
        --max-time "$TELEGRAM_API_TIMEOUT" \
        2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
        echo "$response" | jq -r '.result'
        return 0
    fi
    
    return 1
}

# Get chat information
get_chat_info() {
    if ! is_telegram_configured; then
        log_error "Telegram is not configured"
        return 1
    fi
    
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getChat"
    local response
    
    response=$(curl -s -X GET "$api_url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --connect-timeout "$TELEGRAM_API_TIMEOUT" \
        --max-time "$TELEGRAM_API_TIMEOUT" \
        2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
        echo "$response" | jq -r '.result'
        return 0
    fi
    
    return 1
}

# Send formatted system status
send_system_status() {
    local status_message=""
    
    # System information
    status_message+="📊 <b>System Status Report</b>%0A%0A"
    
    # Server info
    local hostname=$(hostname 2>/dev/null || echo "Unknown")
    local uptime=$(uptime -p 2>/dev/null || echo "Unknown")
    status_message+="🖥️ <b>Server:</b> $hostname%0A"
    status_message+="⏱️ <b>Uptime:</b> $uptime%0A%0A"
    
    # Memory usage
    if command_exists free; then
        local memory_info=$(free -h | awk '/^Mem:/ {printf "Used: %s / %s (%.1f%%)", $3, $2, ($3/$2)*100}')
        status_message+="💾 <b>Memory:</b> $memory_info%0A"
    fi
    
    # Disk usage
    if command_exists df; then
        local disk_info=$(df -h / | awk 'NR==2 {printf "Used: %s / %s (%s)", $3, $2, $5}')
        status_message+="💿 <b>Disk:</b> $disk_info%0A"
    fi
    
    # Load average
    if [[ -f /proc/loadavg ]]; then
        local load_avg=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
        status_message+="📈 <b>Load:</b> $load_avg%0A%0A"
    fi
    
    # Service status
    status_message+="🔧 <b>Services:</b>%0A"
    
    # Docker status
    if command_exists docker; then
        if docker info >/dev/null 2>&1; then
            status_message+="✅ Docker: Running%0A"
        else
            status_message+="❌ Docker: Not running%0A"
        fi
    fi
    
    # Nginx status
    if command_exists systemctl && systemctl is-active --quiet nginx 2>/dev/null; then
        status_message+="✅ Nginx: Running%0A"
    elif command_exists nginx; then
        status_message+="❌ Nginx: Not running%0A"
    fi
    
    # HAProxy status
    if command_exists systemctl && systemctl is-active --quiet haproxy 2>/dev/null; then
        status_message+="✅ HAProxy: Running%0A"
    elif command_exists haproxy; then
        status_message+="❌ HAProxy: Not running%0A"
    fi
    
    send_telegram_notification "$status_message" "normal"
}

# Send backup notification
send_backup_notification() {
    local backup_type="$1"
    local backup_file="$2"
    local backup_size="$3"
    local status="$4"
    
    local message=""
    
    if [[ "$status" == "success" ]]; then
        message+="💾 <b>Backup Completed Successfully</b>%0A%0A"
        message+="📁 <b>Type:</b> $backup_type%0A"
        message+="📄 <b>File:</b> $(basename "$backup_file")%0A"
        message+="📊 <b>Size:</b> $backup_size%0A"
    else
        message+="🚨 <b>Backup Failed</b>%0A%0A"
        message+="📁 <b>Type:</b> $backup_type%0A"
        message+="❌ <b>Error:</b> Backup process failed%0A"
    fi
    
    local level="normal"
    [[ "$status" != "success" ]] && level="high"
    
    send_telegram_notification "$message" "$level"
}

# Send node status notification
send_node_status_notification() {
    local node_name="$1"
    local node_ip="$2"
    local status="$3"
    local details="${4:-}"
    
    local message=""
    local level="normal"
    
    case "$status" in
        "online")
            message+="✅ <b>Node Online</b>%0A%0A"
            message+="🖥️ <b>Node:</b> $node_name%0A"
            message+="🌐 <b>IP:</b> $node_ip%0A"
            ;;
        "offline")
            message+="🔴 <b>Node Offline</b>%0A%0A"
            message+="🖥️ <b>Node:</b> $node_name%0A"
            message+="🌐 <b>IP:</b> $node_ip%0A"
            level="high"
            ;;
        "error")
            message+="🚨 <b>Node Error</b>%0A%0A"
            message+="🖥️ <b>Node:</b> $node_name%0A"
            message+="🌐 <b>IP:</b> $node_ip%0A"
            level="critical"
            ;;
    esac
    
    if [[ -n "$details" ]]; then
        message+="📝 <b>Details:</b> $details%0A"
    fi
    
    send_telegram_notification "$message" "$level"
}

# ============================================================================
# TELEGRAM MANAGEMENT FUNCTIONS
# ============================================================================

# Disable Telegram notifications
disable_telegram_notifications() {
    log_info "Disabling Telegram notifications..."
    
    TELEGRAM_NOTIFICATION_LEVEL=$TELEGRAM_LEVEL_OFF
    set_config_value "TELEGRAM_NOTIFICATION_LEVEL" "$TELEGRAM_LEVEL_OFF"
    
    log_success "Telegram notifications disabled"
}

# Enable Telegram notifications
enable_telegram_notifications() {
    log_info "Enabling Telegram notifications..."
    
    if ! is_telegram_configured; then
        log_error "Telegram is not configured. Please configure it first."
        return 1
    fi
    
    TELEGRAM_NOTIFICATION_LEVEL=$TELEGRAM_LEVEL_ALL
    set_config_value "TELEGRAM_NOTIFICATION_LEVEL" "$TELEGRAM_LEVEL_ALL"
    
    log_success "Telegram notifications enabled"
    send_telegram_notification "🔔 Telegram notifications have been enabled" "normal"
}

# Test Telegram configuration
test_telegram_config() {
    if ! is_telegram_configured; then
        log_error "Telegram is not configured"
        return 1
    fi
    
    log_info "Testing Telegram configuration..."
    
    if send_telegram_message "🧪 This is a test message from Marzban Central Manager%0A%0A✅ If you receive this message, Telegram notifications are working correctly!"; then
        log_success "Telegram test message sent successfully"
        return 0
    else
        log_error "Failed to send Telegram test message"
        return 1
    fi
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize Telegram API module
init_telegram_api() {
    log_debug "Telegram API module initialized"
    return 0
}