# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker QEMU BMC is a containerized QEMU/KVM virtual machine with integrated IPMI BMC (Baseboard Management Controller) functionality. It enables physical-server-like power management and console access for virtual machines, designed for use with containerlab network simulations.

**Documentation is in Japanese.** Key specs are in `docs/DESIGN.md`, `docs/IMPLEMENTATION_PLAN.md`, and `docs/TEST_SPEC.md`.

## Project Status

Implementation follows a 7-phase approach. See `docs/IMPLEMENTATION_PLAN.md` for details and current progress.

## Build Commands

```bash
# Build (when Dockerfile exists)
docker build -t qemu-bmc:latest .

# Build specific phase during development
docker build -f Dockerfile.phase1 -t qemu-bmc:phase1 .

# Run container (requires KVM)
docker run --rm -it --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  qemu-bmc:latest
```

## Test Commands

```bash
# Run all tests
./tests/run_tests.sh all

# Run specific test level
./tests/run_tests.sh unit
./tests/run_tests.sh integration
./tests/run_tests.sh system
```

Test framework: BATS (Bash Automated Testing System). Test dependencies: `bats`, `ipmitool`, `expect`, `curl`.

## Test Evidence

When implementing each phase, save test evidence to `tests/evidence/` with the following format:

```
tests/evidence/phase{N}_test_{YYYYMMDD_HHMMSS}.log
```

Each evidence file must include:
- Test execution date and host information
- All test commands executed
- Complete command output (stdout/stderr)
- Test summary (PASS/FAIL for each criterion)

Example test script pattern:
```bash
LOG_FILE="tests/evidence/phase1_test_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== TEST: Description ==="
# test command here
echo "Result: PASS/FAIL"
```

## Architecture

```
OCI Container
├── supervisord (PID 1) - Process lifecycle management
│   ├── ipmi_sim (priority 10) - OpenIPMI lanserv, IPMI 2.0 simulator
│   └── QEMU/KVM (priority 20) - VM execution
│
└── Network Interfaces
    ├── eth0 - Debug/management (SSH to container)
    ├── eth1 - IPMI network (UDP 623)
    └── eth2+ - VM passthrough (macvtap/bridge to guest)
```

**Key integration points:**
- ipmi_sim controls QEMU via QMP socket (`/var/run/qemu/qmp.sock`)
- Serial Over LAN (SOL) connects to QEMU serial console (`/var/run/qemu/console.sock`)
- Power state tracked in `/var/run/qemu/power.state`

**IPMI power commands map to QMP:**
- Power On → `system_reset` + `cont`
- Power Off → `quit` or `system_powerdown`
- Power Cycle/Hard Reset → `system_reset`
- Soft Shutdown → `system_powerdown` (ACPI)

## Planned Directory Structure

```
docker-qemu-bmc/
├── Dockerfile
├── configs/
│   ├── supervisord.conf
│   ├── ipmi_sim/
│   │   ├── lan.conf
│   │   ├── ipmisim.emu
│   │   └── sdr.conf
│   └── qemu/default.conf
├── scripts/
│   ├── entrypoint.sh
│   ├── start-qemu.sh
│   ├── start-ipmi.sh
│   ├── power-control.sh
│   ├── setup-network.sh
│   └── health-check.sh
└── tests/
    ├── helpers/
    ├── unit/
    ├── integration/
    ├── system/
    └── run_tests.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_MEMORY` | 2048 | VM memory (MB) |
| `VM_CPUS` | 2 | VM CPU count |
| `VM_DISK` | /vm/disk.qcow2 | Main disk path |
| `IPMI_USER` | admin | IPMI username |
| `IPMI_PASS` | password | IPMI password |
| `IPMI_INTERFACE` | eth1 | IPMI bind interface |
| `VM_NETWORKS` | eth2 | NICs to pass to VM (comma-separated) |
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

# Serial Over LAN
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password sol activate
```

## Implementation Phases

1. **Phase 1**: Basic QEMU container - VNC access verification
2. **Phase 2**: supervisord integration - Process management
3. **Phase 3**: IPMI foundation - ipmi_sim responds to `mc info`
4. **Phase 4**: Power control - IPMI power commands via QMP
5. **Phase 5**: Network setup - eth2+ passthrough to VM
6. **Phase 6**: SOL implementation - Serial console via IPMI
7. **Phase 7**: Integration - containerlab support, full test suite
