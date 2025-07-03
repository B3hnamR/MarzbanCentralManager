#!/bin/bash
# Node Connection Debug Tool
# Professional Edition v3.1
# Author: B3hnamR

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        SUCCESS) echo -e "[$timestamp] ${GREEN}✅ SUCCESS:${NC} $message";;
        ERROR)   echo -e "[$timestamp] ${RED}❌ ERROR:${NC} $message";;
        WARNING) echo -e "[$timestamp] ${YELLOW}⚠️  WARNING:${NC} $message";;
        INFO)    echo -e "[$timestamp] ${BLUE}ℹ️  INFO:${NC} $message";;
        DEBUG)   echo -e "[$timestamp] ${PURPLE}🔧 DEBUG:${NC} $message";;
        *)       echo -e "[$timestamp] ${WHITE}📝 LOG:${NC} $message";;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Test network connectivity
test_network_connectivity() {
    local target_ip="$1"
    local target_port="$2"
    
    log "INFO" "Testing network connectivity to $target_ip:$target_port"
    
    # Test 1: Ping test
    log "DEBUG" "Testing ping connectivity..."
    if ping -c 3 -W 5 "$target_ip" >/dev/null 2>&1; then
        log "SUCCESS" "Ping test passed"
    else
        log "ERROR" "Ping test failed - host unreachable"
        return 1
    fi
    
    # Test 2: Port connectivity
    log "DEBUG" "Testing port connectivity..."
    if command_exists nc; then
        if timeout 10 nc -z "$target_ip" "$target_port" 2>/dev/null; then
            log "SUCCESS" "Port $target_port is open and accessible"
        else
            log "ERROR" "Port $target_port is not accessible"
            return 1
        fi
    elif command_exists telnet; then
        if timeout 10 bash -c "echo >/dev/tcp/$target_ip/$target_port" 2>/dev/null; then
            log "SUCCESS" "Port $target_port is open and accessible"
        else
            log "ERROR" "Port $target_port is not accessible"
            return 1
        fi
    else
        log "WARNING" "Neither nc nor telnet available for port testing"
    fi
    
    # Test 3: HTTP/HTTPS connectivity
    log "DEBUG" "Testing HTTP/HTTPS connectivity..."
    local protocols=("https" "http")
    local success=false
    
    for protocol in "${protocols[@]}"; do
        local url="${protocol}://${target_ip}:${target_port}"
        log "DEBUG" "Testing $url"
        
        if command_exists curl; then
            local response=$(curl -s -k --connect-timeout 10 --max-time 15 -w "%{http_code}" "$url" 2>/dev/null || echo "000")
            if [[ "$response" != "000" ]]; then
                log "SUCCESS" "$protocol connection successful (HTTP $response)"
                success=true
                break
            else
                log "WARNING" "$protocol connection failed"
            fi
        fi
    done
    
    if [[ "$success" == "false" ]]; then
        log "ERROR" "No HTTP/HTTPS connectivity established"
        return 1
    fi
    
    return 0
}

# Check node service status
check_node_service_status() {
    local node_ip="$1"
    local ssh_user="$2"
    local ssh_password="$3"
    local ssh_port="${4:-22}"
    
    log "INFO" "Checking node service status on $node_ip"
    
    # Create temporary expect script for SSH
    local expect_script=$(mktemp)
    cat > "$expect_script" << EOF
#!/usr/bin/expect -f
set timeout 30
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $ssh_port $ssh_user@$node_ip
expect {
    "password:" {
        send "$ssh_password\r"
        exp_continue
    }
    "$ " {
        send "echo 'SSH_CONNECTION_SUCCESS'\r"
        expect "SSH_CONNECTION_SUCCESS"
        
        # Check Docker status
        send "docker --version 2>/dev/null || echo 'DOCKER_NOT_FOUND'\r"
        expect -re "(Docker version|DOCKER_NOT_FOUND)"
        
        # Check if Marzban Node container is running
        send "docker ps | grep marzban-node || echo 'CONTAINER_NOT_RUNNING'\r"
        expect -re "(marzban-node|CONTAINER_NOT_RUNNING)"
        
        # Check if ports are listening
        send "ss -tuln | grep ':62050\\|:62051' || echo 'PORTS_NOT_LISTENING'\r"
        expect -re "(62050|62051|PORTS_NOT_LISTENING)"
        
        # Check container logs
        send "docker logs marzban-node --tail 20 2>/dev/null || echo 'NO_LOGS_AVAILABLE'\r"
        expect -re "(NO_LOGS_AVAILABLE|.*)"
        
        send "exit\r"
        expect eof
    }
    timeout {
        puts "SSH connection timeout"
        exit 1
    }
    eof {
        puts "SSH connection failed"
        exit 1
    }
}
EOF
    
    chmod +x "$expect_script"
    
    if command_exists expect; then
        log "DEBUG" "Running SSH diagnostics..."
        local ssh_output
        ssh_output=$("$expect_script" 2>&1 || echo "SSH_FAILED")
        
        echo -e "\n${CYAN}=== SSH Diagnostic Output ===${NC}"
        echo "$ssh_output"
        echo -e "${CYAN}=== End SSH Output ===${NC}\n"
        
        # Analyze output
        if echo "$ssh_output" | grep -q "SSH_CONNECTION_SUCCESS"; then
            log "SUCCESS" "SSH connection established"
        else
            log "ERROR" "SSH connection failed"
            rm -f "$expect_script"
            return 1
        fi
        
        if echo "$ssh_output" | grep -q "Docker version"; then
            log "SUCCESS" "Docker is installed and running"
        else
            log "ERROR" "Docker is not installed or not running"
        fi
        
        if echo "$ssh_output" | grep -q "marzban-node" && ! echo "$ssh_output" | grep -q "CONTAINER_NOT_RUNNING"; then
            log "SUCCESS" "Marzban Node container is running"
        else
            log "ERROR" "Marzban Node container is not running"
        fi
        
        if echo "$ssh_output" | grep -q -E "(62050|62051)" && ! echo "$ssh_output" | grep -q "PORTS_NOT_LISTENING"; then
            log "SUCCESS" "Required ports are listening"
        else
            log "ERROR" "Required ports (62050, 62051) are not listening"
        fi
        
    else
        log "ERROR" "expect command not found - cannot perform SSH diagnostics"
        log "INFO" "Install expect: apt-get install expect"
    fi
    
    rm -f "$expect_script"
    return 0
}

# Check SSL certificates
check_ssl_certificates() {
    local node_ip="$1"
    local node_port="$2"
    
    log "INFO" "Checking SSL certificates for $node_ip:$node_port"
    
    if command_exists openssl; then
        log "DEBUG" "Testing SSL certificate..."
        local ssl_output
        ssl_output=$(timeout 15 openssl s_client -connect "$node_ip:$node_port" -servername "$node_ip" </dev/null 2>&1 || echo "SSL_FAILED")
        
        if echo "$ssl_output" | grep -q "CONNECTED"; then
            log "SUCCESS" "SSL connection established"
            
            # Extract certificate info
            local cert_subject=$(echo "$ssl_output" | grep "subject=" | head -1)
            local cert_issuer=$(echo "$ssl_output" | grep "issuer=" | head -1)
            local cert_verify=$(echo "$ssl_output" | grep "Verify return code:" | head -1)
            
            log "INFO" "Certificate Subject: $cert_subject"
            log "INFO" "Certificate Issuer: $cert_issuer"
            log "INFO" "Certificate Verification: $cert_verify"
        else
            log "ERROR" "SSL connection failed"
            log "DEBUG" "SSL Error Details: $ssl_output"
        fi
    else
        log "WARNING" "openssl command not found - cannot check SSL certificates"
    fi
}

# Test API endpoint
test_api_endpoint() {
    local node_ip="$1"
    local node_port="$2"
    
    log "INFO" "Testing API endpoint $node_ip:$node_port"
    
    local protocols=("https" "http")
    
    for protocol in "${protocols[@]}"; do
        local url="${protocol}://${node_ip}:${node_port}"
        log "DEBUG" "Testing $protocol API endpoint..."
        
        if command_exists curl; then
            local response
            response=$(curl -s -k --connect-timeout 10 --max-time 15 -w "HTTP_CODE:%{http_code}|TIME:%{time_total}" "$url" 2>&1 || echo "CURL_FAILED")
            
            local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
            local time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
            
            if [[ -n "$http_code" && "$http_code" != "000" ]]; then
                log "SUCCESS" "$protocol API responded with HTTP $http_code (${time_total}s)"
                
                # Try to get more info about the service
                local health_url="${url}/health"
                local health_response
                health_response=$(curl -s -k --connect-timeout 5 --max-time 10 "$health_url" 2>/dev/null || echo "NO_HEALTH_ENDPOINT")
                
                if [[ "$health_response" != "NO_HEALTH_ENDPOINT" ]]; then
                    log "INFO" "Health endpoint response: $health_response"
                fi
                
                return 0
            else
                log "WARNING" "$protocol API connection failed"
            fi
        fi
    done
    
    log "ERROR" "All API endpoint tests failed"
    return 1
}

# Generate diagnostic report
generate_diagnostic_report() {
    local node_ip="$1"
    local node_port="$2"
    local ssh_user="$3"
    local ssh_password="$4"
    local ssh_port="${5:-22}"
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              ${CYAN}Node Connection Diagnostic Report${NC}              ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    log "INFO" "Starting comprehensive diagnostic for node $node_ip:$node_port"
    log "INFO" "SSH: $ssh_user@$node_ip:$ssh_port"
    
    echo -e "\n${PURPLE}=== Network Connectivity Test ===${NC}"
    test_network_connectivity "$node_ip" "$node_port"
    
    echo -e "\n${PURPLE}=== SSL Certificate Test ===${NC}"
    check_ssl_certificates "$node_ip" "$node_port"
    
    echo -e "\n${PURPLE}=== API Endpoint Test ===${NC}"
    test_api_endpoint "$node_ip" "$node_port"
    
    echo -e "\n${PURPLE}=== Node Service Status Check ===${NC}"
    check_node_service_status "$node_ip" "$ssh_user" "$ssh_password" "$ssh_port"
    
    echo -e "\n${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    ${GREEN}Diagnostic Complete${NC}                     ║"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Provide recommendations
    echo -e "${YELLOW}📋 Recommendations:${NC}"
    echo "1. If network connectivity failed: Check firewall rules and network configuration"
    echo "2. If SSL failed: Regenerate SSL certificates on the node"
    echo "3. If API failed: Check if Marzban Node service is running"
    echo "4. If SSH failed: Verify SSH credentials and network access"
    echo "5. If ports not listening: Restart Marzban Node container"
    echo ""
    echo -e "${CYAN}🔧 Common fixes:${NC}"
    echo "   - Restart node: docker restart marzban-node"
    echo "   - Check logs: docker logs marzban-node"
    echo "   - Regenerate certs: rm /var/lib/marzban-node/ssl_*.pem && restart"
    echo "   - Check firewall: ufw status / iptables -L"
}

# Main function
main() {
    if [[ $# -lt 4 ]]; then
        echo "Usage: $0 <node_ip> <node_port> <ssh_user> <ssh_password> [ssh_port]"
        echo ""
        echo "Example: $0 185.226.93.38 62050 root mypassword 22"
        exit 1
    fi
    
    local node_ip="$1"
    local node_port="$2"
    local ssh_user="$3"
    local ssh_password="$4"
    local ssh_port="${5:-22}"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log "WARNING" "Not running as root - some tests may fail"
    fi
    
    # Check required tools
    local missing_tools=()
    for tool in curl ping; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "WARNING" "Missing tools: ${missing_tools[*]}"
        log "INFO" "Install with: apt-get install ${missing_tools[*]}"
    fi
    
    generate_diagnostic_report "$node_ip" "$node_port" "$ssh_user" "$ssh_password" "$ssh_port"
}

# Execute main function
main "$@"