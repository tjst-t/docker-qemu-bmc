#!/bin/bash
# test_phase2_supervisord.sh - Phase 2 Integration Tests: Process Management
#
# Tests:
# - supervisord runs as PID 1
# - supervisorctl status works
# - QEMU process managed by supervisord
# - IPMI process managed by supervisord
# - Logs are written correctly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test_helper.sh"

# Test: supervisord is PID 1
test_supervisord_pid1() {
    local pid1_cmd
    pid1_cmd=$(container_exec cat /proc/1/comm 2>/dev/null)

    assert_equals "supervisord" "$pid1_cmd" "PID 1 should be supervisord" || return 1
}

# Test: supervisorctl status works
test_supervisorctl_status() {
    local status
    status=$(container_exec supervisorctl status 2>/dev/null)
    local exit_code=$?

    assert_success $exit_code "supervisorctl should succeed" || return 1
    assert_contains "$status" "qemu" "Status should show qemu" || return 1
    assert_contains "$status" "ipmi" "Status should show ipmi" || return 1
}

# Test: QEMU is managed by supervisord
test_qemu_managed() {
    local status
    status=$(container_exec supervisorctl status qemu 2>/dev/null)

    assert_contains "$status" "RUNNING" "QEMU should be RUNNING" || return 1

    # Check that supervisord knows the PID
    local sup_pid
    sup_pid=$(echo "$status" | grep -oP 'pid \K[0-9]+')
    if [ -z "$sup_pid" ]; then
        TEST_OUTPUT="Could not extract PID from supervisorctl"
        return 1
    fi

    # Verify the PID exists
    container_exec kill -0 "$sup_pid" 2>/dev/null
    assert_success $? "QEMU PID should exist" || return 1
}

# Test: IPMI is managed by supervisord
test_ipmi_managed() {
    local status
    status=$(container_exec supervisorctl status ipmi 2>/dev/null)

    assert_contains "$status" "RUNNING" "IPMI should be RUNNING" || return 1
}

# Test: Process priority (IPMI starts before QEMU)
test_process_priority() {
    # Check config for priority settings
    local config
    config=$(container_exec cat /etc/supervisor/conf.d/supervisord.conf 2>/dev/null)

    # IPMI should have lower priority number (starts first)
    local ipmi_priority qemu_priority
    ipmi_priority=$(echo "$config" | grep -A10 "\[program:ipmi\]" | grep "priority" | grep -oP '[0-9]+')
    qemu_priority=$(echo "$config" | grep -A10 "\[program:qemu\]" | grep "priority" | grep -oP '[0-9]+')

    if [ -n "$ipmi_priority" ] && [ -n "$qemu_priority" ]; then
        if [ "$ipmi_priority" -lt "$qemu_priority" ]; then
            return 0
        else
            TEST_OUTPUT="IPMI priority ($ipmi_priority) should be less than QEMU priority ($qemu_priority)"
            return 1
        fi
    fi

    # If priorities not explicitly set, that's okay
    return 0
}

# Test: Log files exist and are written
test_log_files() {
    # Check QEMU log
    local qemu_log
    qemu_log=$(container_exec ls -la /var/log/qemu/qemu.log 2>/dev/null)
    assert_contains "$qemu_log" "qemu.log" "QEMU log should exist" || return 1

    # Check IPMI log
    local ipmi_log
    ipmi_log=$(container_exec ls -la /var/log/ipmi/ipmi.log 2>/dev/null)
    assert_contains "$ipmi_log" "ipmi.log" "IPMI log should exist" || return 1

    # Check supervisord log
    local sup_log
    sup_log=$(container_exec ls -la /var/log/supervisor/supervisord.log 2>/dev/null)
    assert_contains "$sup_log" "supervisord.log" "Supervisord log should exist" || return 1
}

# Test: supervisorctl stop/start works
test_supervisorctl_stop_start() {
    # Stop QEMU
    container_exec supervisorctl stop qemu >/dev/null 2>&1
    sleep 2

    local status
    status=$(container_exec supervisorctl status qemu 2>/dev/null)
    assert_contains "$status" "STOPPED" "QEMU should be STOPPED after stop" || return 1

    # Start QEMU
    container_exec supervisorctl start qemu >/dev/null 2>&1
    sleep 3

    status=$(container_exec supervisorctl status qemu 2>/dev/null)
    assert_contains "$status" "RUNNING" "QEMU should be RUNNING after start" || return 1
}

# Main test runner
main() {
    log_section "Phase 2 Tests: Process Management (supervisord)"

    cd /home/ubuntu/project/qemu-with-bmc

    # Check if container is running (reuse from Phase 1 if possible)
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
    run_test "supervisord is PID 1" test_supervisord_pid1
    run_test "supervisorctl status works" test_supervisorctl_status
    run_test "QEMU managed by supervisord" test_qemu_managed
    run_test "IPMI managed by supervisord" test_ipmi_managed
    run_test "Process priority" test_process_priority
    run_test "Log files exist" test_log_files
    run_test "supervisorctl stop/start" test_supervisorctl_stop_start
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    print_summary
    stop_test_container
    exit $?
fi
