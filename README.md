# n8n VPS セットアップ (Docker + Caddy)

n8nをVPS上でDocker + Caddyを使用して動作させるための設定ファイルです。

## 前提条件

- VPS（Ubuntu 22.04/24.04 推奨）
- Docker および Docker Compose がインストール済み
- ドメイン名（サブドメインのDNS設定済み）

## セットアップ手順

### 1. VPSにDockerをインストール

```bash
# Docker公式インストールスクリプト
curl -fsSL https://get.docker.com | sh

# 現在のユーザーをdockerグループに追加
sudo usermod -aG docker $USER
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
n8n.example.com -> VPSのIPアドレス (Aレコード)
```

### 5. Dockerボリュームを作成

```bash
docker volume create caddy_data
docker volume create n8n_data
```

### 6. n8nを起動

```bash
docker compose up -d
```

### 7. 動作確認

ブラウザで `https://n8n.example.com` にアクセス

初回アクセス時にアカウント作成画面が表示されます。

## 管理コマンド

```bash
# ログを確認
docker compose logs -f

# n8nを再起動
docker compose restart n8n

# 停止
docker compose down

# ヘルスチェック状態を確認
docker compose ps

# 更新
docker compose pull && docker compose up -d
```

## バックアップ

### n8nデータのバックアップ

```bash
# バックアップディレクトリを作成
mkdir -p ~/n8n-backups

# n8nデータをバックアップ
docker run --rm -v n8n_data:/data -v ~/n8n-backups:/backup alpine \
  tar czf /backup/n8n-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

# Caddyデータをバックアップ（SSL証明書含む）
docker run --rm -v caddy_data:/data -v ~/n8n-backups:/backup alpine \
  tar czf /backup/caddy-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
```

### バックアップからの復元

```bash
# n8nを停止
docker compose down

# n8nデータを復元
docker run --rm -v n8n_data:/data -v ~/n8n-backups:/backup alpine \
  sh -c "rm -rf /data/* && tar xzf /backup/n8n-data-YYYYMMDD-HHMMSS.tar.gz -C /data"

# n8nを再起動
docker compose up -d
```

## アップグレード

### n8nのアップグレード手順

```bash
# 1. バックアップを取得（上記参照）

# 2. 現在のバージョンを確認
docker compose exec n8n n8n --version

# 3. イメージを更新して再起動
docker compose pull n8n
docker compose up -d n8n

# 4. 動作確認
docker compose ps
docker compose logs n8n
```

**注意**: メジャーバージョンアップ時はリリースノートを確認してください。

## トラブルシューティング

### SSL証明書エラー
- DNSレコードが正しく設定されているか確認
- 80/443ポートがファイアウォールで許可されているか確認

```bash
# UFWを使用している場合
sudo ufw allow 80
sudo ufw allow 443
```

### n8nにアクセスできない
```bash
# コンテナの状態を確認
docker compose ps

# ログを確認
docker compose logs n8n
```

## 参考リンク

- [n8n公式ドキュメント](https://docs.n8n.io/)
- [n8n-docker-caddy公式リポジトリ](https://github.com/n8n-io/n8n-docker-caddy)
