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

# Test: VNC connection via vncprobe capture
test_vnc_connection() {
    if ! setup_vncprobe; then
        skip_test "VNC connection" "vncprobe not available"
        return 0
    fi

    local capture_dir
    capture_dir=$(mktemp -d)
    local capture_file="${capture_dir}/vnc_test.png"

    local output
    output=$("$VNCPROBE_BIN" capture -s "127.0.0.1:${VNC_PORT}" -o "$capture_file" --timeout 10 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -f "$capture_file" ]; then
        local file_size
        file_size=$(stat -c%s "$capture_file" 2>/dev/null || stat -f%z "$capture_file" 2>/dev/null)
        log_info "VNC capture successful (${file_size} bytes): $capture_file"
        rm -rf "$capture_dir"
        return 0
    else
        TEST_OUTPUT="vncprobe capture failed (exit code: $exit_code)\n  Output: $output"
        rm -rf "$capture_dir"
        return 1
    fi
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
