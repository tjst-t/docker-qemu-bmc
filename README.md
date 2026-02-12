# Docker QEMU BMC

Containerized QEMU/KVM virtual machine with integrated IPMI BMC (Baseboard Management Controller) functionality. Enables physical-server-like power management and console access for virtual machines, designed for use with [containerlab](https://containerlab.dev/) network simulations.

## Features

- **QEMU/KVM Virtualization** - Full x86_64 VM with VNC console access
- **IPMI 2.0 BMC Simulation** - Compatible with standard `ipmitool` commands
- **Power Control** - On/Off/Cycle/Reset via IPMI chassis commands
- **Serial Over LAN (SOL)** - Remote serial console access via IPMI
- **Network Passthrough** - Container interfaces (eth2+) passed through to VM
- **Boot Mode Selection** - Legacy BIOS (SeaBIOS) or UEFI (OVMF) boot
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

## UEFI Boot Mode

By default, the VM boots in Legacy BIOS mode (SeaBIOS). To use UEFI boot mode with OVMF firmware:

### Run with UEFI

```bash
# Run with UEFI boot mode
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MODE=uefi \
  qemu-bmc:latest
```

### Using docker-compose

```bash
# Edit docker-compose.yml and set VM_BOOT_MODE=uefi
# Or use environment override:
VM_BOOT_MODE=uefi docker-compose up -d
```

### Boot Mode Comparison

| Mode | Firmware | Use Case |
|------|----------|----------|
| `bios` (default) | SeaBIOS | Legacy OS, quick testing |
| `uefi` | OVMF | Modern OS, Secure Boot compatible images |

**Note:** UEFI mode stores NVRAM variables in `/var/run/qemu/OVMF_VARS.fd` within the container. These are reset when the container is recreated.

## Boot Menu Timeout

Set `VM_BOOT_MENU_TIMEOUT` to display the BIOS/UEFI boot menu for the specified duration (in milliseconds). When set to default (0), the boot menu is not displayed and the VM boots immediately.

```bash
# Display boot menu for 30 seconds
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MENU_TIMEOUT=30000 \
  qemu-bmc:latest
```

### Use Cases

**Boot Device Selection for OS Installation**

When installing an OS from CD-ROM, you can select the installation media from the boot menu.

```bash
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -v $(pwd)/iso:/iso:ro \
  -e VM_CDROM=/iso/installer.iso \
  -e VM_BOOT_MENU_TIMEOUT=30000 \
  qemu-bmc:latest
# Connect via VNC -> Select CD-ROM from boot menu to install
```

**Automated BIOS Operation via VNC Tools**

Combine with VNC automation tools such as [vncprobe](https://github.com/tjst-t/vncprobe) to automate boot menu operations.

```bash
# Start container (boot menu waits 30 seconds)
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MENU_TIMEOUT=30000 \
  qemu-bmc:latest

# Capture boot menu screenshot
vncprobe capture -s "127.0.0.1:5900" -o screenshot.png

# Press Escape to open boot device selection menu (SeaBIOS)
vncprobe key -s "127.0.0.1:5900" Escape

# Select device by number
vncprobe key -s "127.0.0.1:5900" 1
```

**Debugging and Troubleshooting**

When a VM fails to boot properly, you can pause at the boot menu to inspect the state.

```bash
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MENU_TIMEOUT=60000 \
  -e VM_BOOT_MODE=uefi \
  qemu-bmc:latest
# Connect via VNC -> Inspect settings in Device Manager or Boot Manager from UEFI menu
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
| `VM_BOOT_MODE` | bios | Boot mode: `bios` (Legacy/SeaBIOS) or `uefi` (OVMF) |
| `VM_BOOT_MENU_TIMEOUT` | 0 | Boot menu display time in ms (0=disabled) |
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
# Run all tests (builds image and runs 91 tests)
./tests/run_tests.sh all

# Run specific phase tests
./tests/run_tests.sh phase1    # QEMU basic
./tests/run_tests.sh phase2    # supervisord
./tests/run_tests.sh phase3    # IPMI foundation
./tests/run_tests.sh phase4    # Power control
./tests/run_tests.sh phase5    # Network
./tests/run_tests.sh phase6    # SOL
./tests/run_tests.sh phase7    # Integration
./tests/run_tests.sh bootmode  # Boot mode (BIOS/UEFI)

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

---

# Docker QEMU BMC (日本語)

IPMI BMC（ベースボード管理コントローラー）機能を統合した、コンテナ化QEMU/KVM仮想マシンです。仮想マシンに対して物理サーバーのような電源管理やコンソールアクセスを実現し、[containerlab](https://containerlab.dev/) によるネットワークシミュレーションでの利用を想定しています。

## 機能

- **QEMU/KVM仮想化** - VNCコンソールアクセス付きのx86_64 VM
- **IPMI 2.0 BMCシミュレーション** - 標準 `ipmitool` コマンドと互換
- **電源制御** - IPMIシャーシコマンドによるオン/オフ/サイクル/リセット
- **Serial Over LAN (SOL)** - IPMI経由のリモートシリアルコンソールアクセス
- **ネットワークパススルー** - コンテナインターフェース（eth2以降）をVMに透過
- **ブートモード選択** - レガシーBIOS（SeaBIOS）またはUEFI（OVMF）ブート
- **プロセス管理** - supervisordが全サービスを管理
- **Containerlab対応** - containerlabトポロジーのノードとして動作

## クイックスタート

### ビルド

```bash
docker build -t qemu-bmc:latest .
```

### 実行

```bash
# VMディスクを作成
mkdir -p vm
qemu-img create -f qcow2 vm/disk.qcow2 20G

# コンテナを実行
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  qemu-bmc:latest
```

### ネットワークパススルー付き実行

VM にネットワークインターフェースを渡して接続テストを行う場合:

```bash
# Dockerネットワークを作成
docker network create mgmt-net
docker network create vm-net

# VM_NETWORKSを指定して実行（eth1がVMに渡される）
docker run --rm --name qemu-bmc --privileged --device /dev/kvm:/dev/kvm --device /dev/net/tun:/dev/net/tun -p 5900:5900 -p 623:623/udp -v $(pwd)/vm:/vm:rw --network mgmt-net --network vm-net -e VM_NETWORKS=eth1 qemu-bmc:latest
```

ネットワークインターフェースの割り当て:
- `eth0`（mgmt-net）- コンテナ管理用、VNC/IPMIアクセス用のIPを保持
- `eth1`（vm-net）- TAPデバイス経由でVMにブリッジ、IPなし（L2のみ）

VM接続のテストには、同じネットワーク上で別のコンテナを起動します:

```bash
docker run --rm -it --network vm-net alpine sh
# コンテナ内: ifconfigでIPを確認し、VMからpingを実行
```

### アクセス

```bash
# VNCコンソール
vncviewer localhost:5900

# IPMI - BMC情報確認
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password mc info

# IPMI - 電源制御
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power status
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power on
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power off
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power cycle

# IPMI - Serial Over LAN
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password sol activate
# ~. で切断
```

## UEFIブートモード

デフォルトではVMはレガシーBIOSモード（SeaBIOS）で起動します。OVMFファームウェアを使用したUEFIブートモードを利用するには:

### UEFIで実行

```bash
# UEFIブートモードで実行
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MODE=uefi \
  qemu-bmc:latest
```

### docker-composeを使用

```bash
# docker-compose.ymlを編集してVM_BOOT_MODE=uefiを設定
# または環境変数で上書き:
VM_BOOT_MODE=uefi docker-compose up -d
```

### ブートモード比較

| モード | ファームウェア | ユースケース |
|--------|--------------|-------------|
| `bios`（デフォルト） | SeaBIOS | レガシーOS、簡易テスト |
| `uefi` | OVMF | モダンOS、Secure Boot対応イメージ |

**注意:** UEFIモードではNVRAM変数がコンテナ内の `/var/run/qemu/OVMF_VARS.fd` に保存されます。コンテナの再作成時にリセットされます。

## ブートメニュータイムアウト

`VM_BOOT_MENU_TIMEOUT` を設定すると、BIOS/UEFIのブートメニューを指定時間（ミリ秒）表示して待機します。デフォルト（0）ではブートメニューは表示されず、即座にブートが開始されます。

```bash
# ブートメニューを30秒間表示
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MENU_TIMEOUT=30000 \
  qemu-bmc:latest
```

### ユースケース

**OSインストール時のブートデバイス選択**

CD-ROMからOSをインストールする際に、ブートメニューからインストールメディアを選択できます。

```bash
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -v $(pwd)/iso:/iso:ro \
  -e VM_CDROM=/iso/installer.iso \
  -e VM_BOOT_MENU_TIMEOUT=30000 \
  qemu-bmc:latest
# VNCで接続 → ブートメニューからCD-ROMを選択してインストール
```

**VNCツールによる自動BIOS操作**

[vncprobe](https://github.com/tjst-t/vncprobe) 等のVNC自動化ツールと組み合わせることで、ブートメニューの操作を自動化できます。

```bash
# コンテナ起動（ブートメニュー30秒待機）
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MENU_TIMEOUT=30000 \
  qemu-bmc:latest

# ブートメニュー画面をスクリーンショット
vncprobe capture -s "127.0.0.1:5900" -o screenshot.png

# Escキーでブートデバイス選択メニューを開く（SeaBIOS）
vncprobe key -s "127.0.0.1:5900" Escape

# デバイスを番号で選択
vncprobe key -s "127.0.0.1:5900" 1
```

**デバッグ・トラブルシューティング**

VMが正常にブートしない場合に、ブートメニューで停止させて状態を確認できます。

```bash
docker run -d --name qemu-bmc --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 -p 623:623/udp \
  -v $(pwd)/vm:/vm:rw \
  -e VM_BOOT_MENU_TIMEOUT=60000 \
  -e VM_BOOT_MODE=uefi \
  qemu-bmc:latest
# VNCで接続 → UEFIメニューからDevice ManagerやBoot Managerで設定確認
```

## Docker Compose

```bash
docker-compose up -d
docker-compose logs -f
docker-compose down
```

## Containerlab

マルチノードトポロジーのデプロイ:

```bash
cd containerlab
containerlab deploy -t example.yml

# ノードIPを取得
NODE1_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-qemu-bmc-lab-node1)

# IPMI経由でノードを制御
ipmitool -I lanplus -H $NODE1_IP -U admin -P password power status
```

## 環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `VM_MEMORY` | 2048 | VMメモリ（MB） |
| `VM_CPUS` | 2 | VM CPUコア数 |
| `VM_DISK` | /vm/disk.qcow2 | VMディスクイメージのパス |
| `VM_CDROM` | （空） | CD-ROM用ISOのパス |
| `VM_BOOT` | c | ブートデバイス（c=ディスク、d=CD-ROM） |
| `VM_BOOT_MODE` | bios | ブートモード: `bios`（レガシー/SeaBIOS）または `uefi`（OVMF） |
| `VM_BOOT_MENU_TIMEOUT` | 0 | ブートメニュー表示時間（ミリ秒、0=無効） |
| `ENABLE_KVM` | true | KVMアクセラレーション有効化 |
| `VNC_PORT` | 5900 | VNC表示ポート |
| `IPMI_USER` | admin | IPMIユーザー名 |
| `IPMI_PASS` | password | IPMIパスワード |
| `VM_NETWORKS` | （空） | VMに渡すインターフェース（例: eth2,eth3） |
| `DEBUG` | false | デバッグログ有効化 |

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│ OCIコンテナ                                                  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ supervisord (PID 1)                                 │   │
│  │                                                     │   │
│  │  ┌──────────────┐       ┌──────────────┐           │   │
│  │  │  ipmi_sim    │       │    QEMU      │           │   │
│  │  │  (優先度     │       │  (優先度     │           │   │
│  │  │   10)        │       │   20)        │           │   │
│  │  └──────┬───────┘       └──────┬───────┘           │   │
│  │         │                      │                   │   │
│  └─────────┼──────────────────────┼───────────────────┘   │
│            │                      │                       │
│            │ QMPソケット          │ シリアルTCP:9002       │
│            │ (電源制御)           │ (SOL)                 │
│            └─────────────────────►├◄──────────────────────┤
│                                   │                       │
│  ネットワークインターフェース:     │                       │
│  ├─ eth0: 管理用                  │                       │
│  ├─ eth1: IPMI (UDP 623)         │                       │
│  └─ eth2+: VMパススルー ──────────┘                       │
│                                                           │
└─────────────────────────────────────────────────────────────┘
```

### 主要な統合ポイント

- **QMPソケット** (`/var/run/qemu/qmp.sock`) - IPMI電源コマンドがQEMUを制御
- **シリアルTCP** (`localhost:9002`) - SOLがVMシリアルコンソールに接続
- **電源状態** (`/var/run/qemu/power.state`) - VM電源状態を追跡

### IPMIからQMPへのコマンドマッピング

| IPMIコマンド | QMPアクション |
|-------------|--------------|
| `power on` | QEMUプロセス起動 |
| `power off` | `quit`（強制オフ） |
| `power cycle` | `system_reset` |
| `power reset` | `system_reset` |
| `power soft` | `system_powerdown`（ACPI） |

## テスト

```bash
# 全テスト実行（イメージビルド後、91テスト実行）
./tests/run_tests.sh all

# フェーズ別テスト
./tests/run_tests.sh phase1    # QEMU基本
./tests/run_tests.sh phase2    # supervisord
./tests/run_tests.sh phase3    # IPMI基盤
./tests/run_tests.sh phase4    # 電源制御
./tests/run_tests.sh phase5    # ネットワーク
./tests/run_tests.sh phase6    # SOL
./tests/run_tests.sh phase7    # 統合テスト
./tests/run_tests.sh bootmode  # ブートモード（BIOS/UEFI）

# クイックスモークテスト
./tests/run_tests.sh quick
```

## 要件

### ホスト要件

- KVMサポート付きLinux（`/dev/kvm`）
- Docker 20.10以上
- `ipmitool`（IPMIテスト用）
- VNCビューワー（コンソールアクセス用）

### コンテナ権限

```yaml
privileged: true
devices:
  - /dev/kvm:/dev/kvm
  - /dev/net/tun:/dev/net/tun
cap_add:
  - NET_ADMIN
  - SYS_ADMIN
```

## 既知の制限事項

### 電源サイクル後のSOL接続

`power cycle` 使用時、QEMUプロセスが再起動されるため、Serial Over LAN（SOL）用のTCPポートが一時的に閉じます。これによりアクティブなSOLセッションが切断されます。

**回避策:**
- 可能な場合は `power cycle` の代わりに `power reset` を使用（SOL接続を維持）
- `power cycle` 後にSOLを再接続:
  ```bash
  ipmitool -I lanplus -H <host> -U admin -P password sol activate
  ```

| コマンド | QEMUプロセス | SOL接続 |
|---------|-------------|---------|
| `power reset` | 維持 | 維持 |
| `power cycle` | 再起動 | 再接続が必要 |

## トラブルシューティング

### KVMが利用不可

`/dev/kvm` が利用できない場合、コンテナはTCG（ソフトウェアエミュレーション）にフォールバックします。動作は遅くなりますが機能します。

### IPMI接続拒否

```bash
# ipmi_simの動作確認
docker exec qemu-bmc supervisorctl status ipmi

# IPMIポートの確認
docker exec qemu-bmc netstat -ulnp | grep 623
```

### 電源制御が動作しない

```bash
# QMPソケットの確認
docker exec qemu-bmc test -S /var/run/qemu/qmp.sock && echo "OK"

# 電源状態ファイルの確認
docker exec qemu-bmc cat /var/run/qemu/power.state
```

### SOLが接続できない

```bash
# シリアルTCPポートのリスン確認
docker exec qemu-bmc ss -tln | grep 9002

# ipmi_simのシリアル接続確認
docker exec qemu-bmc ss -tn | grep 9002

# IPMIログのSOLエラー確認
docker exec qemu-bmc cat /var/log/ipmi/ipmi.log
```

`power cycle` 後にSOLが切断された場合は再接続してください:
```bash
ipmitool -I lanplus -H <host> -U admin -P password sol activate
```

## ライセンス

MIT License

## ドキュメント

詳細なドキュメントは `docs/` ディレクトリにあります（日本語）:

- `docs/DESIGN.md` - アーキテクチャと設計方針
- `docs/IMPLEMENTATION_PLAN.md` - 実装フェーズと進捗
- `docs/TEST_SPEC.md` - テスト仕様
