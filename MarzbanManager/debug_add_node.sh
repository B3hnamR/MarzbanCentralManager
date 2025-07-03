#!/bin/bash
# Debug Add Node Script - Complete Logging
# Professional Edition v3.1

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

# Global variables
NODE_IP=""
SSH_USER=""
SSH_PASSWORD=""
SSH_PORT="22"
NODE_NAME=""

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

# Function to execute SSH commands with detailed logging
ssh_execute() {
    local command="$1"
    local description="$2"
    
    log "DEBUG" "Executing SSH command: $description"
    log "DEBUG" "Command: $command"
    
    local result
    result=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "$command" 2>&1 || echo "SSH_COMMAND_FAILED")
    
    if echo "$result" | grep -q "SSH_COMMAND_FAILED"; then
        log "ERROR" "SSH command failed: $description"
        log "ERROR" "Result: $result"
        return 1
    else
        log "SUCCESS" "SSH command completed: $description"
        if [[ -n "$result" ]]; then
            echo -e "${CYAN}Output:${NC}"
            echo "$result"
        fi
        return 0
    fi
}

# Function to monitor container startup with detailed logging
monitor_container_startup() {
    log "STEP" "Starting detailed container monitoring..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        log "INFO" "Monitoring attempt $attempt/$max_attempts"
        
        # Check container status
        log "DEBUG" "Checking container status..."
        local container_status
        container_status=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "docker ps -a | grep marzban" 2>/dev/null || echo "NO_CONTAINER")
        
        if echo "$container_status" | grep -q "NO_CONTAINER"; then
            log "WARNING" "No marzban container found"
        else
            log "INFO" "Container status: $container_status"
        fi
        
        # Check if container is running
        if echo "$container_status" | grep -q "Up"; then
            log "SUCCESS" "Container is running"
            
            # Check port status
            log "DEBUG" "Checking port 62050..."
            local port_status
            port_status=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "ss -tuln | grep ':62050'" 2>/dev/null || echo "PORT_NOT_LISTENING")
            
            if echo "$port_status" | grep -q "PORT_NOT_LISTENING"; then
                log "WARNING" "Port 62050 is not listening yet"
            else
                log "SUCCESS" "Port 62050 is listening: $port_status"
                
                # Test HTTPS response
                log "DEBUG" "Testing HTTPS response..."
                local https_test
                https_test=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "curl -k -s --connect-timeout 5 --max-time 10 -w '%{http_code}' https://localhost:62050 -o /dev/null" 2>/dev/null || echo "000")
                
                if [[ "$https_test" != "000" ]]; then
                    log "SUCCESS" "HTTPS service is responding (HTTP $https_test)"
                    log "SUCCESS" "🎉 Node deployment completed successfully!"
                    return 0
                else
                    log "WARNING" "HTTPS service not responding yet"
                fi
            fi
        elif echo "$container_status" | grep -q "Restarting"; then
            log "WARNING" "Container is restarting - checking logs..."
            
            # Get container logs
            local container_name
            container_name=$(echo "$container_status" | awk '{print $NF}')
            log "DEBUG" "Container name: $container_name"
            
            local container_logs
            container_logs=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT" "$SSH_USER@$NODE_IP" "docker logs $container_name --tail=5" 2>/dev/null || echo "NO_LOGS")
            
            log "INFO" "Recent container logs:"
            echo -e "${YELLOW}$container_logs${NC}"
            
            # Check for specific errors
            if echo "$container_logs" | grep -q "SSL_CLIENT_CERT_FILE is required"; then
                log "ERROR" "SSL_CLIENT_CERT_FILE error detected - fixing..."
                
                # Fix SSL client certificate
                ssh_execute "cp /var/lib/marzban-node/ssl_cert.pem /var/lib/marzban-node/ssl_client_cert.pem && chmod 600 /var/lib/marzban-node/ssl_client_cert.pem" "Creating client certificate"
                
                # Restart container
                ssh_execute "cd /opt/marzban-node && docker-compose restart" "Restarting container"
                
                sleep 5
                continue
            fi
        else
            log "WARNING" "Container is not running properly"
        fi
        
        # Show progress every 5 attempts
        if [ $((attempt % 5)) -eq 0 ]; then
            log "INFO" "Still monitoring... (attempt $attempt/$max_attempts)"
        fi
        
        sleep 3
    done
    
    log "ERROR" "Container monitoring timed out after $max_attempts attempts"
    return 1
}

# Main debug function
debug_add_node() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}Debug Add Node - Complete Logging${NC}              ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Get node information
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
    echo -n "Enter Node Name [default: TestNode]: "
    read -r node_name
    NODE_NAME=${node_name:-TestNode}
    
    log "INFO" "Starting debug deployment for node: $NODE_NAME ($NODE_IP)"
    
    # Step 1: Test SSH connectivity
    log "STEP" "Testing SSH connectivity..."
    if ssh_execute "echo 'SSH connection successful'" "SSH connectivity test"; then
        log "SUCCESS" "SSH connection established"
    else
        log "ERROR" "SSH connection failed"
        return 1
    fi
    
    # Step 2: Check system info
    log "STEP" "Gathering system information..."
    ssh_execute "uname -a" "System information"
    ssh_execute "free -h" "Memory information"
    ssh_execute "df -h /" "Disk space"
    
    # Step 3: Check Docker
    log "STEP" "Checking Docker installation..."
    ssh_execute "docker --version" "Docker version"
    ssh_execute "docker-compose --version" "Docker Compose version"
    
    # Step 4: Check existing containers
    log "STEP" "Checking existing containers..."
    ssh_execute "docker ps -a | grep marzban || echo 'No marzban containers found'" "Existing containers"
    
    # Step 5: Check directories and files
    log "STEP" "Checking Marzban Node environment..."
    ssh_execute "ls -la /opt/marzban-node/ 2>/dev/null || echo 'Directory not found'" "Marzban Node directory"
    ssh_execute "ls -la /var/lib/marzban-node/ 2>/dev/null || echo 'Directory not found'" "Marzban Node data directory"
    
    # Step 6: Check SSL certificates
    log "STEP" "Checking SSL certificates..."
    ssh_execute "ls -la /var/lib/marzban-node/ssl_* 2>/dev/null || echo 'SSL certificates not found'" "SSL certificates"
    
    # Step 7: Check docker-compose.yml
    log "STEP" "Checking docker-compose configuration..."
    ssh_execute "cd /opt/marzban-node && cat docker-compose.yml 2>/dev/null || echo 'docker-compose.yml not found'" "Docker Compose file"
    
    # Step 8: Check if SSL_CLIENT_CERT_FILE is properly configured
    log "STEP" "Verifying SSL_CLIENT_CERT_FILE configuration..."
    ssh_execute "cd /opt/marzban-node && grep -n 'SSL_CLIENT_CERT_FILE' docker-compose.yml 2>/dev/null || echo 'SSL_CLIENT_CERT_FILE not found in docker-compose.yml'" "SSL_CLIENT_CERT_FILE check"
    
    # Step 9: Start/restart the service
    log "STEP" "Starting Marzban Node service..."
    ssh_execute "cd /opt/marzban-node && docker-compose down" "Stopping existing containers"
    ssh_execute "cd /opt/marzban-node && docker-compose up -d" "Starting containers"
    
    # Step 10: Monitor startup
    monitor_container_startup
    
    # Step 11: Final verification
    log "STEP" "Final verification..."
    ssh_execute "docker ps | grep marzban" "Final container status"
    ssh_execute "ss -tuln | grep ':62050'" "Final port status"
    ssh_execute "curl -k -s --connect-timeout 5 https://localhost:62050 && echo 'HTTPS OK' || echo 'HTTPS FAILED'" "Final HTTPS test"
    
    log "SUCCESS" "Debug deployment completed!"
    
    echo -e "\n${CYAN}🔧 Next Steps:${NC}"
    echo "1. If successful, try adding the node in Central Manager"
    echo "2. If failed, check the logs above for specific errors"
    echo "3. Node endpoint: https://$NODE_IP:62050"
}

# Check dependencies
check_dependencies() {
    if ! command -v sshpass >/dev/null 2>&1; then
        log "ERROR" "sshpass is required but not installed"
        log "INFO" "Install with: apt-get install sshpass"
        exit 1
    fi
}

# Main execution
main() {
    check_dependencies
    debug_add_node
}

main "$@"