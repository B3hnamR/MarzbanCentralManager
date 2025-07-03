#!/bin/bash
# Fix Node Deployment Issues
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

# Fix package manager lock
fix_package_lock() {
    log "STEP" "Fixing package manager lock..."
    
    # Kill unattended-upgrades if running
    if pgrep -f unattended-upgr >/dev/null; then
        log "INFO" "Stopping unattended-upgrades..."
        systemctl stop unattended-upgrades || true
        pkill -f unattended-upgr || true
        sleep 5
    fi
    
    # Remove lock files
    log "INFO" "Removing lock files..."
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/dpkg/lock
    rm -f /var/cache/apt/archives/lock
    
    # Reconfigure dpkg
    log "INFO" "Reconfiguring dpkg..."
    dpkg --configure -a
    
    log "SUCCESS" "Package manager lock fixed"
}

# Install Docker Compose
install_docker_compose() {
    log "STEP" "Installing Docker Compose..."
    
    # Update package list
    apt-get update -y
    
    # Install docker-compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        log "INFO" "Installing docker-compose package..."
        apt-get install -y docker-compose
        
        # Verify installation
        if command -v docker-compose >/dev/null 2>&1; then
            log "SUCCESS" "Docker Compose installed successfully"
            docker-compose --version
        else
            log "ERROR" "Docker Compose installation failed"
            return 1
        fi
    else
        log "INFO" "Docker Compose is already installed"
        docker-compose --version
    fi
}

# Setup Marzban Node properly
setup_marzban_node() {
    log "STEP" "Setting up Marzban Node..."
    
    # Create directory structure
    log "INFO" "Creating directory structure..."
    mkdir -p /opt/marzban-node
    mkdir -p /var/lib/marzban-node
    mkdir -p /var/lib/marzban-node/chocolate
    
    cd /opt/marzban-node
    
    # Clone or update repository
    if [ ! -d ".git" ]; then
        log "INFO" "Cloning Marzban Node repository..."
        git clone https://github.com/Gozargah/Marzban-node.git . || {
            log "ERROR" "Failed to clone repository"
            return 1
        }
    else
        log "INFO" "Updating existing repository..."
        git pull || log "WARNING" "Failed to update repository"
    fi
    
    # Create enhanced docker-compose.yml
    log "INFO" "Creating docker-compose.yml..."
    cat > docker-compose.yml << 'EOF'
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
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
      - /var/lib/marzban-node/chocolate:/var/lib/marzban-node/chocolate
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "ss", "-tuln", "|", "grep", ":62050"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
    
    log "SUCCESS" "Docker Compose configuration created"
}

# Generate SSL certificates
generate_ssl_certificates() {
    log "STEP" "Generating SSL certificates..."
    
    # Generate private key
    openssl genrsa -out /var/lib/marzban-node/ssl_key.pem 4096
    
    # Generate self-signed certificate
    openssl req -new -x509 -key /var/lib/marzban-node/ssl_key.pem \
        -out /var/lib/marzban-node/ssl_cert.pem -days 3650 \
        -subj "/C=US/ST=State/L=City/O=MarzbanNode/OU=IT/CN=marzban-node"
    
    # Set proper permissions
    chmod 600 /var/lib/marzban-node/ssl_key.pem
    chmod 644 /var/lib/marzban-node/ssl_cert.pem
    chown root:root /var/lib/marzban-node/ssl_*.pem
    
    # Create placeholder client cert (will be replaced by panel)
    touch /var/lib/marzban-node/ssl_client_cert.pem
    chmod 600 /var/lib/marzban-node/ssl_client_cert.pem
    
    log "SUCCESS" "SSL certificates generated"
}

# Download geo files
download_geo_files() {
    log "STEP" "Downloading geo files..."
    
    local geo_dir="/var/lib/marzban-node/chocolate"
    
    # Download geoip.dat
    if curl -fsSL -o "$geo_dir/geoip.dat" "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"; then
        log "SUCCESS" "Downloaded geoip.dat"
    else
        log "WARNING" "Failed to download geoip.dat"
    fi
    
    # Download geosite.dat
    if curl -fsSL -o "$geo_dir/geosite.dat" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"; then
        log "SUCCESS" "Downloaded geosite.dat"
    else
        log "WARNING" "Failed to download geosite.dat"
    fi
    
    # Set permissions
    chmod 644 "$geo_dir"/*.dat 2>/dev/null || true
    chown root:root "$geo_dir"/*.dat 2>/dev/null || true
}

# Start Marzban Node service
start_marzban_node() {
    log "STEP" "Starting Marzban Node service..."
    
    cd /opt/marzban-node
    
    # Pull latest image
    docker-compose pull
    
    # Start service
    docker-compose up -d
    
    # Wait for service to start
    log "INFO" "Waiting for service to start..."
    local attempts=0
    local max_attempts=30
    
    while [ $attempts -lt $max_attempts ]; do
        if docker ps | grep -q marzban-node; then
            log "SUCCESS" "Container is running"
            break
        fi
        
        sleep 2
        attempts=$((attempts + 1))
        
        if [ $attempts -eq $max_attempts ]; then
            log "ERROR" "Container failed to start"
            docker-compose logs
            return 1
        fi
    done
    
    # Wait for port to be listening
    log "INFO" "Waiting for port 62050 to be listening..."
    attempts=0
    max_attempts=60
    
    while [ $attempts -lt $max_attempts ]; do
        if ss -tuln | grep -q ':62050'; then
            log "SUCCESS" "Service is listening on port 62050"
            break
        fi
        
        sleep 3
        attempts=$((attempts + 1))
        
        if [ $attempts -eq $max_attempts ]; then
            log "ERROR" "Service failed to listen on port 62050"
            docker logs marzban-node --tail 20
            return 1
        fi
        
        if [ $((attempts % 10)) -eq 0 ]; then
            log "INFO" "Still waiting... (attempt $attempts/$max_attempts)"
        fi
    done
    
    log "SUCCESS" "Marzban Node service started successfully"
}

# Verify installation
verify_installation() {
    log "STEP" "Verifying installation..."
    
    # Check container status
    if docker ps | grep -q marzban-node; then
        log "SUCCESS" "✅ Container is running"
    else
        log "ERROR" "❌ Container is not running"
        return 1
    fi
    
    # Check listening ports
    if ss -tuln | grep -q ':62050'; then
        log "SUCCESS" "✅ Port 62050 is listening"
    else
        log "ERROR" "❌ Port 62050 is not listening"
        return 1
    fi
    
    if ss -tuln | grep -q ':62051'; then
        log "SUCCESS" "✅ Port 62051 is listening"
    else
        log "WARNING" "⚠️  Port 62051 is not listening (may be normal)"
    fi
    
    # Test HTTPS connectivity
    if curl -k -s --connect-timeout 5 https://localhost:62050 >/dev/null 2>&1; then
        log "SUCCESS" "✅ HTTPS service is responding"
    else
        log "WARNING" "⚠️  HTTPS service test failed (may be normal for initial setup)"
    fi
    
    # Show container logs
    echo -e "\n${CYAN}=== Recent Container Logs ===${NC}"
    docker logs marzban-node --tail 10
    
    echo -e "\n${GREEN}✅ Installation verification completed${NC}"
}

# Main execution
main() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}Marzban Node Fix & Setup Tool${NC}                ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    log "INFO" "Starting Marzban Node fix and setup process..."
    
    # Step 1: Fix package lock
    fix_package_lock
    
    # Step 2: Install Docker Compose
    install_docker_compose
    
    # Step 3: Setup Marzban Node
    setup_marzban_node
    
    # Step 4: Generate SSL certificates
    generate_ssl_certificates
    
    # Step 5: Download geo files
    download_geo_files
    
    # Step 6: Start service
    start_marzban_node
    
    # Step 7: Verify installation
    verify_installation
    
    echo -e "\n${WHITE}╔════════════════════════════���═══════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Setup Complete!${NC}                        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "SUCCESS" "🎉 Marzban Node setup completed successfully!"
    log "INFO" "Service endpoint: https://$(hostname -I | awk '{print $1}'):62050"
    log "INFO" "You can now try to retrieve the client certificate from the panel"
    
    echo -e "\n${YELLOW}📋 Next Steps:${NC}"
    echo "1. Go back to your central manager"
    echo "2. Try to add/import the node again"
    echo "3. The certificate retrieval should now work"
    echo ""
    echo -e "${CYAN}🔧 Useful Commands:${NC}"
    echo "- Check status: docker ps | grep marzban-node"
    echo "- View logs: docker logs marzban-node"
    echo "- Restart: docker restart marzban-node"
    echo "- Check ports: ss -tuln | grep -E '(62050|62051)'"
}

main "$@"