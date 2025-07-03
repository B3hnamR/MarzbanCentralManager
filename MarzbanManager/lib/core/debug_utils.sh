#!/bin/bash
# Marzban Central Manager - Debug Utilities Module
# Professional Edition v3.1
# Author: B3hnamR

# ============================================================================
# NODE CONNECTION DEBUG FUNCTIONS
# ============================================================================

# Debug node connection issues
debug_node_connection() {
    local node_ip="$1"
    local node_port="${2:-62050}"
    local ssh_user="${3:-root}"
    local ssh_password="$4"
    local ssh_port="${5:-22}"
    
    log_info "Starting node connection debug for $node_ip:$node_port"
    
    echo -e "\n${CYAN}=== Node Connection Diagnostic ===${NC}"
    echo -e "Target: $node_ip:$node_port"
    echo -e "SSH: $ssh_user@$node_ip:$ssh_port"
    echo ""
    
    # Test 1: Basic connectivity
    log_step "Testing basic connectivity..."
    if ping -c 3 -W 5 "$node_ip" >/dev/null 2>&1; then
        log_success "Ping test passed"
    else
        log_error "Ping test failed - host unreachable"
        return 1
    fi
    
    # Test 2: Port connectivity
    log_step "Testing port connectivity..."
    if command_exists nc; then
        if timeout 10 nc -z "$node_ip" "$node_port" 2>/dev/null; then
            log_success "Port $node_port is accessible"
        else
            log_error "Port $node_port is not accessible"
            log_warning "This is likely the main issue!"
        fi
    else
        log_warning "netcat not available for port testing"
    fi
    
    # Test 3: HTTP/HTTPS connectivity
    log_step "Testing HTTP/HTTPS connectivity..."
    local protocols=("https" "http")
    local connection_success=false
    
    for protocol in "${protocols[@]}"; do
        local url="${protocol}://${node_ip}:${node_port}"
        log_debug "Testing $url"
        
        if command_exists curl; then
            local response
            response=$(curl -s -k --connect-timeout 10 --max-time 15 -w "%{http_code}" "$url" 2>/dev/null || echo "000")
            
            if [[ "$response" != "000" ]]; then
                log_success "$protocol connection successful (HTTP $response)"
                connection_success=true
                break
            else
                log_warning "$protocol connection failed"
            fi
        fi
    done
    
    if [[ "$connection_success" == "false" ]]; then
        log_error "No HTTP/HTTPS connectivity - service may not be running"
    fi
    
    # Test 4: SSH connectivity and service check
    if [[ -n "$ssh_password" ]]; then
        log_step "Testing SSH connectivity and service status..."
        debug_node_ssh_status "$node_ip" "$ssh_user" "$ssh_password" "$ssh_port"
    else
        log_warning "No SSH password provided - skipping SSH diagnostics"
    fi
    
    # Provide recommendations
    echo -e "\n${YELLOW}📋 Diagnostic Summary and Recommendations:${NC}"
    
    if ! ping -c 1 -W 5 "$node_ip" >/dev/null 2>&1; then
        echo "❌ Network connectivity issue:"
        echo "   - Check if the server is online"
        echo "   - Verify IP address is correct"
        echo "   - Check network routing"
    fi
    
    if command_exists nc && ! timeout 5 nc -z "$node_ip" "$node_port" 2>/dev/null; then
        echo "❌ Port accessibility issue:"
        echo "   - Check if Marzban Node service is running"
        echo "   - Verify firewall rules (ufw, iptables)"
        echo "   - Check if port $node_port is listening"
    fi
    
    if [[ "$connection_success" == "false" ]]; then
        echo "❌ Service connectivity issue:"
        echo "   - Restart Marzban Node: docker restart marzban-node"
        echo "   - Check container logs: docker logs marzban-node"
        echo "   - Verify SSL certificates are valid"
    fi
    
    echo -e "\n${CYAN}🔧 Quick Fix Commands:${NC}"
    echo "1. Check service status: docker ps | grep marzban-node"
    echo "2. Restart service: docker restart marzban-node"
    echo "3. Check logs: docker logs marzban-node --tail 50"
    echo "4. Check ports: ss -tuln | grep -E '(62050|62051)'"
    echo "5. Check firewall: ufw status"
    
    return 0
}

# Debug SSH connection and service status
debug_node_ssh_status() {
    local node_ip="$1"
    local ssh_user="$2"
    local ssh_password="$3"
    local ssh_port="$4"
    
    log_debug "Testing SSH connection to $ssh_user@$node_ip:$ssh_port"
    
    # Create a simple SSH test
    local ssh_test_result
    ssh_test_result=$(timeout 15 sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$ssh_port" "$ssh_user@$node_ip" "echo 'SSH_SUCCESS'" 2>/dev/null || echo "SSH_FAILED")
    
    if [[ "$ssh_test_result" == "SSH_SUCCESS" ]]; then
        log_success "SSH connection successful"
        
        # Check Docker and Marzban Node status
        log_debug "Checking Docker and Marzban Node status..."
        
        local docker_status
        docker_status=$(timeout 15 sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$ssh_port" "$ssh_user@$node_ip" "docker ps | grep marzban-node || echo 'CONTAINER_NOT_RUNNING'" 2>/dev/null || echo "SSH_COMMAND_FAILED")
        
        if echo "$docker_status" | grep -q "marzban-node" && ! echo "$docker_status" | grep -q "CONTAINER_NOT_RUNNING"; then
            log_success "Marzban Node container is running"
        else
            log_error "Marzban Node container is not running"
            log_info "Try: docker start marzban-node"
        fi
        
        # Check listening ports
        local port_status
        port_status=$(timeout 15 sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$ssh_port" "$ssh_user@$node_ip" "ss -tuln | grep -E '(62050|62051)' || echo 'PORTS_NOT_LISTENING'" 2>/dev/null || echo "SSH_COMMAND_FAILED")
        
        if echo "$port_status" | grep -q -E "(62050|62051)" && ! echo "$port_status" | grep -q "PORTS_NOT_LISTENING"; then
            log_success "Required ports are listening"
        else
            log_error "Required ports (62050, 62051) are not listening"
            log_info "Service may not be started properly"
        fi
        
    else
        log_error "SSH connection failed"
        log_warning "Cannot perform remote diagnostics"
        
        if ! command_exists sshpass; then
            log_info "Install sshpass for automated SSH testing: apt-get install sshpass"
        fi
    fi
}

# Quick node health check
quick_node_health_check() {
    local node_ip="$1"
    local node_port="${2:-62050}"
    
    log_info "Quick health check for $node_ip:$node_port"
    
    # Test basic connectivity
    if ping -c 1 -W 3 "$node_ip" >/dev/null 2>&1; then
        echo "✅ Host is reachable"
    else
        echo "❌ Host is unreachable"
        return 1
    fi
    
    # Test port
    if command_exists nc && timeout 5 nc -z "$node_ip" "$node_port" 2>/dev/null; then
        echo "✅ Port $node_port is open"
    else
        echo "❌ Port $node_port is closed or filtered"
        return 1
    fi
    
    # Test HTTP response
    if command_exists curl; then
        local http_code
        http_code=$(curl -s -k --connect-timeout 5 --max-time 10 -w "%{http_code}" "https://$node_ip:$node_port" -o /dev/null 2>/dev/null || echo "000")
        
        if [[ "$http_code" != "000" ]]; then
            echo "✅ HTTPS service responding (HTTP $http_code)"
        else
            # Try HTTP
            http_code=$(curl -s --connect-timeout 5 --max-time 10 -w "%{http_code}" "http://$node_ip:$node_port" -o /dev/null 2>/dev/null || echo "000")
            if [[ "$http_code" != "000" ]]; then
                echo "✅ HTTP service responding (HTTP $http_code)"
            else
                echo "❌ No HTTP/HTTPS response"
                return 1
            fi
        fi
    fi
    
    echo "✅ Node appears to be healthy"
    return 0
}

# Initialize debug utilities
init_debug_utils() {
    return 0
}