#!/bin/bash
# test_helper.sh - Common test helper functions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Current test info
CURRENT_TEST=""
TEST_OUTPUT=""

# Container settings
CONTAINER_NAME="${CONTAINER_NAME:-qemu-bmc-test}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-qemu-bmc:latest}"
VNC_PORT="${VNC_PORT:-5910}"
IPMI_PORT="${IPMI_PORT:-6240}"

# vncprobe settings
VNCPROBE_VERSION="${VNCPROBE_VERSION:-v1.0.1}"
VNCPROBE_DIR="${VNCPROBE_DIR:-${TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/bin}"
VNCPROBE_BIN="${VNCPROBE_DIR}/vncprobe"

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        TEST_OUTPUT="$TEST_OUTPUT\n  Expected: '$expected'\n  Actual:   '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        TEST_OUTPUT="$TEST_OUTPUT\n  String does not contain: '$needle'"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"

    if echo "$haystack" | grep -q "$needle"; then
        TEST_OUTPUT="$TEST_OUTPUT\n  String unexpectedly contains: '$needle'"
        return 1
    else
        return 0
    fi
}

assert_success() {
    local exit_code="$1"
    local message="${2:-Command should succeed}"

    if [ "$exit_code" -eq 0 ]; then
        return 0
    else
        TEST_OUTPUT="$TEST_OUTPUT\n  Exit code: $exit_code (expected 0)"
        return 1
    fi
}

assert_failure() {
    local exit_code="$1"
    local message="${2:-Command should fail}"

    if [ "$exit_code" -ne 0 ]; then
        return 0
    else
        TEST_OUTPUT="$TEST_OUTPUT\n  Exit code: $exit_code (expected non-zero)"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"

    if [ -f "$file" ]; then
        return 0
    else
        TEST_OUTPUT="$TEST_OUTPUT\n  File not found: $file"
        return 1
    fi
}

assert_socket_exists() {
    local socket="$1"
    local message="${2:-Socket should exist}"

    if [ -S "$socket" ]; then
        return 0
    else
        TEST_OUTPUT="$TEST_OUTPUT\n  Socket not found: $socket"
        return 1
    fi
}

# Test execution functions
run_test() {
    local test_name="$1"
    local test_func="$2"

    CURRENT_TEST="$test_name"
    TEST_OUTPUT=""
    TESTS_RUN=$((TESTS_RUN + 1))

    echo -n "  Testing: $test_name ... "

    if $test_func; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_pass "OK"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_fail "FAILED"
        if [ -n "$TEST_OUTPUT" ]; then
            echo -e "$TEST_OUTPUT"
        fi
        return 1
    fi
}

skip_test() {
    local test_name="$1"
    local reason="${2:-No reason given}"

    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -n "  Testing: $test_name ... "
    log_skip "SKIPPED ($reason)"
}

# Container management
start_test_container() {
    local image="${1:-$CONTAINER_IMAGE}"

    log_info "Starting test container: $CONTAINER_NAME"

    # Remove existing container if any
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # Start new container
    docker run -d --name "$CONTAINER_NAME" --privileged \
        --device /dev/kvm:/dev/kvm \
        -p "${VNC_PORT}:5900" \
        -p "${IPMI_PORT}:623/udp" \
        -e DEBUG=true \
        "$image" >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        log_fail "Failed to start container"
        return 1
    fi

    # Wait for container to be healthy
    log_info "Waiting for container to be ready..."
    local retries=30
    while [ $retries -gt 0 ]; do
        local status=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)
        if [ "$status" = "healthy" ]; then
            log_info "Container is healthy"
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done

    log_fail "Container did not become healthy in time"
    return 1
}

stop_test_container() {
    log_info "Stopping test container: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

container_exec() {
    docker exec "$CONTAINER_NAME" "$@"
}

# vncprobe helper functions
setup_vncprobe() {
    if [ -x "$VNCPROBE_BIN" ]; then
        return 0
    fi

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)
            log_info "Unsupported architecture for vncprobe: $arch"
            return 1
            ;;
    esac

    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')

    local url="https://github.com/tjst-t/vncprobe/releases/download/${VNCPROBE_VERSION}/vncprobe-${VNCPROBE_VERSION}-${os}-${arch}"

    log_info "Downloading vncprobe ${VNCPROBE_VERSION} (${os}-${arch})..."
    mkdir -p "$VNCPROBE_DIR"
    if curl -fsSL -o "$VNCPROBE_BIN" "$url"; then
        chmod +x "$VNCPROBE_BIN"
        log_info "vncprobe installed to $VNCPROBE_BIN"
        return 0
    else
        log_info "Failed to download vncprobe"
        return 1
    fi
}

# IPMI helper functions
ipmi_cmd() {
    container_exec ipmitool -I lanplus -H 127.0.0.1 -U admin -P password "$@" 2>&1
}

ipmi_cmd_wrong_pass() {
    container_exec ipmitool -I lanplus -H 127.0.0.1 -U admin -P wrongpass "$@" 2>&1
}

ipmi_cmd_wrong_user() {
    container_exec ipmitool -I lanplus -H 127.0.0.1 -U wronguser -P password "$@" 2>&1
}

# Wait functions
wait_for_power_state() {
    local expected_state="$1"
    local timeout="${2:-10}"
    local retries=$timeout

    while [ $retries -gt 0 ]; do
        local current_state=$(ipmi_cmd power status 2>/dev/null | grep -o "on\|off" | head -1)
        if [ "$current_state" = "$expected_state" ]; then
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done
    return 1
}

wait_for_qemu_running() {
    local timeout="${1:-10}"
    local retries=$timeout

    while [ $retries -gt 0 ]; do
        if container_exec supervisorctl status qemu 2>/dev/null | grep -q "RUNNING"; then
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done
    return 1
}

wait_for_qemu_stopped() {
    local timeout="${1:-10}"
    local retries=$timeout

    while [ $retries -gt 0 ]; do
        if container_exec supervisorctl status qemu 2>/dev/null | grep -q "STOPPED"; then
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done
    return 1
}

# Print test summary
print_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "  Total:   $TESTS_RUN"
    echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo -e "${BLUE}========================================${NC}"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Reset counters
reset_counters() {
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
}
