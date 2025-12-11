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
├── setup.sh              # セットアップスクリプト（NEW）
├── setup_auth.sh         # Basic認証設定スクリプト
├── n8n-backup.sh         # バックアップスクリプト（NEW）
├── n8n-restore.sh        # リストアスクリプト（NEW）
├── caddy_config/
│   └── Caddyfile         # Caddyリバースプロキシ設定
└── local_files/          # n8nファイル保存用
```

## 前提条件

- VPS（Ubuntu 22.04/24.04 推奨）
- Docker および Docker Compose がインストール済み
- ドメイン名（サブドメインのDNS設定済み）
- 80/443 ポートが開放されていること

## クイックスタート（推奨）

初めてセットアップする場合は、対話形式のセットアップスクリプトを使用することを推奨します。

```bash
# 1. リポジトリをクローン
git clone <repository-url> ~/n8n-docker-caddy
cd ~/n8n-docker-caddy

# 2. セットアップスクリプトを実行
chmod +x setup.sh
./setup.sh
```

セットアップスクリプトは以下を自動的に実行します：
- Dockerのインストール確認（未インストールの場合はインストール可能）
- .envファイルの対話形式での作成
- Dockerボリュームの作成
- Basic認証の設定（オプション）
- 必要なスクリプトへの実行権限付与

セットアップ完了後、DNSレコードを設定してから以下を実行：

```bash
# 3. n8nを起動
docker compose up -d

# 4. ログを確認
docker compose logs -f
```

詳細な手動セットアップ手順については、下記の「セットアップ手順（手動）」を参照してください。

## セットアップ手順（手動）

> **⚠️ セキュリティ上の重要な注意**
>
> rootユーザーでの日常的な操作は避けてください。セキュリティのベストプラクティスとして、以下を推奨します：
> - 通常の管理作業には一般ユーザー（例：ubuntu、admin）を使用
> - sudoを必要な時のみ使用
> - n8nのインストールディレクトリは一般ユーザーのホームディレクトリ配下に配置

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
git clone <repository-url> ~/n8n-docker-caddy
cd ~/n8n-docker-caddy
```

### 3. 環境変数を設定

```bash
cp .env.example .env
nano .env
```

以下の値を自分の環境に合わせて編集：

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `DATA_FOLDER` | 設定ファイルのパス | `~/n8n-docker-caddy` |
| `DOMAIN_NAME` | メインドメイン | `example.com` |
| `SUBDOMAIN` | サブドメイン | `n8n` |
| `GENERIC_TIMEZONE` | タイムゾーン | `Asia/Tokyo` |
| `SSL_EMAIL` | SSL証明書通知用メール | `your@email.com` |
| `BASIC_AUTH_USER` | Basic認証ユーザー名 | `admin` |
| `BASIC_AUTH_PASSWORD` | Basic認証パスワード | 強力なパスワードを設定 |

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

### 7. Basic認証をセットアップ（オプション）

n8nへのアクセスをBasic認証で保護する場合：

```bash
# パスワードハッシュを生成
./setup_auth.sh
```

このスクリプトは以下を実行します：
- .envファイルのBASIC_AUTH_PASSWORDを読み取る
- Caddyで使用するパスワードハッシュを生成
- .envファイルにBASIC_AUTH_PASSWORD_HASHを追加

### 8. n8nを起動

```bash
# Verify .env file exists and is configured
if [ ! -f .env ]; then
  echo "Error: .env file not found. Please copy .env.example to .env and configure it."
  exit 1
fi

# Start the services
docker compose up -d
```

### 9. 動作確認

```bash
# コンテナの状態を確認（両方 healthy になるまで待つ）
docker compose ps

# ログを確認
docker compose logs -f
```

ブラウザで `https://n8n.example.com` にアクセス

Basic認証を設定した場合は、設定したユーザー名とパスワードでログインします。
その後、初回アクセス時にn8nのアカウント作成画面が表示されます。

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

### スクリプトを使用したバックアップ（推奨）

バックアップスクリプトを使用すると、n8nデータとCaddyデータ（SSL証明書）を簡単にバックアップできます。

```bash
# 1. スクリプト内のN8N_DIRを設定（初回のみ）
nano n8n-backup.sh
# N8N_DIR=/path/to/your/n8n-docker-caddy を実際のパスに変更
# 例: N8N_DIR=/home/ubuntu/n8n-docker-caddy

# 2. バックアップを実行
chmod +x n8n-backup.sh
./n8n-backup.sh
```

バックアップスクリプトの機能：
- n8nサービスの自動停止・再開
- n8nデータのバックアップ
- Caddyデータ（SSL証明書）のバックアップ
- 7日以上古いバックアップの自動削除
- エラーハンドリングと詳細なログ出力

バックアップファイルは `$HOME/n8n-backups/` に保存されます。

### 自動バックアップ（cron）

cronを使用してバックアップを自動化できます：

```bash
# cronに登録（毎日午前3時に実行）
# /path/to/your/n8n-docker-caddy を実際のパスに置き換えてください
(crontab -l 2>/dev/null; echo "0 3 * * * /path/to/your/n8n-docker-caddy/n8n-backup.sh >> $HOME/n8n-backup.log 2>&1") | crontab -

# 例: ~/n8n-docker-caddy にインストールした場合
# (crontab -l 2>/dev/null; echo "0 3 * * * $HOME/n8n-docker-caddy/n8n-backup.sh >> $HOME/n8n-backup.log 2>&1") | crontab -
```

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

### バックアップからの復元（スクリプト使用）

リストアスクリプトを使用すると、バックアップからの復元が簡単になります。

```bash
# 1. スクリプト内のN8N_DIRを設定（初回のみ）
nano n8n-restore.sh
# N8N_DIR=/path/to/your/n8n-docker-caddy を実際のパスに変更
# 例: N8N_DIR=/home/ubuntu/n8n-docker-caddy

# 2. 利用可能なバックアップを確認してリストアを実行
chmod +x n8n-restore.sh
./n8n-restore.sh

# または、特定のバックアップを直接指定
./n8n-restore.sh 20250101-120000
```

リストアスクリプトの機能：
- 利用可能なバックアップの一覧表示
- 既存ボリュームの削除と再作成
- バックアップデータの復元
- 確認プロンプトによる安全性の確保
- n8nサービスの自動起動

### バックアップからの復元（手動）

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

# 3. compose.ymlでn8nのバージョンを更新
# compose.ymlのimageタグを希望する新しいバージョンに変更してください
nano compose.yml

# 4. イメージを更新して再起動
docker compose pull n8n
docker compose up -d n8n

# 5. 動作確認
docker compose ps
docker compose logs n8n

# 6. 新しいバージョンを確認
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

**リソース制限の調整が必要な場合**:
- 20以上のアクティブなワークフロー、または1日500以上の実行がある場合は、`compose.yml`のメモリ制限を4GB以上に増やすことを検討してください
- `deploy.resources.limits.memory`を`4096M`に変更
- CPUリソースも必要に応じて調整してください

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
