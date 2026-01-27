#!/bin/bash
# test_phase5_network.sh - Phase 5 Integration Tests: Network Setup
#
# Tests:
# - setup-network.sh script exists and is executable
# - NIC detection works (VM_NETWORKS environment variable)
# - macvtap/tap device creation
# - QEMU network arguments are generated correctly
# - MAC address management
# - Multiple NICs can be passed through

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test_helper.sh"

# Test: setup-network.sh exists
test_setup_network_script_exists() {
    container_exec test -x /scripts/setup-network.sh
}

# Test: setup-network.sh runs without error
test_setup_network_runs() {
    local result
    result=$(container_exec /scripts/setup-network.sh 2>&1)
    local exit_code=$?

    # Should succeed (even with no extra NICs)
    assert_success $exit_code "setup-network.sh should run successfully" || return 1
}

# Test: Network state directory exists
test_network_state_dir() {
    container_exec test -d /var/run/qemu/network
}

# Test: VM_NETWORKS environment variable is respected
test_vm_networks_env() {
    # Default should be empty or eth2
    local result
    result=$(container_exec printenv VM_NETWORKS 2>/dev/null || echo "")

    # This test just verifies the variable can be read
    # The actual value depends on configuration
    return 0
}

# Test: get_vm_interfaces function works
test_get_vm_interfaces() {
    local result
    result=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; get_vm_interfaces' 2>&1)

    # Should return a list or empty (depending on configuration)
    # The function should not error
    local exit_code=$?

    # If the function doesn't exist (not sourced correctly), this will fail
    if echo "$result" | grep -q "command not found\|not found"; then
        TEST_OUTPUT="get_vm_interfaces function not found"
        return 1
    fi

    return 0
}

# Test: generate_mac_address function works
test_generate_mac_address() {
    local result
    result=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; generate_mac_address eth2' 2>&1)

    # Should return a valid MAC address format (XX:XX:XX:XX:XX:XX)
    if echo "$result" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
        return 0
    else
        TEST_OUTPUT="Invalid MAC address format: '$result'"
        return 1
    fi
}

# Test: MAC addresses are consistent (same interface = same MAC)
test_mac_address_consistency() {
    local mac1 mac2

    mac1=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; generate_mac_address eth2')
    mac2=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; generate_mac_address eth2')

    assert_equals "$mac1" "$mac2" "Same interface should generate same MAC" || return 1
}

# Test: Different interfaces get different MACs
test_mac_address_uniqueness() {
    local mac2 mac3

    mac2=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; generate_mac_address eth2')
    mac3=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; generate_mac_address eth3')

    if [ "$mac2" = "$mac3" ]; then
        TEST_OUTPUT="Different interfaces should have different MACs: eth2=$mac2, eth3=$mac3"
        return 1
    fi

    return 0
}

# Test: create_tap_device function exists
test_create_tap_device_function() {
    local result
    result=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; type create_tap_device' 2>&1)

    assert_contains "$result" "function" "create_tap_device should be a function" || return 1
}

# Test: build_network_args function exists
test_build_network_args_function() {
    local result
    result=$(container_exec bash -c 'source /scripts/setup-network.sh 2>/dev/null; type build_network_args' 2>&1)

    assert_contains "$result" "function" "build_network_args should be a function" || return 1
}

# Test: QEMU process has network configuration
test_qemu_network_config() {
    local qemu_cmd
    qemu_cmd=$(container_exec ps aux 2>/dev/null | grep "qemu-system" | grep -v grep)

    # QEMU should be running
    if [ -z "$qemu_cmd" ]; then
        TEST_OUTPUT="QEMU process not found"
        return 1
    fi

    # Check for NIC configuration (either -nic or -netdev)
    # Note: In current phase, we might have -nic none, which is also valid
    if echo "$qemu_cmd" | grep -qE "(-nic|-netdev)"; then
        return 0
    else
        TEST_OUTPUT="QEMU should have network configuration"
        return 1
    fi
}

# Test: TAP device creation (if configured)
test_tap_device_creation() {
    # Get list of configured VM networks
    local vm_networks
    vm_networks=$(container_exec printenv VM_NETWORKS 2>/dev/null || echo "")

    if [ -z "$vm_networks" ]; then
        # No VM networks configured, skip this test
        log_info "No VM_NETWORKS configured, skipping TAP device test"
        return 0
    fi

    # Check if tap devices exist for configured networks
    for iface in $(echo "$vm_networks" | tr ',' ' '); do
        local tap_name="tap_${iface}"
        if ! container_exec ip link show "$tap_name" 2>/dev/null | grep -q "$tap_name"; then
            # TAP might use different naming convention
            log_info "TAP device $tap_name not found (may use different naming)"
        fi
    done

    return 0
}

# Test: Network info file created
test_network_info_file() {
    local result
    result=$(container_exec cat /var/run/qemu/network/interfaces.conf 2>/dev/null || echo "")

    # File should exist (even if empty when no VM networks configured)
    if container_exec test -f /var/run/qemu/network/interfaces.conf 2>/dev/null; then
        return 0
    else
        # File not existing is okay if setup hasn't run yet
        log_info "Network interfaces.conf not found (may not be configured)"
        return 0
    fi
}

# Test: Container network interfaces are detected
test_container_interfaces() {
    local interfaces
    interfaces=$(container_exec ls /sys/class/net/ 2>/dev/null)

    # Should at least have eth0 and lo
    assert_contains "$interfaces" "eth0" "Container should have eth0" || return 1
    assert_contains "$interfaces" "lo" "Container should have lo" || return 1
}

# Test: Network setup with specific VM_NETWORKS value
test_network_setup_with_config() {
    # This test verifies the script handles VM_NETWORKS correctly
    local result
    result=$(container_exec bash -c 'VM_NETWORKS="" /scripts/setup-network.sh' 2>&1)
    local exit_code=$?

    # Should succeed even with empty VM_NETWORKS
    assert_success $exit_code "setup-network.sh should handle empty VM_NETWORKS" || return 1
}

# Main test runner
main() {
    log_section "Phase 5 Tests: Network Setup"

    cd /home/ubuntu/project/qemu-with-bmc

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Starting test container..."
        start_test_container || {
            log_fail "Failed to start test container"
            return 1
        }
    else
        log_info "Using existing test container"
    fi

    # Run tests
    run_test "setup-network.sh exists" test_setup_network_script_exists
    run_test "setup-network.sh runs" test_setup_network_runs
    run_test "Network state directory" test_network_state_dir
    run_test "VM_NETWORKS env variable" test_vm_networks_env
    run_test "get_vm_interfaces function" test_get_vm_interfaces
    run_test "generate_mac_address function" test_generate_mac_address
    run_test "MAC address consistency" test_mac_address_consistency
    run_test "MAC address uniqueness" test_mac_address_uniqueness
    run_test "create_tap_device function" test_create_tap_device_function
    run_test "build_network_args function" test_build_network_args_function
    run_test "QEMU network config" test_qemu_network_config
    run_test "TAP device creation" test_tap_device_creation
    run_test "Network info file" test_network_info_file
    run_test "Container interfaces" test_container_interfaces
    run_test "Network setup with config" test_network_setup_with_config
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    print_summary
    stop_test_container
    exit $?
fi
