# Docker QEMU BMC

Containerized QEMU/KVM virtual machine with integrated IPMI BMC (Baseboard Management Controller) functionality. Enables physical-server-like power management and console access for virtual machines, designed for use with [containerlab](https://containerlab.dev/) network simulations.

## Features

- **QEMU/KVM Virtualization** - Full x86_64 VM with VNC console access
- **IPMI 2.0 BMC Simulation** - Compatible with standard `ipmitool` commands
- **Power Control** - On/Off/Cycle/Reset via IPMI chassis commands
- **Serial Over LAN (SOL)** - Remote serial console access via IPMI
- **Network Passthrough** - Container interfaces (eth2+) passed through to VM
- **Process Management** - supervisord manages all services
- **Containerlab Ready** - Works as a node in containerlab topologies

## Quick Start

### Build

```bash
docker build -t qemu-bmc:latest .
```

### Run

```bash
# Create a VM disk
mkdir -p vm
qemu-img create -f qcow2 vm/disk.qcow2 20G

# Run the container
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  qemu-bmc:latest
```

### Run with Network Passthrough

To pass network interfaces to the VM for connectivity testing:

```bash
# Create Docker networks
docker network create mgmt-net
docker network create vm-net

# Run with VM_NETWORKS (eth1 will be passed to VM)
docker run --rm --name qemu-bmc --privileged --device /dev/kvm:/dev/kvm --device /dev/net/tun:/dev/net/tun -p 5900:5900 -p 623:623/udp -v $(pwd)/vm:/vm:rw --network mgmt-net --network vm-net -e VM_NETWORKS=eth1 qemu-bmc:latest
```

Network interface assignment:
- `eth0` (mgmt-net) - Container management, keeps IP for VNC/IPMI access
- `eth1` (vm-net) - Bridged to VM via TAP device, no IP (L2 only)

To test VM connectivity, run another container on the same network:

```bash
docker run --rm -it --network vm-net alpine sh
# Inside: ifconfig to get IP, then ping from VM
```

### Access

```bash
# VNC console
vncviewer localhost:5900

# IPMI - Check BMC info
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password mc info

# IPMI - Power control
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power status
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power on
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power off
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power cycle

# IPMI - Serial Over LAN
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password sol activate
# Press ~. to disconnect
```

## Docker Compose

```bash
docker-compose up -d
docker-compose logs -f
docker-compose down
```

## Containerlab

Deploy a multi-node topology:

```bash
cd containerlab
containerlab deploy -t example.yml

# Get node IP
NODE1_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-qemu-bmc-lab-node1)

# Control node via IPMI
ipmitool -I lanplus -H $NODE1_IP -U admin -P password power status
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_MEMORY` | 2048 | VM memory in MB |
| `VM_CPUS` | 2 | Number of VM CPUs |
| `VM_DISK` | /vm/disk.qcow2 | Path to VM disk image |
| `VM_CDROM` | (empty) | Path to ISO for CD-ROM |
| `VM_BOOT` | c | Boot device (c=disk, d=cdrom) |
| `ENABLE_KVM` | true | Enable KVM acceleration |
| `VNC_PORT` | 5900 | VNC display port |
| `IPMI_USER` | admin | IPMI username |
| `IPMI_PASS` | password | IPMI password |
| `VM_NETWORKS` | (empty) | Interfaces to pass to VM (e.g., eth2,eth3) |
| `DEBUG` | false | Enable debug logging |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ OCI Container                                               │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ supervisord (PID 1)                                 │   │
│  │                                                     │   │
│  │  ┌──────────────┐       ┌──────────────┐           │   │
│  │  │  ipmi_sim    │       │    QEMU      │           │   │
│  │  │  (priority   │       │  (priority   │           │   │
│  │  │   10)        │       │   20)        │           │   │
│  │  └──────┬───────┘       └──────┬───────┘           │   │
│  │         │                      │                   │   │
│  └─────────┼──────────────────────┼───────────────────┘   │
│            │                      │                       │
│            │ QMP Socket           │ Serial TCP:9002       │
│            │ (power ctrl)         │ (SOL)                 │
│            └─────────────────────►├◄──────────────────────┤
│                                   │                       │
│  Network Interfaces:              │                       │
│  ├─ eth0: Management              │                       │
│  ├─ eth1: IPMI (UDP 623)          │                       │
│  └─ eth2+: VM passthrough ────────┘                       │
│                                                           │
└─────────────────────────────────────────────────────────────┘
```

### Key Integration Points

- **QMP Socket** (`/var/run/qemu/qmp.sock`) - IPMI power commands control QEMU
- **Serial TCP** (`localhost:9002`) - SOL connects to VM serial console
- **Power State** (`/var/run/qemu/power.state`) - Tracks VM power status

### IPMI to QMP Command Mapping

| IPMI Command | QMP Action |
|--------------|------------|
| `power on` | Start QEMU process |
| `power off` | `quit` (hard off) |
| `power cycle` | `system_reset` |
| `power reset` | `system_reset` |
| `power soft` | `system_powerdown` (ACPI) |

## Directory Structure

```
qemu-with-bmc/
├── Dockerfile              # Production image
├── Dockerfile.phase*       # Development phase images
├── docker-compose.yml      # Development configuration
├── containerlab/
│   └── example.yml         # Containerlab topology example
├── configs/
│   ├── supervisord.conf    # Process management
│   ├── qemu/
│   │   └── default.conf    # QEMU defaults
│   └── ipmi_sim/
│       ├── lan.conf        # IPMI network config
│       └── ipmisim.emu     # BMC emulation settings
├── scripts/
│   ├── entrypoint.sh       # Container entrypoint
│   ├── start-qemu.sh       # QEMU launcher
│   ├── start-ipmi.sh       # ipmi_sim launcher
│   ├── power-control.sh    # QMP power control
│   ├── chassis-control.sh  # IPMI chassis handler
│   ├── setup-network.sh    # Network passthrough
│   └── sol-bridge.sh       # SOL socket bridge
├── tests/
│   ├── run_tests.sh        # Test runner
│   ├── helpers/            # Test utilities
│   └── integration/        # Integration tests
└── docs/
    ├── DESIGN.md           # Architecture design (Japanese)
    ├── IMPLEMENTATION_PLAN.md  # Implementation phases (Japanese)
    └── TEST_SPEC.md        # Test specifications (Japanese)
```

## Testing

```bash
# Run all tests (builds image and runs 76 tests)
./tests/run_tests.sh all

# Run specific phase tests
./tests/run_tests.sh phase1    # QEMU basic
./tests/run_tests.sh phase2    # supervisord
./tests/run_tests.sh phase3    # IPMI foundation
./tests/run_tests.sh phase4    # Power control
./tests/run_tests.sh phase5    # Network
./tests/run_tests.sh phase6    # SOL
./tests/run_tests.sh phase7    # Integration

# Quick smoke test
./tests/run_tests.sh quick
```

## Requirements

### Host Requirements

- Linux with KVM support (`/dev/kvm`)
- Docker 20.10+
- `ipmitool` (for IPMI testing)
- VNC viewer (for console access)

### Container Capabilities

```yaml
privileged: true
devices:
  - /dev/kvm:/dev/kvm
  - /dev/net/tun:/dev/net/tun
cap_add:
  - NET_ADMIN
  - SYS_ADMIN
```

## Known Limitations

### SOL Connection After Power Cycle

When using `power cycle`, the QEMU process restarts, which causes the TCP port for Serial Over LAN (SOL) to temporarily close. This disconnects any active SOL session.

**Workaround:**
- Use `power reset` instead of `power cycle` when possible (maintains SOL connection)
- After `power cycle`, reconnect SOL:
  ```bash
  ipmitool -I lanplus -H <host> -U admin -P password sol activate
  ```

| Command | QEMU Process | SOL Connection |
|---------|--------------|----------------|
| `power reset` | Kept running | Maintained |
| `power cycle` | Restarted | Requires reconnect |

## Troubleshooting

### KVM not available

If `/dev/kvm` is not available, the container falls back to TCG (software emulation), which is slower but functional.

### IPMI connection refused

```bash
# Check if ipmi_sim is running
docker exec qemu-bmc supervisorctl status ipmi

# Check IPMI port
docker exec qemu-bmc netstat -ulnp | grep 623
```

### Power control not working

```bash
# Check QMP socket
docker exec qemu-bmc test -S /var/run/qemu/qmp.sock && echo "OK"

# Check power state file
docker exec qemu-bmc cat /var/run/qemu/power.state
```

### SOL not connecting

```bash
# Check serial TCP port is listening
docker exec qemu-bmc ss -tln | grep 9002

# Check ipmi_sim is connected to serial
docker exec qemu-bmc ss -tn | grep 9002

# Check IPMI log for SOL errors
docker exec qemu-bmc cat /var/log/ipmi/ipmi.log
```

If SOL disconnects after `power cycle`, reconnect with:
```bash
ipmitool -I lanplus -H <host> -U admin -P password sol activate
```

## License

MIT License

## Documentation

Detailed documentation is available in the `docs/` directory (in Japanese):

- `docs/DESIGN.md` - Architecture and design decisions
- `docs/IMPLEMENTATION_PLAN.md` - Implementation phases and progress
- `docs/TEST_SPEC.md` - Test specifications
