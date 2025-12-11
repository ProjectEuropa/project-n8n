# n8n VPS セットアップ (Docker + Caddy)

n8nをVPS上でDocker + Caddyを使用して動作させるための設定ファイルです。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│                        VPS                              │
│  ┌───────────────────────────────────────────────────┐  │
│  │                 Docker Network                    │  │
│  │                                                   │  │
│  │   ┌─────────┐      ┌─────────────────────────┐   │  │
│  │   │  Caddy  │      │          n8n            │   │  │
│  │   │  :80    │ ───▶ │         :5678           │   │  │
│  │   │  :443   │      │   (内部ポートのみ)       │   │  │
│  │   └─────────┘      └─────────────────────────┘   │  │
│  │        │                      │                  │  │
│  │        ▼                      ▼                  │  │
│  │   caddy_data             n8n_data               │  │
│  │   (SSL証明書)          (ワークフロー)            │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         ▲
         │ HTTPS (自動SSL)
         │
    ユーザー
```

## 推奨スペック

| 用途 | CPU | メモリ | ストレージ |
|------|-----|--------|------------|
| 最小 | 1 vCPU | 2 GB | 20 GB |
| 推奨 | 2 vCPU | 4 GB | 40 GB |
| 大規模 | 4 vCPU | 8 GB | 100 GB |

## ファイル構成

```
.
├── compose.yml           # Docker Compose設定
├── .env.example          # 環境変数テンプレート
├── .env                  # 環境変数（要作成）
├── caddy_config/
│   └── Caddyfile         # Caddyリバースプロキシ設定
└── local_files/          # n8nファイル保存用
```

## 前提条件

- VPS（Ubuntu 22.04/24.04 推奨）
- Docker および Docker Compose がインストール済み
- ドメイン名（サブドメインのDNS設定済み）
- 80/443 ポートが開放されていること

## セットアップ手順

### 1. VPSにDockerをインストール

```bash
# Docker公式インストールスクリプト
curl -fsSL https://get.docker.com | sh

# 現在のユーザーをdockerグループに追加
sudo usermod -aG docker $USER

# グループへの追加を反映させるため、ここで一度サーバーからログアウトし、再ログインしてください。
```

### 2. このリポジトリをクローン

```bash
git clone <repository-url> /root/n8n-docker-caddy
cd /root/n8n-docker-caddy
```

### 3. 環境変数を設定

```bash
cp .env.example .env
nano .env
```

以下の値を自分の環境に合わせて編集：

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `DATA_FOLDER` | 設定ファイルのパス | `/root/n8n-docker-caddy` |
| `DOMAIN_NAME` | メインドメイン | `example.com` |
| `SUBDOMAIN` | サブドメイン | `n8n` |
| `GENERIC_TIMEZONE` | タイムゾーン | `Asia/Tokyo` |
| `SSL_EMAIL` | SSL証明書通知用メール | `your@email.com` |

### 4. DNSレコードを設定

DNS管理画面で、サブドメインをVPSのIPアドレスに向ける：

```
タイプ: A
名前: n8n
値: VPSのIPアドレス
TTL: 3600（または自動）
```

設定後、反映を確認：
```bash
dig n8n.example.com +short
```

### 5. ファイアウォールを設定

```bash
# UFWを使用している場合
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# (注意) ufwを有効にすると、許可されていないポートはすべてブロックされます。
# SSH接続が切断されないよう、事前に 'sudo ufw allow <ssh_port>/tcp' を実行していることを確認してください。
sudo ufw enable
sudo ufw status
```

### 6. Dockerボリュームを作成

```bash
docker volume create caddy_data
docker volume create n8n_data
```

### 7. n8nを起動

```bash
docker compose up -d
```

### 8. 動作確認

```bash
# コンテナの状態を確認（両方 healthy になるまで待つ）
docker compose ps

# ログを確認
docker compose logs -f
```

ブラウザで `https://n8n.example.com` にアクセス

初回アクセス時にアカウント作成画面が表示されます。

## 管理コマンド

```bash
# ログを確認
docker compose logs -f

# 特定サービスのログ
docker compose logs -f n8n
docker compose logs -f caddy

# n8nを再起動
docker compose restart n8n

# 全サービス再起動
docker compose restart

# 停止
docker compose down

# ヘルスチェック状態を確認
docker compose ps

# リソース使用状況
docker stats

# n8nシェルに入る
docker compose exec n8n sh

# 更新
docker compose pull && docker compose up -d
```

## バックアップ

### 手動バックアップ

**注意**: データの整合性を保つため、バックアップ前にn8nを停止することを推奨します。

```bash
# バックアップディレクトリを作成
mkdir -p $HOME/n8n-backups

# n8nを停止（データ整合性のため推奨）
docker compose stop n8n

# n8nデータをバックアップ
docker run --rm -v n8n_data:/data -v $HOME/n8n-backups:/backup alpine \
  tar czf /backup/n8n-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

# Caddyデータをバックアップ（SSL証明書含む）
docker run --rm -v caddy_data:/data -v $HOME/n8n-backups:/backup alpine \
  tar czf /backup/caddy-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

# n8nを再開
docker compose start n8n
```

### 自動バックアップ（cron）

```bash
# バックアップスクリプトを作成
cat << 'EOF' > $HOME/n8n-backup.sh
#!/bin/bash
# --------------------------------------------------
# !! 注意 !!
# ご自身の環境に合わせて、以下の N8N_DIR の値を変更してください。
# 例: N8N_DIR=/home/ubuntu/n8n-docker-caddy
# --------------------------------------------------
BACKUP_DIR=$HOME/n8n-backups
N8N_DIR=/root/n8n-docker-caddy
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR

echo "Stopping n8n service for backup..."
cd $N8N_DIR && docker compose stop n8n || exit 1

# n8nデータ
docker run --rm -v n8n_data:/data -v $BACKUP_DIR:/backup alpine \
  tar czf /backup/n8n-data-$DATE.tar.gz -C /data .

# Caddyデータ
docker run --rm -v caddy_data:/data -v $BACKUP_DIR:/backup alpine \
  tar czf /backup/caddy-data-$DATE.tar.gz -C /data .

echo "Starting n8n service..."
cd $N8N_DIR && docker compose start n8n || exit 1

# 7日以上古いバックアップを削除
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

chmod +x $HOME/n8n-backup.sh

# cronに登録（毎日3時に実行）
(crontab -l 2>/dev/null; echo "0 3 * * * $HOME/n8n-backup.sh >> $HOME/n8n-backup.log 2>&1") | crontab -
```

### バックアップからの復元

```bash
# n8nを停止
docker compose down

# 既存ボリュームを削除して再作成（確実な復元のため）
docker volume rm n8n_data
docker volume create n8n_data

# n8nデータを復元（ファイル名を適宜変更）
docker run --rm -v n8n_data:/data -v $HOME/n8n-backups:/backup alpine \
  tar xzf /backup/n8n-data-YYYYMMDD-HHMMSS.tar.gz -C /data

# Caddyデータを復元（必要な場合）
docker volume rm caddy_data
docker volume create caddy_data
docker run --rm -v caddy_data:/data -v $HOME/n8n-backups:/backup alpine \
  tar xzf /backup/caddy-data-YYYYMMDD-HHMMSS.tar.gz -C /data

# n8nを再起動
docker compose up -d
```

## アップグレード

### n8nのアップグレード手順

```bash
# 1. バックアップを取得（上記参照）
~/n8n-backup.sh

# 2. 現在のバージョンを確認
docker compose exec n8n n8n --version

# 3. イメージを更新して再起動
docker compose pull n8n
docker compose up -d n8n

# 4. 動作確認
docker compose ps
docker compose logs n8n

# 5. 新しいバージョンを確認
docker compose exec n8n n8n --version
```

**注意**: メジャーバージョンアップ時は[リリースノート](https://github.com/n8n-io/n8n/releases)を確認してください。

## セキュリティ

### 実装済みのセキュリティ機能

- HTTPS自動化（Let's Encrypt）
- セキュリティヘッダー（XSS, Clickjacking対策）
- n8nポートの内部限定公開
- Serverヘッダーの非公開

### 追加推奨設定

```bash
# fail2banのインストール（ブルートフォース対策）
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# 不要なポートを閉じる
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# (注意) ufwを有効にすると、許可されていないポートはすべてブロックされます。
# SSH接続が切断されないよう、事前に 'sudo ufw allow <ssh_port>/tcp' を実行していることを確認してください。
sudo ufw enable
```

### n8n認証設定

初回アクセス時に管理者アカウントを作成します。強力なパスワードを設定してください。

追加の認証オプション（compose.ymlのenvironmentに追加）：

```yaml
# Basic認証を追加する場合
- N8N_BASIC_AUTH_ACTIVE=true
- N8N_BASIC_AUTH_USER=admin
- N8N_BASIC_AUTH_PASSWORD=your-strong-password
```

## トラブルシューティング

### SSL証明書エラー

```bash
# DNSが正しく設定されているか確認
dig n8n.example.com +short

# Caddyのログを確認
docker compose logs caddy

# 証明書の状態を確認
docker compose exec caddy caddy list-certificates
```

**原因と対策**:
- DNSレコードが未反映 → 数分〜数時間待つ
- ポート80/443がブロック → ファイアウォール確認
- Let's Encryptのレート制限 → 1時間後に再試行

### n8nにアクセスできない

```bash
# コンテナの状態を確認
docker compose ps

# ヘルスチェックの詳細
docker inspect --format='{{json .State.Health}}' $(docker compose ps -q n8n) | jq

# ログを確認
docker compose logs n8n

# ネットワーク確認
docker network ls
docker network inspect n8n-docker-caddy_n8n-network
```

### コンテナが起動しない

```bash
# 詳細ログを確認
docker compose logs --tail=100

# 設定ファイルの構文チェック
docker compose config

# ボリュームの確認
docker volume ls
```

### メモリ不足

```bash
# メモリ使用状況
free -h
docker stats --no-stream

# スワップを追加（必要な場合）
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## FAQ

### Q: Webhookが動作しない

A: `WEBHOOK_URL`が正しく設定されているか確認してください。URLの末尾にスラッシュが必要です。

### Q: ワークフローの実行が遅い

A: VPSのスペックを確認してください。推奨は2 vCPU / 4GB RAM以上です。

### Q: 複数ユーザーで使いたい

A: n8nはデフォルトでマルチユーザー対応です。管理者がユーザーを招待できます。

### Q: 外部データベースを使いたい

A: compose.ymlに以下の環境変数を追加：

```yaml
- DB_TYPE=postgresdb
- DB_POSTGRESDB_HOST=your-db-host
- DB_POSTGRESDB_PORT=5432
- DB_POSTGRESDB_DATABASE=n8n
- DB_POSTGRESDB_USER=n8n
- DB_POSTGRESDB_PASSWORD=your-password
```

### Q: メール送信を設定したい

A: compose.ymlに以下の環境変数を追加：

```yaml
- N8N_EMAIL_MODE=smtp
- N8N_SMTP_HOST=smtp.example.com
- N8N_SMTP_PORT=587
- N8N_SMTP_USER=your-email@example.com
- N8N_SMTP_PASS=your-password
- N8N_SMTP_SENDER=n8n@example.com
```

## 参考リンク

- [n8n公式ドキュメント](https://docs.n8n.io/)
- [n8n-docker-caddy公式リポジトリ](https://github.com/n8n-io/n8n-docker-caddy)
- [n8n環境変数一覧](https://docs.n8n.io/hosting/configuration/environment-variables/)
- [Caddy公式ドキュメント](https://caddyserver.com/docs/)
- [n8nリリースノート](https://github.com/n8n-io/n8n/releases)

## ライセンス

このリポジトリの設定ファイルはMITライセンスです。
n8n自体は[Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md)に従います。
