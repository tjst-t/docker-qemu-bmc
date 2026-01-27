#!/bin/bash
# test_phase4_power.sh - Phase 4 Integration Tests: Power Control
#
# Tests:
# - QMP socket exists
# - Power state file exists
# - power status command works
# - power off command works
# - power on command works
# - power cycle command works
# - power reset command works (QMP reset)
# - State transitions are consistent
# - chassis bootdev pxe/disk/cdrom
# - bootdev applied after power cycle
# - reset after bootdev change becomes power cycle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test_helper.sh"

# Test: QMP socket exists
test_qmp_socket_exists() {
    local result
    result=$(container_exec ls -la /var/run/qemu/qmp.sock 2>&1)

    assert_contains "$result" "qmp.sock" "QMP socket should exist" || return 1
    assert_contains "$result" "srwx" "QMP socket should be a socket file" || return 1
}

# Test: Power state file exists
test_power_state_file() {
    local result
    result=$(container_exec cat /var/run/qemu/power.state 2>&1)

    # Should be either "on" or "off"
    if [ "$result" = "on" ] || [ "$result" = "off" ]; then
        return 0
    else
        TEST_OUTPUT="Power state should be 'on' or 'off', got: '$result'"
        return 1
    fi
}

# Test: power status command works
test_power_status() {
    local result
    result=$(ipmi_cmd power status)
    local exit_code=$?

    assert_success $exit_code "power status should succeed" || return 1
    assert_contains "$result" "Chassis Power is" "Should report chassis power" || return 1
}

# Test: power status shows "on" when QEMU running
test_power_status_on() {
    # Ensure QEMU is running
    wait_for_qemu_running 10

    local result
    result=$(ipmi_cmd power status)

    assert_contains "$result" "on" "Power should be on when QEMU running" || return 1
}

# Test: power off command works
test_power_off() {
    # Ensure QEMU is running first
    wait_for_qemu_running 10

    # Get initial PID
    local initial_pid
    initial_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # Power off
    local result
    result=$(ipmi_cmd power off)

    assert_contains "$result" "Down/Off" "Power off should be acknowledged" || return 1

    # Wait and verify
    sleep 3
    wait_for_qemu_stopped 10 || {
        TEST_OUTPUT="QEMU should be stopped after power off"
        return 1
    }

    # Verify power status
    result=$(ipmi_cmd power status)
    assert_contains "$result" "off" "Power status should show off" || return 1
}

# Test: power on command works
test_power_on() {
    # Ensure QEMU is stopped first
    container_exec supervisorctl stop qemu >/dev/null 2>&1
    sleep 2

    # Power on
    local result
    result=$(ipmi_cmd power on)

    assert_contains "$result" "Up/On" "Power on should be acknowledged" || return 1

    # Wait and verify
    sleep 5
    wait_for_qemu_running 10 || {
        TEST_OUTPUT="QEMU should be running after power on"
        return 1
    }

    # Verify power status
    result=$(ipmi_cmd power status)
    assert_contains "$result" "on" "Power status should show on" || return 1
}

# Test: power cycle command works
test_power_cycle() {
    # Ensure QEMU is running
    wait_for_qemu_running 10

    # Get initial PID
    local initial_pid
    initial_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # Power cycle
    local result
    result=$(ipmi_cmd power cycle)

    assert_contains "$result" "Cycle" "Power cycle should be acknowledged" || return 1

    # Wait for restart
    sleep 5
    wait_for_qemu_running 10 || {
        TEST_OUTPUT="QEMU should be running after power cycle"
        return 1
    }

    # Get new PID
    local new_pid
    new_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # PID should be different (process was restarted)
    if [ "$initial_pid" != "$new_pid" ]; then
        log_info "PID changed from $initial_pid to $new_pid"
        return 0
    else
        TEST_OUTPUT="PID should change after power cycle (was $initial_pid, still $new_pid)"
        return 1
    fi
}

# Test: power reset command works (QMP reset, PID unchanged)
test_power_reset() {
    # Ensure QEMU is running
    wait_for_qemu_running 10

    # Get initial PID
    local initial_pid
    initial_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # Power reset
    local result
    result=$(ipmi_cmd power reset)

    assert_contains "$result" "Reset" "Power reset should be acknowledged" || return 1

    # Wait a moment
    sleep 3

    # QEMU should still be running
    wait_for_qemu_running 5 || {
        TEST_OUTPUT="QEMU should still be running after reset"
        return 1
    }

    # Get current PID
    local current_pid
    current_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # PID should be the same (QMP reset, not process restart)
    if [ "$initial_pid" = "$current_pid" ]; then
        log_info "PID unchanged ($initial_pid) - QMP reset worked"
        return 0
    else
        TEST_OUTPUT="PID should remain same after QMP reset (was $initial_pid, now $current_pid)"
        return 1
    fi
}

# Test: State transitions are consistent
test_state_consistency() {
    # Start from known state
    container_exec supervisorctl start qemu >/dev/null 2>&1
    wait_for_qemu_running 10

    # Verify on state
    local result
    result=$(ipmi_cmd power status)
    assert_contains "$result" "on" "Should be on initially" || return 1

    # Off
    ipmi_cmd power off >/dev/null
    sleep 3
    result=$(ipmi_cmd power status)
    assert_contains "$result" "off" "Should be off after power off" || return 1

    # On
    ipmi_cmd power on >/dev/null
    sleep 5
    result=$(ipmi_cmd power status)
    assert_contains "$result" "on" "Should be on after power on" || return 1

    return 0
}

# Test: chassis_control.sh script works directly
test_chassis_control_script() {
    # Test get power
    local result
    result=$(container_exec /scripts/chassis-control.sh 0x20 get power 2>&1)

    if echo "$result" | grep -qE "^power:[01]$"; then
        return 0
    else
        TEST_OUTPUT="chassis-control.sh get power should return 'power:0' or 'power:1', got: '$result'"
        return 1
    fi
}

# Test: QMP communication works
test_qmp_communication() {
    local result
    result=$(container_exec bash -c 'echo -e "{\"execute\":\"qmp_capabilities\"}\n{\"execute\":\"query-status\"}" | socat - UNIX-CONNECT:/var/run/qemu/qmp.sock 2>/dev/null | tail -1')

    assert_contains "$result" "running" "QMP should report running status" || {
        # May be "paused" or other states, just check we got a response
        if echo "$result" | grep -q "status"; then
            return 0
        fi
        return 1
    }
}

# ============================================
# Boot Device Tests (chassis bootdev)
# ============================================

# Test: Set boot device to PXE
test_bootdev_pxe() {
    ipmi_cmd chassis bootdev pxe >/dev/null 2>&1
    local result
    result=$(container_exec cat /var/run/qemu/boot.device 2>/dev/null)

    if [ "$result" = "pxe" ]; then
        return 0
    else
        TEST_OUTPUT="Boot device should be 'pxe', got: '$result'"
        return 1
    fi
}

# Test: Set boot device to disk (ipmi_sim maps this to "default")
test_bootdev_disk() {
    ipmi_cmd chassis bootdev disk >/dev/null 2>&1
    local result
    result=$(container_exec cat /var/run/qemu/boot.device 2>/dev/null)

    # Note: ipmi_sim maps "disk" to "default"
    if [ "$result" = "default" ]; then
        return 0
    else
        TEST_OUTPUT="Boot device should be 'default' (ipmi_sim maps disk to default), got: '$result'"
        return 1
    fi
}

# Test: Set boot device to cdrom
test_bootdev_cdrom() {
    ipmi_cmd chassis bootdev cdrom >/dev/null 2>&1
    local result
    result=$(container_exec cat /var/run/qemu/boot.device 2>/dev/null)

    if [ "$result" = "cdrom" ]; then
        return 0
    else
        TEST_OUTPUT="Boot device should be 'cdrom', got: '$result'"
        return 1
    fi
}

# Test: Boot device applied after power cycle
test_bootdev_applied_after_cycle() {
    # Set boot device to pxe
    ipmi_cmd chassis bootdev pxe >/dev/null 2>&1

    # Power cycle
    ipmi_cmd power cycle >/dev/null 2>&1
    sleep 5
    wait_for_qemu_running 15

    # Verify QEMU started with -boot n (pxe = network boot)
    local qemu_args
    qemu_args=$(container_exec ps aux 2>/dev/null | grep qemu-system)

    if echo "$qemu_args" | grep -q "\-boot n"; then
        return 0
    else
        TEST_OUTPUT="QEMU should have -boot n after bootdev pxe + cycle, got: $qemu_args"
        return 1
    fi
}

# Test: Reset after bootdev change triggers power cycle (PID changes)
test_bootdev_reset_becomes_cycle() {
    # First, reset boot device and power cycle to clear flags
    ipmi_cmd chassis bootdev disk >/dev/null 2>&1
    ipmi_cmd power cycle >/dev/null 2>&1
    sleep 5
    wait_for_qemu_running 15

    # Get initial PID
    local initial_pid
    initial_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # Now set boot device to cdrom
    ipmi_cmd chassis bootdev cdrom >/dev/null 2>&1

    # Reset should trigger power cycle (not QMP reset) because boot device changed
    ipmi_cmd power reset >/dev/null 2>&1
    sleep 5
    wait_for_qemu_running 15

    # Get new PID
    local new_pid
    new_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # PID should be different (process was restarted, not QMP reset)
    if [ "$initial_pid" != "$new_pid" ]; then
        log_info "PID changed from $initial_pid to $new_pid (reset became power cycle)"
        # Also verify boot device was applied
        local qemu_args
        qemu_args=$(container_exec ps aux 2>/dev/null | grep qemu-system)
        if echo "$qemu_args" | grep -q "\-boot d"; then
            return 0
        else
            TEST_OUTPUT="QEMU should have -boot d after bootdev cdrom + reset"
            return 1
        fi
    else
        TEST_OUTPUT="PID should change when reset after bootdev change (was $initial_pid, still $new_pid)"
        return 1
    fi
}

# Test: Normal reset without bootdev change (PID unchanged)
test_normal_reset_pid_unchanged() {
    # Power cycle first to clear any boot changed flags
    ipmi_cmd power cycle >/dev/null 2>&1
    sleep 5
    wait_for_qemu_running 15

    # Get initial PID
    local initial_pid
    initial_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # Now reset WITHOUT changing boot device
    ipmi_cmd power reset >/dev/null 2>&1
    sleep 3

    # QEMU should still be running
    wait_for_qemu_running 5

    # Get current PID
    local current_pid
    current_pid=$(container_exec pgrep -f "qemu-system" 2>/dev/null)

    # PID should be the same (QMP reset, not process restart)
    if [ "$initial_pid" = "$current_pid" ]; then
        log_info "PID unchanged ($initial_pid) - normal QMP reset"
        return 0
    else
        TEST_OUTPUT="PID should remain same for normal reset (was $initial_pid, now $current_pid)"
        return 1
    fi
}

# Main test runner
main() {
    log_section "Phase 4 Tests: Power Control"

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

    # Wait for everything to be ready
    sleep 3
    wait_for_qemu_running 10

    # Run tests
    run_test "QMP socket exists" test_qmp_socket_exists
    run_test "Power state file" test_power_state_file
    run_test "power status command" test_power_status
    run_test "power status shows on" test_power_status_on
    run_test "power off command" test_power_off
    run_test "power on command" test_power_on
    run_test "power cycle command" test_power_cycle
    run_test "power reset command (QMP)" test_power_reset
    run_test "State consistency" test_state_consistency
    run_test "chassis-control.sh script" test_chassis_control_script
    run_test "QMP communication" test_qmp_communication

    # Boot device tests
    run_test "bootdev pxe" test_bootdev_pxe
    run_test "bootdev disk" test_bootdev_disk
    run_test "bootdev cdrom" test_bootdev_cdrom
    run_test "bootdev applied after cycle" test_bootdev_applied_after_cycle
    run_test "reset after bootdev change" test_bootdev_reset_becomes_cycle
    run_test "normal reset PID unchanged" test_normal_reset_pid_unchanged
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    print_summary
    stop_test_container
    exit $?
fi
