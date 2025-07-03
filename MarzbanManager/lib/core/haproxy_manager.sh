#!/bin/bash
# HAProxy Management System for Marzban Central Manager
# Professional Edition v4.0 - Optimized for Marzban Single Port Configuration

# This file loads the complete HAProxy manager implementation
# Source the complete implementation
source "$(dirname "${BASH_SOURCE[0]}")/haproxy_manager_complete.sh"

# Re-export all functions to ensure they are available
export -f init_haproxy_manager detect_haproxy_configuration find_haproxy_config_path
export -f load_haproxy_configuration analyze_haproxy_marzban_config detect_haproxy_structure
export -f install_haproxy_on_node install_haproxy_on_all_nodes
export -f add_node_to_haproxy add_node_to_haproxy_marzban add_sni_routing_rule add_node_backend
export -f remove_node_from_haproxy remove_node_from_haproxy_marzban sync_haproxy_to_all_nodes sync_haproxy_to_node
export -f auto_haproxy_integration_on_node_add auto_haproxy_integration_on_node_remove
export -f check_haproxy_sync_status_all_nodes validate_haproxy_config reload_haproxy_service
export -f restore_haproxy_backup show_haproxy_status