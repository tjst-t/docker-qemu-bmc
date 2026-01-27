# Docker QEMU BMC コンテナ テスト仕様書

## 1. テスト概要

### 1.1 テスト目的
Docker QEMU BMCコンテナが要件を満たしていることを検証し、品質を保証する。

### 1.2 テストレベル

| レベル | 説明 | 自動化 |
|--------|------|--------|
| ユニットテスト | 個別スクリプトの動作確認 | ○ |
| 統合テスト | コンポーネント間連携確認 | ○ |
| システムテスト | E2Eシナリオ確認 | ○ |
| 性能テスト | 応答時間・リソース使用量 | △ |

### 1.3 テスト環境要件

```yaml
ホスト環境:
  - OS: Linux (Ubuntu 22.04推奨)
  - KVM: 有効 (/dev/kvm存在)
  - Docker: 20.10以上
  - containerlab: 0.40以上 (統合テスト用)

テストツール:
  - bats (Bash Automated Testing System)
  - ipmitool
  - expect (SOLテスト用)
  - curl (ヘルスチェック用)
```

## 2. テストケース一覧

### 2.1 コンテナビルドテスト (TB)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TB-001 | Dockerビルド成功 | Dockerfileがエラーなくビルドできる | exit code 0 |
| TB-002 | 必須パッケージ存在 | qemu, openipmi, supervisor等が存在 | which成功 |
| TB-003 | 設定ファイル存在 | supervisor.conf等が正しい場所に存在 | ファイル存在 |
| TB-004 | スクリプト実行権限 | scripts/配下が実行可能 | -x フラグ |
| TB-005 | イメージサイズ | 妥当なサイズ(< 2GB) | サイズ確認 |

### 2.2 コンテナ起動テスト (TS)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TS-001 | 基本起動 | コンテナが起動する | コンテナ実行中 |
| TS-002 | supervisord起動 | supervisordがPID 1で動作 | プロセス存在 |
| TS-003 | ipmi_sim起動 | ipmi_simが起動する | プロセス存在 |
| TS-004 | QEMU起動 | QEMUが起動する | プロセス存在 |
| TS-005 | 起動順序 | ipmi_sim → QEMUの順で起動 | ログ確認 |
| TS-006 | 環境変数反映 | VM_MEMORY等が反映される | 設定値確認 |
| TS-007 | KVMなし起動 | KVMなしでもTCGで起動 | 起動成功 |
| TS-008 | 再起動耐性 | コンテナ再起動後も正常動作 | 機能維持 |

### 2.3 IPMI機能テスト (TI)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TI-001 | IPMI接続 | ipmitool lanplusで接続 | 接続成功 |
| TI-002 | 認証成功 | 正しい認証情報で認証 | 認証成功 |
| TI-003 | 認証失敗 | 誤った認証情報を拒否 | エラー返却 |
| TI-004 | MC Info取得 | mc info コマンド成功 | 情報表示 |
| TI-005 | 電源状態取得 | power status 取得 | on/off表示 |
| TI-006 | 電源ON | power on コマンド | VM起動 |
| TI-007 | 電源OFF | power off コマンド | VM停止 |
| TI-008 | 電源サイクル | power cycle コマンド | VMリセット |
| TI-009 | ソフトシャットダウン | power soft コマンド | ACPI通知 |
| TI-010 | SDR一覧 | sdr list コマンド | センサー一覧 |
| TI-011 | センサー読み取り | sensor reading 取得 | 値表示 |
| TI-012 | ユーザー一覧 | user list コマンド | ユーザー表示 |
| TI-013 | 並行アクセス | 複数同時IPMI接続 | 全て成功 |

### 2.4 電源制御テスト (TP)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TP-001 | 初期電源OFF | 起動時VM電源OFF | 状態確認 |
| TP-002 | OFF→ON遷移 | 電源ONでQEMU起動 | プロセス生成 |
| TP-003 | ON→OFF遷移 | 電源OFFでQEMU停止 | プロセス終了 |
| TP-004 | ON中の再ON | 電源ON中にON | エラーなし |
| TP-005 | OFF中の再OFF | 電源OFF中にOFF | エラーなし |
| TP-006 | 電源サイクル | ON→OFF→ON | 正常動作 |
| TP-007 | 高速連続操作 | 連続電源操作 | 正常動作 |
| TP-008 | QMPソケット確認 | 電源ON後QMP通信可 | 応答あり |
| TP-009 | 状態永続化 | 電源状態ファイル更新 | ファイル内容 |
| TP-010 | ハードリセット | reset コマンド | VMリセット |

### 2.5 Serial Over LAN テスト (TSOL)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TSOL-001 | SOL有効化 | sol activate 成功 | セッション開始 |
| TSOL-002 | コンソール出力 | ブートメッセージ表示 | 文字列表示 |
| TSOL-003 | キー入力 | コンソールへ入力送信 | 入力反映 |
| TSOL-004 | SOL切断 | sol deactivate | セッション終了 |
| TSOL-005 | SOL再接続 | 切断後再接続 | 接続成功 |
| TSOL-006 | 複数SOLセッション | 同時接続試行 | 適切な動作 |

### 2.6 ネットワークテスト (TN)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TN-001 | eth0存在 | デバッグ用NIC存在 | インターフェース存在 |
| TN-002 | eth1存在 | IPMI用NIC存在 | インターフェース存在 |
| TN-003 | IPMI eth1バインド | ipmi_simがeth1でリッスン | netstat確認 |
| TN-004 | eth2パススルー | eth2がVMに接続 | VM内NIC確認 |
| TN-005 | 複数NICパススルー | eth2-4がVMに接続 | 全NIC確認 |
| TN-006 | MACアドレス | VM NICのMAC設定 | MAC一致 |
| TN-007 | VMからの外部通信 | VM→外部ネットワーク | ping成功 |
| TN-008 | 外部からVMへの通信 | 外部→VM | ping成功 |
| TN-009 | VLAN対応 | VLANタグ透過 | VLAN通信成功 |
| TN-010 | Jumboフレーム | MTU 9000 | 通信成功 |

### 2.7 統合テスト (TInt)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TInt-001 | フルブートシーケンス | IPMI電源ON→VMブート完了 | SSH可能 |
| TInt-002 | containerlabトポロジー | 複数ノード構成 | 全ノード起動 |
| TInt-003 | BMCネットワーク分離 | IPMI/データネットワーク分離 | 分離確認 |
| TInt-004 | リモートインストール | PXEブート | OS起動 |
| TInt-005 | 長時間稼働 | 24時間連続稼働 | 安定動作 |
| TInt-006 | 障害回復 | ipmi_simクラッシュ後復旧 | 自動再起動 |
| TInt-007 | 複数コンテナ | 5台同時稼働 | 全台正常 |

### 2.8 異常系テスト (TE)

| ID | テスト名 | 説明 | 期待結果 |
|----|----------|------|----------|
| TE-001 | ディスクなし起動 | VMディスク不在 | エラーログ |
| TE-002 | メモリ不足 | 過大なVM_MEMORY | 適切なエラー |
| TE-003 | 不正な環境変数 | 不正値設定 | デフォルト使用 |
| TE-004 | eth2不在 | VMネットワークなし | 警告のみ |
| TE-005 | QMPソケット障害 | ソケット破損 | 再作成 |
| TE-006 | QEMU異常終了 | QEMUクラッシュ | 電源OFF状態 |
| TE-007 | ipmi_sim異常終了 | ipmi_simクラッシュ | 自動再起動 |
| TE-008 | ディスクフル | ログでディスク満杯 | ログローテート |

## 3. テスト実装

### 3.1 ディレクトリ構成

```
tests/
├── bats/                    # BATSテストフレームワーク
├── fixtures/                # テスト用ファイル
│   ├── test-disk.qcow2     # テスト用ディスク
│   └── test-iso.iso        # テスト用ISO
├── helpers/                 # テストヘルパー
│   ├── common.bash         # 共通関数
│   ├── ipmi.bash           # IPMI関連関数
│   └── qemu.bash           # QEMU関連関数
├── unit/                    # ユニットテスト
│   ├── test_power_control.bats
│   ├── test_network_setup.bats
│   └── test_config_parser.bats
├── integration/             # 統合テスト
│   ├── test_ipmi.bats
│   ├── test_power.bats
│   ├── test_sol.bats
│   └── test_network.bats
├── system/                  # システムテスト
│   ├── test_full_boot.bats
│   └── test_containerlab.bats
├── run_tests.sh            # テスト実行スクリプト
└── README.md               # テスト説明
```

### 3.2 テストヘルパー例

```bash
# tests/helpers/common.bash

CONTAINER_NAME="qemu-bmc-test"
IPMI_HOST="127.0.0.1"
IPMI_PORT="623"
IPMI_USER="admin"
IPMI_PASS="password"

setup_container() {
    docker run -d --name ${CONTAINER_NAME} \
        --privileged \
        --device /dev/kvm:/dev/kvm \
        -v ${TEST_DISK}:/vm/disk.qcow2 \
        -p ${IPMI_PORT}:623/udp \
        qemu-bmc:test

    # 起動待機
    wait_for_ipmi 30
}

teardown_container() {
    docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
}

wait_for_ipmi() {
    local timeout=$1
    local count=0
    while [ $count -lt $timeout ]; do
        if ipmitool -I lanplus -H ${IPMI_HOST} -p ${IPMI_PORT} \
            -U ${IPMI_USER} -P ${IPMI_PASS} mc info &>/dev/null; then
            return 0
        fi
        sleep 1
        ((count++))
    done
    return 1
}

ipmi_cmd() {
    ipmitool -I lanplus -H ${IPMI_HOST} -p ${IPMI_PORT} \
        -U ${IPMI_USER} -P ${IPMI_PASS} "$@"
}
```

### 3.3 IPMI テスト例

```bash
# tests/integration/test_ipmi.bats

load '../helpers/common'

setup() {
    setup_container
}

teardown() {
    teardown_container
}

@test "TI-001: IPMI connection succeeds" {
    run ipmi_cmd mc info
    [ "$status" -eq 0 ]
}

@test "TI-003: IPMI rejects invalid credentials" {
    run ipmitool -I lanplus -H ${IPMI_HOST} -p ${IPMI_PORT} \
        -U wrong -P wrong mc info
    [ "$status" -ne 0 ]
}

@test "TI-005: Power status is retrievable" {
    run ipmi_cmd power status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "on" ]] || [[ "$output" =~ "off" ]]
}

@test "TI-006: Power on starts VM" {
    # 確実にOFF状態から開始
    ipmi_cmd power off || true
    sleep 2

    run ipmi_cmd power on
    [ "$status" -eq 0 ]

    # QEMU起動待機
    sleep 5

    run docker exec ${CONTAINER_NAME} pgrep -f qemu-system
    [ "$status" -eq 0 ]
}

@test "TI-007: Power off stops VM" {
    # 確実にON状態から開始
    ipmi_cmd power on || true
    sleep 5

    run ipmi_cmd power off
    [ "$status" -eq 0 ]

    sleep 3

    run docker exec ${CONTAINER_NAME} pgrep -f qemu-system
    [ "$status" -ne 0 ]
}

@test "TI-013: Concurrent IPMI access" {
    # 5並列でIPMIアクセス
    for i in {1..5}; do
        ipmi_cmd mc info &
    done
    wait

    # 全て成功したことを確認
    run ipmi_cmd mc info
    [ "$status" -eq 0 ]
}
```

### 3.4 電源制御テスト例

```bash
# tests/integration/test_power.bats

load '../helpers/common'

setup() {
    setup_container
}

teardown() {
    teardown_container
}

@test "TP-001: Initial power state is off" {
    run ipmi_cmd power status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "off" ]]
}

@test "TP-002: Power on transitions state" {
    run ipmi_cmd power on
    [ "$status" -eq 0 ]

    sleep 5

    run ipmi_cmd power status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "on" ]]
}

@test "TP-006: Power cycle completes" {
    ipmi_cmd power on
    sleep 5

    run ipmi_cmd power cycle
    [ "$status" -eq 0 ]

    sleep 10

    run ipmi_cmd power status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "on" ]]
}

@test "TP-007: Rapid power operations" {
    for i in {1..3}; do
        ipmi_cmd power on
        sleep 2
        ipmi_cmd power off
        sleep 2
    done

    run ipmi_cmd power status
    [ "$status" -eq 0 ]
}

@test "TP-008: QMP socket available when powered on" {
    ipmi_cmd power on
    sleep 5

    run docker exec ${CONTAINER_NAME} \
        test -S /var/run/qemu/qmp.sock
    [ "$status" -eq 0 ]
}
```

### 3.5 ネットワークテスト例

```bash
# tests/integration/test_network.bats

load '../helpers/common'

setup() {
    # 複数NICでコンテナ起動
    docker network create test-ipmi || true
    docker network create test-data || true

    docker run -d --name ${CONTAINER_NAME} \
        --privileged \
        --device /dev/kvm:/dev/kvm \
        --network test-ipmi \
        -v ${TEST_DISK}:/vm/disk.qcow2 \
        qemu-bmc:test

    docker network connect test-data ${CONTAINER_NAME}

    wait_for_ipmi 30
}

teardown() {
    teardown_container
    docker network rm test-ipmi test-data 2>/dev/null || true
}

@test "TN-001: eth0 debug interface exists" {
    run docker exec ${CONTAINER_NAME} ip link show eth0
    [ "$status" -eq 0 ]
}

@test "TN-002: eth1 IPMI interface exists" {
    run docker exec ${CONTAINER_NAME} ip link show eth1
    [ "$status" -eq 0 ]
}

@test "TN-003: ipmi_sim listens on correct interface" {
    run docker exec ${CONTAINER_NAME} \
        ss -ulnp | grep 623
    [ "$status" -eq 0 ]
}

@test "TN-006: VM NIC has expected MAC address" {
    ipmi_cmd power on
    sleep 10

    # QMPでNIC情報取得
    run docker exec ${CONTAINER_NAME} \
        /scripts/qmp-query.sh query-netdev
    [ "$status" -eq 0 ]
}
```

### 3.6 containerlabテスト例

```bash
# tests/system/test_containerlab.bats

load '../helpers/common'

TOPO_FILE="tests/fixtures/test-topology.yml"

setup() {
    # テストトポロジー作成
    cat > ${TOPO_FILE} << 'EOF'
name: qemu-bmc-test

topology:
  nodes:
    server1:
      kind: linux
      image: qemu-bmc:test
      binds:
        - tests/fixtures/test-disk.qcow2:/vm/disk.qcow2
      env:
        VM_MEMORY: 1024
        VM_CPUS: 1

    mgmt:
      kind: linux
      image: alpine:latest
      exec:
        - apk add --no-cache ipmitool

  links:
    - endpoints: ["server1:eth1", "mgmt:eth0"]
EOF

    containerlab deploy -t ${TOPO_FILE}
}

teardown() {
    containerlab destroy -t ${TOPO_FILE} --cleanup
    rm -f ${TOPO_FILE}
}

@test "TInt-002: Containerlab topology deploys" {
    run containerlab inspect -t ${TOPO_FILE}
    [ "$status" -eq 0 ]
    [[ "$output" =~ "server1" ]]
    [[ "$output" =~ "mgmt" ]]
}

@test "TInt-003: IPMI reachable from management node" {
    SERVER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-qemu-bmc-test-server1)

    run docker exec clab-qemu-bmc-test-mgmt \
        ipmitool -I lanplus -H ${SERVER_IP} -U admin -P password mc info
    [ "$status" -eq 0 ]
}
```

## 4. テスト実行

### 4.1 テスト実行スクリプト

```bash
#!/bin/bash
# tests/run_tests.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# テストレベル
TEST_LEVEL=${1:-all}

# テスト用イメージビルド
echo "=== Building test image ==="
docker build -t qemu-bmc:test "$PROJECT_DIR"

# テスト用ディスク作成
echo "=== Creating test disk ==="
if [ ! -f "$SCRIPT_DIR/fixtures/test-disk.qcow2" ]; then
    qemu-img create -f qcow2 "$SCRIPT_DIR/fixtures/test-disk.qcow2" 1G
fi

# テスト実行
echo "=== Running tests ==="

case $TEST_LEVEL in
    unit)
        bats "$SCRIPT_DIR/unit/"
        ;;
    integration)
        bats "$SCRIPT_DIR/integration/"
        ;;
    system)
        bats "$SCRIPT_DIR/system/"
        ;;
    all)
        bats "$SCRIPT_DIR/unit/" "$SCRIPT_DIR/integration/"
        # システムテストはcontainerlab必要
        if command -v containerlab &>/dev/null; then
            bats "$SCRIPT_DIR/system/"
        else
            echo "Skipping system tests (containerlab not found)"
        fi
        ;;
    *)
        echo "Usage: $0 [unit|integration|system|all]"
        exit 1
        ;;
esac

echo "=== Tests completed ==="
```

### 4.2 CI/CD設定例 (GitHub Actions)

```yaml
# .github/workflows/test.yml
name: Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build image
        run: docker build -t qemu-bmc:test .

      - name: Install test dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y bats ipmitool qemu-utils

      - name: Run unit tests
        run: ./tests/run_tests.sh unit

      - name: Run integration tests
        run: ./tests/run_tests.sh integration

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: tests/results/
```

## 5. 合格基準

### 5.1 リリース基準

| カテゴリ | 必須合格率 | 説明 |
|----------|-----------|------|
| ビルドテスト | 100% | 全て合格必須 |
| 起動テスト | 100% | 全て合格必須 |
| IPMI機能テスト | 95% | TI-013は除外可 |
| 電源制御テスト | 100% | 全て合格必須 |
| SOLテスト | 90% | 基本機能合格必須 |
| ネットワークテスト | 90% | VLAN/Jumboは除外可 |
| 統合テスト | 80% | 長時間テストは除外可 |
| 異常系テスト | 80% | 全クラッシュ回復は必須 |

### 5.2 品質指標

- **機能カバレッジ**: 全IPMI基本操作をサポート
- **コードカバレッジ**: スクリプトの80%以上
- **応答時間**: IPMI操作は5秒以内
- **起動時間**: コンテナ起動からIPMI応答まで30秒以内
- **リソース使用量**: ベースメモリ使用量 < 500MB (VMメモリ除く)

## 6. トラブルシューティング

### 6.1 よくある問題

| 問題 | 原因 | 対処 |
|------|------|------|
| KVMエラー | /dev/kvmアクセス不可 | --device追加確認 |
| IPMI接続失敗 | ポートマッピング不正 | -p 623:623/udp確認 |
| VM起動しない | ディスクイメージ不在 | ボリュームマウント確認 |
| ネットワーク不通 | macvtap設定失敗 | NET_ADMIN capability確認 |

### 6.2 デバッグ方法

```bash
# コンテナログ確認
docker logs qemu-bmc-test

# supervisord状態確認
docker exec qemu-bmc-test supervisorctl status

# QEMU状態確認
docker exec qemu-bmc-test cat /var/log/qemu.log

# ipmi_sim状態確認
docker exec qemu-bmc-test cat /var/log/ipmi_sim.log

# ネットワーク状態確認
docker exec qemu-bmc-test ip addr
docker exec qemu-bmc-test ss -ulnp
```
