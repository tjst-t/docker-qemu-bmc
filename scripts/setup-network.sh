#!/bin/bash
# setup-network.sh - Network setup for VM passthrough
# Configures eth2+ interfaces for QEMU VM passthrough
#
# This script:
# 1. Detects available network interfaces (eth2+)
# 2. Creates tap devices for VM passthrough
# 3. Generates consistent MAC addresses per interface
# 4. Outputs QEMU network arguments

set -e

# Configuration
NETWORK_STATE_DIR="${NETWORK_STATE_DIR:-/var/run/qemu/network}"
VM_NETWORKS="${VM_NETWORKS:-}"  # Comma-separated list of interfaces (e.g., "eth2,eth3")
DEBUG="${DEBUG:-false}"

# Logging
log() {
    local level="$1"
    shift
    if [ "$DEBUG" = "true" ] || [ "$level" = "ERROR" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
    fi
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

# Initialize network state directory
init_network_state() {
    mkdir -p "$NETWORK_STATE_DIR"
    touch "$NETWORK_STATE_DIR/interfaces.conf"
}

# Get list of VM interfaces to pass through
# Returns: space-separated list of interfaces
get_vm_interfaces() {
    local interfaces=""

    if [ -n "$VM_NETWORKS" ]; then
        # Use explicitly configured interfaces
        interfaces=$(echo "$VM_NETWORKS" | tr ',' ' ')
    else
        # Auto-detect: find eth2 and higher
        for iface in /sys/class/net/eth*; do
            if [ -d "$iface" ]; then
                local name=$(basename "$iface")
                local num=${name#eth}
                # Only include eth2 and higher (eth0=debug, eth1=IPMI)
                if [ "$num" -ge 2 ] 2>/dev/null; then
                    interfaces="$interfaces $name"
                fi
            fi
        done
    fi

    echo $interfaces
}

# Generate a consistent MAC address for an interface
# Uses a hash of the interface name to ensure consistency
generate_mac_address() {
    local iface="$1"
    local base_mac="52:54:00"  # QEMU OUI prefix

    # Generate deterministic bytes from interface name
    # Using md5sum for consistency (available everywhere)
    local hash=$(echo -n "$iface" | md5sum | cut -c1-6)

    local byte1=${hash:0:2}
    local byte2=${hash:2:2}
    local byte3=${hash:4:2}

    echo "${base_mac}:${byte1}:${byte2}:${byte3}"
}

# Create a tap device for an interface
# Args: $1 = host interface name, $2 = tap device name
create_tap_device() {
    local host_iface="$1"
    local tap_name="$2"

    # Check if tap device already exists
    if ip link show "$tap_name" &>/dev/null; then
        log_info "TAP device $tap_name already exists"
        return 0
    fi

    # Create tap device
    log_info "Creating TAP device $tap_name"
    ip tuntap add dev "$tap_name" mode tap

    # Bring up the tap device
    ip link set "$tap_name" up

    # If host interface exists, bridge them
    if ip link show "$host_iface" &>/dev/null; then
        # Get the MAC address of the host interface
        local host_mac=$(cat /sys/class/net/$host_iface/address 2>/dev/null || echo "")

        if [ -n "$host_mac" ]; then
            # Set tap device to same MAC for bridging
            ip link set "$tap_name" address "$host_mac" 2>/dev/null || true
        fi

        log_info "TAP device $tap_name created and linked to $host_iface"
    fi

    return 0
}

# Create a macvtap device for an interface (alternative to tap)
# Args: $1 = host interface name
create_macvtap_device() {
    local host_iface="$1"
    local macvtap_name="macvtap_${host_iface}"

    # Check if host interface exists
    if ! ip link show "$host_iface" &>/dev/null; then
        log_error "Host interface $host_iface does not exist"
        return 1
    fi

    # Check if macvtap already exists
    if ip link show "$macvtap_name" &>/dev/null; then
        log_info "macvtap device $macvtap_name already exists"
        return 0
    fi

    # Create macvtap device in bridge mode
    log_info "Creating macvtap device $macvtap_name on $host_iface"
    ip link add link "$host_iface" name "$macvtap_name" type macvtap mode bridge

    # Bring up the macvtap device
    ip link set "$macvtap_name" up

    # Get the tap device number for QEMU
    local tapnum=$(cat /sys/class/net/$macvtap_name/ifindex 2>/dev/null || echo "")

    if [ -n "$tapnum" ]; then
        log_info "macvtap device $macvtap_name created (tap$tapnum)"
    fi

    return 0
}

# Build QEMU network arguments for all VM interfaces
# Returns: QEMU command line arguments for networking
build_network_args() {
    local args=""
    local netid=0

    local interfaces=$(get_vm_interfaces)

    if [ -z "$interfaces" ]; then
        # No VM networks configured, use no network
        echo "-nic none"
        return 0
    fi

    for iface in $interfaces; do
        local mac=$(generate_mac_address "$iface")
        local tap_name="tap${netid}"

        # Try to create tap device
        if create_tap_device "$iface" "$tap_name" 2>/dev/null; then
            # Use tap device
            args="$args -netdev tap,id=net${netid},ifname=${tap_name},script=no,downscript=no"
            args="$args -device virtio-net-pci,netdev=net${netid},mac=${mac}"
        else
            # Fallback to user-mode networking (slower but works without privileges)
            log_info "Falling back to user-mode networking for $iface"
            args="$args -netdev user,id=net${netid}"
            args="$args -device virtio-net-pci,netdev=net${netid},mac=${mac}"
        fi

        # Record interface mapping
        echo "${iface}:net${netid}:${mac}:${tap_name}" >> "$NETWORK_STATE_DIR/interfaces.conf"

        netid=$((netid + 1))
    done

    echo "$args"
}

# Get network arguments without creating devices (for inspection)
get_network_args_preview() {
    local args=""
    local netid=0

    local interfaces=$(get_vm_interfaces)

    if [ -z "$interfaces" ]; then
        echo "-nic none"
        return 0
    fi

    for iface in $interfaces; do
        local mac=$(generate_mac_address "$iface")
        args="$args -netdev tap,id=net${netid},ifname=tap${netid},script=no,downscript=no"
        args="$args -device virtio-net-pci,netdev=net${netid},mac=${mac}"
        netid=$((netid + 1))
    done

    echo "$args"
}

# Cleanup network devices
cleanup_network() {
    log_info "Cleaning up network devices"

    # Remove tap devices
    for tap in /sys/class/net/tap*; do
        if [ -d "$tap" ]; then
            local name=$(basename "$tap")
            ip link delete "$name" 2>/dev/null || true
            log_info "Removed $name"
        fi
    done

    # Remove macvtap devices
    for macvtap in /sys/class/net/macvtap_*; do
        if [ -d "$macvtap" ]; then
            local name=$(basename "$macvtap")
            ip link delete "$name" 2>/dev/null || true
            log_info "Removed $name"
        fi
    done

    # Clear state file
    > "$NETWORK_STATE_DIR/interfaces.conf"
}

# Show current network configuration
show_network_config() {
    echo "=== Network Configuration ==="
    echo "VM_NETWORKS: ${VM_NETWORKS:-<auto-detect>}"
    echo ""
    echo "Detected VM interfaces:"
    get_vm_interfaces | tr ' ' '\n' | while read iface; do
        if [ -n "$iface" ]; then
            local mac=$(generate_mac_address "$iface")
            echo "  $iface -> MAC: $mac"
        fi
    done
    echo ""
    echo "QEMU network arguments (preview):"
    get_network_args_preview
}

# Main function
main() {
    local cmd="${1:-setup}"

    init_network_state

    case "$cmd" in
        setup)
            log_info "Setting up network for VM passthrough"
            build_network_args
            ;;
        cleanup)
            cleanup_network
            ;;
        show)
            show_network_config
            ;;
        interfaces)
            get_vm_interfaces
            ;;
        mac)
            if [ -n "$2" ]; then
                generate_mac_address "$2"
            else
                echo "Usage: $0 mac <interface>" >&2
                exit 1
            fi
            ;;
        args)
            build_network_args
            ;;
        *)
            echo "Usage: $0 {setup|cleanup|show|interfaces|mac <iface>|args}" >&2
            exit 1
            ;;
    esac
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
