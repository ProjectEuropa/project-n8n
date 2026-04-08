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
├── .env.example
├── caddy_config/
├── openfang_config/
├── scripts/
├── credentials/
└── workspace/
```
