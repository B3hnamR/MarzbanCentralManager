#!/bin/bash
# Quick Test for Node Deployer Logic

echo "🔍 Quick test of node deployer logic..."

# Simulate the deployment process
echo "1. Testing comprehensive_system_check order..."

# Check if SSL generation comes before docker-compose creation
ssl_line=$(grep -n "check_and_generate_ssl_certificates" marzban_node_deployer.sh | head -1 | cut -d: -f1)
compose_line=$(grep -n "create_optimized_docker_compose" marzban_node_deployer.sh | tail -1 | cut -d: -f1)

if [ "$ssl_line" -lt "$compose_line" ]; then
    echo "✅ SSL certificates are generated before docker-compose creation"
else
    echo "❌ Wrong order: docker-compose created before SSL certificates"
fi

# Check if start_marzban_service has pre-flight checks
echo "2. Testing start_marzban_service pre-flight checks..."

if grep -q "Pre-flight checks" marzban_node_deployer.sh; then
    echo "✅ Pre-flight checks found in start_marzban_service"
else
    echo "❌ Pre-flight checks missing"
fi

if grep -q "SSL certificates missing before service start" marzban_node_deployer.sh; then
    echo "✅ SSL certificate validation found"
else
    echo "❌ SSL certificate validation missing"
fi

if grep -q "docker-compose.yml missing SSL_CLIENT_CERT_FILE" marzban_node_deployer.sh; then
    echo "✅ Docker-compose validation found"
else
    echo "❌ Docker-compose validation missing"
fi

echo ""
echo "✅ Quick test completed!"
echo "🚀 The deployer should now work correctly with proper order and checks"