#!/bin/bash
# Test script for node deployer

echo "Testing node deployer syntax..."

# Check syntax
if bash -n marzban_node_deployer.sh; then
    echo "✅ Syntax check passed"
else
    echo "❌ Syntax check failed"
    exit 1
fi

# Check if all required functions exist
echo "Checking required functions..."

required_functions=(
    "comprehensive_system_check"
    "check_and_fix_package_lock"
    "check_and_install_docker"
    "check_and_install_docker_compose"
    "check_and_setup_environment"
    "check_and_generate_ssl_certificates"
    "create_optimized_docker_compose"
    "start_marzban_service"
)

for func in "${required_functions[@]}"; do
    if grep -q "^$func()" marzban_node_deployer.sh; then
        echo "✅ Function $func exists"
    else
        echo "❌ Function $func missing"
    fi
done

echo "✅ Test completed"