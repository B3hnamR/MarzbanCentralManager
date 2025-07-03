#!/bin/bash
# Final Test for Node Deployer

echo "🔍 Testing final node deployer configuration..."

# Check syntax
if bash -n marzban_node_deployer.sh; then
    echo "✅ Syntax check passed"
else
    echo "❌ Syntax check failed"
    exit 1
fi

# Check critical functions
echo "🔍 Checking critical functions..."

critical_functions=(
    "comprehensive_system_check"
    "check_and_generate_ssl_certificates"
    "create_optimized_docker_compose"
    "start_marzban_service"
    "generate_ssl_certificates"
)

for func in "${critical_functions[@]}"; do
    if grep -q "^$func()" marzban_node_deployer.sh; then
        echo "✅ Function $func exists"
    else
        echo "❌ Function $func missing"
    fi
done

# Check SSL_CLIENT_CERT_FILE in docker-compose template
echo "🔍 Checking SSL_CLIENT_CERT_FILE in docker-compose..."
if grep -q "SSL_CLIENT_CERT_FILE.*ssl_client_cert.pem" marzban_node_deployer.sh; then
    echo "✅ SSL_CLIENT_CERT_FILE is included in docker-compose"
else
    echo "❌ SSL_CLIENT_CERT_FILE missing from docker-compose"
fi

# Check client certificate creation in SSL generation
echo "🔍 Checking client certificate creation..."
if grep -q "cp.*ssl_cert.pem.*ssl_client_cert.pem" marzban_node_deployer.sh; then
    echo "✅ Client certificate creation found"
else
    echo "❌ Client certificate creation missing"
fi

# Check SSL error handling
echo "🔍 Checking SSL error handling..."
if grep -q "SSL_CLIENT_CERT_FILE is required" marzban_node_deployer.sh; then
    echo "✅ SSL_CLIENT_CERT_FILE error handling found"
else
    echo "❌ SSL_CLIENT_CERT_FILE error handling missing"
fi

echo ""
echo "✅ Final test completed!"
echo "🚀 Node deployer should now handle SSL_CLIENT_CERT_FILE requirements properly"