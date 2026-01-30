# Docker QEMU BMC - Final Production Image
# Containerized QEMU/KVM with integrated IPMI BMC functionality
#
# Features:
# - QEMU/KVM virtualization with VNC access
# - IPMI 2.0 BMC simulation (ipmi_sim)
# - Power control via IPMI (on/off/cycle/reset)
# - Serial Over LAN (SOL) support
# - Network passthrough (eth2+ to VM)
# - Process management via supervisord
#
# Usage:
#   docker build -t qemu-bmc:latest .
#   docker run --privileged --device /dev/kvm:/dev/kvm \
#     -p 5900:5900 -p 623:623/udp \
#     -v /path/to/disk.qcow2:/vm/disk.qcow2 \
#     qemu-bmc:latest

FROM ubuntu:22.04

LABEL maintainer="qemu-bmc"
LABEL description="QEMU/KVM VM with integrated IPMI BMC for containerlab"
LABEL version="1.0"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
# - qemu-system-x86: VM execution
# - supervisor: Process management
# - openipmi/ipmitool: IPMI simulation and tools
# - socat: Socket bridging for SOL and QMP
# - iproute2: Network configuration
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-utils \
    supervisor \
    openipmi \
    ipmitool \
    socat \
    iproute2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create directory structure
RUN mkdir -p \
    /vm \
    /iso \
    /scripts \
    /configs/qemu \
    /configs/ipmi_sim \
    /var/run/qemu \
    /var/run/qemu/network \
    /var/log/qemu \
    /var/log/supervisor \
    /var/log/ipmi

# Copy configuration files
COPY configs/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY configs/qemu/default.conf /configs/qemu/
COPY configs/ipmi_sim/lan.conf /configs/ipmi_sim/
COPY configs/ipmi_sim/ipmisim.emu /configs/ipmi_sim/

# Copy scripts
COPY scripts/entrypoint.sh /scripts/
COPY scripts/start-qemu.sh /scripts/
COPY scripts/start-ipmi.sh /scripts/
COPY scripts/power-control.sh /scripts/
COPY scripts/chassis-control.sh /scripts/
COPY scripts/setup-network.sh /scripts/
COPY scripts/sol-bridge.sh /scripts/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# ============================================
# Environment Variables
# ============================================

# VM Configuration
ENV VM_MEMORY=2048
ENV VM_CPUS=2
ENV VM_DISK=/vm/disk.qcow2
ENV VM_CDROM=""
ENV VM_BOOT=c
ENV ENABLE_KVM=true
ENV VNC_PORT=5900
ENV DEBUG=false

# IPMI Configuration
ENV IPMI_USER=admin
ENV IPMI_PASS=password

# Internal paths (usually don't need to change)
ENV QMP_SOCK=/var/run/qemu/qmp.sock
ENV POWER_STATE_FILE=/var/run/qemu/power.state
ENV SERIAL_SOCK=/var/run/qemu/console.sock
ENV SOL_PORT=9002

# Network Configuration
# Set VM_NETWORKS to comma-separated list of interfaces to pass to VM
# e.g., VM_NETWORKS=eth2,eth3
ENV VM_NETWORKS=""
ENV NETWORK_STATE_DIR=/var/run/qemu/network

# ============================================
# Ports
# ============================================

# VNC console
EXPOSE 5900

# IPMI RMCP (UDP)
EXPOSE 623/udp

# ============================================
# Volumes
# ============================================

# VM disk images
VOLUME ["/vm"]

# ISO images for CDROM
VOLUME ["/iso"]

# ============================================
# Health Check
# ============================================

# Check that all critical services are running
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD supervisorctl status qemu | grep -q RUNNING && \
        supervisorctl status ipmi | grep -q RUNNING || exit 1

# ============================================
# Entrypoint
# ============================================

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
