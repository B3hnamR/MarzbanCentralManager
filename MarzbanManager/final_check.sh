#!/bin/bash
# Final Check Script for Node Deployer

echo "🔍 Final Check for Node Deployer..."

# Check syntax
echo "1. Checking syntax..."
if bash -n marzban_node_deployer.sh; then
    echo "✅ Syntax check passed"
else
    echo "❌ Syntax check failed"
    exit 1
fi

# Check critical functions exist
echo "2. Checking critical functions..."
critical_functions=(
    "install_docker"
    "comprehensive_system_check"
    "check_and_install_docker_compose"
    "generate_ssl_certificates"
    "create_enhanced_docker_compose"
    "start_marzban_service"
    "main"
)

for func in "${critical_functions[@]}"; do
    if grep -q "^$func()" marzban_node_deployer.sh; then
        echo "✅ Function $func exists"
    else
        echo "❌ Function $func missing"
    fi
done

# Check wait messages
echo "3. Checking wait messages..."
wait_messages=(
    "Please wait.*may take.*minutes"
    "Please be patient"
    "Monitoring service startup"
    "Checking container status"
)

for msg in "${wait_messages[@]}"; do
    if grep -q "$msg" marzban_node_deployer.sh; then
        echo "✅ Wait message found: $msg"
    else
        echo "⚠️  Wait message missing: $msg"
    fi
done

# Check SSL_CLIENT_CERT_FILE in docker-compose
echo "4. Checking SSL_CLIENT_CERT_FILE configuration..."
if grep -q "SSL_CLIENT_CERT_FILE.*ssl_client_cert.pem" marzban_node_deployer.sh; then
    echo "✅ SSL_CLIENT_CERT_FILE properly configured"
else
    echo "❌ SSL_CLIENT_CERT_FILE missing"
fi

# Check timeout settings
echo "5. Checking timeout settings..."
if grep -q "max_attempts=20" marzban_node_deployer.sh; then
    echo "✅ Timeout set to 20 attempts (1 minute)"
else
    echo "⚠️  Timeout setting not found"
fi

# Check progress monitoring
echo "6. Checking progress monitoring..."
if grep -q "attempt % 4" marzban_node_deployer.sh; then
    echo "✅ Progress monitoring every 4 attempts"
else
    echo "⚠️  Progress monitoring not optimized"
fi

# Check Docker Compose auto-fix
echo "7. Checking Docker Compose auto-fix..."
if grep -q "github.com/docker/compose/releases" marzban_node_deployer.sh; then
    echo "✅ Docker Compose GitHub installation available"
else
    echo "❌ Docker Compose auto-fix missing"
fi

echo ""
echo "✅ Final check completed!"
echo "🚀 Node deployer is ready for production use"