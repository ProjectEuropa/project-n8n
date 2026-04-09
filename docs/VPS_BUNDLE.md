# OpenFang VPS Bundle

このディレクトリは VPS 配置用の最小構成です。

## 初回セットアップ

```bash
cp .env.example .env
./scripts/setup-vps.sh
docker compose up -d --build
```

## 必須確認

- DNS が VPS を向いていること
- 80/443 が開いていること
- `credentials/adc.json` または `.env` で指定した GCP 認証ファイルが存在すること
- `.env` に対象アーキテクチャの `OPENFANG_SHA256_*` が設定されていること

## patched UI を使う場合

`vertex-ai` を UI の provider セレクトに出したい場合は、`.env` で source build 用の source ref を指定し、override Compose を重ねます。

```env
OPENFANG_SOURCE_REPO=https://github.com/RightNow-AI/openfang
OPENFANG_SOURCE_REF=v0.5.6
OPENFANG_SOURCE_COMMIT=<pinned-full-commit-sha>
```

build は override Compose を重ねて実行します。

```bash
docker compose -f compose.yml -f compose.source-build.yml up -d --build openfang
```

UI 上書きファイルは `openfang_config/upstream-overrides/` から source tree に反映します。
`openfang_config/upstream-src/` に source を vendor しておくと、local 検証では `git clone` を省けます。

注意:

- source build は通常より重いです
- `OPENFANG_SOURCE_COMMIT` を設定すると、source ref が想定コミットかを build 時に検証できます
- local で回すなら `./scripts/vendor-openfang-source.sh` を先に実行した方が速いです
- 小さい VPS では build が厳しい場合があります

## 日常運用

ログ確認:

```bash
docker compose logs -f
```

バックアップ:

```bash
./scripts/backup.sh
```

復元:

```bash
./scripts/restore.sh
```

## ファイル配置

```text
.
├── compose.yml
├── compose.source-build.yml
├── .env.example
├── caddy_config/
├── openfang_config/
├── scripts/
├── credentials/
└── workspace/
```
