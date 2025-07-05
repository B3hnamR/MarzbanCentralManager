#!/bin/bash
# Marzban Central Manager - Professional Edition v3.1
# Enhanced Modular Architecture
# Author: B3hnamR

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

# Enhanced error handling and strict mode
set -euo pipefail
IFS=$'\n\t'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# ============================================================================
# MODULE LOADING SYSTEM
# ============================================================================

# Load a module with error handling
load_module() {
    local module_path="$1"
    local module_name="$(basename "$module_path" .sh)"
    
    if [[ -f "$module_path" ]]; then
        if source "$module_path"; then
            echo "✅ Loaded module: $module_name"
            return 0
        else
            echo "❌ Failed to load module: $module_name" >&2
            return 1
        fi
    else
        echo "❌ Module not found: $module_path" >&2
        return 1
    fi
}

# Load all required modules
load_all_modules() {
    echo "🔧 Loading Marzban Central Manager modules..."
    
    # Core modules (order matters)
    local core_modules=(
        "$LIB_DIR/core/config.sh"
        "$LIB_DIR/core/logger.sh"
        "$LIB_DIR/core/utils.sh"
        "$LIB_DIR/core/dependencies.sh"
    )
    
    # API modules
    local api_modules=(
        "$LIB_DIR/api/marzban_api.sh"
        "$LIB_DIR/api/telegram_api.sh"
        "$LIB_DIR/api/template_api.sh"
        "$LIB_DIR/api/subscription_api.sh"
    )
    
    # Node management modules
    local node_modules=(
        "$LIB_DIR/nodes/ssh_operations.sh"
        "$LIB_DIR/nodes/node_manager.sh"
    )
    
    # Backup modules
    local backup_modules=(
        "$LIB_DIR/backup/backup_manager.sh"
    )
    
    # Load modules in order
    local all_modules=("${core_modules[@]}" "${api_modules[@]}" "${node_modules[@]}" "${backup_modules[@]}")
    
    for module in "${all_modules[@]}"; do
        if ! load_module "$module"; then
            echo "❌ Critical error: Failed to load required module: $module" >&2
            exit 1
        fi
    done
    
    echo "✅ All modules loaded successfully"
}

# ============================================================================
# INITIALIZATION FUNCTIONS
# ============================================================================

# Initialize all systems
initialize_system() {
    echo "🚀 Initializing Marzban Central Manager..."
    
    # Initialize configuration
    if ! init_config; then
        echo "❌ Failed to initialize configuration" >&2
        exit 1
    fi
    
    # Initialize logging
    if ! init_logging; then
        echo "❌ Failed to initialize logging system" >&2
        exit 1
    fi
    
    # Initialize utilities
    if ! init_utils; then
        log_error "Failed to initialize utilities"
        exit 1
    fi
    
    # Initialize dependencies
    if ! init_dependencies; then
        log_error "Failed to initialize dependencies"
        exit 1
    fi
    
    # Initialize API modules
    if ! init_marzban_api; then
        log_error "Failed to initialize Marzban API"
        exit 1
    fi
    
    if ! init_telegram_api; then
        log_error "Failed to initialize Telegram API"
        exit 1
    fi
    
    if ! init_template_api; then
        log_error "Failed to initialize Template API"
        exit 1
    fi
    
    if ! init_subscription_api; then
        log_error "Failed to initialize Subscription API"
        exit 1
    fi
    
    # Initialize SSH operations
    if ! init_ssh_operations; then
        log_warning "SSH operations initialization had issues"
    fi
    
    # Initialize node manager
    if ! init_node_manager; then
        log_error "Failed to initialize node manager"
        exit 1
    fi
    
    # Initialize backup manager
    if ! init_backup_manager; then
        log_error "Failed to initialize backup manager"
        exit 1
    fi
    
    log_success "System initialization completed"
}

# Check system requirements (silent mode with error reporting)
check_system_requirements() {
    local issues_found=false
    
    # Check if running as root
    if ! is_root; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check dependencies silently
    if ! check_all_dependencies >/dev/null 2>&1; then
        issues_found=true
        log_warning "Some dependencies are missing"
        log_prompt "Would you like to install missing dependencies? (y/n):"
        read -r install_deps
        
        if [[ "$install_deps" =~ ^[Yy]$ ]]; then
            log_info "Installing missing dependencies..."
            if ! install_all_dependencies; then
                log_error "Failed to install dependencies"
                exit 1
            fi
            log_success "Dependencies installed successfully"
        else
            log_warning "Continuing with missing dependencies - some features may not work"
        fi
    fi
    
    # Detect services silently
    if ! detect_main_server_services >/dev/null 2>&1; then
        issues_found=true
        log_warning "Service detection completed with warnings"
    fi
    
    # Only show success message if there were issues
    if [[ "$issues_found" == "true" ]]; then
        log_success "System requirements check completed"
    fi
    
    return 0
}

# ============================================================================
# LOCK MANAGEMENT
# ============================================================================

# Acquire script lock
acquire_script_lock() {
    if ! acquire_lock_with_timeout "$LOCKFILE" 60; then
        log_error "Another instance is already running or failed to acquire lock"
        exit 1
    fi
    
    # Setup cleanup on exit
    trap 'release_lock "$LOCKFILE"; log_info "Script lock released"' EXIT
    trap 'log_error "Script interrupted"; exit 1' INT TERM
    
    log_debug "Script lock acquired"
}

# ============================================================================
# MAIN MENU SYSTEM
# ============================================================================

# Display main menu
show_main_menu() {
    clear
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}Marzban Central Manager v3.1${NC}                ║"
    echo -e "${WHITE}║                  ${GREEN}Professional Edition${NC}                    ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Show system status
    show_system_status
    
    echo -e "\n${PURPLE}📋 Node Management:${NC}"
    echo " 1.  Add New Node"
    echo " 2.  Import Existing Node"
    echo " 3.  List All Nodes"
    echo " 4.  Update Node Configuration"
    echo " 5.  Remove Node"
    echo " 6.  Monitor Node Health"
    
    echo -e "\n${PURPLE}🔧 System Operations:${NC}"
    echo " 7.  Sync HAProxy Configuration"
    echo " 8.  Update All Node Certificates"
    echo " 9.  Restart All Node Services"
    echo " 10. Update Geo Files"
    
    echo -e "\n${PURPLE}💾 Backup & Restore:${NC}"
    echo " 11. Create Full Backup"
    echo " 12. Create Main Server Backup"
    echo " 13. Create Nodes Backup"
    echo " 14. List Available Backups"
    echo " 15. Setup Automated Backup"
    
    echo -e "\n${PURPLE}⚙️  Configuration:${NC}"
    echo " 16. Configure Marzban API"
    echo " 17. Configure Telegram Notifications"
    echo " 18. Show API Status"
    echo " 19. Show Telegram Status"
    echo " 20. Dependency Status"
    
    echo -e "\n${PURPLE}🔍 Monitoring & Logs:${NC}"
    echo " 21. Start Continuous Monitoring"
    echo " 22. View System Logs"
    echo " 23. Clean Old Logs"
    echo " 24. System Information"
    
    echo -e "\n${PURPLE}👥 User Management:${NC}"
    echo " 25. List All Users"
    echo " 26. Add New User"
    echo " 27. Modify User"
    echo " 28. Delete User"
    echo " 29. Reset User Data Usage"
    
    echo -e "\n${PURPLE}📋 Template Management:${NC}"
    echo " 30. List User Templates"
    echo " 31. Create User Template"
    echo " 32. Modify User Template"
    echo " 33. Delete User Template"
    
    echo -e "\n${PURPLE}📱 Subscription Tools:${NC}"
    echo " 34. Analyze Subscription"
    echo " 35. Test Subscription Access"
    echo " 36. Download Subscription Configs"
    
    echo -e "\n${PURPLE}🛠️  Advanced:${NC}"
    echo " 37. Nginx Management"
    echo " 38. HAProxy Management"
    echo " 39. Bulk Operations"
    echo " 40. Import/Export Configuration"
    
    echo -e "\n 41. ${RED}Exit${NC}"
    echo ""
}

# Show system status
show_system_status() {
    local node_count
    node_count=$(get_node_count 2>/dev/null || echo "0")
    
    echo -e "${BLUE}📊 System Status:${NC}"
    echo -e "   Nodes: $node_count configured"
    echo -e "   API: $(is_api_configured && echo "${GREEN}Configured${NC}" || echo "${RED}Not configured${NC}")"
    echo -e "   Telegram: $(is_telegram_configured && echo "${GREEN}Configured${NC}" || echo "${RED}Not configured${NC}")"
    echo -e "   Auto Backup: $([ "${AUTO_BACKUP_ENABLED:-false}" == "true" ] && echo "${GREEN}Enabled${NC}" || echo "${RED}Disabled${NC}")"
}

# ============================================================================
# MENU HANDLERS
# ============================================================================

# Handle menu selection
handle_menu_selection() {
    local choice="$1"
    
    case "$choice" in
        1) handle_add_new_node ;;
        2) handle_import_existing_node ;;
        3) handle_list_all_nodes ;;
        4) handle_update_node_config ;;
        5) handle_remove_node ;;
        6) handle_monitor_node_health ;;
        7) handle_sync_haproxy ;;
        8) handle_update_certificates ;;
        9) handle_restart_services ;;
        10) handle_update_geo_files ;;
        11) handle_create_full_backup ;;
        12) handle_create_main_backup ;;
        13) handle_create_nodes_backup ;;
        14) handle_list_backups ;;
        15) handle_setup_automated_backup ;;
        16) handle_configure_api ;;
        17) handle_configure_telegram ;;
        18) handle_show_api_status ;;
        19) handle_show_telegram_status ;;
        20) handle_dependency_status ;;
        21) handle_continuous_monitoring ;;
        22) handle_view_logs ;;
        23) handle_clean_logs ;;
        24) handle_system_info ;;
        25) handle_list_users ;;
        26) handle_add_user ;;
        27) handle_modify_user ;;
        28) handle_delete_user ;;
        29) handle_reset_user_data ;;
        30) handle_list_templates ;;
        31) handle_create_template ;;
        32) handle_modify_template ;;
        33) handle_delete_template ;;
        34) handle_analyze_subscription ;;
        35) handle_test_subscription ;;
        36) handle_download_subscription ;;
        37) handle_nginx_management ;;
        38) handle_haproxy_management ;;
        39) handle_bulk_operations ;;
        40) handle_import_export ;;
        41) handle_exit ;;
        *) 
            log_error "Invalid option: $choice"
            return 1
            ;;
    esac
}

# Node management handlers
handle_add_new_node() {
    log_step "Adding new node..."
    
    local node_name node_ip node_user="root" node_port="22" node_domain node_password
    
    log_prompt "Enter Node Name:"
    read -r node_name
    
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log_error "Node '$node_name' already exists"
        return 1
    fi
    
    log_prompt "Enter Node IP:"
    read -r node_ip
    
    if ! is_valid_ip "$node_ip"; then
        log_error "Invalid IP address"
        return 1
    fi
    
    log_prompt "Enter SSH Username [default: root]:"
    read -r node_user_input
    node_user=${node_user_input:-$node_user}
    
    log_prompt "Enter SSH Port [default: 22]:"
    read -r node_port_input
    node_port=${node_port_input:-$node_port}
    
    if ! is_valid_port "$node_port"; then
        log_error "Invalid port number"
        return 1
    fi
    
    log_prompt "Enter Node Domain:"
    read -r node_domain
    
    if ! is_valid_domain "$node_domain"; then
        log_error "Invalid domain name"
        return 1
    fi
    
    log_prompt "Enter SSH Password:"
    read -s node_password
    echo ""
    
    if is_empty "$node_password"; then
        log_error "Password cannot be empty"
        return 1
    fi
    
    # Deploy the node
    if deploy_new_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
        log_success "Node '$node_name' added successfully"
    else
        log_error "Failed to add node '$node_name'"
        return 1
    fi
}

handle_import_existing_node() {
    log_step "Importing existing node..."
    
    local node_name node_ip node_user="root" node_port="22" node_domain node_password
    
    log_prompt "Enter Node Name:"
    read -r node_name
    
    if get_node_config_by_name "$node_name" >/dev/null 2>&1; then
        log_error "Node '$node_name' already exists"
        return 1
    fi
    
    log_prompt "Enter Node IP:"
    read -r node_ip
    
    log_prompt "Enter SSH Username [default: root]:"
    read -r node_user_input
    node_user=${node_user_input:-$node_user}
    
    log_prompt "Enter SSH Port [default: 22]:"
    read -r node_port_input
    node_port=${node_port_input:-$node_port}
    
    log_prompt "Enter Node Domain:"
    read -r node_domain
    
    log_prompt "Enter SSH Password:"
    read -s node_password
    echo ""
    
    # Import the node
    if import_existing_node "$node_name" "$node_ip" "$node_user" "$node_port" "$node_domain" "$node_password"; then
        log_success "Node '$node_name' imported successfully"
    else
        log_error "Failed to import node '$node_name'"
        return 1
    fi
}

handle_list_all_nodes() {
    list_configured_nodes
}

handle_update_node_config() {
    log_info "Node configuration update feature coming soon..."
    # TODO: Implement node configuration update
}

handle_remove_node() {
    load_nodes_config
    
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        log_warning "No nodes configured to remove"
        return 0
    fi
    
    echo -e "\n${PURPLE}Available Nodes:${NC}"
    local i=1
    for entry in "${NODES_ARRAY[@]}"; do
        IFS=';' read -r name ip user port domain password node_id <<< "$entry"
        echo " $i. $name ($ip) - $domain"
        ((i++))
    done
    echo ""
    
    log_prompt "Select node to remove (number):"
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#NODES_ARRAY[@]} ]]; then
        log_error "Invalid selection"
        return 1
    fi
    
    local selected_index=$((selection - 1))
    local node_entry="${NODES_ARRAY[$selected_index]}"
    IFS=';' read -r name ip user port domain password node_id <<< "$node_entry"
    
    if remove_node_completely "$name"; then
        log_success "Node '$name' removed successfully"
    else
        log_error "Failed to remove node '$name'"
        return 1
    fi
}

handle_monitor_node_health() {
    monitor_all_nodes_health
}

# System operation handlers
handle_sync_haproxy() {
    log_info "HAProxy sync feature coming soon..."
    # TODO: Implement HAProxy sync
}

handle_update_certificates() {
    update_all_node_certificates
}

handle_restart_services() {
    log_info "Service restart feature coming soon..."
    # TODO: Implement service restart
}

handle_update_geo_files() {
    log_info "Geo files update feature coming soon..."
    # TODO: Implement geo files update
}

# Backup handlers
handle_create_full_backup() {
    create_full_backup
}

handle_create_main_backup() {
    create_main_server_backup
}

handle_create_nodes_backup() {
    create_nodes_backup
}

handle_list_backups() {
    list_available_backups
}

handle_setup_automated_backup() {
    setup_automated_backup
}

# Configuration handlers
handle_configure_api() {
    configure_marzban_api
}

handle_configure_telegram() {
    configure_telegram_notifications
}

handle_show_api_status() {
    show_api_status
}

handle_show_telegram_status() {
    show_telegram_status
}

handle_dependency_status() {
    get_dependency_status
}

# Monitoring handlers
handle_continuous_monitoring() {
    log_info "Continuous monitoring feature coming soon..."
    # TODO: Implement continuous monitoring
}

handle_view_logs() {
    if [[ -f "$LOGFILE" ]]; then
        echo -e "\n${CYAN}Recent log entries:${NC}"
        tail -50 "$LOGFILE"
    else
        log_info "No log file found"
    fi
}

handle_clean_logs() {
    clean_old_logs
}

handle_system_info() {
    echo -e "\n${CYAN}System Information:${NC}"
    get_system_info
    echo ""
    get_backup_statistics
}

# User management handlers
handle_list_users() {
    if ! ensure_api_configured; then
        return 1
    fi
    
    log_step "Fetching all users..."
    local users_response
    users_response=$(get_all_users)
    
    if [[ $? -eq 0 ]] && echo "$users_response" | jq empty 2>/dev/null; then
        local user_count
        user_count=$(echo "$users_response" | jq length)
        
        echo -e "\n${WHITE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║            ${CYAN}Users List ($user_count users)${NC}            ║"
        echo -e "${WHITE}╚════════════════════════════════════════════╝${NC}\n"
        
        if [[ $user_count -eq 0 ]]; then
            echo "No users found"
        else
            echo "$users_response" | jq -r '.[] | 
                "Username: \(.username)
Status: \(.status)
Data Limit: \(if .data_limit == 0 then "Unlimited" else (.data_limit | tostring) + " bytes" end)
Used Traffic: \(.used_traffic // 0) bytes
Created: \(.created_at // "Unknown")
---"'
        fi
    else
        log_error "Failed to fetch users list"
        return 1
    fi
}

handle_add_user() {
    log_info "User creation feature coming soon..."
    log_info "This will include interactive user creation with templates"
}

handle_modify_user() {
    log_info "User modification feature coming soon..."
    log_info "This will include interactive user editing"
}

handle_delete_user() {
    if ! ensure_api_configured; then
        return 1
    fi
    
    log_prompt "Enter username to delete:"
    read -r username
    
    if [[ -z "$username" ]]; then
        log_error "Username cannot be empty"
        return 1
    fi
    
    # Confirm deletion
    log_prompt "Are you sure you want to delete user '$username'? (yes/no):"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "User deletion cancelled"
        return 0
    fi
    
    if delete_user "$username"; then
        log_success "User '$username' deleted successfully"
    else
        log_error "Failed to delete user '$username'"
        return 1
    fi
}

handle_reset_user_data() {
    if ! ensure_api_configured; then
        return 1
    fi
    
    echo -e "\n${YELLOW}Reset User Data Usage:${NC}"
    echo "1. Reset specific user"
    echo "2. Reset all users"
    echo ""
    
    log_prompt "Choose option:"
    read -r reset_option
    
    case "$reset_option" in
        1)
            log_prompt "Enter username:"
            read -r username
            
            if [[ -z "$username" ]]; then
                log_error "Username cannot be empty"
                return 1
            fi
            
            if reset_user_data_usage "$username"; then
                log_success "Data usage reset for user '$username'"
            else
                log_error "Failed to reset data usage for user '$username'"
                return 1
            fi
            ;;
        2)
            log_prompt "Are you sure you want to reset data usage for ALL users? (yes/no):"
            read -r confirmation
            
            if [[ "$confirmation" != "yes" ]]; then
                log_info "Operation cancelled"
                return 0
            fi
            
            if reset_all_users_data_usage; then
                log_success "Data usage reset for all users"
            else
                log_error "Failed to reset data usage for all users"
                return 1
            fi
            ;;
        *)
            log_error "Invalid option"
            return 1
            ;;
    esac
}

# Template management handlers
handle_list_templates() {
    if ! ensure_api_configured; then
        return 1
    fi
    
    log_step "Fetching user templates..."
    list_templates_formatted
}

handle_create_template() {
    if ! ensure_api_configured; then
        return 1
    fi
    
    create_template_interactive
}

handle_modify_template() {
    if ! ensure_api_configured; then
        return 1
    fi
    
    modify_template_interactive
}

handle_delete_template() {
    if ! ensure_api_configured; then
        return 1
    fi
    
    # List templates first
    list_templates_formatted
    
    log_prompt "Enter Template ID to delete:"
    read -r template_id
    
    if [[ -z "$template_id" ]] || ! [[ "$template_id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid template ID"
        return 1
    fi
    
    # Confirm deletion
    log_prompt "Are you sure you want to delete template ID $template_id? (yes/no):"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Template deletion cancelled"
        return 0
    fi
    
    if delete_template_by_id "$template_id"; then
        log_success "Template deleted successfully"
    else
        log_error "Failed to delete template"
        return 1
    fi
}

# Subscription management handlers
handle_analyze_subscription() {
    analyze_subscription_interactive
}

handle_test_subscription() {
    log_prompt "Enter Subscription URL to test:"
    read -r subscription_url
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL cannot be empty"
        return 1
    fi
    
    test_subscription_access "$subscription_url"
}

handle_download_subscription() {
    log_prompt "Enter Subscription URL:"
    read -r subscription_url
    
    if [[ -z "$subscription_url" ]]; then
        log_error "Subscription URL cannot be empty"
        return 1
    fi
    
    log_prompt "Enter output directory [default: ./subscription_configs]:"
    read -r output_dir
    output_dir=${output_dir:-./subscription_configs}
    
    download_subscription_configs "$subscription_url" "$output_dir"
}

# Advanced handlers
handle_nginx_management() {
    log_info "Nginx management feature coming soon..."
    # TODO: Implement Nginx management
}

handle_haproxy_management() {
    log_info "HAProxy management feature coming soon..."
    # TODO: Implement HAProxy management
}

handle_bulk_operations() {
    log_info "Bulk operations feature coming soon..."
    # TODO: Implement bulk operations
}

handle_import_export() {
    log_info "Import/Export feature coming soon..."
    # TODO: Implement import/export
}

handle_exit() {
    log_info "Exiting Marzban Central Manager..."
    exit 0
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup-full)
                create_full_backup
                exit $?
                ;;
            --backup-main)
                create_main_server_backup
                exit $?
                ;;
            --backup-nodes)
                create_nodes_backup
                exit $?
                ;;
            --monitor-health)
                monitor_all_nodes_health
                exit $?
                ;;
            --update-certificates)
                update_all_node_certificates
                exit $?
                ;;
            --list-users)
                ensure_api_configured && get_all_users | jq .
                exit $?
                ;;
            --list-templates)
                ensure_api_configured && get_all_templates | jq .
                exit $?
                ;;
            --analyze-subscription)
                if [[ -n "$2" ]]; then
                    analyze_subscription_info "$2"
                    exit $?
                else
                    echo "Error: Subscription URL required"
                    exit 1
                fi
                ;;
            --dependency-check)
                check_all_dependencies
                exit $?
                ;;
            --install-dependencies)
                install_all_dependencies
                exit $?
                ;;
            --version)
                echo "Marzban Central Manager $SCRIPT_VERSION"
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

# Show help information
show_help() {
    echo "Marzban Central Manager - Professional Edition v3.1"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Backup Options:"
    echo "  --backup-full           Create full system backup"
    echo "  --backup-main           Create main server backup"
    echo "  --backup-nodes          Create nodes backup"
    echo ""
    echo "Node Management:"
    echo "  --monitor-health        Monitor all nodes health"
    echo "  --update-certificates   Update certificates on all nodes"
    echo ""
    echo "User Management:"
    echo "  --list-users            List all users (JSON output)"
    echo ""
    echo "Template Management:"
    echo "  --list-templates        List all user templates (JSON output)"
    echo ""
    echo "Subscription Tools:"
    echo "  --analyze-subscription <URL>  Analyze subscription URL"
    echo ""
    echo "System:"
    echo "  --dependency-check      Check system dependencies"
    echo "  --install-dependencies  Install missing dependencies"
    echo "  --version               Show version information"
    echo "  --help, -h              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive menu"
    echo "  $0 --backup-full                     # Create full backup"
    echo "  $0 --list-users                      # List all users"
    echo "  $0 --analyze-subscription <URL>      # Analyze subscription"
    echo ""
    echo "If no options are provided, the interactive menu will be displayed."
}

# ============================================================================
# MAIN EXECUTION LOOP
# ============================================================================

# Main interactive loop
main_loop() {
    while true; do
        show_main_menu
        
        log_prompt "Choose an option [1-29]:"
        read -r choice
        
        echo ""
        
        if handle_menu_selection "$choice"; then
            if [[ "$choice" != "29" ]]; then
                echo ""
                log_prompt "Press Enter to continue..."
                read -s -r
            fi
        else
            echo ""
            log_prompt "Press Enter to continue..."
            read -s -r
        fi
    done
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    # Load all modules
    load_all_modules
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Acquire script lock
    acquire_script_lock
    
    # Initialize system
    initialize_system
    
    # Check system requirements
    check_system_requirements
    
    # Start main loop
    main_loop
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Execute main function with all arguments
main "$@"