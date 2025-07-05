#!/bin/bash
# Marzban Central Manager - Subscription API Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# SUBSCRIPTION MANAGEMENT FUNCTIONS
# ============================================================================

# Get user subscription by URL
get_user_subscription() {
    local subscription_url="$1"
    local format="${2:-}"
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL is required"
        return 1
    fi
    
    log_debug "Fetching user subscription from URL"
    
    local curl_args=(
        -s
        -L
        --connect-timeout "$API_CONNECT_TIMEOUT"
        --max-time "$API_MAX_TIME"
        --insecure
    )
    
    # Add format parameter if specified
    if [[ -n "$format" ]]; then
        subscription_url="${subscription_url}?format=${format}"
    fi
    
    local response
    response=$(curl "${curl_args[@]}" "$subscription_url" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$response" ]]; then
        echo "$response"
        return 0
    else
        log_error "Failed to fetch subscription"
        return 1
    fi
}

# Get user subscription info (JSON format)
get_user_subscription_info() {
    local subscription_url="$1"
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL is required"
        return 1
    fi
    
    # Extract base URL and add /info endpoint
    local base_url
    if [[ "$subscription_url" =~ ^(.*)/sub/(.*)$ ]]; then
        base_url="${BASH_REMATCH[1]}/sub/${BASH_REMATCH[2]}/info"
    else
        log_error "Invalid subscription URL format"
        return 1
    fi
    
    log_debug "Fetching subscription info from: $base_url"
    
    local response
    response=$(curl -s -L \
        --connect-timeout "$API_CONNECT_TIMEOUT" \
        --max-time "$API_MAX_TIME" \
        --insecure \
        "$base_url" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$response" | jq empty 2>/dev/null; then
        echo "$response"
        return 0
    else
        log_error "Failed to fetch subscription info"
        log_debug "Response: $response"
        return 1
    fi
}

# Parse subscription URL to extract username
extract_username_from_subscription() {
    local subscription_url="$1"
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL is required"
        return 1
    fi
    
    # Extract JWT token from URL
    if [[ "$subscription_url" =~ /sub/([^/?]+) ]]; then
        local jwt_token="${BASH_REMATCH[1]}"
        
        # Decode JWT payload (base64 decode the middle part)
        local payload
        payload=$(echo "$jwt_token" | cut -d'.' -f2)
        
        # Add padding if needed
        local padding=$((4 - ${#payload} % 4))
        if [[ $padding -ne 4 ]]; then
            payload="${payload}$(printf '%*s' $padding | tr ' ' '=')"
        fi
        
        # Decode and extract username
        local decoded
        decoded=$(echo "$payload" | base64 -d 2>/dev/null)
        
        if [[ $? -eq 0 ]] && echo "$decoded" | jq empty 2>/dev/null; then
            local username
            username=$(echo "$decoded" | jq -r '.sub // empty')
            
            if [[ -n "$username" && "$username" != "null" ]]; then
                echo "$username"
                return 0
            fi
        fi
    fi
    
    log_error "Could not extract username from subscription URL"
    return 1
}

# Validate subscription URL format
validate_subscription_url() {
    local subscription_url="$1"
    
    if [[ -z "$subscription_url" ]]; then
        return 1
    fi
    
    # Check if URL matches expected pattern
    if [[ "$subscription_url" =~ ^https?://[^/]+/sub/[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get subscription configs in different formats
get_subscription_configs() {
    local subscription_url="$1"
    local format="${2:-base64}"
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL is required"
        return 1
    fi
    
    case "$format" in
        "base64"|"")
            get_user_subscription "$subscription_url"
            ;;
        "clash")
            get_user_subscription "$subscription_url" "clash"
            ;;
        "sing-box")
            get_user_subscription "$subscription_url" "sing-box"
            ;;
        "outline")
            get_user_subscription "$subscription_url" "outline"
            ;;
        *)
            log_error "Unsupported format: $format"
            log_info "Supported formats: base64, clash, sing-box, outline"
            return 1
            ;;
    esac
}

# ============================================================================
# SUBSCRIPTION ANALYSIS FUNCTIONS
# ============================================================================

# Analyze subscription info
analyze_subscription_info() {
    local subscription_url="$1"
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL is required"
        return 1
    fi
    
    log_info "Analyzing subscription..."
    
    # Get subscription info
    local sub_info
    sub_info=$(get_user_subscription_info "$subscription_url")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get subscription info"
        return 1
    fi
    
    # Extract username
    local username
    username=$(extract_username_from_subscription "$subscription_url")
    
    if [[ $? -eq 0 ]]; then
        log_info "Username: $username"
    else
        log_warning "Could not extract username from URL"
    fi
    
    # Parse and display info
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║           ${CYAN}Subscription Analysis${NC}           ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    if echo "$sub_info" | jq empty 2>/dev/null; then
        # Extract key information
        local total_usage used_traffic data_limit expire_date status
        
        total_usage=$(echo "$sub_info" | jq -r '.total // 0')
        used_traffic=$(echo "$sub_info" | jq -r '.used_traffic // 0')
        data_limit=$(echo "$sub_info" | jq -r '.data_limit // 0')
        expire_date=$(echo "$sub_info" | jq -r '.expire // null')
        status=$(echo "$sub_info" | jq -r '.status // "unknown"')
        
        # Display formatted information
        echo -e "${BLUE}👤 User Information:${NC}"
        [[ -n "$username" ]] && echo "   Username: $username"
        echo "   Status: $(format_user_status "$status")"
        
        echo -e "\n${BLUE}📊 Usage Statistics:${NC}"
        echo "   Used Traffic: $(format_bytes "$used_traffic")"
        echo "   Total Traffic: $(format_bytes "$total_usage")"
        
        if [[ "$data_limit" != "0" && "$data_limit" != "null" ]]; then
            echo "   Data Limit: $(format_bytes "$data_limit")"
            local usage_percentage
            usage_percentage=$(echo "scale=2; $used_traffic * 100 / $data_limit" | bc 2>/dev/null || echo "0")
            echo "   Usage: ${usage_percentage}%"
        else
            echo "   Data Limit: Unlimited"
        fi
        
        echo -e "\n${BLUE}⏰ Expiration:${NC}"
        if [[ "$expire_date" != "null" && -n "$expire_date" ]]; then
            local expire_timestamp
            expire_timestamp=$(date -d "$expire_date" +%s 2>/dev/null)
            local current_timestamp
            current_timestamp=$(date +%s)
            
            if [[ $expire_timestamp -gt $current_timestamp ]]; then
                local days_left
                days_left=$(( (expire_timestamp - current_timestamp) / 86400 ))
                echo "   Expires: $expire_date ($days_left days left)"
            else
                echo "   Status: ${RED}Expired${NC} ($expire_date)"
            fi
        else
            echo "   Expires: Never"
        fi
        
        # Show links if available
        local links
        links=$(echo "$sub_info" | jq -r '.links // []')
        if [[ "$links" != "[]" && "$links" != "null" ]]; then
            local link_count
            link_count=$(echo "$links" | jq length)
            echo -e "\n${BLUE}🔗 Available Configs:${NC}"
            echo "   Total Configs: $link_count"
        fi
        
    else
        echo "Raw subscription info:"
        echo "$sub_info"
    fi
    
    return 0
}

# Format user status with colors
format_user_status() {
    local status="$1"
    
    case "$status" in
        "active")
            echo "${GREEN}Active${NC}"
            ;;
        "limited")
            echo "${YELLOW}Limited${NC}"
            ;;
        "expired")
            echo "${RED}Expired${NC}"
            ;;
        "disabled")
            echo "${RED}Disabled${NC}"
            ;;
        *)
            echo "${DIM}$status${NC}"
            ;;
    esac
}

# Format bytes to human readable
format_bytes() {
    local bytes="$1"
    
    if [[ -z "$bytes" || "$bytes" == "null" || "$bytes" == "0" ]]; then
        echo "0 B"
        return
    fi
    
    if command_exists numfmt; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        # Fallback calculation
        local units=("B" "KB" "MB" "GB" "TB")
        local size=$bytes
        local unit=0
        
        while [[ $size -gt 1024 && $unit -lt 4 ]]; do
            size=$((size / 1024))
            ((unit++))
        done
        
        echo "${size} ${units[$unit]}"
    fi
}

# ============================================================================
# SUBSCRIPTION TESTING FUNCTIONS
# ============================================================================

# Test subscription accessibility
test_subscription_access() {
    local subscription_url="$1"
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL is required"
        return 1
    fi
    
    log_info "Testing subscription accessibility..."
    
    # Validate URL format
    if ! validate_subscription_url "$subscription_url"; then
        log_error "Invalid subscription URL format"
        return 1
    fi
    
    # Test basic access
    local response
    response=$(curl -s -I \
        --connect-timeout 10 \
        --max-time 20 \
        --insecure \
        "$subscription_url" 2>/dev/null)
    
    local http_code
    http_code=$(echo "$response" | head -1 | grep -o '[0-9]\{3\}')
    
    case "$http_code" in
        "200")
            log_success "Subscription is accessible (HTTP $http_code)"
            ;;
        "404")
            log_error "Subscription not found (HTTP $http_code)"
            return 1
            ;;
        "403")
            log_error "Access forbidden (HTTP $http_code)"
            return 1
            ;;
        "")
            log_error "No response from subscription URL"
            return 1
            ;;
        *)
            log_warning "Unexpected HTTP response: $http_code"
            ;;
    esac
    
    # Test info endpoint
    local info_response
    info_response=$(get_user_subscription_info "$subscription_url" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        log_success "Subscription info endpoint is accessible"
    else
        log_warning "Subscription info endpoint is not accessible"
    fi
    
    return 0
}

# ============================================================================
# INTERACTIVE SUBSCRIPTION MANAGEMENT
# ============================================================================

# Interactive subscription analysis
analyze_subscription_interactive() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Subscription Analysis Tool${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    log_prompt "Enter Subscription URL:"
    read -r subscription_url
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL cannot be empty"
        return 1
    fi
    
    # Test accessibility first
    if test_subscription_access "$subscription_url"; then
        # Perform analysis
        analyze_subscription_info "$subscription_url"
    else
        log_error "Subscription is not accessible"
        return 1
    fi
}

# Download subscription configs
download_subscription_configs() {
    local subscription_url="$1"
    local output_dir="${2:-./subscription_configs}"
    local formats=("base64" "clash" "sing-box")
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL is required"
        return 1
    fi
    
    # Extract username for filename
    local username
    username=$(extract_username_from_subscription "$subscription_url")
    local filename_base="${username:-subscription}"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    log_info "Downloading subscription configs to: $output_dir"
    
    for format in "${formats[@]}"; do
        log_info "Downloading $format format..."
        
        local config_data
        config_data=$(get_subscription_configs "$subscription_url" "$format")
        
        if [[ $? -eq 0 && -n "$config_data" ]]; then
            local output_file="$output_dir/${filename_base}_${format}.txt"
            echo "$config_data" > "$output_file"
            log_success "Saved $format config to: $output_file"
        else
            log_warning "Failed to download $format config"
        fi
    done
    
    log_success "Subscription configs download completed"
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize subscription API module
init_subscription_api() {
    log_debug "Subscription API module initialized"
    return 0
}