#!/bin/bash
# run_tests.sh - Main test runner for qemu-bmc
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh all          # Run all tests
#   ./run_tests.sh phase1       # Run Phase 1 tests only
#   ./run_tests.sh phase2       # Run Phase 2 tests only
#   ./run_tests.sh phase3       # Run Phase 3 tests only
#   ./run_tests.sh phase4       # Run Phase 4 tests only
#   ./run_tests.sh integration  # Run all integration tests
#   ./run_tests.sh unit         # Run all unit tests
#   ./run_tests.sh quick        # Quick smoke test

set -e

# Save the tests directory path (won't be overwritten when sourcing test files)
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TESTS_DIR")"

# For backward compatibility
SCRIPT_DIR="$TESTS_DIR"

# Source test helper
source "$TESTS_DIR/helpers/test_helper.sh"

# Test configuration
export CONTAINER_NAME="${CONTAINER_NAME:-qemu-bmc-test}"
export CONTAINER_IMAGE="${CONTAINER_IMAGE:-qemu-bmc:phase4}"
export VNC_PORT="${VNC_PORT:-5910}"
export IPMI_PORT="${IPMI_PORT:-6240}"

# Timestamp for log file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$TESTS_DIR/evidence/test_run_${TIMESTAMP}.log"

# Track overall results
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# Ensure log directory exists
mkdir -p "$TESTS_DIR/evidence"

# Print banner
print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║             QEMU-BMC Test Suite                              ║"
    echo "║             $(date)                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

# Build Docker image
build_image() {
    log_section "Building Docker Image"
    cd "$PROJECT_DIR"

    if docker build -f Dockerfile.phase4 -t "$CONTAINER_IMAGE" . 2>&1 | tee -a "$LOG_FILE" | tail -5; then
        log_pass "Docker image built successfully"
        return 0
    else
        log_fail "Docker image build failed"
        return 1
    fi
}

# Run a test suite
run_test_suite() {
    local suite_name="$1"
    local suite_file="$2"

    if [ ! -f "$suite_file" ]; then
        log_fail "Test suite not found: $suite_file"
        return 1
    fi

    # Reset counters for this suite
    reset_counters

    # Run the suite
    source "$suite_file"
    main

    # Accumulate results
    TOTAL_TESTS=$((TOTAL_TESTS + TESTS_RUN))
    TOTAL_PASSED=$((TOTAL_PASSED + TESTS_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + TESTS_FAILED))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + TESTS_SKIPPED))
}

# Run Phase 1 tests
run_phase1() {
    run_test_suite "Phase 1" "$TESTS_DIR/integration/test_phase1_qemu.sh"
}

# Run Phase 2 tests
run_phase2() {
    run_test_suite "Phase 2" "$TESTS_DIR/integration/test_phase2_supervisord.sh"
}

# Run Phase 3 tests
run_phase3() {
    run_test_suite "Phase 3" "$TESTS_DIR/integration/test_phase3_ipmi.sh"
}

# Run Phase 4 tests
run_phase4() {
    run_test_suite "Phase 4" "$TESTS_DIR/integration/test_phase4_power.sh"
}

# Run Phase 5 tests
run_phase5() {
    run_test_suite "Phase 5" "$TESTS_DIR/integration/test_phase5_network.sh"
}

# Run Phase 6 tests
run_phase6() {
    run_test_suite "Phase 6" "$TESTS_DIR/integration/test_phase6_sol.sh"
}

# Run Phase 7 tests
run_phase7() {
    run_test_suite "Phase 7" "$TESTS_DIR/integration/test_phase7_integration.sh"
}

# Run all integration tests
run_integration() {
    run_phase1
    run_phase2
    run_phase3
    run_phase4
    run_phase5
    run_phase6
    run_phase7
}

# Run unit tests (placeholder)
run_unit() {
    log_section "Unit Tests"
    log_info "No unit tests implemented yet"
}

# Quick smoke test
run_quick() {
    log_section "Quick Smoke Test"

    # Just verify container starts and basic IPMI works
    start_test_container || return 1

    reset_counters

    # Basic checks
    run_test "Container running" test_container_running
    run_test "IPMI responds" test_ipmi_responds
    run_test "Power status" test_power_status_quick

    TOTAL_TESTS=$((TOTAL_TESTS + TESTS_RUN))
    TOTAL_PASSED=$((TOTAL_PASSED + TESTS_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + TESTS_FAILED))
}

# Quick test functions
test_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

test_ipmi_responds() {
    ipmi_cmd mc info >/dev/null 2>&1
}

test_power_status_quick() {
    ipmi_cmd power status | grep -q "Chassis Power"
}

# Run all tests
run_all() {
    build_image || return 1
    start_test_container || return 1

    run_integration
    # run_unit  # Enable when unit tests are implemented
}

# Print final summary
print_final_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    FINAL TEST SUMMARY                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Total Tests:  $TOTAL_TESTS"
    echo -e "  ${GREEN}Passed:       $TOTAL_PASSED${NC}"
    echo -e "  ${RED}Failed:       $TOTAL_FAILED${NC}"
    echo -e "  ${YELLOW}Skipped:      $TOTAL_SKIPPED${NC}"
    echo ""

    if [ $TOTAL_FAILED -eq 0 ]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                    ALL TESTS PASSED!                         ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        return 0
    else
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                    SOME TESTS FAILED!                        ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        return 1
    fi
}

# Cleanup
cleanup() {
    log_info "Cleaning up..."
    stop_test_container
}

# Main
main() {
    local test_target="${1:-all}"

    print_banner

    # Set up logging - strip ANSI color codes for log file, keep colors for terminal
    exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) 2>&1

    log_info "Log file: $LOG_FILE"
    log_info "Test target: $test_target"

    # Change to project directory
    cd "$PROJECT_DIR"

    # Run appropriate tests
    case "$test_target" in
        all)
            run_all
            ;;
        integration)
            build_image || exit 1
            start_test_container || exit 1
            run_integration
            ;;
        unit)
            run_unit
            ;;
        phase1)
            build_image || exit 1
            start_test_container || exit 1
            run_phase1
            ;;
        phase2)
            build_image || exit 1
            start_test_container || exit 1
            run_phase2
            ;;
        phase3)
            build_image || exit 1
            start_test_container || exit 1
            run_phase3
            ;;
        phase4)
            build_image || exit 1
            start_test_container || exit 1
            run_phase4
            ;;
        phase5)
            CONTAINER_IMAGE="qemu-bmc:phase5"
            docker build -f Dockerfile.phase5 -t "$CONTAINER_IMAGE" . 2>&1 | tail -5
            start_test_container || exit 1
            run_phase5
            ;;
        phase6)
            CONTAINER_IMAGE="qemu-bmc:phase6"
            docker build -f Dockerfile.phase6 -t "$CONTAINER_IMAGE" . 2>&1 | tail -5
            start_test_container || exit 1
            run_phase6
            ;;
        phase7)
            # Phase 7 tests use the final Dockerfile
            run_phase7
            ;;
        quick)
            build_image || exit 1
            run_quick
            ;;
        *)
            echo "Usage: $0 {all|integration|unit|phase1|phase2|phase3|phase4|phase5|phase6|phase7|quick}"
            exit 1
            ;;
    esac

    local result=$?

    # Cleanup
    cleanup

    # Print summary
    print_final_summary

    # Save summary to log
    echo ""
    echo "Test completed at: $(date)"
    echo "Log saved to: $LOG_FILE"

    exit $result
}

# Handle interrupts
trap cleanup EXIT INT TERM

# Run main
main "$@"
