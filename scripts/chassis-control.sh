#!/bin/bash
# chassis-control.sh - IPMI chassis control handler for ipmi_sim
# Called by ipmi_sim via chassis_control directive
# Usage: chassis-control.sh <mc_addr> get|set <parm> [<value>]

set -e

MC_ADDR="$1"
OPERATION="$2"
PARAM="$3"
VALUE="$4"

POWER_STATE_FILE="/var/run/qemu/power.state"
BOOT_DEVICE_FILE="/var/run/qemu/boot.device"
BOOT_CHANGED_FILE="/var/run/qemu/boot.changed"
DEBUG="${DEBUG:-false}"

log() {
    if [ "$DEBUG" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [chassis-control] $*" >&2
    fi
}

# Initialize state files
init_state() {
    if [ ! -f "$POWER_STATE_FILE" ]; then
        echo "on" > "$POWER_STATE_FILE"
    fi
    if [ ! -f "$BOOT_DEVICE_FILE" ]; then
        echo "default" > "$BOOT_DEVICE_FILE"
    fi
}

# Check if QEMU is running
is_qemu_running() {
    supervisorctl status qemu 2>/dev/null | grep -q "RUNNING"
}

# Get power state (returns 1 for on, 0 for off)
get_power() {
    if is_qemu_running; then
        echo "1"
    else
        echo "0"
    fi
}

# Set power state
set_power() {
    local val="$1"
    log "set_power called with value: $val"

    if [ "$val" = "1" ]; then
        # Power On - clear boot changed flag
        rm -f "$BOOT_CHANGED_FILE"
        if ! is_qemu_running; then
            supervisorctl start qemu >/dev/null 2>&1 || true
            log "Power ON executed"
        fi
        echo "on" > "$POWER_STATE_FILE"
    else
        # Power Off
        if is_qemu_running; then
            supervisorctl stop qemu >/dev/null 2>&1 || true
            log "Power OFF executed"
        fi
        echo "off" > "$POWER_STATE_FILE"
    fi
}

# Set reset (pulse - always triggers reset)
set_reset() {
    local val="$1"
    log "set_reset called with value: $val"

    if [ "$val" = "1" ]; then
        # Check if boot device was changed - need full power cycle
        if [ -f "$BOOT_CHANGED_FILE" ] && [ "$(cat "$BOOT_CHANGED_FILE")" = "1" ]; then
            log "Boot device changed, converting reset to power cycle"
            rm -f "$BOOT_CHANGED_FILE"
            # Power cycle: stop then start QEMU to apply new boot device
            supervisorctl stop qemu >/dev/null 2>&1 || true
            sleep 1
            supervisorctl start qemu >/dev/null 2>&1 || true
            return
        fi

        # Normal reset via QMP
        if is_qemu_running; then
            local QMP_SOCK="/var/run/qemu/qmp.sock"
            if [ -S "$QMP_SOCK" ]; then
                echo -e '{"execute":"qmp_capabilities"}\n{"execute":"system_reset"}' | \
                    socat - "UNIX-CONNECT:$QMP_SOCK" >/dev/null 2>&1 || true
                log "Reset via QMP executed"
            else
                # Fallback: restart via supervisord
                supervisorctl restart qemu >/dev/null 2>&1 || true
                log "Reset via supervisord executed"
            fi
        fi
    fi
}

# Get boot device
get_boot() {
    if [ -f "$BOOT_DEVICE_FILE" ]; then
        cat "$BOOT_DEVICE_FILE"
    else
        echo "default"
    fi
}

# Set boot device
set_boot() {
    local val="$1"
    log "set_boot called with value: $val"

    case "$val" in
        none|pxe|disk|cdrom|bios|default)
            echo "$val" > "$BOOT_DEVICE_FILE"
            echo "1" > "$BOOT_CHANGED_FILE"  # Mark as changed for next reset/power on
            log "Boot device set to: $val"
            ;;
        *)
            echo "Invalid boot device: $val"
            exit 1
            ;;
    esac
}

# Set identify (LED blink - we just log it)
set_identify() {
    local interval="$1"
    local force="$2"
    log "Identify requested: interval=$interval force=$force"
    # No physical LED to blink, just acknowledge
}

# Handle GET operation
do_get() {
    local parm="$1"

    case "$parm" in
        power)
            echo "power:$(get_power)"
            ;;
        boot)
            echo "boot:$(get_boot)"
            ;;
        *)
            echo "Unknown parameter: $parm"
            exit 1
            ;;
    esac
}

# Handle SET operation
do_set() {
    local parm="$1"
    local val="$2"

    case "$parm" in
        power)
            set_power "$val"
            ;;
        reset)
            set_reset "$val"
            ;;
        boot)
            set_boot "$val"
            ;;
        identify)
            set_identify "$val" "${5:-0}"
            ;;
        *)
            echo "Unknown parameter: $parm"
            exit 1
            ;;
    esac
}

# Main
main() {
    init_state
    log "Called: $0 $*"

    case "$OPERATION" in
        get)
            do_get "$PARAM"
            ;;
        set)
            do_set "$PARAM" "$VALUE"
            ;;
        check)
            # Not supported
            exit 1
            ;;
        *)
            echo "Usage: $0 <mc_addr> get|set <parm> [<value>]" >&2
            exit 1
            ;;
    esac
}

main "$@"
