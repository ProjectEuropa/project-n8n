# VPS自動デプロイ設定ガイド

このドキュメントでは、GitHub Actionsを使用してn8nをVPSに自動デプロイする方法を説明します。

## 概要

- **トリガー**: `main`ブランチへのプッシュ、または手動実行
- **デプロイ方法**: SSH経由でVPSに接続し、最新のコードをpullしてDocker Composeで再起動
- **ダウンタイム**: 最小限（数秒程度）

## セットアップ手順

### 1. ワークフローファイルを配置

`deploy-workflow.yml`を`.github/workflows/deploy.yml`に移動します：

```bash
mv deploy-workflow.yml .github/workflows/deploy.yml
git add .github/workflows/deploy.yml
git commit -m "Add VPS deployment workflow"
git push
```

### 2. VPSの準備

#### 2.1 デプロイ用のSSHキーを作成

VPS上で専用のSSHキーペアを作成します（ローカルマシンで実行）：

```bash
# SSH鍵ペアを生成
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_deploy_key -N ""

# 秘密鍵の内容を表示（後でGitHub Secretsに登録）
cat ~/.ssh/github_deploy_key
```

#### 2.2 公開鍵をVPSに登録

```bash
# 公開鍵をVPSにコピー
ssh-copy-id -i ~/.ssh/github_deploy_key.pub your-user@your-vps-ip

# または手動で追加する場合
cat ~/.ssh/github_deploy_key.pub
# VPSにSSHで接続して、上記の公開鍵を ~/.ssh/authorized_keys に追加
```

#### 2.3 VPS上でリポジトリをクローン

VPSにSSHで接続し、デプロイ先ディレクトリにリポジトリをクローンします：

```bash
# 推奨: ホームディレクトリ配下に配置
cd ~
git clone https://github.com/ProjectEuropa/project-n8n.git n8n-docker-caddy
cd n8n-docker-caddy

# .envファイルを作成
cp .env.example .env
nano .env
# 必要な環境変数を設定してください

# Dockerボリュームを作成
docker volume create caddy_data
docker volume create n8n_data

# 初回起動
docker compose up -d
```

### 3. GitHub Secretsの設定

GitHubリポジトリの Settings > Secrets and variables > Actions で以下のシークレットを追加します：

| シークレット名 | 説明 | 例 |
|---------------|------|-----|
| `VPS_SSH_PRIVATE_KEY` | デプロイ用SSH秘密鍵の**全体** | `-----BEGIN OPENSSH PRIVATE KEY-----\n...` |
| `VPS_HOST` | VPSのIPアドレスまたはホスト名 | `123.45.67.89` または `vps.example.com` |
| `VPS_USER` | SSH接続するユーザー名 | `ubuntu` |
| `VPS_DEPLOY_PATH` | デプロイ先のディレクトリ | `/home/ubuntu/n8n-docker-caddy` |

#### SSH秘密鍵の登録方法

1. ローカルで秘密鍵の内容をコピー：
   ```bash
   cat ~/.ssh/github_deploy_key | pbcopy  # macOS
   # または
   cat ~/.ssh/github_deploy_key  # 内容を手動でコピー
   ```

2. GitHubで New repository secret をクリック
3. Name: `VPS_SSH_PRIVATE_KEY`
4. Secret: コピーした秘密鍵の内容をそのまま貼り付け（改行含む）
5. Add secret をクリック

### 4. デプロイテスト

#### 手動デプロイ

1. GitHubリポジトリの **Actions** タブに移動
2. **Deploy to VPS** ワークフローを選択
3. **Run workflow** ボタンをクリック
4. ブランチを選択（通常は `main`）
5. **Run workflow** をクリック

#### 自動デプロイ

`main`ブランチに変更をプッシュすると自動的にデプロイが実行されます：

```bash
git add .
git commit -m "Update configuration"
git push origin main
```

## ワークフローの動作

1. **Checkout**: 最新のコードをチェックアウト
2. **SSH Setup**: SSH秘密鍵を設定
3. **Deploy**: VPSに接続して以下を実行：
   - 最新のコードをgit pull
   - Docker Composeでイメージをpull
   - サービスを再起動
   - ヘルスチェック
4. **Cleanup**: 秘密鍵を削除

## トラブルシューティング

### SSH接続エラー

```
Permission denied (publickey)
```

**原因**: SSH鍵が正しく設定されていない

**解決方法**:
1. VPSの`~/.ssh/authorized_keys`に公開鍵が追加されているか確認
2. GitHub Secretsの`VPS_SSH_PRIVATE_KEY`が正しいか確認
3. VPSのSSHDログを確認: `sudo tail -f /var/log/auth.log`

### .env ファイルが見つからない

```
Warning: .env file not found
```

**原因**: VPS上で`.env`ファイルが作成されていない

**解決方法**:
```bash
# VPSにSSHで接続
cd ~/n8n-docker-caddy
cp .env.example .env
nano .env
# 必要な設定を記入して保存
```

### Docker Composeエラー

```
docker compose: command not found
```

**原因**: Docker Composeがインストールされていない

**解決方法**:
```bash
# Docker Desktop（Compose V2含む）をインストール
curl -fsSL https://get.docker.com | sh
```

### サービスがhealthyにならない

**原因**: 設定エラーまたはリソース不足

**解決方法**:
```bash
# VPSでログを確認
docker compose logs -f

# 特定のサービスのログ
docker compose logs n8n
docker compose logs caddy

# リソース使用状況を確認
docker stats
free -h
```

### デプロイは成功するがサービスにアクセスできない

**チェックリスト**:
1. DNS設定が正しいか確認: `dig n8n.example.com +short`
2. ファイアウォールでポート80/443が開放されているか確認
3. `.env`ファイルのドメイン設定が正しいか確認
4. Caddyのログを確認: `docker compose logs caddy`

## セキュリティベストプラクティス

### SSH鍵の管理

- ✅ **推奨**: デプロイ専用のSSH鍵を使用
- ✅ **推奨**: 鍵には強力なパスフレーズを設定（GitHub Actionsでは不要）
- ❌ **非推奨**: 個人用のSSH鍵を使用しない
- ❌ **非推奨**: 同じ鍵を複数のサービスで使い回さない

### VPSのセキュリティ

```bash
# fail2banをインストール（ブルートフォース対策）
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# UFWでファイアウォールを設定
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### GitHub Actionsのセキュリティ

- ✅ **推奨**: Environment secretsを使用（本番環境専用）
- ✅ **推奨**: ワークフローの実行ログを定期的に確認
- ❌ **非推奨**: シークレットをコード内にハードコードしない
- ❌ **非推奨**: デバッグ出力でシークレットを表示しない

## 高度な設定

### デプロイ通知の追加

Slack、Discord、メールなどへの通知を追加できます。

#### Slack通知の例

```yaml
- name: Notify Slack
  if: always()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "n8n deployment to VPS: ${{ job.status }}"
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### ロールバック機能

デプロイ失敗時に自動的に前のバージョンに戻す機能を追加：

```bash
# デプロイスクリプトに追加
# 更新前のコミットIDを保存
OLD_COMMIT=$(git rev-parse HEAD)
# デプロイ実行と失敗時のロールバック
git reset --hard origin/main && docker compose up -d || {
  echo "Deployment failed, rolling back to ${OLD_COMMIT}..."
  git reset --hard $OLD_COMMIT
  docker compose up -d
  exit 1
}
```

### Blue-Green デプロイ

ダウンタイムゼロのデプロイを実現：

1. 新しいバージョンを別のコンテナで起動
2. ヘルスチェックが成功したら切り替え
3. 古いバージョンを停止

### マルチVPSデプロイ

複数のVPSに同時デプロイする場合は、matrix strategyを使用：

```yaml
strategy:
  matrix:
    vps:
      - { host: 'vps1.example.com', user: 'ubuntu' }
      - { host: 'vps2.example.com', user: 'ubuntu' }
```

## 参考リンク

- [GitHub Actions ドキュメント](https://docs.github.com/ja/actions)
- [Docker Compose ドキュメント](https://docs.docker.com/compose/)
- [n8n ドキュメント](https://docs.n8n.io/)
- [SSH鍵の管理ベストプラクティス](https://docs.github.com/ja/authentication/connecting-to-github-with-ssh)

## FAQ

### Q: デプロイの頻度はどのくらいが適切ですか？

A: プロジェクトの規模によりますが、以下が一般的です：
- 小規模: 週1-2回
- 中規模: 日1-2回
- 大規模: 1日数回（CI/CDパイプライン完備の場合）

### Q: デプロイ中にn8nが停止しますか？

A: `docker compose up -d`は rolling update を行うため、通常は数秒程度のダウンタイムで済みます。ただし、データベースマイグレーションが必要な場合は長くなる可能性があります。

### Q: 本番環境でのバックアップは？

A: デプロイ前に自動バックアップを取ることを強く推奨します。まず、VPS上にbackup.shスクリプトを作成する必要があります：

```bash
# VPS上で /home/n8n-deploy/backup.sh として作成
#!/bin/bash
BACKUP_DIR="/home/n8n-deploy/backups"
mkdir -p $BACKUP_DIR
docker compose exec -T n8n tar -czf - /home/node/.n8n > "$BACKUP_DIR/n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
# 古いバックアップを削除（7日以上前）
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
```

その後、デプロイワークフロー内のDeploy to VPSステップ内で、git pullの前に以下を追加：

```bash
# バックアップスクリプトが存在する場合のみ実行
if [ -f ./backup.sh ]; then
  echo "📦 Creating backup..."
  ./backup.sh
fi
```

### Q: 特定のブランチのみデプロイしたい

A: ワークフローの`on`セクションを修正：

```yaml
on:
  push:
    branches:
      - main
      - production
```
