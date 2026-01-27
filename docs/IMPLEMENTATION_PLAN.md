# 実装計画 - ステップバイステップアプローチ

## 概要

一気通貫ではなく、各フェーズで動作確認を行いながら段階的に実装を進める。
問題が発生した場合に切り分けを容易にし、確実に動作する基盤の上に機能を追加していく。

## フェーズ一覧

| Phase | 名称 | 目標 | 動作確認 |
|-------|------|------|----------|
| 1 | 基盤コンテナ | QEMUが単体で動作 | VNC接続でVM起動確認 |
| 2 | プロセス管理 | supervisordでQEMU管理 | supervisorctl status |
| 3 | IPMI基盤 | ipmi_simが起動・応答 | ipmitool mc info |
| 4 | 電源制御 | IPMIでVM電源操作 | ipmitool power on/off |
| 5 | ネットワーク | eth2+をVMにパススルー | VM内からping |
| 6 | SOL実装 | シリアルコンソール接続 | ipmitool sol activate |
| 7 | 統合・調整 | containerlab対応 | 完全なシナリオ動作 |

---

## Phase 1: 基盤コンテナ (QEMU単体動作)

### 目標
Docker内でQEMU/KVMが起動し、VNCでアクセスできることを確認する。

### 成果物
- `Dockerfile.phase1`
- `scripts/start-qemu.sh`
- `configs/qemu/default.conf`

### 実装内容
1. ベースDockerfile作成（Ubuntu 22.04 + QEMU）
2. 最小限のQEMU起動スクリプト
3. テスト用の小さなディスクイメージ作成
4. VNCポート公開

### 動作確認
```bash
# ビルド
docker build -f Dockerfile.phase1 -t qemu-bmc:phase1 .

# 起動
docker run --rm -it --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  qemu-bmc:phase1

# VNC接続（別ターミナル）
vncviewer localhost:5900
```

### 合格基準
- [ ] コンテナがビルドできる
- [ ] コンテナが起動する
- [ ] QEMUプロセスが動作している
- [ ] VNCで接続できる（BIOS画面等が見える）

---

## Phase 2: プロセス管理 (supervisord導入)

### 目標
supervisordでQEMUプロセスを管理し、状態監視できるようにする。

### 成果物
- `Dockerfile.phase2`（Phase1を拡張）
- `configs/supervisord.conf`
- `scripts/entrypoint.sh`

### 実装内容
1. supervisordパッケージ追加
2. supervisord設定ファイル作成
3. エントリーポイントスクリプト作成
4. ログ出力設定

### 動作確認
```bash
# ビルド・起動
docker build -f Dockerfile.phase2 -t qemu-bmc:phase2 .
docker run --rm -it --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  qemu-bmc:phase2

# 状態確認（別ターミナル）
docker exec <container> supervisorctl status
```

### 合格基準
- [ ] supervisordがPID 1で動作
- [ ] `supervisorctl status`でqemuがRUNNING
- [ ] ログが適切に出力されている
- [ ] VNC接続が引き続き動作

---

## Phase 3: IPMI基盤 (ipmi_sim導入)

### 目標
ipmi_simが起動し、ipmitoolで基本的な通信ができることを確認する。

### 成果物
- `Dockerfile.phase3`
- `scripts/start-ipmi.sh`
- `configs/ipmi_sim/lan.conf`
- `configs/ipmi_sim/ipmisim.emu`

### 実装内容
1. openipmiパッケージ追加
2. ipmi_sim設定ファイル作成
3. supervisordにipmi_simを追加
4. 基本的なIPMI応答の設定

### 動作確認
```bash
# ビルド・起動
docker build -f Dockerfile.phase3 -t qemu-bmc:phase3 .
docker run --rm -it --privileged \
  --device /dev/kvm:/dev/kvm \
  -p 5900:5900 \
  -p 623:623/udp \
  qemu-bmc:phase3

# IPMI接続テスト（別ターミナル）
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password mc info
```

### 合格基準
- [ ] ipmi_simプロセスが動作
- [ ] UDP 623でリッスン
- [ ] `mc info`が応答を返す
- [ ] 認証が機能する（正しい/誤った認証情報）

---

## Phase 4: 電源制御

### 目標
IPMIの電源コマンドでQEMU VMを制御できるようにする。

### 成果物
- `scripts/power-control.sh`
- `configs/ipmi_sim/ipmisim.emu`（更新）
- QMPソケット設定

### 実装内容
1. QEMUにQMPソケットを追加
2. 電源制御スクリプト作成（QMP経由）
3. ipmi_simのコマンドハンドラ設定
4. 電源状態管理

### 動作確認
```bash
# コンテナ起動後
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power status
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power off
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power on
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password power cycle
```

### 合格基準
- [ ] `power status`が正しい状態を返す
- [ ] `power off`でQEMUが停止
- [ ] `power on`でQEMUが起動
- [ ] `power cycle`でQEMUが再起動
- [ ] 状態遷移が一貫している

---

## Phase 5: ネットワーク設定

### 目標
eth2以降のインターフェースをVMにパススルーする。

### 成果物
- `scripts/setup-network.sh`
- `scripts/start-qemu.sh`（更新）

### 実装内容
1. コンテナ起動時のNIC検出
2. macvtapデバイス作成
3. QEMU起動引数の動的生成
4. MACアドレス管理

### 動作確認
```bash
# 複数ネットワークでコンテナ起動
docker network create test-net
docker run --rm -it --privileged \
  --device /dev/kvm:/dev/kvm \
  --network bridge \
  -p 5900:5900 -p 623:623/udp \
  qemu-bmc:phase5

docker network connect test-net <container>

# VM内でNIC確認（VNC経由）
```

### 合格基準
- [ ] eth2がVMに接続される
- [ ] 複数NICが正しくマッピング
- [ ] VM内からネットワーク通信可能

---

## Phase 6: Serial Over LAN (SOL)

### 目標
IPMIのSOL機能でVMのシリアルコンソールにアクセスする。

### 成果物
- `scripts/start-qemu.sh`（更新：シリアル設定）
- `configs/ipmi_sim/lan.conf`（更新：SOL設定）
- `scripts/sol-bridge.sh`

### 実装内容
1. QEMUシリアルコンソールソケット設定
2. ipmi_simのSOL設定
3. ソケットブリッジ（必要に応じて）

### 動作確認
```bash
# SOL接続
ipmitool -I lanplus -H 127.0.0.1 -U admin -P password sol activate

# コンソール出力確認、入力テスト
# ~. で切断
```

### 合格基準
- [ ] `sol activate`で接続できる
- [ ] VMのコンソール出力が見える
- [ ] キー入力がVMに送信される
- [ ] `sol deactivate`で切断できる

---

## Phase 7: 統合・調整

### 目標
全機能を統合し、containerlab対応を完了する。

### 成果物
- `Dockerfile`（最終版）
- `docker-compose.yml`
- `containerlab/example.yml`
- テストスクリプト一式

### 実装内容
1. 全Dockerfileの統合
2. 設定の最終調整
3. ドキュメント整備
4. containerlabトポロジー例作成

### 動作確認
```bash
# containerlab でデプロイ
containerlab deploy -t containerlab/example.yml

# 全機能テスト
./tests/run_tests.sh all
```

### 合格基準
- [ ] containerlabでデプロイできる
- [ ] 複数ノード構成が動作
- [ ] 全テストケースが合格
- [ ] ドキュメントが完備

---

## 進捗トラッキング

| Phase | 状態 | 開始日 | 完了日 | 備考 |
|-------|------|--------|--------|------|
| 1 | 未着手 | - | - | |
| 2 | 未着手 | - | - | |
| 3 | 未着手 | - | - | |
| 4 | 未着手 | - | - | |
| 5 | 未着手 | - | - | |
| 6 | 未着手 | - | - | |
| 7 | 未着手 | - | - | |

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| KVMが使えない環境 | Phase1でブロック | TCGフォールバック実装 |
| ipmi_simの設定複雑 | Phase3-4で遅延 | 最小構成から段階的に |
| macvtapの権限問題 | Phase5でブロック | bridge方式も検討 |
| SOLの互換性問題 | Phase6で遅延 | socat経由の代替案 |
