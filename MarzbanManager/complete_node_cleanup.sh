#!/bin/bash
# Complete Node Server Cleanup Script
# Professional Edition v3.1 - Enhanced & Comprehensive
# Author: B3hnamR

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

# Global variables
NODE_IP=""
SSH_USER=""
SSH_PASSWORD=""
SSH_PORT="22"
CLEANUP_LEVEL="full"
BACKUP_BEFORE_CLEANUP=false

log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $message";;
        DEBUG)   echo -e "[$timestamp] ${CYAN}🐛 DEBUG:${NC} $message";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message";;
    esac
}

# Function to execute SSH commands with enhanced error handling
ssh_execute() {
    local command="$1"
    local description="$2"
    local show_output="${3:-true}"
    local ignore_errors="${4:-false}"
    
    log "DEBUG" "Executing: $description"
    
    local result exit_code
    result=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "$command" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -ne 0 && "$ignore_errors" == "false" ]]; then
        log "ERROR" "Failed: $description"
        if [[ "$show_output" == "true" ]]; then
            echo -e "${RED}Error Output:${NC} $result"
        fi
        return 1
    else
        if [[ $exit_code -eq 0 ]]; then
            log "SUCCESS" "Completed: $description"
        else
            log "WARNING" "Completed with warnings: $description"
        fi
        
        if [[ "$show_output" == "true" && -n "$result" && "$result" != *"Warning: Permanently added"* ]]; then
            echo -e "${CYAN}Output:${NC} $result"
        fi
        return 0
    fi
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-ip)
                NODE_IP="$2"
                shift 2
                ;;
            --ssh-user)
                SSH_USER="$2"
                shift 2
                ;;
            --ssh-port)
                SSH_PORT="$2"
                shift 2
                ;;
            --ssh-password)
                SSH_PASSWORD="$2"
                shift 2
                ;;
            --cleanup-level)
                CLEANUP_LEVEL="$2"
                shift 2
                ;;
            --backup)
                BACKUP_BEFORE_CLEANUP=true
                shift
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
}

# Function to show help
show_help() {
    echo "Complete Node Server Cleanup Script v3.1"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --node-ip <ip>              Node IP address"
    echo "  --ssh-user <user>           SSH username (default: root)"
    echo "  --ssh-port <port>           SSH port (default: 22)"
    echo "  --ssh-password <password>   SSH password"
    echo "  --cleanup-level <level>     Cleanup level: basic|full|nuclear (default: full)"
    echo "  --backup                    Create backup before cleanup"
    echo "  --help, -h                  Show this help message"
    echo ""
    echo "Cleanup Levels:"
    echo "  basic   - Remove only Marzban Node containers and basic files"
    echo "  full    - Complete cleanup including Docker images and system files"
    echo "  nuclear - Everything + Docker removal + system reset"
    echo ""
    echo "Examples:"
    echo "  $0 --node-ip 1.2.3.4 --ssh-password secret"
    echo "  $0 --node-ip 1.2.3.4 --cleanup-level nuclear --backup"
}

# Function to create backup before cleanup
create_backup() {
    if [[ "$BACKUP_BEFORE_CLEANUP" != "true" ]]; then
        return 0
    fi
    
    log "STEP" "Creating backup before cleanup..."
    
    local backup_dir="/tmp/marzban_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="marzban_node_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # Create backup on remote server
    local backup_command="
        mkdir -p $backup_dir &&
        cp -r /opt/marzban-node $backup_dir/ 2>/dev/null || true &&
        cp -r /var/lib/marzban-node $backup_dir/ 2>/dev/null || true &&
        cp -r /etc/marzban-node $backup_dir/ 2>/dev/null || true &&
        docker ps -a --filter 'name=marzban' --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' > $backup_dir/containers_info.txt 2>/dev/null || true &&
        docker images --filter 'reference=*marzban*' --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' > $backup_dir/images_info.txt 2>/dev/null || true &&
        crontab -l > $backup_dir/crontab_backup.txt 2>/dev/null || true &&
        systemctl list-units --type=service | grep marzban > $backup_dir/services_info.txt 2>/dev/null || true &&
        tar -czf /tmp/$backup_file -C /tmp \$(basename $backup_dir) 2>/dev/null &&
        rm -rf $backup_dir &&
        echo 'Backup created: /tmp/$backup_file'
    "
    
    if ssh_execute "$backup_command" "Create backup" true true; then
        log "SUCCESS" "Backup created successfully: /tmp/$backup_file"
        log "INFO" "You can download it with: scp $SSH_USER@$NODE_IP:/tmp/$backup_file ./"
    else
        log "WARNING" "Backup creation failed, continuing with cleanup..."
    fi
}

# Function to stop all Marzban services
stop_marzban_services() {
    log "STEP" "Stopping all Marzban services..."
    
    # Stop systemd services
    ssh_execute "systemctl stop marzban-node 2>/dev/null || true" "Stop Marzban Node systemd service" true true
    ssh_execute "systemctl stop marzban 2>/dev/null || true" "Stop Marzban systemd service" true true
    
    # Stop Docker containers
    ssh_execute "docker stop \$(docker ps -q --filter 'name=marzban') 2>/dev/null || true" "Stop Marzban containers" true true
    
    # Stop docker-compose services
    ssh_execute "cd /opt/marzban-node 2>/dev/null && docker-compose down --remove-orphans 2>/dev/null || true" "Stop docker-compose services" true true
    ssh_execute "cd ~/Marzban-node 2>/dev/null && docker-compose down --remove-orphans 2>/dev/null || true" "Stop docker-compose services (home)" true true
    
    # Kill any remaining processes
    ssh_execute "pkill -f marzban 2>/dev/null || true" "Kill remaining Marzban processes" true true
    
    log "SUCCESS" "All Marzban services stopped"
}

# Function to remove containers and images
remove_containers_and_images() {
    log "STEP" "Removing containers and images..."
    
    # Remove containers
    ssh_execute "docker rm -f \$(docker ps -aq --filter 'name=marzban') 2>/dev/null || true" "Remove Marzban containers" true true
    
    # Remove images based on cleanup level
    if [[ "$CLEANUP_LEVEL" == "basic" ]]; then
        ssh_execute "docker rmi gozargah/marzban-node:latest 2>/dev/null || true" "Remove Marzban Node image" true true
    else
        ssh_execute "docker rmi \$(docker images --filter 'reference=*marzban*' -q) 2>/dev/null || true" "Remove all Marzban images" true true
        ssh_execute "docker rmi \$(docker images --filter 'reference=gozargah/*' -q) 2>/dev/null || true" "Remove Gozargah images" true true
    fi
    
    log "SUCCESS" "Containers and images removed"
}

# Function to remove files and directories
remove_files_and_directories() {
    log "STEP" "Removing files and directories..."
    
    # Main directories
    ssh_execute "rm -rf /opt/marzban-node" "Remove /opt/marzban-node" true true
    ssh_execute "rm -rf /var/lib/marzban-node" "Remove /var/lib/marzban-node" true true
    ssh_execute "rm -rf /etc/marzban-node" "Remove /etc/marzban-node" true true
    ssh_execute "rm -rf ~/Marzban-node" "Remove ~/Marzban-node" true true
    ssh_execute "rm -rf /opt/marzban" "Remove /opt/marzban (if exists)" true true
    ssh_execute "rm -rf /var/lib/marzban" "Remove /var/lib/marzban (if exists)" true true
    
    # Configuration files
    ssh_execute "rm -f /etc/marzban* 2>/dev/null || true" "Remove configuration files" true true
    ssh_execute "rm -f ~/.marzban* 2>/dev/null || true" "Remove user config files" true true
    
    # Temporary files
    ssh_execute "find /tmp -name '*marzban*' -delete 2>/dev/null || true" "Remove temporary files" true true
    ssh_execute "find /var/tmp -name '*marzban*' -delete 2>/dev/null || true" "Remove var/tmp files" true true
    
    # Log files
    ssh_execute "rm -f /var/log/marzban* 2>/dev/null || true" "Remove log files" true true
    ssh_execute "find /var/log -name '*marzban*' -delete 2>/dev/null || true" "Remove all log files" true true
    
    # Cache and runtime files
    ssh_execute "rm -rf /run/marzban* 2>/dev/null || true" "Remove runtime files" true true
    ssh_execute "rm -rf /var/cache/marzban* 2>/dev/null || true" "Remove cache files" true true
    
    log "SUCCESS" "Files and directories removed"
}

# Function to remove systemd services
remove_systemd_services() {
    log "STEP" "Removing systemd services..."
    
    # Stop and disable services
    ssh_execute "systemctl stop marzban-node 2>/dev/null || true" "Stop marzban-node service" true true
    ssh_execute "systemctl disable marzban-node 2>/dev/null || true" "Disable marzban-node service" true true
    ssh_execute "systemctl stop marzban 2>/dev/null || true" "Stop marzban service" true true
    ssh_execute "systemctl disable marzban 2>/dev/null || true" "Disable marzban service" true true
    
    # Remove service files
    ssh_execute "rm -f /etc/systemd/system/marzban* 2>/dev/null || true" "Remove systemd service files" true true
    ssh_execute "rm -f /lib/systemd/system/marzban* 2>/dev/null || true" "Remove lib systemd files" true true
    ssh_execute "rm -f /usr/lib/systemd/system/marzban* 2>/dev/null || true" "Remove usr/lib systemd files" true true
    
    # Reload systemd
    ssh_execute "systemctl daemon-reload" "Reload systemd daemon" true true
    ssh_execute "systemctl reset-failed 2>/dev/null || true" "Reset failed services" true true
    
    log "SUCCESS" "Systemd services removed"
}

# Function to clean environment
clean_environment() {
    log "STEP" "Cleaning environment..."
    
    # Remove from shell profiles
    ssh_execute "sed -i '/marzban/Id' /root/.bashrc 2>/dev/null || true" "Clean .bashrc" true true
    ssh_execute "sed -i '/MARZBAN/Id' /root/.bashrc 2>/dev/null || true" "Clean environment variables" true true
    ssh_execute "sed -i '/marzban/Id' /root/.profile 2>/dev/null || true" "Clean .profile" true true
    ssh_execute "sed -i '/marzban/Id' /etc/environment 2>/dev/null || true" "Clean /etc/environment" true true
    
    # Remove cron jobs
    ssh_execute "crontab -l 2>/dev/null | grep -v marzban | crontab - 2>/dev/null || true" "Remove cron jobs" true true
    
    # Remove aliases and functions
    ssh_execute "unalias marzban-node 2>/dev/null || true" "Remove aliases" true true
    
    # Remove from PATH
    ssh_execute "sed -i 's|:/opt/marzban[^:]*||g' /etc/environment 2>/dev/null || true" "Clean PATH" true true
    
    log "SUCCESS" "Environment cleaned"
}

# Function to clean Docker system
clean_docker_system() {
    log "STEP" "Cleaning Docker system..."
    
    if [[ "$CLEANUP_LEVEL" == "basic" ]]; then
        ssh_execute "docker system prune -f" "Basic Docker cleanup" true true
    else
        ssh_execute "docker system prune -af --volumes" "Complete Docker cleanup" true true
        ssh_execute "docker volume prune -f" "Remove unused volumes" true true
        ssh_execute "docker network prune -f" "Remove unused networks" true true
        ssh_execute "docker builder prune -af" "Clean build cache" true true
    fi
    
    log "SUCCESS" "Docker system cleaned"
}

# Function to remove Docker completely (nuclear option)
remove_docker_completely() {
    if [[ "$CLEANUP_LEVEL" != "nuclear" ]]; then
        return 0
    fi
    
    log "STEP" "Removing Docker completely (nuclear option)..."
    
    # Stop Docker
    ssh_execute "systemctl stop docker 2>/dev/null || true" "Stop Docker service" true true
    ssh_execute "systemctl stop docker.socket 2>/dev/null || true" "Stop Docker socket" true true
    ssh_execute "systemctl disable docker 2>/dev/null || true" "Disable Docker service" true true
    
    # Remove Docker packages
    ssh_execute "apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true" "Remove Docker packages" true true
    
    # Remove Docker data
    ssh_execute "rm -rf /var/lib/docker" "Remove Docker data directory" true true
    ssh_execute "rm -rf /var/lib/containerd" "Remove containerd data" true true
    ssh_execute "rm -rf /etc/docker" "Remove Docker configuration" true true
    ssh_execute "rm -rf /etc/containerd" "Remove containerd config" true true
    
    # Remove Docker repository
    ssh_execute "rm -f /etc/apt/sources.list.d/docker.list" "Remove Docker repository" true true
    ssh_execute "rm -f /etc/apt/keyrings/docker.gpg" "Remove Docker GPG key" true true
    ssh_execute "rm -f /usr/share/keyrings/docker-archive-keyring.gpg" "Remove Docker archive key" true true
    
    # Clean packages
    ssh_execute "apt-get autoremove -y" "Remove unused packages" true true
    ssh_execute "apt-get autoclean" "Clean package cache" true true
    
    log "SUCCESS" "Docker completely removed"
}

# Function to remove management scripts
remove_management_scripts() {
    log "STEP" "Removing management scripts..."
    
    # Remove marzban-node command
    ssh_execute "rm -f /usr/local/bin/marzban-node 2>/dev/null || true" "Remove marzban-node command" true true
    ssh_execute "rm -f /usr/bin/marzban-node 2>/dev/null || true" "Remove marzban-node from /usr/bin" true true
    
    # Remove installation scripts
    ssh_execute "find /tmp -name '*marzban*deployer*' -delete 2>/dev/null || true" "Remove deployer scripts" true true
    ssh_execute "find /root -name '*marzban*' -type f -delete 2>/dev/null || true" "Remove scripts from root" true true
    
    log "SUCCESS" "Management scripts removed"
}

# Function to reset network configuration
reset_network_config() {
    if [[ "$CLEANUP_LEVEL" != "nuclear" ]]; then
        return 0
    fi
    
    log "STEP" "Resetting network configuration..."
    
    # Remove iptables rules (be careful!)
    ssh_execute "iptables -t nat -F 2>/dev/null || true" "Flush NAT table" true true
    ssh_execute "iptables -t mangle -F 2>/dev/null || true" "Flush mangle table" true true
    
    # Reset UFW if needed
    ssh_execute "ufw --force reset 2>/dev/null || true" "Reset UFW (if installed)" true true
    
    log "SUCCESS" "Network configuration reset"
}

# Function to perform final verification
final_verification() {
    log "STEP" "Performing final verification..."
    
    echo -e "\n${CYAN}=== Final Verification Report ===${NC}"
    
    # Check containers
    local containers_check
    containers_check=$(ssh_execute "docker ps -a 2>/dev/null | grep marzban || echo 'No Marzban containers found'" "Check containers" false true)
    echo -e "${BLUE}Containers:${NC} $containers_check"
    
    # Check images
    local images_check
    images_check=$(ssh_execute "docker images 2>/dev/null | grep marzban || echo 'No Marzban images found'" "Check images" false true)
    echo -e "${BLUE}Images:${NC} $images_check"
    
    # Check directories
    local dirs_check
    dirs_check=$(ssh_execute "find /opt /var/lib /etc -name '*marzban*' 2>/dev/null || echo 'No Marzban directories found'" "Check directories" false true)
    echo -e "${BLUE}Directories:${NC} $dirs_check"
    
    # Check processes
    local processes_check
    processes_check=$(ssh_execute "ps aux | grep marzban | grep -v grep || echo 'No Marzban processes running'" "Check processes" false true)
    echo -e "${BLUE}Processes:${NC} $processes_check"
    
    # Check ports
    local ports_check
    ports_check=$(ssh_execute "ss -tuln | grep -E '(62050|62051)' || echo 'Ports 62050/62051 are free'" "Check ports" false true)
    echo -e "${BLUE}Ports:${NC} $ports_check"
    
    # Check services
    local services_check
    services_check=$(ssh_execute "systemctl list-units --type=service | grep marzban || echo 'No Marzban services found'" "Check services" false true)
    echo -e "${BLUE}Services:${NC} $services_check"
    
    # Check disk space
    ssh_execute "df -h /" "Check disk space" true true
    
    log "SUCCESS" "Final verification completed"
}

# Main cleanup function
complete_cleanup() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${RED}Complete Node Server Cleanup${NC}                ║"
    echo -e "${WHITE}║                ${YELLOW}⚠️  WARNING: This will remove everything!${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "INFO" "Cleanup Level: $CLEANUP_LEVEL"
    log "INFO" "Target Server: $SSH_USER@$NODE_IP:$SSH_PORT"
    log "INFO" "Backup Before Cleanup: $BACKUP_BEFORE_CLEANUP"
    
    case "$CLEANUP_LEVEL" in
        "basic")
            log "WARNING" "Basic cleanup: Containers, basic files, and images"
            ;;
        "full")
            log "WARNING" "Full cleanup: Everything except Docker itself"
            ;;
        "nuclear")
            log "WARNING" "Nuclear cleanup: Everything including Docker and system reset"
            ;;
    esac
    
    echo -e "\n${RED}${BOLD}This will completely remove all Marzban Node components!${NC}"
    echo -n "Are you sure you want to proceed? (type 'YES' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    log "STEP" "Starting complete cleanup process..."
    
    # Execute cleanup steps
    create_backup
    stop_marzban_services
    remove_containers_and_images
    remove_files_and_directories
    remove_systemd_services
    remove_management_scripts
    clean_environment
    clean_docker_system
    remove_docker_completely
    reset_network_config
    final_verification
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Cleanup Complete!${NC}                       ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════���═══════╝${NC}\n"
    
    log "SUCCESS" "🎉 Complete cleanup finished successfully!"
    log "INFO" "Cleanup Level: $CLEANUP_LEVEL"
    log "INFO" "The server is now clean and ready for fresh installation"
    
    if [[ "$CLEANUP_LEVEL" == "nuclear" ]]; then
        log "INFO" "Docker has been completely removed"
        log "INFO" "Network configuration has been reset"
    fi
    
    if [[ "$BACKUP_BEFORE_CLEANUP" == "true" ]]; then
        log "INFO" "Backup was created before cleanup"
    fi
}

# Function to get connection details interactively
get_connection_details() {
    if [[ -z "$NODE_IP" ]]; then
        echo -n "Enter Node IP: "
        read -r NODE_IP
    fi
    
    if [[ -z "$SSH_USER" ]]; then
        echo -n "Enter SSH Username [default: root]: "
        read -r ssh_user
        SSH_USER=${ssh_user:-root}
    fi
    
    if [[ -z "$SSH_PASSWORD" ]]; then
        echo -n "Enter SSH Password: "
        read -s SSH_PASSWORD
        echo ""
    fi
    
    if [[ "$SSH_PORT" == "22" ]]; then
        echo -n "Enter SSH Port [default: 22]: "
        read -r ssh_port
        SSH_PORT=${ssh_port:-22}
    fi
    
    if [[ "$CLEANUP_LEVEL" == "full" ]]; then
        echo -e "\n${YELLOW}Cleanup Levels:${NC}"
        echo "1. Basic   - Remove containers and basic files"
        echo "2. Full    - Complete cleanup (recommended)"
        echo "3. Nuclear - Everything + Docker removal"
        echo -n "Choose cleanup level [1-3, default: 2]: "
        read -r level_choice
        
        case "$level_choice" in
            1) CLEANUP_LEVEL="basic" ;;
            3) CLEANUP_LEVEL="nuclear" ;;
            *) CLEANUP_LEVEL="full" ;;
        esac
    fi
    
    echo -n "Create backup before cleanup? (y/n) [default: n]: "
    read -r backup_choice
    if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
        BACKUP_BEFORE_CLEANUP=true
    fi
}

# Check dependencies
check_dependencies() {
    if ! command -v sshpass >/dev/null 2>&1; then
        log "ERROR" "sshpass is required but not installed"
        log "INFO" "Install with: apt-get install sshpass"
        exit 1
    fi
}

# Test SSH connection
test_ssh_connection() {
    log "STEP" "Testing SSH connection to $NODE_IP..."
    
    if ssh_execute "echo 'SSH connection successful'" "SSH connectivity test" false; then
        log "SUCCESS" "SSH connection established successfully"
        
        # Get basic system info
        local os_info
        os_info=$(ssh_execute "cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"'" "Get OS info" false true)
        log "INFO" "Target OS: $os_info"
        
        return 0
    else
        log "ERROR" "SSH connection failed"
        return 1
    fi
}

# Main function
main() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        ${CYAN}Complete Node Server Cleanup Script v3.1${NC}         ║"
    echo -e "${WHITE}║              ${GREEN}Enhanced & Comprehensive Edition${NC}              ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check dependencies
    check_dependencies
    
    # Get connection details if not provided
    get_connection_details
    
    # Test SSH connection
    if test_ssh_connection; then
        complete_cleanup
    else
        log "ERROR" "Cannot proceed without SSH connection"
        exit 1
    fi
}

# Execute main function
main "$@"