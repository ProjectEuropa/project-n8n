# OpenClaw VPS セットアップ (Docker + Caddy)

OpenClawをVPS上でDocker + Caddyを使用して動作させるための設定ファイルです。
Vertex AI Gemini をモデルプロバイダとして使用します。

## アーキテクチャ

```
┌──────────────────────────────────────────────────────┐
│                      ConoHa VPS                       │
│  ┌────────────────────────────────────────────────┐  │
│  │                Docker Network                  │  │
│  │                                                │  │
│  │   ┌─────────┐    ┌───────────┐  ┌───────────┐ │  │
│  │   │  Caddy  │    │  OpenClaw │  │ Watchtower│ │  │
│  │   │  :80    │───▶│  :18789   │  │(自動更新) │ │  │
│  │   │  :443   │    │  (Web UI) │  │           │ │  │
│  │   └─────────┘    └───────────┘  └───────────┘ │  │
│  │        │               │                       │  │
│  │        ▼               ▼                       │  │
│  │   caddy_data      openclaw_data                │  │
│  │  (SSL証明書)    (設定・データ)                  │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
     ▲ HTTPS + Basic認証            Vertex AI Gemini ▲
     │                                               │
  ブラウザ                                        GCP API
```

## 推奨スペック

| 用途 | CPU | メモリ | ストレージ |
|------|-----|--------|------------|
| 最小 | 1 vCPU | 2 GB (+swap) | 20 GB |
| 推奨 | 2 vCPU | 4 GB | 40 GB |

> ⚠️ 2GB RAMの場合は2-4GBのswapを追加してください（setup-openclaw.shで設定可能）

## ファイル構成

```
.
├── compose.yml              # Docker Compose設定
├── .env.example             # 環境変数テンプレート
├── .env                     # 環境変数（要作成）
├── setup-openclaw.sh        # セットアップスクリプト
├── openclaw-backup.sh       # バックアップスクリプト
├── openclaw-restore.sh      # リストアスクリプト
├── caddy_config/
│   └── Caddyfile            # Caddyリバースプロキシ設定
└── workspace/               # OpenClawワークスペース
    └── SOUL.md              # AI人格・日本語設定
```

## 前提条件

- VPS（Ubuntu 22.04/24.04 推奨）
- Docker および Docker Compose がインストール済み
- ドメイン名（サブドメインのDNS設定済み）
- 80/443 ポートが開放されていること
- GCPプロジェクト（Vertex AI API 有効化済み）
- GCPサービスアカウントキー

## クイックスタート

```bash
# 1. リポジトリをクローン
git clone <repository-url> ~/project-n8n
cd ~/project-n8n

# 2. セットアップスクリプトを実行
chmod +x setup-openclaw.sh
./setup-openclaw.sh

# 3. GCP認証情報を配置
# サービスアカウントキーを .env の GCP_CREDENTIALS_PATH で指定したパスに配置

# 4. DNSレコードを設定（サブドメイン → VPSのIPアドレス）

# 5. ファイアウォール設定
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 6. OpenClawを起動
docker compose up -d

# 7. ログを確認
docker compose logs -f
```

## GCPセットアップ手順

### 1. GCPプロジェクトの準備

```bash
# Vertex AI API を有効化
gcloud services enable aiplatform.googleapis.com --project=YOUR_PROJECT_ID
```

### 2. サービスアカウントの作成

```bash
# サービスアカウント作成
gcloud iam service-accounts create openclaw-vertex \
  --display-name="OpenClaw Vertex AI" \
  --project=YOUR_PROJECT_ID

# Vertex AI 権限を付与
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:openclaw-vertex@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"

# 鍵ファイルを発行
gcloud iam service-accounts keys create adc.json \
  --iam-account=openclaw-vertex@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### 3. 鍵ファイルをVPSに配置

```bash
# ローカルからVPSに転送
scp adc.json user@vps-ip:/root/.config/gcloud/adc.json

# VPS上で権限を設定
ssh user@vps-ip 'chmod 600 /root/.config/gcloud/adc.json'
```

### 4. 予算アラートの設定

GCP Console → 課金 → 予算とアラートで、月額の上限を設定してください。
API費用暴走防止のため必須です。

## セットアップ手順（手動）

> **⚠️ セキュリティ上の重要な注意**
>
> rootユーザーでの日常的な操作は避けてください。セキュリティのベストプラクティスとして、以下を推奨します：
> - 通常の管理作業には一般ユーザーを使用
> - sudoを必要な時のみ使用

### 1. VPSにDockerをインストール

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# 再ログインが必要
```

### 2. Swap を追加（2GB RAM VPSの場合）

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 3. 環境変数を設定

```bash
cp .env.example .env
nano .env
```

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `DOMAIN_NAME` | メインドメイン | `example.com` |
| `SUBDOMAIN` | サブドメイン | `ai` |
| `SSL_EMAIL` | SSL証明書通知用メール | `your@email.com` |
| `GCP_PROJECT_ID` | GCPプロジェクトID | `my-project-123` |
| `GCP_CREDENTIALS_PATH` | サービスアカウントキーのパス | `~/.config/gcloud/adc.json` |
| `VERTEX_AI_LOCATION` | Vertex AIリージョン | `asia-northeast1` |
| `BASIC_AUTH_USER` | Basic認証ユーザー名 | `admin` |
| `BASIC_AUTH_PASSWORD_HASH` | Basic認証パスワードハッシュ | `setup-openclaw.sh` で自動生成 |

### 4. DNSレコードを設定

```
タイプ: A
名前: ai（サブドメイン）
値: VPSのIPアドレス
TTL: 3600
```

### 5. ファイアウォールを設定

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### 6. Dockerボリュームを作成

```bash
docker volume create caddy_data
docker volume create openclaw_data
```

### 7. OpenClawを起動

```bash
docker compose up -d
docker compose logs -f
```

ブラウザで `https://ai.example.com` にアクセスしてください。
（Basic認証を設定した場合は、設定したユーザー名とパスワードでログインします。）

### 8. 初回アクセス時のデバイス承認 (Pairing)

OpenClawのWeb UI（Dashboard）に初めてアクセスすると「pairing required」と表示され、接続が待機状態になります。これは未知のデバイスからのアクセスを防ぐためのセキュリティ機能です。

VPSのターミナルで以下のコマンドを実行し、アクセスを承認してください。

```bash
# 保留中のペアリングリクエストを確認
docker compose exec openclaw openclaw devices list

# 該当する Request ID（例: 753d6374-b841-...）をコピーし、approve します
docker compose exec openclaw openclaw devices approve <Request ID>
```

承認が完了すると、ブラウザの画面が自動的に操作可能な状態（Chat UI）に切り替わります。

## 管理コマンド

```bash
# ログを確認
docker compose logs -f

# 特定サービスのログ
docker compose logs -f openclaw
docker compose logs -f caddy
docker compose logs -f watchtower

# OpenClawを再起動
docker compose restart openclaw

# 全サービス再起動
docker compose restart

# 停止
docker compose down

# リソース使用状況
docker stats

# 更新（Watchtowerが自動で行うが、手動の場合）
docker compose pull && docker compose up -d
```

## バックアップ

### スクリプトを使用したバックアップ（推奨）

```bash
# 1. スクリプト内のAPP_DIRを設定（setup-openclaw.sh未使用時のみ）
nano openclaw-backup.sh
# APP_DIR=/path/to/your/project-n8n を実際のパスに変更

# 2. バックアップを実行
chmod +x openclaw-backup.sh
./openclaw-backup.sh
```

バックアップ対象：
- OpenClawデータ（`openclaw_data` ボリューム）
- ワークスペース（`workspace/` ディレクトリ）
- Caddyデータ（SSL証明書）

バックアップファイルは `$HOME/openclaw-backups/` に保存されます。
7日以上古いバックアップは自動削除されます。

### 自動バックアップ（cron）

```bash
# 毎日午前3時に実行
(crontab -l 2>/dev/null; echo "0 3 * * * /path/to/project-n8n/openclaw-backup.sh >> $HOME/openclaw-backup.log 2>&1") | crontab -
```

### バックアップからの復元

```bash
chmod +x openclaw-restore.sh
./openclaw-restore.sh

# または、特定のバックアップを直接指定
./openclaw-restore.sh 20260401-120000
```

## セキュリティ

### 実装済みのセキュリティ機能

- HTTPS自動化（Let's Encrypt）
- セキュリティヘッダー（XSS, Clickjacking対策）
- OpenClawポートの内部限定公開
- Serverヘッダーの非公開
- Basic認証によるアクセス制御
- GCP認証情報のread-onlyマウント

### 追加推奨設定

```bash
# fail2banのインストール（ブルートフォース対策）
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# unattended-upgradesの有効化
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades
```

## トラブルシューティング

### SSL証明書エラー

```bash
# DNSが正しく設定されているか確認
dig ai.example.com +short

# Caddyのログを確認
docker compose logs caddy
```

### OpenClawにアクセスできない

```bash
# コンテナの状態を確認
docker compose ps

# ログを確認
docker compose logs openclaw

# ネットワーク確認
docker network ls
```

### メモリ不足

```bash
# メモリ使用状況
free -h
docker stats --no-stream

# Swapの確認
swapon --show
```

### GCP認証エラー

```bash
# 認証情報ファイルの確認
ls -la /root/.config/gcloud/adc.json

# コンテナ内から認証ファイルの存在確認（内容は表示しない）
docker compose exec openclaw ls -la /tmp/keys/adc.json
```

## 運用コスト見込み

| 項目 | 月額 |
|---|---|
| ConoHa VPS 2GB | ~1,500円 |
| Vertex AI Gemini Flash | 0〜1,000円 |
| **合計** | **~1,500〜2,500円** |

## 今後の予定

- [ ] WIFキーレス化（#14）: GitHub Actions + Workload Identity Federationでサービスアカウントキーを廃止
- [ ] CSPヘッダーの最適化: OpenClaw Web UIの動作確認後にCSPを絞る

## 参考リンク

- [OpenClaw公式ドキュメント](https://docs.openclaw.ai)
- [Vertex AI設定ガイド](https://docs.openclaw.ai/concepts/model-providers)
- [Caddy公式ドキュメント](https://caddyserver.com/docs/)
- [Watchtower](https://github.com/containrrr/watchtower)

## ライセンス

このリポジトリの設定ファイルはMITライセンスです。
