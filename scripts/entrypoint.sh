#!/bin/bash
# entrypoint.sh - Container entrypoint script
# Sets up environment and starts supervisord

set -e

# Create necessary directories
mkdir -p /var/run/qemu /var/log/qemu /var/log/supervisor

# Export environment variables for child processes
export VM_MEMORY="${VM_MEMORY:-2048}"
export VM_CPUS="${VM_CPUS:-2}"
export VM_DISK="${VM_DISK:-/vm/disk.qcow2}"
export VM_CDROM="${VM_CDROM:-}"
export VM_BOOT="${VM_BOOT:-c}"
export ENABLE_KVM="${ENABLE_KVM:-true}"
export VNC_PORT="${VNC_PORT:-5900}"
export DEBUG="${DEBUG:-false}"

# Debug output
if [ "$DEBUG" = "true" ]; then
    echo "=== Container Environment ==="
    echo "VM_MEMORY: ${VM_MEMORY}"
    echo "VM_CPUS: ${VM_CPUS}"
    echo "VM_DISK: ${VM_DISK}"
    echo "ENABLE_KVM: ${ENABLE_KVM}"
    echo "VNC_PORT: ${VNC_PORT}"
    echo "============================="
fi

# Check KVM availability
if [ "$ENABLE_KVM" = "true" ]; then
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "INFO: KVM device available"
    else
        echo "WARN: KVM device not available, will use TCG emulation"
    fi
fi

# Execute command (default: supervisord)
exec "$@"
