#!/bin/bash
set -euo pipefail

# Marzban Node Deployer Script - Professional Edition v3.0

# --- Global Variables ---
NODE_DOMAIN=""
NODE_NAME=""
MAIN_PANEL_IP=""

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

# --- Enhanced Logging ---
log() {
    local level="$1" msg="$2"
    case "$level" in
        "SUCCESS") echo -e "${GREEN}✅ $msg${NC}" ;;
        "ERROR")   echo -e "${RED}❌ $msg${NC}" >&2 ;;
        "INFO")    echo -e "${BLUE}ℹ️  $msg${NC}" ;;
        "STEP")    echo -e "${PURPLE}🔧 $msg${NC}" ;;
        *)         echo -e "$msg" ;;
    esac
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) NODE_DOMAIN="$2"; shift 2 ;;
        --name) NODE_NAME="$2"; shift 2 ;;
        --main-panel-ip) MAIN_PANEL_IP="$2"; shift 2 ;;
        *) log "ERROR" "Unknown option: $1"; exit 1 ;;
    esac
done

command_exists() { command -v "$1" >/dev/null 2>&1; }

install_docker_enhanced() {
    log "STEP" "Installing Docker..."
    if ! command_exists docker; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg >/dev/null 2>&1
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -y >/dev/null 2>&1
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
        systemctl start docker && systemctl enable docker
        log "SUCCESS" "Docker installed."
    else
        log "INFO" "Docker is already installed."
    fi
}

# --- Main Deployment Function ---
main_deployment() {
    log "INFO" "Starting Marzban Node Professional Deployment..."
    install_docker_enhanced
    
    log "STEP" "Configuring Marzban Node..."
    mkdir -p /opt/marzban-node /var/lib/marzban-node/chocolate
    cd /opt/marzban-node
    if [ ! -d ".git" ]; then git clone https://github.com/Gozargah/Marzban-node.git . >/dev/null 2>&1; else git pull >/dev/null 2>&1; fi
    
    # Create docker-compose with SSL_CLIENT_CERT_FILE commented out initially
    cat > docker-compose.yml << EOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SERVICE_PROTOCOL: "rest"
      SERVICE_PORT: 62050
      XRAY_API_PORT: 62051
      XRAY_ASSETS_PATH: "/var/lib/marzban-node/chocolate"
      # The following lines will be uncommented by the main manager script later
      # SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      # SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      # SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
EOF

    # Generate self-signed certs for the node itself (not for panel communication yet)
    openssl genrsa -out /var/lib/marzban-node/ssl_key.pem 2048 >/dev/null 2>&1
    openssl req -new -x509 -key /var/lib/marzban-node/ssl_key.pem -out /var/lib/marzban-node/ssl_cert.pem -days 365 -subj "/CN=${NODE_DOMAIN}" >/dev/null 2>&1
    
    # Start the service in its basic mode (without panel cert)
    log "STEP" "Starting node in standalone mode for initial health check by panel..."
    docker compose pull >/dev/null 2>&1
    docker compose up -d
    
    log "SUCCESS" "Node deployed in standalone mode, ready for panel registration."
}

main_deployment