#!/bin/bash
# test_phase1_qemu.sh - Phase 1 Integration Tests: Basic QEMU Container
#
# Tests:
# - Docker image builds successfully
# - Container starts
# - QEMU process runs (KVM or TCG)
# - VNC port is accessible

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test_helper.sh"

# Test: Docker image builds
test_docker_build() {
    local output
    output=$(docker build -t qemu-bmc:latest . 2>&1)
    local exit_code=$?

    assert_success $exit_code "Docker build should succeed" || return 1
    assert_contains "$output" "Successfully built" "Output should indicate success" || return 1
}

# Test: Container starts successfully
test_container_starts() {
    # Container should already be started by setup
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)

    assert_equals "running" "$status" "Container should be running" || return 1
}

# Test: QEMU process is running
test_qemu_process_running() {
    local status
    status=$(container_exec supervisorctl status qemu 2>/dev/null)

    assert_contains "$status" "RUNNING" "QEMU should be running" || return 1
}

# Test: KVM or TCG acceleration
test_qemu_acceleration() {
    local qemu_cmd
    qemu_cmd=$(container_exec ps aux 2>/dev/null | grep "qemu-system" | grep -v grep)

    # Should have either kvm or tcg acceleration
    if echo "$qemu_cmd" | grep -q "accel=kvm"; then
        log_info "Using KVM acceleration"
        return 0
    elif echo "$qemu_cmd" | grep -q "accel=tcg"; then
        log_info "Using TCG acceleration (fallback)"
        return 0
    else
        TEST_OUTPUT="Neither KVM nor TCG acceleration detected"
        return 1
    fi
}

# Test: VNC port is listening
test_vnc_port_listening() {
    local listen_check
    listen_check=$(container_exec cat /proc/net/tcp 2>/dev/null | grep ":170C")  # 5900 in hex

    if [ -n "$listen_check" ]; then
        return 0
    fi

    # Alternative check via QEMU command line
    local qemu_cmd
    qemu_cmd=$(container_exec ps aux 2>/dev/null | grep "qemu-system" | grep -v grep)

    assert_contains "$qemu_cmd" "-vnc" "QEMU should have VNC configured" || return 1
}

# Test: VNC connection (if vncviewer available on host)
test_vnc_connection() {
    # Check if we can connect to VNC port from host
    if command -v nc &>/dev/null; then
        local result
        result=$(echo "" | nc -w 2 127.0.0.1 "$VNC_PORT" 2>&1 | head -c 3)
        if [ "$result" = "RFB" ]; then
            return 0
        fi
    fi

    # If nc not available or connection failed, check port is exposed
    local ports
    ports=$(docker port "$CONTAINER_NAME" 5900 2>/dev/null)
    assert_contains "$ports" "$VNC_PORT" "VNC port should be exposed" || return 1
}

# Main test runner
main() {
    log_section "Phase 1 Tests: Basic QEMU Container"

    cd /home/ubuntu/project/qemu-with-bmc

    # Setup
    log_info "Setting up test environment..."
    start_test_container || {
        log_fail "Failed to start test container"
        return 1
    }

    # Run tests
    run_test "Docker build" test_docker_build
    run_test "Container starts" test_container_starts
    run_test "QEMU process running" test_qemu_process_running
    run_test "QEMU acceleration (KVM/TCG)" test_qemu_acceleration
    run_test "VNC port listening" test_vnc_port_listening
    run_test "VNC connection" test_vnc_connection

    # Note: Container cleanup is handled by run_tests.sh or manually
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    print_summary
    stop_test_container
    exit $?
fi
