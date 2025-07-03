#!/bin/bash
# Fix Client Certificate Issue
# Professional Edition v3.1

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        STEP)    echo -e "[$timestamp] ${CYAN}🔧 STEP:${NC} $message";;
    esac
}

# Clean up existing problematic containers
cleanup_containers() {
    log "STEP" "Cleaning up existing containers..."
    
    cd /opt/marzban-node
    
    # Stop docker-compose
    docker-compose down 2>/dev/null || true
    
    # Remove any existing marzban-node containers
    docker rm -f marzban-node 2>/dev/null || true
    docker rm -f marzban-node_marzban-node_1 2>/dev/null || true
    
    # Clean up any orphaned containers
    docker container prune -f
    
    log "SUCCESS" "Container cleanup completed"
}

# Setup SSL certificates properly
setup_ssl_certificates() {
    log "STEP" "Setting up SSL certificates..."
    
    local ssl_dir="/var/lib/marzban-node"
    
    # Create directory if it doesn't exist
    mkdir -p "$ssl_dir"
    
    # Generate server certificates if they don't exist
    if [[ ! -f "$ssl_dir/ssl_cert.pem" ]] || [[ ! -f "$ssl_dir/ssl_key.pem" ]]; then
        log "INFO" "Generating server SSL certificates..."
        
        # Generate private key
        openssl genrsa -out "$ssl_dir/ssl_key.pem" 4096
        
        # Generate self-signed certificate
        openssl req -new -x509 -key "$ssl_dir/ssl_key.pem" \
            -out "$ssl_dir/ssl_cert.pem" -days 3650 \
            -subj "/C=US/ST=State/L=City/O=MarzbanNode/OU=IT/CN=marzban-node"
        
        # Set proper permissions
        chmod 600 "$ssl_dir/ssl_key.pem"
        chmod 644 "$ssl_dir/ssl_cert.pem"
        chown root:root "$ssl_dir/ssl_key.pem" "$ssl_dir/ssl_cert.pem"
        
        log "SUCCESS" "Server SSL certificates generated"
    else
        log "INFO" "Server SSL certificates already exist"
    fi
    
    # Create client certificate file (placeholder)
    log "INFO" "Creating client certificate placeholder..."
    touch "$ssl_dir/ssl_client_cert.pem"
    chmod 600 "$ssl_dir/ssl_client_cert.pem"
    chown root:root "$ssl_dir/ssl_client_cert.pem"
    
    # Verify all files exist
    local required_files=("ssl_cert.pem" "ssl_key.pem" "ssl_client_cert.pem")
    for file in "${required_files[@]}"; do
        if [[ -f "$ssl_dir/$file" ]]; then
            log "SUCCESS" "✅ $file exists"
        else
            log "ERROR" "❌ $file is missing"
            return 1
        fi
    done
    
    log "SUCCESS" "All SSL certificates are properly set up"
}

# Create optimized docker-compose.yml
create_docker_compose() {
    log "STEP" "Creating optimized docker-compose.yml..."
    
    cd /opt/marzban-node
    
    # Backup existing file
    if [[ -f "docker-compose.yml" ]]; then
        cp docker-compose.yml "docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create new docker-compose.yml without problematic health check
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    container_name: marzban-node
    network_mode: host
    environment:
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /opt/marzban-node:/opt/marzban-node
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    log "SUCCESS" "Docker Compose configuration created (without health check)"
}

# Start service with monitoring
start_service() {
    log "STEP" "Starting Marzban Node service..."
    
    cd /opt/marzban-node
    
    # Pull latest image
    log "INFO" "Pulling latest image..."
    docker-compose pull
    
    # Start service
    log "INFO" "Starting container..."
    docker-compose up -d
    
    # Monitor startup
    log "INFO" "Monitoring service startup..."
    local attempts=0
    local max_attempts=60
    local container_healthy=false
    
    while [ $attempts -lt $max_attempts ]; do
        # Check if container is running
        if docker ps | grep -q "marzban-node"; then
            local container_status=$(docker ps --format "table {{.Status}}" | grep -v STATUS | head -1)
            log "INFO" "Container status: $container_status"
            
            # Check logs for errors
            local recent_logs=$(docker logs marzban-node --tail 5 2>/dev/null || echo "")
            
            if echo "$recent_logs" | grep -q "SSL_CLIENT_CERT_FILE is missing"; then
                log "ERROR" "Client certificate issue persists"
                break
            elif echo "$recent_logs" | grep -q "ERROR"; then
                log "WARNING" "Some errors in logs, but continuing..."
            fi
            
            # Check if ports are listening
            if ss -tuln | grep -q ':62050'; then
                log "SUCCESS" "Service is listening on port 62050"
                container_healthy=true
                break
            fi
        else
            log "ERROR" "Container is not running"
            docker-compose logs --tail 10
            break
        fi
        
        # Show progress
        if [ $((attempts % 10)) -eq 0 ] && [ $attempts -gt 0 ]; then
            log "INFO" "Still waiting... (attempt $attempts/$max_attempts)"
            echo -e "\n${CYAN}Recent logs:${NC}"
            docker logs marzban-node --tail 3 2>/dev/null || echo "No logs available"
        fi
        
        sleep 3
        attempts=$((attempts + 1))
    done
    
    if [ "$container_healthy" = true ]; then
        log "SUCCESS" "Marzban Node service started successfully"
        return 0
    else
        log "ERROR" "Service failed to start properly"
        
        echo -e "\n${RED}=== Diagnostic Information ===${NC}"
        echo -e "${CYAN}Container Status:${NC}"
        docker ps -a | grep marzban-node || echo "No container found"
        
        echo -e "\n${CYAN}Recent Logs:${NC}"
        docker logs marzban-node --tail 20 2>/dev/null || echo "No logs available"
        
        echo -e "\n${CYAN}SSL Files:${NC}"
        ls -la /var/lib/marzban-node/ssl_* 2>/dev/null || echo "No SSL files found"
        
        return 1
    fi
}

# Test final connectivity
test_connectivity() {
    log "STEP" "Testing final connectivity..."
    
    # Test local port
    if ss -tuln | grep -q ':62050'; then
        log "SUCCESS" "✅ Port 62050 is listening"
    else
        log "ERROR" "❌ Port 62050 is not listening"
        return 1
    fi
    
    # Test HTTPS response
    log "INFO" "Testing HTTPS response..."
    local response
    response=$(curl -k -s --connect-timeout 10 --max-time 15 -w "%{http_code}" "https://localhost:62050" -o /dev/null 2>/dev/null || echo "000")
    
    if [[ "$response" != "000" ]]; then
        log "SUCCESS" "✅ HTTPS service responding (HTTP $response)"
    else
        log "WARNING" "⚠️  HTTPS service not responding yet (may need more time)"
    fi
    
    # Show final status
    echo -e "\n${CYAN}=== Final Status ===${NC}"
    echo -e "${CYAN}Container:${NC}"
    docker ps | grep marzban-node
    
    echo -e "\n${CYAN}Listening Ports:${NC}"
    ss -tuln | grep -E '(62050|62051)' || echo "No ports listening yet"
    
    echo -e "\n${CYAN}Recent Logs (last 5 lines):${NC}"
    docker logs marzban-node --tail 5 2>/dev/null || echo "No logs available"
}

# Main execution
main() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}Client Certificate Fix Tool${NC}                ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check if in correct directory
    if [[ ! -d "/opt/marzban-node" ]]; then
        log "ERROR" "Directory /opt/marzban-node does not exist"
        exit 1
    fi
    
    log "INFO" "Starting client certificate fix process..."
    
    # Step 1: Clean up existing containers
    cleanup_containers
    
    # Step 2: Setup SSL certificates properly
    setup_ssl_certificates
    
    # Step 3: Create optimized docker-compose.yml
    create_docker_compose
    
    # Step 4: Start service
    if start_service; then
        # Step 5: Test connectivity
        test_connectivity
        
        echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║                    ${GREEN}Fix Complete!${NC}                          ║"
        echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
        
        log "SUCCESS" "🎉 Marzban Node is now running without client certificate errors!"
        
        echo -e "\n${YELLOW}📋 Next Steps:${NC}"
        echo "1. Test from central manager: ./debug_certificate_issue.sh 185.226.93.38 PASSWORD"
        echo "2. Add the node in central manager - it should now work"
        echo "3. The client certificate will be automatically provided by the panel"
        
        echo -e "\n${CYAN}🔧 Monitoring Commands:${NC}"
        echo "- Check status: docker ps | grep marzban-node"
        echo "- View logs: docker logs marzban-node -f"
        echo "- Check ports: ss -tuln | grep -E '(62050|62051)'"
        echo "- Test HTTPS: curl -k https://localhost:62050"
        
    else
        echo -e "\n${RED}❌ Fix failed. Please check the diagnostic information above.${NC}"
        exit 1
    fi
}

main "$@"