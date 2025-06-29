#!/bin/bash
set -euo pipefail

log() {
    echo ">> $1"
}

# Install Docker
if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker..."
    apt-get update -y >/dev/null && apt-get install -y ca-certificates curl gnupg >/dev/null
    install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y >/dev/null && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
fi

# Prepare Marzban Node environment
log "Preparing Marzban Node environment..."
mkdir -p /opt/marzban-node /var/lib/marzban-node
cd /opt/marzban-node
if [ ! -d ".git" ]; then git clone https://github.com/Gozargah/Marzban-node.git . >/dev/null 2>&1; else git pull >/dev/null 2>&1; fi

# Create docker-compose file
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

# Create self-signed server certs
openssl genrsa -out /var/lib/marzban-node/ssl_key.pem 2048 >/dev/null 2>&1
openssl req -new -x509 -key /var/lib/marzban-node/ssl_key.pem -out /var/lib/marzban-node/ssl_cert.pem -days 365 -subj "/CN=marzban-node" >/dev/null 2>&1

log "Environment is ready. Node service is NOT started."