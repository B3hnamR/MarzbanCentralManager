#!/bin/bash
set -euo pipefail

# Marzban Node Deployer Script - Professional Edition v3.0
# Enhanced with better error handling, logging, and monitoring

# --- Global Variables ---
NODE_DOMAIN=""
NODE_NAME=""
MAIN_PANEL_IP=""
REINSTALL="false"
UPDATE_GEO="false"
BACKUP="false"

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

# --- Enhanced Logging ---
log() {
    local level="$1" msg="$2" ts
    ts=$(date '+%H:%M:%S')
    case "$level" in
        "SUCCESS") echo -e "[$ts] ${GREEN}✅ $msg${NC}" ;;
        "ERROR")   echo -e "[$ts] ${RED}❌ $msg${NC}" >&2 ;;
        "INFO")    echo -e "[$ts] ${BLUE}ℹ️  $msg${NC}" ;;
        "STEP")    echo -e "[$ts] ${PURPLE}🔧 $msg${NC}" ;;
        "WARNING") echo -e "[$ts] ${YELLOW}⚠️  $msg${NC}" ;;
        *)         echo -e "[$ts] $msg" ;;
    esac
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) NODE_DOMAIN="$2"; shift 2 ;;
        --name) NODE_NAME="$2"; shift 2 ;;
        --main-panel-ip) MAIN_PANEL_IP="$2"; shift 2 ;;
        --reinstall) REINSTALL="true"; shift 1 ;;
        --update-geo) UPDATE_GEO="true"; shift 1 ;;
        --backup) BACKUP="true"; shift 1 ;;
        *) log "ERROR" "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Helper Functions ---
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_system_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check available memory
    local mem_gb; mem_gb=$(free -g | awk 'NR==2{print $2}')
    if [ "$mem_gb" -lt 1 ]; then
        log "WARNING" "System has less than 1GB RAM. Performance may be affected."
    fi
    
    # Check disk space
    local disk_gb; disk_gb=$(df / | awk 'NR==2{print int($4/1024/1024)}')
    if [ "$disk_gb" -lt 5 ]; then
        log "WARNING" "Less than 5GB free disk space available."
    fi
    
    # Check architecture
    local arch; arch=$(uname -m)
    if [[ ! "$arch" =~ ^(x86_64|amd64|aarch64|arm64)$ ]]; then
        log "WARNING" "Architecture $arch may not be fully supported."
    fi
    
    log "SUCCESS" "System requirements check completed."
}

# --- Core Functions ---
create_node_backup() {
    log "STEP" "Creating comprehensive backup on this node..."
    local backup_file="/tmp/node_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    if tar -czf "$backup_file" \
        --warning=no-file-changed \
        "/opt/marzban-node/" \
        "/var/lib/marzban-node/" \
        "/etc/systemd/system/marzban-node*" \
        "/etc/haproxy/" \
        2>/dev/null; then # Added /etc/haproxy/ to backup path for completeness
        log "SUCCESS" "Node backup created: $backup_file"
        echo "$backup_file"  # Return backup file path
        return 0
    else
        log "ERROR" "Failed to create node backup."
        return 1
    fi
}

update_geo_files_on_node() {
    log "STEP" "Updating geo files with multiple sources..."
    local geo_dir="/var/lib/marzban-node/chocolate"
    mkdir -p "$geo_dir"
    cd "$geo_dir" || { log "ERROR" "Cannot access geo directory"; return 1; }
    
    log "INFO" "Downloading geo files from primary sources..."
    local success=false
    
    # Primary source: v2fly (most compatible)
    if wget -q --timeout=30 -O geosite.dat.tmp \
       "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat" && \
       [ -s geosite.dat.tmp ] && \
       wget -q --timeout=30 -O geoip.dat.tmp \
       "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat" && \
       [ -s geoip.dat.tmp ]; then
        
        mv geosite.dat.tmp geosite.dat
        mv geoip.dat.tmp geoip.dat
        success=true
        log "SUCCESS" "Geo files downloaded from v2fly sources."
        
    # Fallback source: Chocolate4U
    elif wget -q --timeout=30 -O geosite.dat.tmp \
         "https://github.com/Chocolate4U/Iran-sing-box-rules/releases/latest/download/geosite.dat" && \
         [ -s geosite.dat.tmp ] && \
         wget -q --timeout=30 -O geoip.dat.tmp \
         "https://github.com/Chocolate4U/Iran-sing-box-rules/releases/latest/download/geoip.dat" && \
         [ -s geoip.dat.tmp ]; then
        
        mv geosite.dat.tmp geosite.dat
        mv geoip.dat.tmp geoip.dat
        success=true
        log "WARNING" "Geo files downloaded from Chocolate4U (fallback source)."
    fi
    
    if [ "$success" = true ]; then
        chmod 644 *.dat
        chown root:root *.dat
        
        # Verify file integrity
        if [ -s geosite.dat ] && [ -s geoip.dat ]; then
            log "SUCCESS" "Geo files updated and verified. Restarting container..."
            cd /opt/marzban-node && docker compose restart >/dev/null 2>&1
            log "SUCCESS" "Geo files update completed successfully."
        else
            log "ERROR" "Downloaded geo files are empty or corrupted."
            return 1
        fi
    else
        log "ERROR" "Failed to download geo files from all sources."
        rm -f *.tmp 2>/dev/null || true
        return 1
    fi
    
    return 0
}

install_docker_enhanced() {
    log "STEP" "Installing Docker with enhanced configuration..."
    
    if ! command_exists docker; then
        log "INFO" "Docker not found. Installing from official repository..."
        
        # Install prerequisites
        apt update >/dev/null 2>&1
        apt install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null
        
        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        
        # Install Docker
        apt update >/dev/null 2>&1
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
        
        # Start and enable Docker
        systemctl start docker
        systemctl enable docker
        
        # Add current user to docker group
        usermod -aG docker "$USER" 2>/dev/null || true
        
        log "SUCCESS" "Docker installed and configured successfully."
    else
        log "INFO" "Docker is already installed."
    fi
    
    # Verify Docker installation
    if docker --version >/dev/null 2>&1; then
        log "SUCCESS" "Docker verification successful."
    else
        log "ERROR" "Docker installation verification failed."
        return 1
    fi
}

install_marzban_node() {
    log "STEP" "Installing Marzban Node..."
    
    # Create directories
    mkdir -p /opt/marzban-node /var/lib/marzban-node
    cd /opt/marzban-node || { log "ERROR" "Cannot access /opt/marzban-node"; return 1; }
    
    # Download latest Marzban Node
    log "INFO" "Downloading Marzban Node repository..."
    if [ -d ".git" ]; then
        git pull origin master >/dev/null 2>&1 || {
            log "WARNING" "Git pull failed, removing and re-cloning..."
            cd / && rm -rf /opt/marzban-node
            mkdir -p /opt/marzban-node
            cd /opt/marzban-node
            git clone https://github.com/Gozargah/Marzban-node.git . >/dev/null 2>&1
        }
    else
        git clone https://github.com/Gozargah/Marzban-node.git . >/dev/null 2>&1
    fi
    
    # Create docker-compose.yml with proper configuration
    log "INFO" "Creating optimized docker-compose.yml..."
    cat > docker-compose.yml << EOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      # IMPORTANT: XRAY_ASSETS_PATH must point to the directory containing geosite.dat and geoip.dat
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate" 
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /opt/marzban-node:/opt/marzban-node
      # Add this volume for geo files
      - /var/lib/marzban-node/chocolate:/var/lib/marzban-node/chocolate
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    
    # Set proper permissions
    chmod 644 docker-compose.yml
    chmod 700 /var/lib/marzban-node
    
    log "SUCCESS" "Marzban Node installation completed."
}

generate_ssl_certificates() {
    log "STEP" "Generating SSL certificates..."
    
    cd /var/lib/marzban-node || { log "ERROR" "Cannot access certificate directory"; return 1; }
    
    # Generate private key
    openssl genrsa -out ssl_key.pem 2048 2>/dev/null
    
    # Generate certificate
    openssl req -new -x509 -key ssl_key.pem -out ssl_cert.pem -days 365 -subj "/CN=${NODE_DOMAIN}" 2>/dev/null
    
    # Set proper permissions
    chmod 600 ssl_key.pem ssl_cert.pem
    chown root:root ssl_key.pem ssl_cert.pem
    
    log "SUCCESS" "SSL certificates generated successfully."
}

configure_firewall() {
    log "STEP" "Configuring firewall rules..."
    
    # Check if ufw is installed and active
    if command_exists ufw && ufw status | grep -q "Status: active"; then
        log "INFO" "Configuring UFW firewall..."
        ufw allow 62050/tcp comment "Marzban Node Service" >/dev/null 2>&1
        ufw allow 62051/tcp comment "Marzban Node API" >/dev/null 2>&1
        ufw allow from "$MAIN_PANEL_IP" comment "Marzban Panel Access" >/dev/null 2>&1
        log "SUCCESS" "UFW firewall configured."
    elif command_exists iptables; then
        log "INFO" "Configuring iptables firewall..."
        iptables -A INPUT -p tcp --dport 62050 -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -p tcp --dport 62051 -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -s "$MAIN_PANEL_IP" -j ACCEPT 2>/dev/null || true
        
        # Save iptables rules (handle different saving methods)
        if command_exists netfilter-persistent; then # Debian/Ubuntu
            netfilter-persistent save >/dev/null 2>&1
        elif command_exists service; then # Old init systems
            service iptables save >/dev/null 2>&1
        elif command_exists /usr/libexec/iptables/iptables.init; then # RHEL/CentOS
            /usr/libexec/iptables/iptables.init save >/dev/null 2>&1
        elif command_exists iptables-save; then # Generic
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        log "SUCCESS" "iptables firewall configured."
    else
        log "WARNING" "No firewall detected. Manual configuration may be required."
    fi
}

start_marzban_node() {
    log "STEP" "Starting Marzban Node service..."
    
    cd /opt/marzban-node || { log "ERROR" "Cannot access Marzban Node directory"; return 1; }
    
    # Pull latest image
    docker compose pull >/dev/null 2>&1
    
    # Start service
    if docker compose up -d >/dev/null 2>&1; then
        log "SUCCESS" "Marzban Node service started successfully."
        
        # Wait for service to be ready
        log "INFO" "Waiting for service to be ready..."
        sleep 10
        
        # Check service status
        if docker compose ps | grep -q "Up"; then
            log "SUCCESS" "Marzban Node is running and ready."
        else
            log "ERROR" "Marzban Node failed to start properly."
            docker compose logs --tail=20
            return 1
        fi
    else
        log "ERROR" "Failed to start Marzban Node service."
        return 1
    fi
}

perform_health_check() {
    log "STEP" "Performing comprehensive health check..."
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log "ERROR" "Docker service is not running."
        return 1
    fi
    
    # Check Marzban Node container
    if ! docker compose ps | grep -q "Up"; then
        log "ERROR" "Marzban Node container is not running."
        return 1
    fi
    
    # Check service ports
    local ports=("62050" "62051")
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            log "SUCCESS" "Port $port is listening."
        else
            log "WARNING" "Port $port is not listening."
        fi
    done
    
    # Check API endpoint (Marzban Node API, not panel)
    if curl -s --connect-timeout 5 http://localhost:62051/health >/dev/null 2>&1; then # Changed to 62051 for Xray API
        log "SUCCESS" "Health endpoint is responding."
    else
        log "WARNING" "Health endpoint is not responding (this may be normal for Marzban Node API)."
    fi
    
    log "SUCCESS" "Health check completed."
}

cleanup_installation() {
    log "INFO" "Cleaning up installation files..."
    
    # Remove temporary files
    rm -f /tmp/marzban_node_deployer.sh 2>/dev/null || true
    rm -f /tmp/*.tmp 2>/dev/null || true
    
    # Clean Docker system
    docker system prune -f >/dev/null 2>&1 || true
    
    log "SUCCESS" "Cleanup completed."
}

# --- Main Deployment Function ---
main_deployment() {
    log "INFO" "Starting Marzban Node Professional Deployment..."
    log "INFO" "Node: $NODE_NAME | Domain: $NODE_DOMAIN | Panel IP: $MAIN_PANEL_IP"
    
    # Validate required parameters
    if [ -z "$NODE_DOMAIN" ] || [ -z "$NODE_NAME" ] || [ -z "$MAIN_PANEL_IP" ]; then
        log "ERROR" "Missing required parameters. Usage: --domain <domain> --name <name> --main-panel-ip <ip>"
        exit 1
    fi
    
    # Create backup if requested
    if [ "$BACKUP" = "true" ]; then
        create_node_backup || log "WARNING" "Backup creation failed, continuing..."
    fi
    
    # System checks
    check_system_requirements
    
    # Install Docker
    install_docker_enhanced || { log "ERROR" "Docker installation failed"; exit 1; }
    
    # Install Marzban Node
    install_marzban_node || { log "ERROR" "Marzban Node installation failed"; exit 1; }
    
    # Generate SSL certificates
    generate_ssl_certificates || { log "ERROR" "SSL certificate generation failed"; exit 1; }
    
    # Configure firewall
    configure_firewall || log "WARNING" "Firewall configuration failed, continuing..."
    
    # Update geo files if requested (or transferred from main later)
    if [ "$UPDATE_GEO" = "true" ]; then
        update_geo_files_on_node || log "WARNING" "Geo files update failed, continuing..."
    fi
    
    # Start Marzban Node
    start_marzban_node || { log "ERROR" "Failed to start Marzban Node"; exit 1; }
    
    # Perform health check
    perform_health_check || log "WARNING" "Some health checks failed, but deployment may still be successful."
    
    # Cleanup
    cleanup_installation
    
    # Final summary
    log "SUCCESS" "🎉 Marzban Node deployment completed successfully!"
    echo ""
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Deployment Summary${NC}                      ║"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "📝 Node Name: $NODE_NAME"
    echo -e "🌐 Domain: $NODE_DOMAIN"
    echo -e "🔗 Service Port: 62050"
    echo -e "🔗 API Port: 62051"
    echo -e "📁 Installation Path: /opt/marzban-node"
    echo -e "🔐 Certificates Path: /var/lib/marzban-node"
    echo -e "✅ Status: Ready for Panel Connection"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "1. This node has been deployed successfully."
    echo "2. The Central Manager will now finalize the setup (API connection, certificate deployment)."
    echo "3. Please wait for the Central Manager to complete its process."
    echo ""
}

# --- Script Entry Point ---
main_deployment