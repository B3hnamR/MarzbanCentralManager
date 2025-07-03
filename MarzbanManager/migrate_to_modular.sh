#!/bin/bash
# Marzban Central Manager - Migration Script
# Migrate from monolithic to modular architecture
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# MIGRATION CONFIGURATION
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLD_SCRIPT="$SCRIPT_DIR/marzban_central_manager.sh"
NEW_SCRIPT="$SCRIPT_DIR/marzban_central_manager_new.sh"
BACKUP_SCRIPT="$SCRIPT_DIR/marzban_central_manager_backup_$(date +%Y%m%d_%H%M%S).sh"

# Configuration paths
MANAGER_DIR="/root/MarzbanManager"
CONFIG_FILE="$MANAGER_DIR/marzban_manager.conf"
NODES_CONFIG="$MANAGER_DIR/marzban_managed_nodes.conf"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        "SUCCESS") echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message" ;;
        "ERROR")   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message" ;;
        "WARNING") echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message" ;;
        "INFO")    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message" ;;
        "STEP")    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $message" ;;
        *)         echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message" ;;
    esac
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Check if old script exists
check_old_script() {
    if [[ ! -f "$OLD_SCRIPT" ]]; then
        log "ERROR" "Old script not found: $OLD_SCRIPT"
        exit 1
    fi
    
    if [[ ! -x "$OLD_SCRIPT" ]]; then
        log "WARNING" "Old script is not executable"
        chmod +x "$OLD_SCRIPT"
    fi
    
    log "SUCCESS" "Old script found and validated"
}

# Check if new script exists
check_new_script() {
    if [[ ! -f "$NEW_SCRIPT" ]]; then
        log "ERROR" "New modular script not found: $NEW_SCRIPT"
        exit 1
    fi
    
    if [[ ! -x "$NEW_SCRIPT" ]]; then
        log "INFO" "Making new script executable"
        chmod +x "$NEW_SCRIPT"
    fi
    
    log "SUCCESS" "New modular script found and validated"
}

# Check if lib directory exists
check_lib_directory() {
    local lib_dir="$SCRIPT_DIR/lib"
    
    if [[ ! -d "$lib_dir" ]]; then
        log "ERROR" "Library directory not found: $lib_dir"
        exit 1
    fi
    
    # Check core modules
    local core_modules=(
        "$lib_dir/core/config.sh"
        "$lib_dir/core/logger.sh"
        "$lib_dir/core/utils.sh"
        "$lib_dir/core/dependencies.sh"
    )
    
    for module in "${core_modules[@]}"; do
        if [[ ! -f "$module" ]]; then
            log "ERROR" "Core module missing: $module"
            exit 1
        fi
    done
    
    log "SUCCESS" "Library directory and core modules validated"
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

# Create backup of old script
backup_old_script() {
    log "STEP" "Creating backup of old script..."
    
    if cp "$OLD_SCRIPT" "$BACKUP_SCRIPT"; then
        log "SUCCESS" "Backup created: $BACKUP_SCRIPT"
    else
        log "ERROR" "Failed to create backup"
        exit 1
    fi
}

# Backup configuration files
backup_configurations() {
    log "STEP" "Backing up configuration files..."
    
    local backup_dir="$MANAGER_DIR/migration_backup_$(date +%Y%m%d_%H%M%S)"
    
    if mkdir -p "$backup_dir"; then
        log "INFO" "Created backup directory: $backup_dir"
    else
        log "ERROR" "Failed to create backup directory"
        exit 1
    fi
    
    # Backup manager config
    if [[ -f "$CONFIG_FILE" ]]; then
        if cp "$CONFIG_FILE" "$backup_dir/"; then
            log "SUCCESS" "Manager configuration backed up"
        else
            log "WARNING" "Failed to backup manager configuration"
        fi
    fi
    
    # Backup nodes config
    if [[ -f "$NODES_CONFIG" ]]; then
        if cp "$NODES_CONFIG" "$backup_dir/"; then
            log "SUCCESS" "Nodes configuration backed up"
        else
            log "WARNING" "Failed to backup nodes configuration"
        fi
    fi
    
    # Backup entire manager directory
    if tar -czf "$backup_dir/full_manager_backup.tar.gz" -C "$(dirname "$MANAGER_DIR")" "$(basename "$MANAGER_DIR")" 2>/dev/null; then
        log "SUCCESS" "Full manager directory backed up"
    else
        log "WARNING" "Failed to create full backup archive"
    fi
    
    echo "$backup_dir" > "$MANAGER_DIR/.last_migration_backup"
    log "INFO" "Backup location saved for rollback: $backup_dir"
}

# ============================================================================
# TESTING FUNCTIONS
# ============================================================================

# Test new script functionality
test_new_script() {
    log "STEP" "Testing new modular script..."
    
    # Test basic functionality
    log "INFO" "Testing version command..."
    if "$NEW_SCRIPT" --version >/dev/null 2>&1; then
        log "SUCCESS" "Version command works"
    else
        log "ERROR" "Version command failed"
        return 1
    fi
    
    # Test dependency check
    log "INFO" "Testing dependency check..."
    if "$NEW_SCRIPT" --dependency-check >/dev/null 2>&1; then
        log "SUCCESS" "Dependency check works"
    else
        log "WARNING" "Dependency check had issues (may be normal)"
    fi
    
    # Test help command
    log "INFO" "Testing help command..."
    if "$NEW_SCRIPT" --help >/dev/null 2>&1; then
        log "SUCCESS" "Help command works"
    else
        log "ERROR" "Help command failed"
        return 1
    fi
    
    log "SUCCESS" "New script basic tests passed"
    return 0
}

# Test configuration compatibility
test_configuration_compatibility() {
    log "STEP" "Testing configuration compatibility..."
    
    # Source the new script's config module to test
    if source "$SCRIPT_DIR/lib/core/config.sh" 2>/dev/null; then
        log "SUCCESS" "Configuration module loads successfully"
    else
        log "ERROR" "Failed to load configuration module"
        return 1
    fi
    
    # Test if existing config can be loaded
    if [[ -f "$CONFIG_FILE" ]]; then
        if source "$CONFIG_FILE" 2>/dev/null; then
            log "SUCCESS" "Existing configuration is compatible"
        else
            log "WARNING" "Existing configuration may have compatibility issues"
        fi
    else
        log "INFO" "No existing configuration found (fresh installation)"
    fi
    
    return 0
}

# ============================================================================
# MIGRATION FUNCTIONS
# ============================================================================

# Migrate script files
migrate_script_files() {
    log "STEP" "Migrating script files..."
    
    # Replace old script with new one
    if mv "$OLD_SCRIPT" "${OLD_SCRIPT}.old"; then
        log "SUCCESS" "Old script renamed to .old"
    else
        log "ERROR" "Failed to rename old script"
        return 1
    fi
    
    if cp "$NEW_SCRIPT" "$OLD_SCRIPT"; then
        log "SUCCESS" "New script installed as main script"
    else
        log "ERROR" "Failed to install new script"
        # Restore old script
        mv "${OLD_SCRIPT}.old" "$OLD_SCRIPT"
        return 1
    fi
    
    if chmod +x "$OLD_SCRIPT"; then
        log "SUCCESS" "Main script permissions set"
    else
        log "WARNING" "Failed to set script permissions"
    fi
    
    return 0
}

# Update cron jobs
update_cron_jobs() {
    log "STEP" "Updating cron jobs..."
    
    # Get current crontab
    local current_cron
    current_cron=$(crontab -l 2>/dev/null || echo "")
    
    if [[ -n "$current_cron" ]]; then
        # Update paths in cron jobs
        local updated_cron
        updated_cron=$(echo "$current_cron" | sed "s|$OLD_SCRIPT|$OLD_SCRIPT|g")
        
        if [[ "$updated_cron" != "$current_cron" ]]; then
            echo "$updated_cron" | crontab -
            log "SUCCESS" "Cron jobs updated"
        else
            log "INFO" "No cron job updates needed"
        fi
    else
        log "INFO" "No existing cron jobs found"
    fi
}

# Update systemd services (if any)
update_systemd_services() {
    log "STEP" "Checking for systemd services..."
    
    local service_files=(
        "/etc/systemd/system/marzban-central-manager.service"
        "/etc/systemd/system/marzban-backup.service"
        "/etc/systemd/system/marzban-monitor.service"
    )
    
    local updated_services=0
    
    for service_file in "${service_files[@]}"; do
        if [[ -f "$service_file" ]]; then
            log "INFO" "Updating service file: $service_file"
            
            # Update script path in service file
            if sed -i "s|$OLD_SCRIPT|$OLD_SCRIPT|g" "$service_file"; then
                ((updated_services++))
                log "SUCCESS" "Updated service: $(basename "$service_file")"
            else
                log "WARNING" "Failed to update service: $(basename "$service_file")"
            fi
        fi
    done
    
    if [[ $updated_services -gt 0 ]]; then
        systemctl daemon-reload
        log "SUCCESS" "Systemd daemon reloaded"
    else
        log "INFO" "No systemd services found to update"
    fi
}

# ============================================================================
# VERIFICATION FUNCTIONS
# ============================================================================

# Verify migration success
verify_migration() {
    log "STEP" "Verifying migration..."
    
    # Test main script
    if [[ -x "$OLD_SCRIPT" ]]; then
        log "SUCCESS" "Main script is executable"
    else
        log "ERROR" "Main script is not executable"
        return 1
    fi
    
    # Test version
    local version_output
    if version_output=$("$OLD_SCRIPT" --version 2>/dev/null); then
        log "SUCCESS" "Version check passed: $version_output"
    else
        log "ERROR" "Version check failed"
        return 1
    fi
    
    # Test configuration loading
    if "$OLD_SCRIPT" --dependency-check >/dev/null 2>&1; then
        log "SUCCESS" "Configuration loading works"
    else
        log "WARNING" "Configuration loading may have issues"
    fi
    
    log "SUCCESS" "Migration verification completed"
    return 0
}

# ============================================================================
# ROLLBACK FUNCTIONS
# ============================================================================

# Rollback migration
rollback_migration() {
    log "STEP" "Rolling back migration..."
    
    # Restore old script
    if [[ -f "${OLD_SCRIPT}.old" ]]; then
        if mv "${OLD_SCRIPT}.old" "$OLD_SCRIPT"; then
            log "SUCCESS" "Old script restored"
        else
            log "ERROR" "Failed to restore old script"
            return 1
        fi
    else
        log "ERROR" "Old script backup not found"
        return 1
    fi
    
    # Restore configurations if needed
    local backup_location
    if [[ -f "$MANAGER_DIR/.last_migration_backup" ]]; then
        backup_location=$(cat "$MANAGER_DIR/.last_migration_backup")
        
        if [[ -d "$backup_location" ]]; then
            log "INFO" "Configuration backup found: $backup_location"
            log "INFO" "Manual restoration may be needed if configurations were modified"
        fi
    fi
    
    log "SUCCESS" "Rollback completed"
    return 0
}

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

# Show migration summary
show_migration_summary() {
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}Migration to Modular Architecture v3.1${NC}         ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}This script will migrate your Marzban Central Manager to the new modular architecture.${NC}\n"
    
    echo -e "${PURPLE}What will be done:${NC}"
    echo "  ✅ Backup current script and configurations"
    echo "  ✅ Test new modular script functionality"
    echo "  ✅ Replace old script with new modular version"
    echo "  ✅ Update cron jobs and systemd services"
    echo "  ✅ Verify migration success"
    echo ""
    
    echo -e "${PURPLE}Benefits of modular architecture:${NC}"
    echo "  🏗️  Better code organization and maintainability"
    echo "  🔧 Easier debugging and development"
    echo "  📦 Reusable modules"
    echo "  🚀 Better performance and error handling"
    echo "  📚 Improved documentation and testing"
    echo ""
    
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • Your existing configurations will be preserved"
    echo "  • A complete backup will be created before migration"
    echo "  • You can rollback if needed using the backup"
    echo "  • The migration is reversible"
    echo ""
}

# Interactive migration
interactive_migration() {
    show_migration_summary
    
    echo -e "${CYAN}Do you want to proceed with the migration? (y/n):${NC}"
    read -r proceed
    
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        log "INFO" "Migration cancelled by user"
        exit 0
    fi
    
    echo ""
    log "STEP" "Starting migration process..."
    
    # Validation phase
    log "INFO" "Phase 1: Validation"
    check_root
    check_old_script
    check_new_script
    check_lib_directory
    
    # Backup phase
    log "INFO" "Phase 2: Backup"
    backup_old_script
    backup_configurations
    
    # Testing phase
    log "INFO" "Phase 3: Testing"
    if ! test_new_script; then
        log "ERROR" "New script testing failed. Migration aborted."
        exit 1
    fi
    
    if ! test_configuration_compatibility; then
        log "WARNING" "Configuration compatibility issues detected"
        echo -e "${YELLOW}Do you want to continue anyway? (y/n):${NC}"
        read -r continue_anyway
        
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log "INFO" "Migration cancelled due to compatibility issues"
            exit 1
        fi
    fi
    
    # Migration phase
    log "INFO" "Phase 4: Migration"
    if ! migrate_script_files; then
        log "ERROR" "Script migration failed. Attempting rollback..."
        rollback_migration
        exit 1
    fi
    
    update_cron_jobs
    update_systemd_services
    
    # Verification phase
    log "INFO" "Phase 5: Verification"
    if ! verify_migration; then
        log "ERROR" "Migration verification failed. Consider rollback."
        echo -e "${YELLOW}Do you want to rollback? (y/n):${NC}"
        read -r rollback
        
        if [[ "$rollback" =~ ^[Yy]$ ]]; then
            rollback_migration
            exit 1
        fi
    fi
    
    # Success
    echo ""
    log "SUCCESS" "🎉 Migration completed successfully!"
    echo ""
    echo -e "${GREEN}Your Marzban Central Manager has been upgraded to the modular architecture v3.1.${NC}"
    echo -e "${BLUE}You can now use the same commands as before, but with improved performance and maintainability.${NC}"
    echo ""
    echo -e "${PURPLE}Next steps:${NC}"
    echo "  • Test the new script: ./marzban_central_manager.sh --version"
    echo "  • Check functionality: ./marzban_central_manager.sh --dependency-check"
    echo "  • Read the documentation: cat MODULAR_ARCHITECTURE.md"
    echo ""
    echo -e "${YELLOW}Backup location:${NC} $(cat "$MANAGER_DIR/.last_migration_backup" 2>/dev/null || echo "Not available")"
    echo -e "${YELLOW}Old script backup:${NC} $BACKUP_SCRIPT"
    echo ""
}

# Command line migration
command_line_migration() {
    local force=false
    local test_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --test-only)
                test_only=true
                shift
                ;;
            --rollback)
                rollback_migration
                exit $?
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ "$test_only" == "true" ]]; then
        log "INFO" "Running test-only mode..."
        check_root
        check_old_script
        check_new_script
        check_lib_directory
        test_new_script
        test_configuration_compatibility
        log "SUCCESS" "All tests passed. Migration should be safe."
        exit 0
    fi
    
    if [[ "$force" == "false" ]]; then
        interactive_migration
    else
        log "INFO" "Running forced migration..."
        # Run all steps without prompts
        check_root
        check_old_script
        check_new_script
        check_lib_directory
        backup_old_script
        backup_configurations
        test_new_script
        test_configuration_compatibility
        migrate_script_files
        update_cron_jobs
        update_systemd_services
        verify_migration
        log "SUCCESS" "Forced migration completed"
    fi
}

# Show help
show_help() {
    echo "Marzban Central Manager - Migration Script v3.1"
    echo "Author: B3hnamR"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force         Run migration without interactive prompts"
    echo "  --test-only     Only test compatibility, don't migrate"
    echo "  --rollback      Rollback to previous version"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "If no options are provided, interactive migration will be started."
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    if [[ $# -eq 0 ]]; then
        interactive_migration
    else
        command_line_migration "$@"
    fi
}

# Execute main function
main "$@"