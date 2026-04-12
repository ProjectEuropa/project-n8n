# OpenFang VPS Deployment

OpenFang を Docker Compose + Caddy で VPS に載せるためのリポジトリです。
普段の編集対象はこのリポジトリで、VPS にアップロードする実体は `dist/vps/` にまとめて作る運用を前提にしています。

## 構成

```text
.
├── compose.yml                  # 本番用 Compose
├── compose.source-build.yml     # OpenFang を source build に切り替える上書き Compose
├── .env.example                 # VPS 用の環境変数テンプレート
├── caddy_config/
│   └── Caddyfile
├── openfang_config/
│   ├── Dockerfile
│   ├── Dockerfile.patched
│   ├── config.toml
│   ├── entrypoint.sh
│   ├── fake-gcloud.sh
│   ├── gcp-token.py
│   └── upstream-overrides/
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

## RTK の安全な試用

RTK は global hook としては使わず、PR レビュー前に巨大 diff をざっと読む補助だけに限定します。この repo では [`scripts/rtk-safe.sh`](scripts/rtk-safe.sh#L1) 経由で実行してください。

```bash
./scripts/rtk-safe.sh git diff
./scripts/rtk-safe.sh git diff main...HEAD
./scripts/rtk-safe.sh git status
```

この wrapper は `RTK_TELEMETRY_DISABLED=1` と `RTK_TEE=0` を強制し、`rtk init -g`、Claude Code global hook、`aws`、`gh`、`curl`、`wget`、`docker`、`kubectl`、`.env`、`credentials`、secret/token/password を含む引数、CI での実行を拒否します。許可コマンドは `git diff/status/log/show` と `cargo test` だけです。

### 1. ローカルで設定を調整

- `compose.yml`
- `.env.example`
- `caddy_config/Caddyfile`
- `openfang_config/*`
- `OPENFANG_SHA256_AMD64` / `OPENFANG_SHA256_ARM64`

patched UI build が必要なときだけ:

- `compose.source-build.yml`
- `OPENFANG_SOURCE_REPO`
- `OPENFANG_SOURCE_REF`

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

## OpenFang UI Patch

OpenFang upstream の `/api/providers` に `vertex-ai` が出ないため、UI の provider セレクトには既定 provider が載らないことがあります。

この repo では通常どおり GitHub Releases のバイナリを使いながら、必要なときだけ [`openfang_config/Dockerfile.patched`](openfang_config/Dockerfile.patched#L1) で source build に切り替えられるようにしています。UI 上書きファイルは [`openfang_config/upstream-overrides/crates/openfang-api/static/js/app.js`](openfang_config/upstream-overrides/crates/openfang-api/static/js/app.js#L1) などに置いてあります。

使い方:

```bash
cp .env.example .env
```

`.env` で以下を設定します。

```env
OPENFANG_SOURCE_REPO=https://github.com/RightNow-AI/openfang
OPENFANG_SOURCE_REF=v0.5.6
OPENFANG_SOURCE_COMMIT=<pinned-full-commit-sha>
```

その後に override Compose を重ねて build します。

```bash
docker compose -f compose.yml -f compose.source-build.yml up -d --build openfang
```

ローカルで UI だけ素早く確認したいときは、debug build 用 override を使えます。

```bash
./scripts/vendor-openfang-source.sh
docker compose -f compose.yml -f compose.source-build.yml -f compose.local-fast.yml -f compose.local-ui.yml up -d --build openfang
```

`openfang_config/upstream-src/` に vendored source がある場合、`Dockerfile.patched` は `git clone` をスキップしてそちらを使います。ローカルで UI を詰めるときはこの経路の方が速いです。

注意:

- `Dockerfile.patched` は Rust source build なので、通常ビルドよりかなり重いです
- `./scripts/vendor-openfang-source.sh` を先に実行すると、毎回の remote clone を避けられます
- `OPENFANG_SOURCE_COMMIT` を設定すると、source ref が想定コミットかを build 時に検証できます
- `compose.local-fast.yml` は local 確認専用です。debug build なので本番用には使いません
- 小さい VPS で直接 build すると時間やメモリが厳しい可能性があります
- デフォルト運用は引き続き [`openfang_config/Dockerfile`](openfang_config/Dockerfile#L1) のままです
- API key 認証モードでは、upstream UI の都合でキーを `localStorage` に保持します。XSS が成立すると読み取られるので、使えるなら session/httpOnly Cookie ベースの認証を優先してください

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
