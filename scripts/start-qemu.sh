#!/bin/bash
# start-qemu.sh - Minimal QEMU startup script for Phase 1
# Starts QEMU with VNC access for basic verification

set -e

# Load default configuration
if [ -f /configs/qemu/default.conf ]; then
    source /configs/qemu/default.conf
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

    # Boot device
    cmd="$cmd -boot ${VM_BOOT}"

    # VNC configuration (listen on all interfaces for container access)
    cmd="$cmd -vnc :${VNC_DISPLAY}"

    # Disable default network (will be configured in later phases)
    cmd="$cmd -nic none"

    # Run in foreground (no daemonize for container)
    cmd="$cmd -nographic -serial mon:stdio"

    echo "$cmd"
}

# Main
main() {
    echo "Starting QEMU (Phase 1)..."

    # Build and execute QEMU command
    QEMU_CMD=$(build_qemu_cmd)

    if [ "$DEBUG" = "true" ]; then
        echo "QEMU Command: $QEMU_CMD"
    fi

    # Execute QEMU
    exec $QEMU_CMD
}

main "$@"
