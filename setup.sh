#!/bin/bash

# n8n初期セットアップスクリプト
# Dockerボリュームの作成、.envファイルの生成を支援します

set -e

echo "==============================================="
echo "n8n + Caddy セットアップスクリプト"
echo "==============================================="
echo ""

# --------------------------------------------------
# 前提条件の確認
# --------------------------------------------------

echo "🔍 前提条件を確認しています..."
echo ""

# Dockerの確認
if ! command -v docker &> /dev/null; then
    echo "❌ Dockerがインストールされていません。"
    echo ""
    echo "Dockerをインストールしてください:"
    echo "  curl -fsSL https://get.docker.com | sh"
    echo "  sudo usermod -aG docker \$USER"
    echo ""
    echo "その後、ログアウトして再ログインしてください。"
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    echo "❌ Dockerデーモンが実行されていないか、権限がありません。"
    echo ""
    echo "権限の問題の場合:"
    echo "  sudo usermod -aG docker \$USER"
    echo "  その後、ログアウトして再ログインしてください。"
    echo ""
    echo "Dockerが起動していない場合:"
    echo "  sudo systemctl start docker"
    exit 1
fi

echo "✅ Docker: インストール済み"

# Docker Composeの確認
if ! docker compose version &> /dev/null; then
    echo "❌ Docker Composeがインストールされていません。"
    echo ""
    echo "最新のDockerにはDocker Composeが含まれています。"
    echo "Dockerを更新してください:"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

echo "✅ Docker Compose: インストール済み"
echo ""

# --------------------------------------------------
# .envファイルの作成
# --------------------------------------------------

if [ -f .env ]; then
    echo "⚠️  .envファイルが既に存在します。"
    echo ""
    echo "上書きしますか？ (yes/no)"
    read -r OVERWRITE

    if [ "$OVERWRITE" != "yes" ]; then
        echo "ℹ️  .envファイルの作成をスキップしました。"
        ENV_CREATED=false
    else
        cp .env .env.backup.$(date +%Y%m%d-%H%M%S)
        echo "📁 既存の.envをバックアップしました。"
        ENV_CREATED=true
    fi
else
    ENV_CREATED=true
fi

if [ "$ENV_CREATED" = true ]; then
    echo ""
    echo "📝 .envファイルを作成します。"
    echo ""

    # 現在のディレクトリの絶対パスを取得
    CURRENT_DIR=$(pwd)

    # ドメイン名を入力
    echo "ドメイン名を入力してください（例: example.com）:"
    read -r DOMAIN_NAME

    # サブドメインを入力
    echo "サブドメインを入力してください（例: n8n）:"
    read -r SUBDOMAIN

    # SSL証明書用メールアドレスを入力
    echo "SSL証明書通知用のメールアドレスを入力してください:"
    read -r SSL_EMAIL

    # タイムゾーンを入力（デフォルト: Asia/Tokyo）
    echo "タイムゾーンを入力してください（デフォルト: Asia/Tokyo）:"
    read -r TIMEZONE
    TIMEZONE=${TIMEZONE:-Asia/Tokyo}

    # Basic認証の設定
    echo ""
    echo "Basic認証を設定しますか？ (yes/no)"
    echo "（推奨: セキュリティ強化のため設定を推奨）"
    read -r USE_BASIC_AUTH

    if [ "$USE_BASIC_AUTH" = "yes" ]; then
        echo "Basic認証のユーザー名を入力してください:"
        read -r BASIC_AUTH_USER

        echo "Basic認証のパスワードを入力してください（12文字以上推奨）:"
        read -rs BASIC_AUTH_PASSWORD
        echo ""
    else
        BASIC_AUTH_USER=""
        BASIC_AUTH_PASSWORD=""
    fi

    # .envファイルを作成
    cat > .env << EOF
# n8n Docker + Caddy 環境変数設定
# 自動生成日: $(date)

# データ保存ディレクトリ（絶対パス）
DATA_FOLDER=$CURRENT_DIR

# ドメイン設定
DOMAIN_NAME=$DOMAIN_NAME
SUBDOMAIN=$SUBDOMAIN

# タイムゾーン
GENERIC_TIMEZONE=$TIMEZONE

# SSL証明書用メールアドレス（Let's Encrypt通知用）
SSL_EMAIL=$SSL_EMAIL

# Basic認証設定（オプション）
BASIC_AUTH_USER=$BASIC_AUTH_USER
BASIC_AUTH_PASSWORD=$BASIC_AUTH_PASSWORD
BASIC_AUTH_PASSWORD_HASH=
EOF

    echo "✅ .envファイルを作成しました。"
fi

echo ""

# --------------------------------------------------
# Dockerボリュームの作成
# --------------------------------------------------

echo "🔧 Dockerボリュームを作成しています..."
echo ""

# 既存のボリュームを確認
if docker volume ls | grep -q "caddy_data"; then
    echo "ℹ️  caddy_data ボリュームは既に存在します。"
else
    docker volume create caddy_data
    echo "✅ caddy_data ボリュームを作成しました。"
fi

if docker volume ls | grep -q "n8n_data"; then
    echo "ℹ️  n8n_data ボリュームは既に存在します。"
else
    docker volume create n8n_data
    echo "✅ n8n_data ボリュームを作成しました。"
fi

echo ""

# --------------------------------------------------
# Basic認証のセットアップ
# --------------------------------------------------

if [ "$ENV_CREATED" = true ] && [ "$USE_BASIC_AUTH" = "yes" ]; then
    echo "🔐 Basic認証のパスワードハッシュを生成しています..."

    if [ -f setup_auth.sh ]; then
        # setup_auth.shが存在する場合は実行
        ./setup_auth.sh
    else
        echo "⚠️  setup_auth.sh が見つかりません。Basic認証の設定をスキップします。"
        echo "   後で手動で './setup_auth.sh' を実行してください。"
    fi

    echo ""
fi

# --------------------------------------------------
# スクリプトファイルに実行権限を付与
# --------------------------------------------------

echo "🔧 スクリプトファイルに実行権限を付与しています..."

for script in setup_auth.sh n8n-backup.sh n8n-restore.sh setup.sh; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        echo "✅ $script"
    fi
done

echo ""

# --------------------------------------------------
# 次のステップを表示
# --------------------------------------------------

echo "==============================================="
echo "✅ セットアップが完了しました！"
echo "==============================================="
echo ""
echo "次のステップ:"
echo ""
echo "1. DNSレコードを設定してください:"
echo "   タイプ: A"
echo "   名前: $SUBDOMAIN"
echo "   値: <VPSのIPアドレス>"
echo ""
echo "   設定後、以下のコマンドで確認:"
if [ -n "$SUBDOMAIN" ] && [ -n "$DOMAIN_NAME" ]; then
    echo "   dig $SUBDOMAIN.$DOMAIN_NAME +short"
fi
echo ""
echo "2. ファイアウォールを設定してください:"
echo "   sudo ufw allow 80/tcp"
echo "   sudo ufw allow 443/tcp"
echo "   sudo ufw enable"
echo ""
echo "3. .envファイルの内容を確認してください:"
echo "   cat .env"
echo ""
echo "4. n8nを起動してください:"
echo "   docker compose up -d"
echo ""
echo "5. サービスの状態を確認してください:"
echo "   docker compose ps"
echo "   docker compose logs -f"
echo ""
if [ -n "$SUBDOMAIN" ] && [ -n "$DOMAIN_NAME" ]; then
    echo "6. ブラウザでアクセスしてください:"
    echo "   https://$SUBDOMAIN.$DOMAIN_NAME"
fi
echo ""
echo "⚠️  重要な注意事項:"
echo "- .envファイルは絶対にGitにコミットしないでください"
echo "- パスワードは強力なものを設定してください"
echo "- 定期的にバックアップを取得してください（./n8n-backup.sh）"
echo ""
