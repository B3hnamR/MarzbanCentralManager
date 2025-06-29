#!/bin/bash
set -euo pipefail

# Marzban Node Deployer - Final Edition

log() {
    echo ">> $1"
}

# 1. Install Docker if not present
if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y ca-certificates curl gnupg >/dev/null 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y >/dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    log "Docker installed successfully."
fi

# 2. Prepare Marzban Node environment
log "Preparing Marzban Node environment..."
mkdir -p /opt/marzban-node /var/lib/marzban-node
cd /opt/marzban-node
if [ ! -d ".git" ]; then git clone https://github.com/Gozargah/Marzban-node.git . >/dev/null 2>&1; else git pull >/dev/null 2>&1; fi

# 3. Create docker-compose file
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
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
EOF

# 4. Create self-signed certs AND a dummy client cert to allow the service to start
openssl genrsa -out /var/lib/marzban-node/ssl_key.pem 2048 >/dev/null 2>&1
openssl req -new -x509 -key /var/lib/marzban-node/ssl_key.pem -out /var/lib/marzban-node/ssl_cert.pem -days 365 -subj "/CN=marzban-node" >/dev/null 2>&1
touch /var/lib/marzban-node/ssl_client_cert.pem

# 5. Start the service with the dummy cert
log "Starting node with dummy certificate..."
docker compose pull >/dev/null 2>&1
docker compose up -d

log "Node environment is ready and service is running in standalone mode."