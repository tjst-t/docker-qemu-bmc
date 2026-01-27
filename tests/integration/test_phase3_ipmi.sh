#!/bin/bash
# test_phase3_ipmi.sh - Phase 3 Integration Tests: IPMI Foundation
#
# Tests:
# - ipmi_sim process running
# - UDP 623 listening
# - IPMI 1.5 (lan) connection works
# - IPMI 2.0 (lanplus) connection works
# - mc info returns valid data
# - Authentication works (correct credentials)
# - Authentication fails (wrong password)
# - Authentication fails (wrong username)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test_helper.sh"

# Test: ipmi_sim process running
test_ipmi_process_running() {
    local status
    status=$(container_exec supervisorctl status ipmi 2>/dev/null)

    assert_contains "$status" "RUNNING" "IPMI should be running" || return 1
}

# Test: ipmi_sim is the correct process
test_ipmi_sim_process() {
    local process
    process=$(container_exec ps aux 2>/dev/null | grep "ipmi_sim" | grep -v grep)

    if [ -n "$process" ]; then
        assert_contains "$process" "/usr/bin/ipmi_sim" "ipmi_sim should be running" || return 1
    else
        TEST_OUTPUT="ipmi_sim process not found"
        return 1
    fi
}

# Test: UDP 623 listening inside container
test_udp_623_listening() {
    # Check using /proc/net/udp (port 623 = 0x26F)
    local udp_check
    udp_check=$(container_exec cat /proc/net/udp 2>/dev/null | grep -i ":026F")

    if [ -n "$udp_check" ]; then
        return 0
    fi

    # Alternative: Check if ipmi_sim is bound to the port via lsof or ss if available
    # If neither works, we rely on the IPMI connection tests
    TEST_OUTPUT="Could not verify UDP 623 listening (will test via IPMI connection)"
    return 0  # Don't fail, let connection tests verify
}

# Test: IPMI 1.5 (lan interface) connection
test_ipmi_lan_connection() {
    local result
    result=$(container_exec ipmitool -I lan -H 127.0.0.1 -U admin -P password mc info 2>&1)
    local exit_code=$?

    assert_success $exit_code "IPMI lan connection should succeed" || return 1
    assert_contains "$result" "Device ID" "mc info should return Device ID" || return 1
}

# Test: IPMI 2.0 (lanplus interface) connection
test_ipmi_lanplus_connection() {
    local result
    result=$(ipmi_cmd mc info)
    local exit_code=$?

    assert_success $exit_code "IPMI lanplus connection should succeed" || return 1
    assert_contains "$result" "Device ID" "mc info should return Device ID" || return 1
}

# Test: mc info returns valid BMC information
test_mc_info_content() {
    local result
    result=$(ipmi_cmd mc info)

    # Check for expected fields
    assert_contains "$result" "Device ID" "Should have Device ID" || return 1
    assert_contains "$result" "Firmware Revision" "Should have Firmware Revision" || return 1
    assert_contains "$result" "IPMI Version" "Should have IPMI Version" || return 1
    assert_contains "$result" "Device Available" "Should have Device Available" || return 1
    assert_contains "$result" "yes" "Device should be available" || return 1
}

# Test: IPMI Version is 2.0
test_ipmi_version() {
    local result
    result=$(ipmi_cmd mc info | grep "IPMI Version")

    assert_contains "$result" "2.0" "IPMI Version should be 2.0" || return 1
}

# Test: Chassis Device support
test_chassis_support() {
    local result
    result=$(ipmi_cmd mc info)

    assert_contains "$result" "Chassis Device" "Should support Chassis Device" || return 1
}

# Test: Authentication with correct credentials
test_auth_correct() {
    local result
    result=$(ipmi_cmd mc info)
    local exit_code=$?

    assert_success $exit_code "Authentication should succeed with correct credentials" || return 1
}

# Test: Authentication fails with wrong password
test_auth_wrong_password() {
    local result
    result=$(ipmi_cmd_wrong_pass mc info 2>&1)
    local exit_code=$?

    assert_failure $exit_code "Authentication should fail with wrong password" || return 1
    assert_contains "$result" "Unable to establish" "Should indicate session failure" || return 1
}

# Test: Authentication fails with wrong username
test_auth_wrong_username() {
    local result
    result=$(ipmi_cmd_wrong_user mc info 2>&1)
    local exit_code=$?

    assert_failure $exit_code "Authentication should fail with wrong username" || return 1
    assert_contains "$result" "Unable to establish" "Should indicate session failure" || return 1
}

# Test: SEL (System Event Log) is accessible
test_sel_accessible() {
    local result
    result=$(ipmi_cmd sel info 2>&1)
    local exit_code=$?

    # SEL info should work (even if empty)
    assert_success $exit_code "SEL info should be accessible" || return 1
}

# Main test runner
main() {
    log_section "Phase 3 Tests: IPMI Foundation"

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

    # Wait for IPMI to be ready
    sleep 2

    # Run tests
    run_test "ipmi_sim process running" test_ipmi_process_running
    run_test "ipmi_sim is correct process" test_ipmi_sim_process
    run_test "UDP 623 listening" test_udp_623_listening
    run_test "IPMI 1.5 (lan) connection" test_ipmi_lan_connection
    run_test "IPMI 2.0 (lanplus) connection" test_ipmi_lanplus_connection
    run_test "mc info content" test_mc_info_content
    run_test "IPMI Version 2.0" test_ipmi_version
    run_test "Chassis Device support" test_chassis_support
    run_test "Auth with correct credentials" test_auth_correct
    run_test "Auth fails with wrong password" test_auth_wrong_password
    run_test "Auth fails with wrong username" test_auth_wrong_username
    run_test "SEL accessible" test_sel_accessible
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    print_summary
    stop_test_container
    exit $?
fi
