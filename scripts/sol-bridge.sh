#!/bin/bash
# sol-bridge.sh - Bridge QEMU serial console to TCP for ipmi_sim SOL
# Creates a TCP listener that bridges to the QEMU serial socket

set -e

SERIAL_SOCK="${SERIAL_SOCK:-/var/run/qemu/console.sock}"
SOL_PORT="${SOL_PORT:-9002}"
DEBUG="${DEBUG:-false}"

log() {
    if [ "$DEBUG" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [sol-bridge] $*" >&2
    fi
}

# Wait for QEMU serial socket to be available
wait_for_socket() {
    local timeout="${1:-30}"
    local count=0

    log "Waiting for QEMU serial socket: $SERIAL_SOCK"

    while [ ! -S "$SERIAL_SOCK" ]; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            echo "ERROR: Timeout waiting for $SERIAL_SOCK" >&2
            return 1
        fi
    done

    log "Serial socket available"
    return 0
}

# Start the bridge
start_bridge() {
    log "Starting SOL bridge: $SERIAL_SOCK <-> TCP:$SOL_PORT"

    # Use socat to bridge Unix socket to TCP
    # TCP-LISTEN: listen on TCP port for ipmi_sim connection
    # UNIX-CONNECT: connect to QEMU serial socket
    exec socat TCP-LISTEN:${SOL_PORT},reuseaddr,fork UNIX-CONNECT:${SERIAL_SOCK}
}

# Main
main() {
    echo "SOL Bridge starting..."
    echo "  Serial socket: $SERIAL_SOCK"
    echo "  TCP port: $SOL_PORT"

    # Wait for QEMU to create the serial socket
    wait_for_socket 60 || exit 1

    # Start the bridge
    start_bridge
}

main "$@"
