#!/bin/bash
# start-qemu.sh - QEMU startup script
# Starts QEMU with VNC access and QMP control, managed by supervisord
# Phase 4: Added QMP socket for power control
# Phase 5: Added network passthrough support
# Phase 6: Added serial console socket for SOL

set -e

# Load default configuration
if [ -f /configs/qemu/default.conf ]; then
    source /configs/qemu/default.conf
fi

# Load network setup functions (Phase 5)
if [ -f /scripts/setup-network.sh ]; then
    source /scripts/setup-network.sh
fi

# Environment variables (with defaults)
VM_MEMORY="${VM_MEMORY:-2048}"
VM_CPUS="${VM_CPUS:-2}"
VM_DISK="${VM_DISK:-/vm/disk.qcow2}"
VM_CDROM="${VM_CDROM:-}"
VM_BOOT="${VM_BOOT:-c}"
ENABLE_KVM="${ENABLE_KVM:-true}"
VNC_PORT="${VNC_PORT:-5900}"
DEBUG="${DEBUG:-false}"

# QMP socket for power control (Phase 4)
QMP_SOCK="${QMP_SOCK:-/var/run/qemu/qmp.sock}"
POWER_STATE_FILE="${POWER_STATE_FILE:-/var/run/qemu/power.state}"

# Serial console socket for SOL (Phase 6)
SERIAL_SOCK="${SERIAL_SOCK:-/var/run/qemu/console.sock}"

# Boot device file (set by IPMI chassis bootdev)
BOOT_DEVICE_FILE="${BOOT_DEVICE_FILE:-/var/run/qemu/boot.device}"

# Get boot device from IPMI setting and convert to QEMU parameter
get_boot_param() {
    local boot_dev="default"

    # Read boot device from IPMI setting if exists
    if [ -f "$BOOT_DEVICE_FILE" ]; then
        boot_dev=$(cat "$BOOT_DEVICE_FILE")
    fi

    # Map IPMI boot device to QEMU -boot parameter
    case "$boot_dev" in
        pxe)     echo "n" ;;        # Network boot
        disk)    echo "c" ;;        # Hard disk
        cdrom)   echo "d" ;;        # CD-ROM
        bios)    echo "menu=on" ;;  # Boot menu
        none)    echo "c" ;;        # Default to disk
        default) echo "c" ;;        # Default to disk
        *)       echo "c" ;;        # Fallback to disk
    esac
}

# Calculate VNC display number (5900 = :0, 5901 = :1, etc.)
VNC_DISPLAY=$((VNC_PORT - 5900))

# Debug output
if [ "$DEBUG" = "true" ]; then
    echo "=== QEMU Configuration ==="
    echo "VM_MEMORY: ${VM_MEMORY}"
    echo "VM_CPUS: ${VM_CPUS}"
    echo "VM_DISK: ${VM_DISK}"
    echo "VM_CDROM: ${VM_CDROM}"
    echo "VM_BOOT: ${VM_BOOT}"
    echo "ENABLE_KVM: ${ENABLE_KVM}"
    echo "VNC_PORT: ${VNC_PORT} (display :${VNC_DISPLAY})"
    echo "=========================="
fi

# Check KVM availability
check_kvm() {
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        return 0
    fi
    return 1
}

# Build QEMU command
build_qemu_cmd() {
    local cmd="qemu-system-x86_64"

    # Machine type and acceleration
    if [ "$ENABLE_KVM" = "true" ] && check_kvm; then
        cmd="$cmd -machine q35,accel=kvm -cpu host"
        echo "INFO: KVM acceleration enabled" >&2
    else
        cmd="$cmd -machine q35,accel=tcg -cpu qemu64"
        echo "WARN: KVM not available, using TCG (slower)" >&2
    fi

    # Memory and CPUs
    cmd="$cmd -m ${VM_MEMORY} -smp ${VM_CPUS}"

    # Disk configuration
    if [ -n "$VM_DISK" ] && [ -f "$VM_DISK" ]; then
        cmd="$cmd -drive file=${VM_DISK},format=qcow2,if=virtio"
    else
        echo "WARN: Disk image not found at ${VM_DISK}, booting without disk" >&2
    fi

    # CDROM configuration
    if [ -n "$VM_CDROM" ] && [ -f "$VM_CDROM" ]; then
        cmd="$cmd -cdrom ${VM_CDROM}"
    fi

    # Boot device - check IPMI setting first, then env var fallback
    local boot_param=$(get_boot_param)
    cmd="$cmd -boot ${boot_param}"
    echo "INFO: Boot device: ${boot_param}" >&2

    # VNC configuration (listen on all interfaces for container access)
    cmd="$cmd -vnc :${VNC_DISPLAY}"

    # QMP socket for power control (Phase 4)
    cmd="$cmd -qmp unix:${QMP_SOCK},server,nowait"

    # Network configuration (Phase 5)
    if type build_network_args &>/dev/null; then
        local net_args=$(build_network_args 2>/dev/null)
        if [ -n "$net_args" ]; then
            cmd="$cmd $net_args"
            echo "INFO: Network configured: $net_args" >&2
        else
            cmd="$cmd -nic none"
            echo "INFO: No network interfaces configured" >&2
        fi
    else
        cmd="$cmd -nic none"
        echo "INFO: Network setup not available, using no network" >&2
    fi

    # Serial console socket for SOL (Phase 6)
    cmd="$cmd -chardev socket,id=serial0,path=${SERIAL_SOCK},server=on,wait=off"
    cmd="$cmd -serial chardev:serial0"

    # Run in foreground (no daemonize for container)
    cmd="$cmd -nographic -monitor stdio"

    echo "$cmd"
}

# Set power state
set_power_state() {
    local state="$1"
    echo "$state" > "$POWER_STATE_FILE"
}

# Cleanup on exit
cleanup() {
    set_power_state "off"
    echo "QEMU stopped, power state set to off"
}

# Main
main() {
    echo "Starting QEMU..."

    # Set up cleanup trap
    trap cleanup EXIT

    # Remove stale sockets if they exist
    rm -f "$QMP_SOCK"
    rm -f "$SERIAL_SOCK"

    # Build and execute QEMU command
    QEMU_CMD=$(build_qemu_cmd)

    if [ "$DEBUG" = "true" ]; then
        echo "QEMU Command: $QEMU_CMD"
    fi

    # Mark power state as on
    set_power_state "on"

    # Execute QEMU
    exec $QEMU_CMD
}

main "$@"
