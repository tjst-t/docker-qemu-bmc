# Docker QEMU BMC コンテナ設計書

## 1. 概要

### 1.1 目的
containerlabで動作する、QEMU/KVM仮想マシンとBMC（IPMIインターフェース）を統合したOCIコンテナを作成する。このコンテナにより、物理サーバーのように電源管理やコンソールアクセスが可能な仮想マシン環境を提供する。

### 1.2 ユースケース
- containerlabを使用したネットワークトポロジーのシミュレーション
- IPMIを使用したサーバー管理のテスト環境構築
- 仮想データセンター環境のプロトタイピング

## 2. アーキテクチャ

### 2.1 全体構成図

```
┌─────────────────────────────────────────────────────────────────┐
│                     OCI Container                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    supervisord                               ││
│  │  ┌──────────────────────┐    ┌────────────────────────────┐ ││
│  │  │      ipmi_sim        │    │         QEMU/KVM           │ ││
│  │  │  (OpenIPMI lanserv)  │    │                            │ ││
│  │  │                      │    │  ┌──────────────────────┐  │ ││
│  │  │  - Power Control ────┼────┼─►│    Guest VM          │  │ ││
│  │  │  - SOL Console   ────┼────┼─►│                      │  │ ││
│  │  │  - Sensor Data       │    │  │  eth0 ─► virtio-net  │  │ ││
│  │  │                      │    │  │  eth1 ─► virtio-net  │  │ ││
│  │  └──────────────────────┘    │  │  ...                 │  │ ││
│  │           │                   │  └──────────────────────┘  │ ││
│  │           │                   └────────────────────────────┘ ││
│  └───────────┼──────────────────────────────────────────────────┘│
│              │                                                   │
│  ┌───────────┴───────────────────────────────────────────────┐  │
│  │                   Network Interfaces                       │  │
│  │  eth0 (debug)  │  eth1 (IPMI)  │  eth2+ (VM passthrough)  │  │
│  └────────────────┴───────────────┴───────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 コンポーネント詳細

#### 2.2.1 supervisord
- 全プロセスのライフサイクル管理
- qemuとipmi_simの起動順序制御
- プロセス監視と自動再起動

#### 2.2.2 QEMU/KVM
- 仮想マシンの実行エンジン
- QMP (QEMU Machine Protocol) ソケットを公開
- VNCまたはSPICEコンソールの提供

#### 2.2.3 ipmi_sim (OpenIPMI lanserv)
- IPMI 2.0プロトコルのシミュレーション
- QMPを通じたVM電源制御
- Serial Over LAN (SOL) の提供
- センサーデータのシミュレーション

## 3. ネットワーク設計

### 3.1 インターフェース割り当て

| Interface | 用途 | 説明 |
|-----------|------|------|
| eth0 | デバッグ/管理 | SSH、監視用。コンテナ自体へのアクセス |
| eth1 | IPMI | ipmi_simがリッスン。BMC管理用ネットワーク |
| eth2+ | VM接続 | ゲストVMに直接パススルー（macvtapまたはbridge） |

### 3.2 ネットワーク構成詳細

```
Container Network Namespace
├── eth0 ─────────────────────────► Debug Network (management)
│     └── IP: DHCP or Static
│
├── eth1 ─────────────────────────► IPMI Network
│     └── ipmi_sim binds to this interface
│         └── UDP 623 (IPMI RMCP)
│
├── eth2 ─────► macvtap/bridge ───► VM eth0 (virtio-net)
├── eth3 ─────► macvtap/bridge ───► VM eth1 (virtio-net)
└── ...
```

### 3.3 VM内ネットワーク構成

ゲストVMから見たネットワーク：
- eth2(host) → eth0(guest)
- eth3(host) → eth1(guest)
- 以降同様にマッピング

## 4. 実装仕様

### 4.1 ディレクトリ構成

```
docker-qemu-bmc/
├── Dockerfile                    # マルチステージビルド
├── docker-compose.yml            # 開発・テスト用
├── configs/
│   ├── supervisord.conf          # supervisor設定
│   ├── ipmi_sim/
│   │   ├── lan.conf              # IPMI LAN設定
│   │   ├── ipmisim.emu           # エミュレーション設定
│   │   └── sdr.conf              # センサー定義
│   └── qemu/
│       └── default.conf          # デフォルトVM設定
├── scripts/
│   ├── entrypoint.sh             # コンテナエントリーポイント
│   ├── start-qemu.sh             # QEMU起動スクリプト
│   ├── start-ipmi.sh             # ipmi_sim起動スクリプト
│   ├── power-control.sh          # 電源制御ヘルパー
│   ├── setup-network.sh          # ネットワーク設定
│   └── health-check.sh           # ヘルスチェック
├── docs/
│   ├── DESIGN.md                 # 本ドキュメント
│   └── USAGE.md                  # 使用方法
└── tests/
    ├── test_ipmi.sh              # IPMIテスト
    ├── test_power.sh             # 電源制御テスト
    ├── test_network.sh           # ネットワークテスト
    └── test_integration.sh       # 統合テスト
```

### 4.2 Dockerfile仕様

```dockerfile
# ベースイメージ
FROM ubuntu:22.04

# 必要パッケージ
- qemu-system-x86 (または qemu-kvm)
- openipmi
- ipmitool
- supervisor
- socat
- bridge-utils
- iproute2
- jq (QMP応答パース用)

# ボリューム
- /vm         : VMディスクイメージ格納
- /iso        : ISOイメージ格納
- /config     : カスタム設定

# ポート
- 623/udp     : IPMI RMCP
- 5900/tcp    : VNC (オプション)
- 2222/tcp    : SSH to container (オプション)
```

### 4.3 環境変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `VM_MEMORY` | 2048 | VMメモリ(MB) |
| `VM_CPUS` | 2 | VM CPU数 |
| `VM_DISK` | /vm/disk.qcow2 | メインディスクパス |
| `VM_CDROM` | - | CDROMイメージパス |
| `VM_BOOT` | c | ブートデバイス (c=disk, d=cdrom, n=network) |
| `IPMI_USER` | admin | IPMIユーザー名 |
| `IPMI_PASS` | password | IPMIパスワード |
| `IPMI_INTERFACE` | eth1 | IPMIバインドインターフェース |
| `VM_NETWORKS` | eth2 | VMに接続するNIC (カンマ区切り) |
| `ENABLE_KVM` | true | KVMアクセラレーション有効化 |
| `VNC_PORT` | 5900 | VNCポート |
| `DEBUG` | false | デバッグモード |

### 4.4 supervisord設定

```ini
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log

[program:ipmi_sim]
command=/scripts/start-ipmi.sh
priority=10
autorestart=true
stdout_logfile=/var/log/ipmi_sim.log

[program:qemu]
command=/scripts/start-qemu.sh
priority=20
autorestart=false          # QEMUは意図的停止を許可
stdout_logfile=/var/log/qemu.log

[eventlistener:qemu_monitor]
command=/scripts/qemu-monitor.py
events=PROCESS_STATE
```

### 4.5 QEMU起動仕様

#### 4.5.1 QMPソケット
```
/var/run/qemu/qmp.sock     # QMP制御用
/var/run/qemu/console.sock # シリアルコンソール用
```

#### 4.5.2 QEMU起動コマンド例
```bash
qemu-system-x86_64 \
  -name guest=vm,debug-threads=on \
  -machine q35,accel=kvm \
  -cpu host \
  -m ${VM_MEMORY} \
  -smp ${VM_CPUS} \
  -drive file=${VM_DISK},format=qcow2,if=virtio \
  -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:xx:xx:xx \
  -chardev socket,id=qmp,path=/var/run/qemu/qmp.sock,server=on,wait=off \
  -mon chardev=qmp,mode=control \
  -chardev socket,id=serial0,path=/var/run/qemu/console.sock,server=on,wait=off \
  -serial chardev:serial0 \
  -vnc :0 \
  -daemonize
```

#### 4.5.3 ブートモード

`VM_BOOT_MODE` 環境変数でブートモードを切り替えられます：

| 値 | 説明 |
|---|---|
| `bios` | Legacy BIOS (SeaBIOS) - デフォルト |
| `uefi` | UEFI (OVMF) |

UEFIモードでは、OVMFファームウェアが使用されます。NVRAM変数は `/var/run/qemu/OVMF_VARS.fd` に保存されます。

### 4.6 ipmi_sim設定仕様

#### 4.6.1 電源制御コマンドマッピング

| IPMI Command | 動作 |
|--------------|------|
| Power On | QMP: `system_reset` + `cont` |
| Power Off | QMP: `quit` または `system_powerdown` |
| Power Cycle | QMP: `system_reset` |
| Hard Reset | QMP: `system_reset` |
| Soft Shutdown | QMP: `system_powerdown` (ACPI) |

#### 4.6.2 電源状態管理
```
/var/run/qemu/power.state  # on/off状態を保持
```

電源状態はQMPクエリまたはpidファイルで判定：
- QEMUプロセス存在 + running状態 → Power On
- QEMUプロセス存在 + paused状態 → Power On (suspended)
- QEMUプロセス不在 → Power Off

#### 4.6.3 Serial Over LAN (SOL)
- ipmi_simのSOL機能をQEMUのシリアルコンソールに接続
- socatでソケット間をブリッジ
```bash
socat UNIX-CONNECT:/var/run/qemu/console.sock \
      UNIX-LISTEN:/var/run/ipmi/sol.sock
```

### 4.7 ネットワーク設定スクリプト

#### 4.7.1 setup-network.sh の動作
1. eth2以降のインターフェースを検出
2. 各インターフェースに対してmacvtapデバイスを作成
3. QEMUの起動引数を生成
4. ブリッジモードの場合はブリッジを設定

```bash
# macvtapの作成例
ip link add link eth2 name macvtap0 type macvtap mode bridge
ip link set macvtap0 up
```

### 4.8 ヘルスチェック

```bash
#!/bin/bash
# health-check.sh

# 1. supervisordの状態確認
supervisorctl status | grep -q RUNNING || exit 1

# 2. ipmi_simの応答確認
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password mc info || exit 1

# 3. QEMUの状態確認（電源ONの場合のみ）
if [ -f /var/run/qemu/power.state ] && [ "$(cat /var/run/qemu/power.state)" = "on" ]; then
    pgrep -f qemu-system || exit 1
fi

exit 0
```

## 5. containerlabとの統合

### 5.1 トポロジー定義例

```yaml
name: qemu-bmc-lab

topology:
  nodes:
    server1:
      kind: linux
      image: qemu-bmc:latest
      binds:
        - ./disks/server1.qcow2:/vm/disk.qcow2
      env:
        VM_MEMORY: 4096
        VM_CPUS: 4
      ports:
        - 6230:623/udp    # IPMI
        - 5901:5900/tcp   # VNC
      exec:
        - ip addr add 192.168.1.10/24 dev eth1  # IPMI network

    bmc-mgmt:
      kind: linux
      image: alpine:latest

  links:
    - endpoints: ["server1:eth1", "bmc-mgmt:eth0"]  # IPMI network
    - endpoints: ["server1:eth2", "switch1:eth1"]   # VM data network
```

### 5.2 必要な権限

```yaml
# docker-compose.yml または containerlab
services:
  qemu-bmc:
    privileged: true          # KVMアクセスに必要
    devices:
      - /dev/kvm:/dev/kvm     # KVMデバイス
      - /dev/net/tun:/dev/net/tun  # TAPデバイス用
    cap_add:
      - NET_ADMIN             # ネットワーク設定用
      - SYS_ADMIN             # macvtap用
```

## 6. セキュリティ考慮事項

### 6.1 IPMIセキュリティ
- デフォルトパスワードの変更を推奨
- IPMI 2.0のRMCP+暗号化を使用
- IPMIネットワークの分離

### 6.2 コンテナセキュリティ
- privilegedモードが必要（KVMアクセス）
- 本番環境では最小権限での実行を検討
- シークレット管理の外部化

## 7. 制限事項

1. **KVM依存**: ホストでKVMが利用可能である必要がある
2. **ネストされた仮想化**: 一部の環境ではネストされた仮想化が無効
3. **パフォーマンス**: コンテナ内QEMUはベアメタルよりオーバーヘッドあり
4. **IPMI互換性**: 完全なIPMI互換ではなく、基本的な操作のみサポート

## 8. 今後の拡張

1. **Redfish API対応**: 現代的なBMC APIの追加
2. **仮想メディア**: ISOマウントのIPMI経由サポート
3. **センサーシミュレーション**: 温度、電圧などの動的シミュレーション
4. **複数VM対応**: 1コンテナで複数VMの管理
5. **Web UI**: 簡易的な管理画面
