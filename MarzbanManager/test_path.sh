#!/bin/bash
# Test script to verify deployer path

echo "Current script: $0"
echo "Script directory: $(dirname "$0")"
echo "Parent directory: $(dirname "$(dirname "$0")")"
echo "Deployer path: $(dirname "$(dirname "$0")")/marzban_node_deployer_fixed.sh"

# Check if deployer exists
deployer_script="$(dirname "$(dirname "$0")")/marzban_node_deployer_fixed.sh"
if [[ -f "$deployer_script" ]]; then
    echo "✅ Deployer script found: $deployer_script"
else
    echo "❌ Deployer script NOT found: $deployer_script"
fi