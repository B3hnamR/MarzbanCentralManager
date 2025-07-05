#!/bin/bash
# Marzban Central Manager - Template API Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# USER TEMPLATE MANAGEMENT API FUNCTIONS
# ============================================================================

# Get all user templates
get_all_templates() {
    log_debug "Fetching all user templates from API"
    api_get "user-template"
}

# Get specific template by ID
get_template_by_id() {
    local template_id="$1"
    
    if [[ -z "$template_id" ]]; then
        log_error "Template ID is required"
        return 1
    fi
    
    log_debug "Fetching template $template_id from API"
    api_get "user-template/$template_id"
}

# Add new user template
add_template() {
    local template_data="$1"
    
    if [[ -z "$template_data" ]]; then
        log_error "Template data is required"
        return 1
    fi
    
    log_info "Adding new user template..."
    local response
    response=$(api_post "user-template" "$template_data")
    
    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local template_id
        template_id=$(echo "$response" | jq -r .id)
        log_success "Template added successfully with ID: $template_id"
        echo "$response"
        return 0
    else
        log_error "Failed to add template"
        log_debug "API response: $response"
        return 1
    fi
}

# Modify user template
modify_template_by_id() {
    local template_id="$1"
    local template_data="$2"
    
    if [[ -z "$template_id" || -z "$template_data" ]]; then
        log_error "Template ID and template data are required"
        return 1
    fi
    
    log_info "Modifying template $template_id..."
    local response
    response=$(api_put "user-template/$template_id" "$template_data")
    
    if [[ $? -eq 0 ]]; then
        log_success "Template $template_id modified successfully"
        echo "$response"
        return 0
    else
        log_error "Failed to modify template $template_id"
        log_debug "API response: $response"
        return 1
    fi
}

# Delete user template
delete_template_by_id() {
    local template_id="$1"
    
    if [[ -z "$template_id" ]]; then
        log_error "Template ID is required"
        return 1
    fi
    
    log_info "Deleting template $template_id..."
    local response
    response=$(api_delete "user-template/$template_id")
    
    if [[ $? -eq 0 ]]; then
        log_success "Template $template_id deleted successfully"
        return 0
    else
        log_error "Failed to delete template $template_id"
        log_debug "API response: $response"
        return 1
    fi
}

# ============================================================================
# TEMPLATE HELPER FUNCTIONS
# ============================================================================

# Create template JSON data
create_template_json() {
    local name="$1"
    local inbounds="$2"
    local data_limit="${3:-0}"
    local expire_duration="${4:-0}"
    local username_prefix="${5:-}"
    local username_suffix="${6:-}"
    
    if [[ -z "$name" || -z "$inbounds" ]]; then
        log_error "Template name and inbounds are required"
        return 1
    fi
    
    local template_json
    template_json=$(jq -n \
        --arg name "$name" \
        --argjson inbounds "$inbounds" \
        --argjson data_limit "$data_limit" \
        --argjson expire_duration "$expire_duration" \
        --arg username_prefix "$username_prefix" \
        --arg username_suffix "$username_suffix" \
        '{
            name: $name,
            inbounds: $inbounds,
            data_limit: $data_limit,
            expire_duration: $expire_duration,
            username_prefix: ($username_prefix | if . == "" then null else . end),
            username_suffix: ($username_suffix | if . == "" then null else . end)
        }')
    
    echo "$template_json"
}

# List templates in a formatted way
list_templates_formatted() {
    local templates_response
    templates_response=$(get_all_templates)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to fetch templates"
        return 1
    fi
    
    if ! echo "$templates_response" | jq empty 2>/dev/null; then
        log_error "Invalid JSON response from API"
        return 1
    fi
    
    local template_count
    template_count=$(echo "$templates_response" | jq length)
    
    if [[ $template_count -eq 0 ]]; then
        echo "No user templates found"
        return 0
    fi
    
    echo "User Templates ($template_count found):"
    echo "======================================="
    
    echo "$templates_response" | jq -r '.[] | 
        "ID: \(.id)
Name: \(.name)
Data Limit: \(if .data_limit == 0 then "Unlimited" else (.data_limit | tostring) + " bytes" end)
Expire Duration: \(if .expire_duration == 0 then "Never" else (.expire_duration | tostring) + " seconds" end)
Username Prefix: \(.username_prefix // "None")
Username Suffix: \(.username_suffix // "None")
Inbounds: \(.inbounds | to_entries | map("\(.key): \(.value | join(\", \"))") | join(" | "))
---"'
}

# Get template by name
get_template_by_name() {
    local template_name="$1"
    
    if [[ -z "$template_name" ]]; then
        log_error "Template name is required"
        return 1
    fi
    
    local templates_response
    templates_response=$(get_all_templates)
    
    if [[ $? -eq 0 ]] && echo "$templates_response" | jq empty 2>/dev/null; then
        local template
        template=$(echo "$templates_response" | jq -r ".[] | select(.name==\"$template_name\")")
        
        if [[ -n "$template" && "$template" != "null" ]]; then
            echo "$template"
            return 0
        fi
    fi
    
    return 1
}

# Check if template exists
template_exists() {
    local template_name="$1"
    
    if [[ -z "$template_name" ]]; then
        return 1
    fi
    
    get_template_by_name "$template_name" >/dev/null 2>&1
}

# ============================================================================
# INTERACTIVE TEMPLATE MANAGEMENT
# ============================================================================

# Interactive template creation
create_template_interactive() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Create New User Template${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
    
    # Get template name
    log_prompt "Template Name:"
    read -r template_name
    
    if [[ -z "$template_name" ]]; then
        log_error "Template name cannot be empty"
        return 1
    fi
    
    # Check if template already exists
    if template_exists "$template_name"; then
        log_error "Template '$template_name' already exists"
        return 1
    fi
    
    # Get inbounds
    echo -e "\n${YELLOW}Available Inbounds:${NC}"
    local inbounds_response
    inbounds_response=$(get_inbounds 2>/dev/null)
    
    if [[ $? -eq 0 ]] && echo "$inbounds_response" | jq empty 2>/dev/null; then
        echo "$inbounds_response" | jq -r 'to_entries[] | "  \(.key): \(.value.tag)"'
    else
        log_warning "Could not fetch inbounds list"
    fi
    
    echo -e "\n${YELLOW}Enter inbounds configuration (JSON format):${NC}"
    echo -e "${DIM}Example: {\"vmess\": [\"VMess TCP\"], \"vless\": [\"VLESS TCP REALITY\"]}${NC}"
    log_prompt "Inbounds JSON:"
    read -r inbounds_json
    
    # Validate inbounds JSON
    if ! echo "$inbounds_json" | jq empty 2>/dev/null; then
        log_error "Invalid JSON format for inbounds"
        return 1
    fi
    
    # Get data limit
    log_prompt "Data Limit in bytes (0 for unlimited) [default: 0]:"
    read -r data_limit
    data_limit=${data_limit:-0}
    
    # Validate data limit
    if ! [[ "$data_limit" =~ ^[0-9]+$ ]]; then
        log_error "Data limit must be a number"
        return 1
    fi
    
    # Get expire duration
    log_prompt "Expire Duration in seconds (0 for never) [default: 0]:"
    read -r expire_duration
    expire_duration=${expire_duration:-0}
    
    # Validate expire duration
    if ! [[ "$expire_duration" =~ ^[0-9]+$ ]]; then
        log_error "Expire duration must be a number"
        return 1
    fi
    
    # Get username prefix
    log_prompt "Username Prefix (optional):"
    read -r username_prefix
    
    # Get username suffix
    log_prompt "Username Suffix (optional):"
    read -r username_suffix
    
    # Create template
    local template_data
    template_data=$(create_template_json "$template_name" "$inbounds_json" "$data_limit" "$expire_duration" "$username_prefix" "$username_suffix")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create template data"
        return 1
    fi
    
    # Add template via API
    local response
    response=$(add_template "$template_data")
    
    if [[ $? -eq 0 ]]; then
        log_success "Template '$template_name' created successfully"
        echo -e "\n${CYAN}Template Details:${NC}"
        echo "$response" | jq .
        return 0
    else
        log_error "Failed to create template '$template_name'"
        return 1
    fi
}

# Interactive template modification
modify_template_interactive() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║         ${CYAN}Modify User Template${NC}            ║"
    echo -e "${WHITE}╚══════════════��═════════════════════════════╝${NC}\n"
    
    # List existing templates
    list_templates_formatted
    
    # Get template ID
    log_prompt "Enter Template ID to modify:"
    read -r template_id
    
    if [[ -z "$template_id" ]] || ! [[ "$template_id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid template ID"
        return 1
    fi
    
    # Get existing template
    local existing_template
    existing_template=$(get_template_by_id "$template_id")
    
    if [[ $? -ne 0 ]]; then
        log_error "Template with ID $template_id not found"
        return 1
    fi
    
    echo -e "\n${CYAN}Current Template:${NC}"
    echo "$existing_template" | jq .
    
    # Get new values (with current values as defaults)
    local current_name current_data_limit current_expire_duration current_prefix current_suffix
    current_name=$(echo "$existing_template" | jq -r .name)
    current_data_limit=$(echo "$existing_template" | jq -r .data_limit)
    current_expire_duration=$(echo "$existing_template" | jq -r .expire_duration)
    current_prefix=$(echo "$existing_template" | jq -r '.username_prefix // ""')
    current_suffix=$(echo "$existing_template" | jq -r '.username_suffix // ""')
    
    echo -e "\n${YELLOW}Enter new values (press Enter to keep current value):${NC}"
    
    log_prompt "Template Name [current: $current_name]:"
    read -r new_name
    new_name=${new_name:-$current_name}
    
    log_prompt "Data Limit [current: $current_data_limit]:"
    read -r new_data_limit
    new_data_limit=${new_data_limit:-$current_data_limit}
    
    log_prompt "Expire Duration [current: $current_expire_duration]:"
    read -r new_expire_duration
    new_expire_duration=${new_expire_duration:-$current_expire_duration}
    
    log_prompt "Username Prefix [current: $current_prefix]:"
    read -r new_prefix
    new_prefix=${new_prefix:-$current_prefix}
    
    log_prompt "Username Suffix [current: $current_suffix]:"
    read -r new_suffix
    new_suffix=${new_suffix:-$current_suffix}
    
    # Keep existing inbounds (could be enhanced to allow modification)
    local current_inbounds
    current_inbounds=$(echo "$existing_template" | jq .inbounds)
    
    # Create updated template data
    local updated_template
    updated_template=$(create_template_json "$new_name" "$current_inbounds" "$new_data_limit" "$new_expire_duration" "$new_prefix" "$new_suffix")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create updated template data"
        return 1
    fi
    
    # Update template via API
    local response
    response=$(modify_template_by_id "$template_id" "$updated_template")
    
    if [[ $? -eq 0 ]]; then
        log_success "Template updated successfully"
        echo -e "\n${CYAN}Updated Template:${NC}"
        echo "$response" | jq .
        return 0
    else
        log_error "Failed to update template"
        return 1
    fi
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize template API module
init_template_api() {
    log_debug "Template API module initialized"
    return 0
}