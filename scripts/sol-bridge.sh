#!/bin/bash
# sol-bridge.sh - SOL bridge placeholder
# QEMU now provides TCP socket directly for SOL, so this script just waits
# to keep supervisord happy

set -e

SOL_PORT="${SOL_PORT:-9002}"

echo "SOL Bridge: QEMU provides TCP:${SOL_PORT} directly for SOL"
echo "This process will wait indefinitely..."

# Wait for QEMU to start TCP listener
sleep 5

# Check if QEMU's TCP port is available
for i in $(seq 1 30); do
    if ss -tln | grep -q ":${SOL_PORT} "; then
        echo "SOL TCP port ${SOL_PORT} is ready (provided by QEMU)"
        break
    fi
    sleep 1
done

# Keep running (supervisord expects this process to stay alive)
exec sleep infinity
