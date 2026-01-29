# GitHub Container Registry 自動プッシュ設計

## 概要

Push 時に自動でコンテナをビルドし、GitHub Container Registry (ghcr.io) にプッシュする。

## 要件

- **トリガー:** タグ作成時のみ（`v*` パターン）
- **タグ形式:** シンプル（タグそのまま）+ `latest`
- **プラットフォーム:** amd64 のみ

## イメージタグ

| トリガー | 生成されるタグ |
|----------|----------------|
| `v1.0.0` タグ | `ghcr.io/tjst-t/docker-qemu-bmc:v1.0.0` + `:latest` |

**方針:** main への push ではビルドしない。タグ = リリースとし、`latest` は最新リリースを指す。

## ワークフロー

**ファイル:** `.github/workflows/build-and-push.yml`

**使用 Actions:**
- `actions/checkout@v4`
- `docker/login-action@v3`
- `docker/metadata-action@v5`
- `docker/build-push-action@v5`

**認証:** `GITHUB_TOKEN`（追加設定不要）

**キャッシュ:** GitHub Actions cache (gha)
