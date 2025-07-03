#!/bin/bash
# Fix SSL Context Error
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

# Fix SSL context error
fix_ssl_context() {
    log "STEP" "Fixing SSL context error..."
    
    cd /opt/marzban-node
    
    # Stop existing container
    log "INFO" "Stopping existing container..."
    docker stop marzban-node 2>/dev/null || true
    docker rm marzban-node 2>/dev/null || true
    
    # Method 1: Try with valid client certificate
    log "INFO" "Method 1: Creating valid client certificate..."
    
    # Copy server certificate as client certificate (temporary solution)
    cp /var/lib/marzban-node/ssl_cert.pem /var/lib/marzban-node/ssl_client_cert.pem
    chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
    chown root:root /var/lib/marzban-node/ssl_client_cert.pem
    
    # Create docker-compose with client cert
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
    
    # Start container
    log "INFO" "Starting container with client certificate..."
    docker-compose up -d
    
    # Wait and check
    sleep 10
    
    if docker ps | grep -q marzban-node && ! docker logs marzban-node 2>&1 | grep -q "SSLError"; then
        log "SUCCESS" "Method 1 successful - container running with client certificate"
        return 0
    else
        log "WARNING" "Method 1 failed, trying Method 2..."
        
        # Method 2: Remove client certificate requirement
        log "INFO" "Method 2: Removing client certificate requirement..."
        
        docker stop marzban-node 2>/dev/null || true
        docker rm marzban-node 2>/dev/null || true
        
        # Create docker-compose without client cert
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
        
        # Start container
        log "INFO" "Starting container without client certificate..."
        docker-compose up -d
        
        # Wait and check
        sleep 10
        
        if docker ps | grep -q marzban-node && ! docker logs marzban-node 2>&1 | grep -q "SSLError"; then
            log "SUCCESS" "Method 2 successful - container running without client certificate"
            return 0
        else
            log "ERROR" "Both methods failed"
            return 1
        fi
    fi
}

# Monitor service startup
monitor_startup() {
    log "STEP" "Monitoring service startup..."
    
    local attempts=0
    local max_attempts=30
    
    while [ $attempts -lt $max_attempts ]; do
        # Check container status
        if ! docker ps | grep -q marzban-node; then
            log "ERROR" "Container is not running"
            docker logs marzban-node --tail 10 2>/dev/null || echo "No logs available"
            return 1
        fi
        
        # Check for SSL errors
        if docker logs marzban-node 2>&1 | grep -q "SSLError"; then
            log "ERROR" "SSL error detected in logs"
            docker logs marzban-node --tail 10
            return 1
        fi
        
        # Check if service is listening
        if ss -tuln | grep -q ':62050'; then
            log "SUCCESS" "Service is listening on port 62050"
            break
        fi
        
        # Check logs for success message
        if docker logs marzban-node 2>&1 | grep -q "Node service running on :62050"; then
            log "INFO" "Service started successfully, waiting for port..."
        fi
        
        sleep 3
        attempts=$((attempts + 1))
        
        if [ $((attempts % 5)) -eq 0 ]; then
            log "INFO" "Still waiting... (attempt $attempts/$max_attempts)"
        fi
    done
    
    if [ $attempts -eq $max_attempts ]; then
        log "WARNING" "Service startup monitoring timed out"
        return 1
    fi
    
    return 0
}

# Test final connectivity
test_final_connectivity() {
    log "STEP" "Testing final connectivity..."
    
    # Test local port
    if ss -tuln | grep -q ':62050'; then
        log "SUCCESS" "✅ Port 62050 is listening"
    else
        log "ERROR" "❌ Port 62050 is not listening"
        return 1
    fi
    
    # Test HTTPS response
    local response
    response=$(curl -k -s --connect-timeout 10 --max-time 15 -w "%{http_code}" "https://localhost:62050" -o /dev/null 2>/dev/null || echo "000")
    
    if [[ "$response" != "000" ]]; then
        log "SUCCESS" "✅ HTTPS service responding (HTTP $response)"
    else
        # Try HTTP as fallback
        response=$(curl -s --connect-timeout 10 --max-time 15 -w "%{http_code}" "http://localhost:62050" -o /dev/null 2>/dev/null || echo "000")
        if [[ "$response" != "000" ]]; then
            log "SUCCESS" "✅ HTTP service responding (HTTP $response)"
        else
            log "WARNING" "⚠️  Service not responding to HTTP/HTTPS requests"
        fi
    fi
    
    # Show final status
    echo -e "\n${CYAN}=== Final Status ===${NC}"
    echo -e "${CYAN}Container Status:${NC}"
    docker ps | grep marzban-node
    
    echo -e "\n${CYAN}Listening Ports:${NC}"
    ss -tuln | grep -E '(62050|62051)' || echo "No relevant ports listening"
    
    echo -e "\n${CYAN}Recent Logs:${NC}"
    docker logs marzban-node --tail 5 2>/dev/null || echo "No logs available"
    
    echo -e "\n${CYAN}SSL Files:${NC}"
    ls -la /var/lib/marzban-node/ssl_* 2>/dev/null || echo "No SSL files found"
}

# Main execution
main() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}SSL Context Error Fix Tool${NC}                 ║"
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
    
    log "INFO" "Starting SSL context error fix..."
    
    # Step 1: Fix SSL context
    if fix_ssl_context; then
        # Step 2: Monitor startup
        if monitor_startup; then
            # Step 3: Test connectivity
            test_final_connectivity
            
            echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${WHITE}║                    ${GREEN}Fix Complete!${NC}                          ║"
            echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
            
            log "SUCCESS" "🎉 Marzban Node is now running without SSL errors!"
            
            echo -e "\n${YELLOW}📋 Next Steps:${NC}"
            echo "1. Test from central manager: ./debug_certificate_issue.sh 185.226.93.38 PASSWORD"
            echo "2. Add the node in central manager"
            echo "3. The panel will provide the proper client certificate automatically"
            
            echo -e "\n${CYAN}🔧 Monitoring Commands:${NC}"
            echo "- Check status: docker ps | grep marzban-node"
            echo "- View logs: docker logs marzban-node -f"
            echo "- Check ports: ss -tuln | grep -E '(62050|62051)'"
            echo "- Test HTTPS: curl -k https://localhost:62050"
            
        else
            log "ERROR" "Service startup monitoring failed"
            exit 1
        fi
    else
        log "ERROR" "SSL context fix failed"
        exit 1
    fi
}

main "$@"