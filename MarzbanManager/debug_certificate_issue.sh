#!/bin/bash
# Certificate Issue Debug Script
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
        DEBUG)   echo -e "[$timestamp] ${CYAN}🔧 DEBUG:${NC} $message";;
    esac
}

# Main debug function
debug_certificate_issue() {
    local node_ip="$1"
    local node_port="${2:-62050}"
    local ssh_user="${3:-root}"
    local ssh_password="$4"
    
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}Certificate Issue Debug Tool${NC}                ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "INFO" "Debugging certificate issue for node: $node_ip:$node_port"
    
    # Step 1: Test basic connectivity
    echo -e "\n${CYAN}=== Step 1: Basic Connectivity Test ===${NC}"
    if ping -c 3 -W 5 "$node_ip" >/dev/null 2>&1; then
        log "SUCCESS" "Host $node_ip is reachable"
    else
        log "ERROR" "Host $node_ip is unreachable"
        echo -e "${RED}❌ CRITICAL: Cannot reach the host. Check network connectivity.${NC}"
        return 1
    fi
    
    # Step 2: Test port connectivity
    echo -e "\n${CYAN}=== Step 2: Port Connectivity Test ===${NC}"
    if command -v nc >/dev/null 2>&1; then
        if timeout 10 nc -z "$node_ip" "$node_port" 2>/dev/null; then
            log "SUCCESS" "Port $node_port is open and accessible"
        else
            log "ERROR" "Port $node_port is not accessible"
            echo -e "${RED}❌ CRITICAL: Port $node_port is closed or filtered.${NC}"
            echo -e "${YELLOW}This is likely why certificate retrieval fails!${NC}"
            
            # Provide specific troubleshooting steps
            echo -e "\n${YELLOW}🔧 Troubleshooting Steps:${NC}"
            echo "1. SSH to the node and check if Marzban Node is running:"
            echo "   ssh $ssh_user@$node_ip"
            echo "   docker ps | grep marzban-node"
            echo ""
            echo "2. If container is not running, start it:"
            echo "   docker start marzban-node"
            echo ""
            echo "3. Check if ports are listening:"
            echo "   ss -tuln | grep -E '(62050|62051)'"
            echo ""
            echo "4. Check firewall rules:"
            echo "   ufw status"
            echo "   iptables -L"
            echo ""
            echo "5. Check container logs:"
            echo "   docker logs marzban-node --tail 50"
            
            return 1
        fi
    else
        log "WARNING" "netcat not available, installing..."
        apt-get update && apt-get install -y netcat-openbsd
    fi
    
    # Step 3: Test HTTPS connectivity
    echo -e "\n${CYAN}=== Step 3: HTTPS Connectivity Test ===${NC}"
    local https_url="https://$node_ip:$node_port"
    
    if command -v curl >/dev/null 2>&1; then
        local response
        response=$(curl -s -k --connect-timeout 10 --max-time 15 -w "%{http_code}" "$https_url" 2>/dev/null || echo "000")
        
        if [[ "$response" != "000" ]]; then
            log "SUCCESS" "HTTPS service is responding (HTTP $response)"
        else
            log "ERROR" "HTTPS service is not responding"
            
            # Try HTTP as fallback
            local http_url="http://$node_ip:$node_port"
            response=$(curl -s --connect-timeout 10 --max-time 15 -w "%{http_code}" "$http_url" 2>/dev/null || echo "000")
            
            if [[ "$response" != "000" ]]; then
                log "WARNING" "HTTP service is responding but HTTPS is not"
                echo -e "${YELLOW}⚠️  SSL certificate issue detected${NC}"
            else
                log "ERROR" "Neither HTTP nor HTTPS is responding"
                echo -e "${RED}❌ Service is not running properly${NC}"
            fi
        fi
    fi
    
    # Step 4: SSH and check service status
    if [[ -n "$ssh_password" ]]; then
        echo -e "\n${CYAN}=== Step 4: Remote Service Status Check ===${NC}"
        
        if command -v sshpass >/dev/null 2>&1; then
            log "INFO" "Checking remote service status via SSH..."
            
            # Check Docker status
            local docker_status
            docker_status=$(timeout 15 sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$ssh_user@$node_ip" "docker ps | grep marzban-node || echo 'NOT_RUNNING'" 2>/dev/null || echo "SSH_FAILED")
            
            if [[ "$docker_status" == "SSH_FAILED" ]]; then
                log "ERROR" "SSH connection failed"
                echo -e "${RED}❌ Cannot connect via SSH. Check SSH credentials.${NC}"
            elif echo "$docker_status" | grep -q "marzban-node" && ! echo "$docker_status" | grep -q "NOT_RUNNING"; then
                log "SUCCESS" "Marzban Node container is running"
                
                # Check container health
                local container_logs
                container_logs=$(timeout 15 sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$ssh_user@$node_ip" "docker logs marzban-node --tail 10 2>/dev/null || echo 'NO_LOGS'" 2>/dev/null || echo "SSH_FAILED")
                
                echo -e "\n${CYAN}Recent container logs:${NC}"
                echo "$container_logs"
                
            else
                log "ERROR" "Marzban Node container is not running"
                echo -e "${RED}❌ CRITICAL: Container is not running!${NC}"
                
                echo -e "\n${YELLOW}🔧 Fix Commands:${NC}"
                echo "SSH to the node and run:"
                echo "1. docker start marzban-node"
                echo "2. docker logs marzban-node"
                echo "3. If container fails to start, check: docker-compose up -d"
            fi
            
            # Check listening ports
            local port_status
            port_status=$(timeout 15 sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$ssh_user@$node_ip" "ss -tuln | grep -E '(62050|62051)' || echo 'NOT_LISTENING'" 2>/dev/null || echo "SSH_FAILED")
            
            if echo "$port_status" | grep -q -E "(62050|62051)" && ! echo "$port_status" | grep -q "NOT_LISTENING"; then
                log "SUCCESS" "Required ports are listening"
                echo "Listening ports: $port_status"
            else
                log "ERROR" "Required ports are not listening"
                echo -e "${RED}❌ Ports 62050/62051 are not listening${NC}"
            fi
            
        else
            log "WARNING" "sshpass not available, installing..."
            apt-get update && apt-get install -y sshpass
        fi
    fi
    
    # Step 5: SSL Certificate check
    echo -e "\n${CYAN}=== Step 5: SSL Certificate Check ===${NC}"
    if command -v openssl >/dev/null 2>&1; then
        log "INFO" "Testing SSL certificate..."
        
        local ssl_output
        ssl_output=$(timeout 15 openssl s_client -connect "$node_ip:$node_port" -servername "$node_ip" </dev/null 2>&1 || echo "SSL_FAILED")
        
        if echo "$ssl_output" | grep -q "CONNECTED"; then
            log "SUCCESS" "SSL connection established"
            
            # Extract certificate details
            local cert_subject=$(echo "$ssl_output" | grep "subject=" | head -1)
            local cert_verify=$(echo "$ssl_output" | grep "Verify return code:" | head -1)
            
            echo "Certificate: $cert_subject"
            echo "Verification: $cert_verify"
            
            if echo "$ssl_output" | grep -q "Verify return code: 0"; then
                log "SUCCESS" "SSL certificate is valid"
            else
                log "WARNING" "SSL certificate has verification issues"
                echo -e "${YELLOW}⚠️  Certificate may be self-signed or expired${NC}"
            fi
        else
            log "ERROR" "SSL connection failed"
            echo -e "${RED}❌ SSL handshake failed${NC}"
            
            if [[ -n "$ssh_password" ]] && command -v sshpass >/dev/null 2>&1; then
                echo -e "\n${YELLOW}🔧 SSL Certificate Fix:${NC}"
                echo "SSH to the node and regenerate certificates:"
                echo "1. cd /opt/marzban-node"
                echo "2. rm /var/lib/marzban-node/ssl_*.pem"
                echo "3. docker restart marzban-node"
                echo "4. Check logs: docker logs marzban-node"
            fi
        fi
    fi
    
    # Final recommendations
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${YELLOW}Final Diagnosis${NC}                        ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}📋 Most Likely Issues:${NC}"
    echo "1. ❌ Marzban Node service is not running"
    echo "2. ❌ Firewall is blocking port $node_port"
    echo "3. ❌ SSL certificates are invalid or missing"
    echo "4. ❌ Container failed to start properly"
    
    echo -e "\n${CYAN}🔧 Step-by-Step Fix:${NC}"
    echo "1. SSH to the node: ssh $ssh_user@$node_ip"
    echo "2. Check container: docker ps | grep marzban-node"
    echo "3. If not running: docker start marzban-node"
    echo "4. Check logs: docker logs marzban-node --tail 20"
    echo "5. Check ports: ss -tuln | grep -E '(62050|62051)'"
    echo "6. Check firewall: ufw status"
    echo "7. If SSL issues: rm /var/lib/marzban-node/ssl_*.pem && docker restart marzban-node"
    
    echo -e "\n${GREEN}✅ After fixing, test again with this script${NC}"
}

# Main execution
main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <node_ip> <ssh_password> [node_port] [ssh_user]"
        echo ""
        echo "Example: $0 185.226.93.38 mypassword 62050 root"
        echo ""
        echo "This will debug why certificate retrieval fails for the node."
        exit 1
    fi
    
    local node_ip="$1"
    local ssh_password="$2"
    local node_port="${3:-62050}"
    local ssh_user="${4:-root}"
    
    debug_certificate_issue "$node_ip" "$node_port" "$ssh_user" "$ssh_password"
}

main "$@"