#!/bin/bash
# start-ipmi.sh - IPMI simulator startup script
# Starts ipmi_sim (OpenIPMI lanserv) for BMC simulation

set -e

# Environment variables
IPMI_USER="${IPMI_USER:-admin}"
IPMI_PASS="${IPMI_PASS:-password}"
DEBUG="${DEBUG:-false}"

# Configuration paths
LAN_CONF="/configs/ipmi_sim/lan.conf"
EMU_CONF="/configs/ipmi_sim/ipmisim.emu"

# Debug output
if [ "$DEBUG" = "true" ]; then
    echo "=== IPMI Configuration ==="
    echo "IPMI_USER: ${IPMI_USER}"
    echo "LAN_CONF: ${LAN_CONF}"
    echo "EMU_CONF: ${EMU_CONF}"
    echo "=========================="
fi

# Check configuration files
if [ ! -f "$LAN_CONF" ]; then
    echo "ERROR: LAN configuration not found: $LAN_CONF" >&2
    exit 1
fi

if [ ! -f "$EMU_CONF" ]; then
    echo "ERROR: EMU configuration not found: $EMU_CONF" >&2
    exit 1
fi

echo "Starting IPMI simulator..."

# Run ipmi_sim with configuration
# -c: LAN configuration file
# -f: EMU command file (MC configuration)
# -n: don't daemonize (run in foreground for supervisord)
exec /usr/bin/ipmi_sim -n -c "$LAN_CONF" -f "$EMU_CONF"
