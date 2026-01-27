#!/bin/bash
# test_phase7_integration.sh - Phase 7 Integration Tests: Final Integration
#
# Tests:
# - Final Dockerfile exists and builds
# - docker-compose.yml exists and is valid
# - containerlab example exists
# - All services start correctly
# - End-to-end functionality works

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test_helper.sh"

# Test: Final Dockerfile exists
test_dockerfile_exists() {
    if [ -f "$PROJECT_DIR/Dockerfile" ]; then
        return 0
    else
        TEST_OUTPUT="Final Dockerfile not found"
        return 1
    fi
}

# Test: docker-compose.yml exists
test_docker_compose_exists() {
    if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        return 0
    else
        TEST_OUTPUT="docker-compose.yml not found"
        return 1
    fi
}

# Test: containerlab example exists
test_containerlab_example_exists() {
    if [ -f "$PROJECT_DIR/containerlab/example.yml" ]; then
        return 0
    else
        TEST_OUTPUT="containerlab/example.yml not found"
        return 1
    fi
}

# Test: Final Dockerfile builds successfully
test_dockerfile_builds() {
    local output
    output=$(docker build -t qemu-bmc:latest "$PROJECT_DIR" 2>&1)
    local exit_code=$?

    assert_success $exit_code "Final Dockerfile should build" || return 1
    assert_contains "$output" "Successfully" "Build should succeed" || return 1
}

# Test: Container starts with final image
test_container_starts() {
    docker rm -f qemu-bmc-final-test 2>/dev/null || true

    docker run -d --name qemu-bmc-final-test --privileged \
        --device /dev/kvm:/dev/kvm \
        -p 5920:5900 \
        -p 6250:623/udp \
        qemu-bmc:latest >/dev/null 2>&1

    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        TEST_OUTPUT="Failed to start container with final image"
        return 1
    fi

    # Wait for healthy
    local retries=30
    while [ $retries -gt 0 ]; do
        local status=$(docker inspect --format='{{.State.Health.Status}}' qemu-bmc-final-test 2>/dev/null)
        if [ "$status" = "healthy" ]; then
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done

    TEST_OUTPUT="Container did not become healthy"
    return 1
}

# Test: All three services running (qemu, ipmi, sol-bridge)
test_all_services_running() {
    local status
    status=$(docker exec qemu-bmc-final-test supervisorctl status 2>/dev/null)

    assert_contains "$status" "qemu" "QEMU service should exist" || return 1
    assert_contains "$status" "ipmi" "IPMI service should exist" || return 1
    assert_contains "$status" "sol-bridge" "SOL bridge service should exist" || return 1

    # All should be RUNNING
    local running_count=$(echo "$status" | grep -c "RUNNING")
    if [ "$running_count" -ge 3 ]; then
        return 0
    else
        TEST_OUTPUT="Not all services are running: $status"
        return 1
    fi
}

# Test: IPMI responds
test_ipmi_responds() {
    local result
    result=$(docker exec qemu-bmc-final-test ipmitool -I lanplus -H 127.0.0.1 -U admin -P password mc info 2>&1)
    local exit_code=$?

    assert_success $exit_code "IPMI should respond" || return 1
    assert_contains "$result" "IPMI Version" "Should return IPMI version" || return 1
}

# Test: Power control works
test_power_control_works() {
    local result

    # Power status
    result=$(docker exec qemu-bmc-final-test ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power status 2>&1)
    assert_contains "$result" "Chassis Power" "Power status should work" || return 1

    # Power off
    docker exec qemu-bmc-final-test ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power off >/dev/null 2>&1
    sleep 3

    result=$(docker exec qemu-bmc-final-test ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power status 2>&1)
    assert_contains "$result" "off" "Power should be off" || return 1

    # Power on
    docker exec qemu-bmc-final-test ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power on >/dev/null 2>&1
    sleep 5

    result=$(docker exec qemu-bmc-final-test ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power status 2>&1)
    assert_contains "$result" "on" "Power should be on" || return 1
}

# Test: Serial console socket exists
test_serial_console_exists() {
    docker exec qemu-bmc-final-test test -S /var/run/qemu/console.sock
}

# Test: QMP socket exists
test_qmp_socket_exists() {
    docker exec qemu-bmc-final-test test -S /var/run/qemu/qmp.sock
}

# Test: Environment variables are set correctly
test_environment_variables() {
    local vars
    vars=$(docker exec qemu-bmc-final-test printenv 2>/dev/null)

    assert_contains "$vars" "VM_MEMORY" "VM_MEMORY should be set" || return 1
    assert_contains "$vars" "IPMI_USER" "IPMI_USER should be set" || return 1
    assert_contains "$vars" "SERIAL_SOCK" "SERIAL_SOCK should be set" || return 1
}

# Test: docker-compose.yml syntax is valid
test_docker_compose_valid() {
    if command -v docker-compose &>/dev/null; then
        local result
        result=$(docker-compose -f "$PROJECT_DIR/docker-compose.yml" config 2>&1)
        local exit_code=$?

        if [ $exit_code -eq 0 ]; then
            return 0
        else
            TEST_OUTPUT="docker-compose.yml is invalid: $result"
            return 1
        fi
    else
        # docker-compose not installed, check YAML syntax manually
        if grep -q "services:" "$PROJECT_DIR/docker-compose.yml"; then
            return 0
        else
            TEST_OUTPUT="docker-compose.yml missing services section"
            return 1
        fi
    fi
}

# Test: containerlab example YAML is valid
test_containerlab_yaml_valid() {
    local content
    content=$(cat "$PROJECT_DIR/containerlab/example.yml" 2>/dev/null)

    assert_contains "$content" "name:" "Should have topology name" || return 1
    assert_contains "$content" "topology:" "Should have topology section" || return 1
    assert_contains "$content" "nodes:" "Should have nodes section" || return 1
}

# Cleanup test container
cleanup_final_test() {
    docker stop qemu-bmc-final-test 2>/dev/null || true
    docker rm qemu-bmc-final-test 2>/dev/null || true
}

# Main test runner
main() {
    log_section "Phase 7 Tests: Final Integration"

    # Set PROJECT_DIR for tests
    PROJECT_DIR="/home/ubuntu/project/qemu-with-bmc"
    cd "$PROJECT_DIR"

    # Run file existence tests first (don't need container)
    run_test "Final Dockerfile exists" test_dockerfile_exists
    run_test "docker-compose.yml exists" test_docker_compose_exists
    run_test "containerlab example exists" test_containerlab_example_exists
    run_test "docker-compose.yml valid" test_docker_compose_valid
    run_test "containerlab YAML valid" test_containerlab_yaml_valid

    # Build and test container
    run_test "Final Dockerfile builds" test_dockerfile_builds
    run_test "Container starts" test_container_starts
    run_test "All services running" test_all_services_running
    run_test "IPMI responds" test_ipmi_responds
    run_test "Power control works" test_power_control_works
    run_test "Serial console socket" test_serial_console_exists
    run_test "QMP socket exists" test_qmp_socket_exists
    run_test "Environment variables" test_environment_variables

    # Cleanup
    cleanup_final_test
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    print_summary
    exit $?
fi
