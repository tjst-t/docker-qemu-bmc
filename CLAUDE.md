# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker QEMU BMC is a containerized QEMU/KVM virtual machine with integrated IPMI BMC (Baseboard Management Controller) functionality. It enables physical-server-like power management and console access for virtual machines, designed for use with containerlab network simulations.

**Documentation is in Japanese.** Key specs are in `docs/DESIGN.md`, `docs/IMPLEMENTATION_PLAN.md`, and `docs/TEST_SPEC.md`.

## Project Status

**All 7 phases are complete.** The project is production-ready with 76 passing tests.

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Basic QEMU container | Complete |
| 2 | supervisord integration | Complete |
| 3 | IPMI foundation | Complete |
| 4 | Power control | Complete |
| 5 | Network passthrough | Complete |
| 6 | Serial Over LAN | Complete |
| 7 | Final integration | Complete |

## Build Commands

```bash
# Build production image
docker build -t qemu-bmc:latest .

# Build specific phase during development
docker build -f Dockerfile.phase1 -t qemu-bmc:phase1 .

# Run container (requires KVM)
docker run --rm -it --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  -v /path/to/vm:/vm:rw \
  qemu-bmc:latest

# Using docker-compose
docker-compose up -d
```

## Test Commands

```bash
# Run all tests (76 tests)
./tests/run_tests.sh all

# Run specific phase tests
./tests/run_tests.sh phase1    # QEMU basic (9 tests)
./tests/run_tests.sh phase2    # supervisord (9 tests)
./tests/run_tests.sh phase3    # IPMI foundation (11 tests)
./tests/run_tests.sh phase4    # Power control (12 tests)
./tests/run_tests.sh phase5    # Network (15 tests)
./tests/run_tests.sh phase6    # SOL (12 tests)
./tests/run_tests.sh phase7    # Integration (13 tests)

# Quick smoke test
./tests/run_tests.sh quick
```

Test framework: Custom bash-based test runner with helpers. Test dependencies: `docker`, `ipmitool`.

## Architecture

```
OCI Container
├── supervisord (PID 1) - Process lifecycle management
│   ├── ipmi_sim (priority 10) - OpenIPMI lanserv, IPMI 2.0 simulator
│   ├── QEMU/KVM (priority 20) - VM execution
│   └── sol-bridge (priority 25) - Serial socket to TCP bridge
│
├── Sockets
│   ├── /var/run/qemu/qmp.sock - QMP for power control
│   ├── /var/run/qemu/console.sock - Serial console for SOL
│   └── /var/run/qemu/power.state - Power state tracking
│
└── Network Interfaces
    ├── eth0 - Container management
    ├── eth1 - IPMI network (UDP 623)
    └── eth2+ - VM passthrough (TAP devices)
```

**Key integration points:**
- ipmi_sim controls QEMU via QMP socket (`/var/run/qemu/qmp.sock`)
- Serial Over LAN (SOL) connects to QEMU serial console via sol-bridge
- Power state tracked in `/var/run/qemu/power.state`

**IPMI power commands map to:**
- Power On → Start QEMU process via supervisorctl
- Power Off → Stop QEMU via QMP `quit`
- Power Cycle/Reset → QMP `system_reset`
- Soft Shutdown → QMP `system_powerdown` (ACPI)

## Directory Structure

```
qemu-with-bmc/
├── Dockerfile              # Production image
├── Dockerfile.phase*       # Development phase images
├── docker-compose.yml      # Development/testing config
├── containerlab/
│   └── example.yml         # Two-node topology example
├── configs/
│   ├── supervisord.conf    # Process management
│   ├── qemu/default.conf   # QEMU defaults
│   └── ipmi_sim/
│       ├── lan.conf        # IPMI network + SOL config
│       └── ipmisim.emu     # BMC emulation settings
├── scripts/
│   ├── entrypoint.sh       # Container entrypoint
│   ├── start-qemu.sh       # QEMU launcher with network/serial
│   ├── start-ipmi.sh       # ipmi_sim launcher
│   ├── power-control.sh    # QMP power control
│   ├── chassis-control.sh  # IPMI chassis handler
│   ├── setup-network.sh    # TAP device creation for VM
│   └── sol-bridge.sh       # socat serial-to-TCP bridge
├── tests/
│   ├── run_tests.sh        # Main test runner
│   ├── helpers/
│   │   └── test_helper.sh  # Test utilities
│   └── integration/
│       └── test_phase*.sh  # Phase-specific tests
└── docs/
    ├── DESIGN.md           # Architecture (Japanese)
    ├── IMPLEMENTATION_PLAN.md  # Phases (Japanese)
    └── TEST_SPEC.md        # Test specs (Japanese)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_MEMORY` | 2048 | VM memory (MB) |
| `VM_CPUS` | 2 | VM CPU count |
| `VM_DISK` | /vm/disk.qcow2 | Main disk path |
| `VM_CDROM` | (empty) | ISO path for CD-ROM |
| `VM_BOOT` | c | Boot device (c=disk, d=cdrom) |
| `VM_BOOT_MODE` | bios | Boot mode: bios (Legacy) or uefi (OVMF) |
| `IPMI_USER` | admin | IPMI username |
| `IPMI_PASS` | password | IPMI password |
| `VM_NETWORKS` | (empty) | NICs to pass to VM (comma-separated, e.g., eth2,eth3) |
| `ENABLE_KVM` | true | Enable KVM acceleration |
| `VNC_PORT` | 5900 | VNC port |
| `DEBUG` | false | Debug mode |

## Required Host Capabilities

```yaml
privileged: true
devices:
  - /dev/kvm:/dev/kvm
  - /dev/net/tun:/dev/net/tun
cap_add:
  - NET_ADMIN
  - SYS_ADMIN
```

## Testing with IPMI

```bash
# Basic connectivity
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password mc info

# Power control
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power status
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power on
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power off
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power cycle

# Serial Over LAN
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password sol activate
# Press ~. to disconnect
```

## Containerlab Deployment

```bash
cd containerlab
containerlab deploy -t example.yml

# Get node IP and control via IPMI
NODE1_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-qemu-bmc-lab-node1)
ipmitool -I lanplus -H $NODE1_IP -U admin -P password power status
```
