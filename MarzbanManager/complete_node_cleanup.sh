#!/bin/bash
# Complete Node Server Cleanup Script
# Professional Edition v3.1

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

log() {
    local level="$1" message="$2" timestamp; timestamp=$(date '+%H:%M:%S')
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        STEP)    echo -e "[$timestamp] ${PURPLE}🔧 STEP:${NC} $message";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message";;
    esac
}

# Function to execute SSH commands
ssh_execute() {
    local command="$1"
    local description="$2"
    
    log "INFO" "Executing: $description"
    
    local result
    result=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "$command" 2>&1 || echo "SSH_COMMAND_FAILED")
    
    if echo "$result" | grep -q "SSH_COMMAND_FAILED"; then
        log "ERROR" "Failed: $description"
        log "ERROR" "Result: $result"
        return 1
    else
        log "SUCCESS" "Completed: $description"
        if [[ -n "$result" ]] && [[ "$result" != *"Warning: Permanently added"* ]]; then
            echo -e "${CYAN}Output:${NC} $result"
        fi
        return 0
    fi
}

# Complete cleanup function
complete_cleanup() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${RED}Complete Node Server Cleanup${NC}                ║"
    echo -e "${WHITE}║                ${YELLOW}⚠️  WARNING: This will remove everything!${NC}        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "WARNING" "This will completely remove all Marzban Node components from the server"
    log "WARNING" "Including: containers, images, volumes, files, directories, and configurations"
    
    echo -n "Are you sure you want to proceed? (type 'YES' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    log "STEP" "Starting complete cleanup process..."
    
    # Step 1: Stop and remove all Marzban containers
    log "STEP" "Stopping and removing all Marzban containers..."
    ssh_execute "docker stop \$(docker ps -aq --filter 'name=marzban') 2>/dev/null || true" "Stop all Marzban containers"
    ssh_execute "docker rm \$(docker ps -aq --filter 'name=marzban') 2>/dev/null || true" "Remove all Marzban containers"
    
    # Step 2: Stop docker-compose services
    log "STEP" "Stopping docker-compose services..."
    ssh_execute "cd /opt/marzban-node 2>/dev/null && docker-compose down 2>/dev/null || true" "Stop docker-compose services"
    
    # Step 3: Remove Docker images
    log "STEP" "Removing Docker images..."
    ssh_execute "docker rmi gozargah/marzban-node:latest 2>/dev/null || true" "Remove Marzban Node image"
    ssh_execute "docker rmi \$(docker images | grep marzban | awk '{print \$3}') 2>/dev/null || true" "Remove all Marzban images"
    
    # Step 4: Remove directories and files
    log "STEP" "Removing directories and files..."
    ssh_execute "rm -rf /opt/marzban-node" "Remove /opt/marzban-node directory"
    ssh_execute "rm -rf /var/lib/marzban-node" "Remove /var/lib/marzban-node directory"
    ssh_execute "rm -rf /etc/marzban-node" "Remove /etc/marzban-node directory"
    
    # Step 5: Remove backup files
    log "STEP" "Removing backup files..."
    ssh_execute "find /opt -name '*marzban*' -type f -delete 2>/dev/null || true" "Remove Marzban backup files in /opt"
    ssh_execute "find /var/lib -name '*marzban*' -type d -exec rm -rf {} + 2>/dev/null || true" "Remove Marzban backup directories in /var/lib"
    ssh_execute "find /tmp -name '*marzban*' -delete 2>/dev/null || true" "Remove temporary Marzban files"
    
    # Step 6: Remove log files
    log "STEP" "Removing log files..."
    ssh_execute "rm -f /var/log/marzban* 2>/dev/null || true" "Remove Marzban log files"
    ssh_execute "find /var/log -name '*marzban*' -delete 2>/dev/null || true" "Remove all Marzban log files"
    
    # Step 7: Clean Docker system
    log "STEP" "Cleaning Docker system..."
    ssh_execute "docker system prune -af" "Clean Docker system (images, containers, networks)"
    ssh_execute "docker volume prune -f" "Clean Docker volumes"
    ssh_execute "docker network prune -f" "Clean Docker networks"
    
    # Step 8: Remove systemd services (if any)
    log "STEP" "Removing systemd services..."
    ssh_execute "systemctl stop marzban-node 2>/dev/null || true" "Stop Marzban Node service"
    ssh_execute "systemctl disable marzban-node 2>/dev/null || true" "Disable Marzban Node service"
    ssh_execute "rm -f /etc/systemd/system/marzban* 2>/dev/null || true" "Remove systemd service files"
    ssh_execute "systemctl daemon-reload" "Reload systemd daemon"
    
    # Step 9: Remove cron jobs
    log "STEP" "Removing cron jobs..."
    ssh_execute "crontab -l 2>/dev/null | grep -v marzban | crontab - 2>/dev/null || true" "Remove Marzban cron jobs"
    
    # Step 10: Remove environment variables and aliases
    log "STEP" "Cleaning environment..."
    ssh_execute "sed -i '/marzban/Id' /root/.bashrc 2>/dev/null || true" "Remove Marzban aliases from .bashrc"
    ssh_execute "sed -i '/MARZBAN/Id' /root/.bashrc 2>/dev/null || true" "Remove Marzban environment variables"
    ssh_execute "unset \$(env | grep -i marzban | cut -d= -f1) 2>/dev/null || true" "Unset Marzban environment variables"
    
    # Step 11: Remove Docker (optional)
    echo -e "\n${YELLOW}Do you want to remove Docker completely? (y/n):${NC}"
    read -r remove_docker
    
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        log "STEP" "Removing Docker completely..."
        ssh_execute "systemctl stop docker" "Stop Docker service"
        ssh_execute "apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose" "Remove Docker packages"
        ssh_execute "rm -rf /var/lib/docker" "Remove Docker data directory"
        ssh_execute "rm -rf /etc/docker" "Remove Docker configuration"
        ssh_execute "rm -f /etc/apt/sources.list.d/docker.list" "Remove Docker repository"
        ssh_execute "rm -f /etc/apt/keyrings/docker.gpg" "Remove Docker GPG key"
        ssh_execute "apt-get autoremove -y" "Remove unused packages"
        ssh_execute "apt-get autoclean" "Clean package cache"
    fi
    
    # Step 12: Final verification
    log "STEP" "Performing final verification..."
    
    echo -e "\n${CYAN}=== Final Verification ===${NC}"
    
    # Check containers
    ssh_execute "docker ps -a 2>/dev/null | grep marzban || echo 'No Marzban containers found'" "Check remaining containers"
    
    # Check images
    ssh_execute "docker images 2>/dev/null | grep marzban || echo 'No Marzban images found'" "Check remaining images"
    
    # Check directories
    ssh_execute "ls -la /opt/ 2>/dev/null | grep marzban || echo 'No Marzban directories in /opt'" "Check /opt directory"
    ssh_execute "ls -la /var/lib/ 2>/dev/null | grep marzban || echo 'No Marzban directories in /var/lib'" "Check /var/lib directory"
    
    # Check processes
    ssh_execute "ps aux | grep marzban | grep -v grep || echo 'No Marzban processes running'" "Check running processes"
    
    # Check ports
    ssh_execute "ss -tuln | grep -E '(62050|62051)' || echo 'Ports 62050/62051 are free'" "Check ports"
    
    # Check disk space freed
    ssh_execute "df -h /" "Check disk space"
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Cleanup Complete!${NC}                       ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "SUCCESS" "🎉 Complete cleanup finished successfully!"
    log "INFO" "The server is now clean and ready for fresh installation"
    log "INFO" "All Marzban Node components have been removed"
    
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        log "INFO" "Docker has also been completely removed"
    else
        log "INFO" "Docker is still installed and can be used for other purposes"
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

# Main function
main() {
    check_dependencies
    
    # Get connection details
    echo -n "Enter Node IP: "
    read -r NODE_IP
    echo -n "Enter SSH Username [default: root]: "
    read -r ssh_user
    SSH_USER=${ssh_user:-root}
    echo -n "Enter SSH Password: "
    read -s SSH_PASSWORD
    echo ""
    echo -n "Enter SSH Port [default: 22]: "
    read -r ssh_port
    SSH_PORT=${ssh_port:-22}
    
    # Test SSH connection
    log "STEP" "Testing SSH connection..."
    if ssh_execute "echo 'SSH connection successful'" "SSH connectivity test"; then
        log "SUCCESS" "SSH connection established"
        complete_cleanup
    else
        log "ERROR" "SSH connection failed"
        exit 1
    fi
}

# Execute main function
main "$@"