#!/bin/bash
# power-control.sh - QEMU power control via QMP
# Used by ipmi_sim for chassis control

set -e

QMP_SOCK="/var/run/qemu/qmp.sock"
POWER_STATE_FILE="/var/run/qemu/power.state"
DEBUG="${DEBUG:-false}"

log() {
    local level="$1"
    shift
    if [ "$DEBUG" = "true" ] || [ "$level" = "ERROR" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
    fi
}

# Initialize power state file
init_power_state() {
    if [ ! -f "$POWER_STATE_FILE" ]; then
        echo "off" > "$POWER_STATE_FILE"
    fi
}

# Get current power state
get_power_state() {
    if [ -f "$POWER_STATE_FILE" ]; then
        cat "$POWER_STATE_FILE"
    else
        echo "off"
    fi
}

# Set power state
set_power_state() {
    local state="$1"
    echo "$state" > "$POWER_STATE_FILE"
    log "INFO" "Power state set to: $state"
}

# Check if QEMU is running via supervisord
is_qemu_running() {
    supervisorctl status qemu 2>/dev/null | grep -q "RUNNING"
}

# Check if QMP socket exists and is accessible
is_qmp_available() {
    [ -S "$QMP_SOCK" ]
}

# Send QMP command and get response
qmp_command() {
    local cmd="$1"
    local response

    if ! is_qmp_available; then
        log "ERROR" "QMP socket not available"
        return 1
    fi

    # QMP requires capabilities negotiation first, then the command
    response=$(echo -e '{"execute":"qmp_capabilities"}\n'"$cmd" | \
        socat - "UNIX-CONNECT:$QMP_SOCK" 2>/dev/null | \
        tail -1)

    log "DEBUG" "QMP command: $cmd"
    log "DEBUG" "QMP response: $response"

    echo "$response"
}

# Power On - Start QEMU via supervisord
power_on() {
    log "INFO" "Power ON requested"

    if is_qemu_running; then
        log "INFO" "QEMU already running"
        set_power_state "on"
        return 0
    fi

    supervisorctl start qemu

    # Wait for QEMU to start and QMP to become available
    local retries=10
    while [ $retries -gt 0 ]; do
        if is_qemu_running && is_qmp_available; then
            set_power_state "on"
            log "INFO" "Power ON successful"
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done

    log "ERROR" "Power ON failed"
    return 1
}

# Power Off - Graceful shutdown via ACPI, then force if needed
power_off() {
    log "INFO" "Power OFF requested"

    if ! is_qemu_running; then
        log "INFO" "QEMU not running"
        set_power_state "off"
        return 0
    fi

    # Try graceful ACPI shutdown first
    if is_qmp_available; then
        qmp_command '{"execute":"system_powerdown"}' >/dev/null 2>&1 || true

        # Wait for graceful shutdown
        local retries=5
        while [ $retries -gt 0 ]; do
            if ! is_qemu_running; then
                set_power_state "off"
                log "INFO" "Power OFF successful (ACPI)"
                return 0
            fi
            sleep 1
            retries=$((retries - 1))
        done
    fi

    # Force stop via supervisord
    log "INFO" "Forcing power off via supervisord"
    supervisorctl stop qemu >/dev/null 2>&1 || true

    set_power_state "off"
    log "INFO" "Power OFF successful (forced)"
    return 0
}

# Hard Power Off - Immediate stop
power_off_hard() {
    log "INFO" "Hard Power OFF requested"

    if ! is_qemu_running; then
        log "INFO" "QEMU not running"
        set_power_state "off"
        return 0
    fi

    # Quit QEMU immediately via QMP
    if is_qmp_available; then
        qmp_command '{"execute":"quit"}' >/dev/null 2>&1 || true
    fi

    # Ensure stopped via supervisord
    supervisorctl stop qemu >/dev/null 2>&1 || true

    set_power_state "off"
    log "INFO" "Hard Power OFF successful"
    return 0
}

# Power Cycle - Off then On
power_cycle() {
    log "INFO" "Power CYCLE requested"

    power_off_hard
    sleep 1
    power_on
}

# Reset - VM reset without full power cycle
power_reset() {
    log "INFO" "Power RESET requested"

    if ! is_qemu_running; then
        log "INFO" "QEMU not running, starting..."
        power_on
        return $?
    fi

    if is_qmp_available; then
        qmp_command '{"execute":"system_reset"}' >/dev/null 2>&1
        log "INFO" "Power RESET successful"
        return 0
    fi

    log "ERROR" "QMP not available for reset"
    return 1
}

# Get power status - returns 0 for on, 1 for off
power_status() {
    if is_qemu_running; then
        set_power_state "on"
        echo "on"
        return 0
    else
        set_power_state "off"
        echo "off"
        return 1
    fi
}

# Main - handle commands
main() {
    init_power_state

    local cmd="${1:-status}"

    case "$cmd" in
        on|start)
            power_on
            ;;
        off|stop)
            power_off
            ;;
        off_hard|hard_off)
            power_off_hard
            ;;
        cycle)
            power_cycle
            ;;
        reset)
            power_reset
            ;;
        status)
            power_status
            ;;
        *)
            echo "Usage: $0 {on|off|off_hard|cycle|reset|status}" >&2
            exit 1
            ;;
    esac
}

main "$@"
