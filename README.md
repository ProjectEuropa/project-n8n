# OpenFang VPS Deployment

OpenFang を Docker Compose + Caddy で VPS に載せるためのリポジトリです。
普段の編集対象はこのリポジトリで、VPS にアップロードする実体は `dist/vps/` にまとめて作る運用を前提にしています。

## 構成

```text
.
├── compose.yml                  # 本番用 Compose
├── .env.example                 # VPS 用の環境変数テンプレート
├── caddy_config/
│   └── Caddyfile
├── openfang_config/
│   ├── Dockerfile
│   ├── config.toml
│   ├── entrypoint.sh
│   ├── fake-gcloud.sh
│   └── gcp-token.py
├── scripts/
│   ├── setup-vps.sh             # VPS 初期セットアップ
│   ├── backup.sh                # openfang_data / workspace / caddy_data のバックアップ
│   ├── restore.sh               # バックアップからの復元
│   └── build-vps-bundle.sh      # dist/vps/ を生成
├── docs/
│   └── VPS_BUNDLE.md            # dist/vps/ に同梱する運用手順
└── workspace/
    └── SOUL.md
```

## 推奨フロー

### 1. ローカルで設定を調整

- `compose.yml`
- `.env.example`
- `caddy_config/Caddyfile`
- `openfang_config/*`
- `OPENFANG_SHA256_AMD64` / `OPENFANG_SHA256_ARM64`

## 2. VPS 用バンドルを生成

```bash
./scripts/build-vps-bundle.sh
```

生成先:

```text
dist/vps/
```

このディレクトリだけを VPS に転送すれば足ります。

## 3. VPS に転送

```bash
rsync -avz dist/vps/ user@your-vps:/opt/openfang/
```

`scp -r dist/vps user@your-vps:/opt/openfang` でも構いません。

## 4. VPS で初期設定と起動

```bash
cd /opt/openfang
cp .env.example .env
./scripts/setup-vps.sh
docker compose up -d --build
```

## サービス構成

- `caddy`
  - 80/443 を公開
  - TLS 終端、Basic 認証、IP 制限を担当
- `openfang`
  - Caddy 配下の内部サービス
  - ホストには直接公開しない
- `watchtower`
  - コンテナ自動更新

## ボリューム

デフォルト名:

- `openfang_data`
- `caddy_data`
- `caddy_config`

必要なら `.env` で次を上書きできます。

- `OPENFANG_DATA_VOLUME`
- `CADDY_DATA_VOLUME`
- `CADDY_CONFIG_VOLUME`

## 運用

バックアップ:

```bash
./scripts/backup.sh
```

リストア:

```bash
./scripts/restore.sh
./scripts/restore.sh 20260408-120000
```

## 注意点

- `.env` や `credentials/` 配下はコミットしません。
- `openfang` は Caddy 経由で使う前提なので、Compose ではホストポートを直接開けていません。
- GCP サービスアカウントキーを同梱する場合は、VPS 上の `credentials/adc.json` に配置してください。
- `OPENFANG_SHA256_AMD64` / `OPENFANG_SHA256_ARM64` を空のままにすると、`openfang` のビルドは失敗します。
