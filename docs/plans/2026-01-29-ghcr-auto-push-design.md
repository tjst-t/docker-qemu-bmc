# GitHub Container Registry 自動プッシュ設計

## 概要

Push 時に自動でコンテナをビルドし、GitHub Container Registry (ghcr.io) にプッシュする。

## 要件

- **トリガー:** main ブランチへの push + タグ作成時
- **タグ形式:** シンプル（タグそのまま）
- **プラットフォーム:** amd64 のみ

## イメージタグ

| トリガー | 生成されるタグ |
|----------|----------------|
| main への push | `ghcr.io/tjst-t/docker-qemu-bmc:latest` |
| `v1.0.0` タグ | `ghcr.io/tjst-t/docker-qemu-bmc:v1.0.0` |

## ワークフロー

**ファイル:** `.github/workflows/build-and-push.yml`

**使用 Actions:**
- `actions/checkout@v4`
- `docker/login-action@v3`
- `docker/metadata-action@v5`
- `docker/build-push-action@v5`

**認証:** `GITHUB_TOKEN`（追加設定不要）

**キャッシュ:** GitHub Actions cache (gha)
