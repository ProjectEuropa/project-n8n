#!/bin/bash
# n8n + Caddy セットアップスクリプト
# このスクリプトはn8nの初期セットアップを対話形式で実行します

set -euo pipefail

echo "========================================="
echo "  n8n + Caddy セットアップスクリプト"
echo "========================================="
echo ""

# Dockerのインストール確認
echo "▶ Dockerのインストール状態を確認中..."
if ! command -v docker &> /dev/null; then
    echo "❌ Dockerがインストールされていません。"
    echo ""
    read -p "Dockerをインストールしますか？ (y/N): " install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        echo "▶ Dockerをインストール中..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        echo "✅ Dockerのインストールが完了しました。"
        echo "⚠️  dockerグループへの追加を反映させるため、一度ログアウトして再ログインしてください。"
        echo "    再ログイン後、このスクリプトを再度実行してください。"
        exit 0
    else
        echo "❌ Dockerが必要です。セットアップを中止します。"
        exit 1
    fi
else
    echo "✅ Dockerがインストールされています。"
fi

# Docker Composeの確認
if ! docker compose version &> /dev/null; then
    echo "❌ Docker Composeが利用できません。"
    exit 1
else
    echo "✅ Docker Composeが利用可能です。"
fi

echo ""

# .envファイルの確認と作成
if [ -f .env ]; then
    echo "⚠️  .envファイルが既に存在します。"
    read -p ".envファイルを再作成しますか？ (y/N): " recreate_env
    if [[ ! "$recreate_env" =~ ^[Yy]$ ]]; then
        echo "既存の.envファイルを使用します。"
        ENV_EXISTS=true
    else
        ENV_EXISTS=false
    fi
else
    ENV_EXISTS=false
fi

if [ "$ENV_EXISTS" = false ]; then
    echo ""
    echo "▶ 環境変数を設定します。"
    echo ""

    # ドメイン名の入力
    read -p "ドメイン名を入力してください (例: example.com): " domain_name
    while [ -z "$domain_name" ]; do
        echo "❌ ドメイン名は必須です。"
        read -p "ドメイン名を入力してください (例: example.com): " domain_name
    done

    # サブドメインの入力
    read -p "サブドメインを入力してください (例: n8n) [デフォルト: n8n]: " subdomain
    subdomain=${subdomain:-n8n}

    # SSL通知用メールアドレスの入力
    read -p "SSL証明書通知用のメールアドレスを入力してください: " ssl_email
    while [ -z "$ssl_email" ]; do
        echo "❌ メールアドレスは必須です。"
        read -p "SSL証明書通知用のメールアドレスを入力してください: " ssl_email
    done

    # タイムゾーンの入力
    read -p "タイムゾーンを入力してください [デフォルト: Asia/Tokyo]: " timezone
    timezone=${timezone:-Asia/Tokyo}

    # Basic認証の設定
    echo ""
    read -p "Basic認証を有効にしますか？ (Y/n): " enable_basic_auth
    if [[ ! "$enable_basic_auth" =~ ^[Nn]$ ]]; then
        read -p "Basic認証のユーザー名を入力してください [デフォルト: admin]: " basic_user
        basic_user=${basic_user:-admin}

        read -sp "Basic認証のパスワードを入力してください: " basic_password
        echo ""
        while [ -z "$basic_password" ]; do
            echo "❌ パスワードは必須です。"
            read -sp "Basic認証のパスワードを入力してください: " basic_password
            echo ""
        done
    else
        basic_user=""
        basic_password=""
    fi

    # .envファイルを作成
    echo ""
    echo "▶ .envファイルを作成中..."

    # 現在のディレクトリを取得
    current_dir=$(pwd)

    cat > .env <<EOF
# n8n + Caddy 環境変数設定ファイル
# このファイルは setup.sh によって自動生成されました

# データフォルダのパス（このリポジトリのディレクトリ）
DATA_FOLDER=${current_dir}

# ドメイン設定
DOMAIN_NAME=${domain_name}
SUBDOMAIN=${subdomain}

# タイムゾーン
GENERIC_TIMEZONE=${timezone}

# SSL証明書設定
SSL_EMAIL=${ssl_email}
EOF

    # Basic認証の設定を追加
    if [ -n "$basic_user" ]; then
        cat >> .env <<EOF

# Basic認証設定
BASIC_AUTH_USER=${basic_user}
BASIC_AUTH_PASSWORD=${basic_password}
EOF
    fi

    echo "✅ .envファイルを作成しました。"

    # バックアップ/リストアスクリプトのN8N_DIRを自動設定
    echo ""
    echo "▶ バックアップ/リストアスクリプトを設定中..."
    # current_dir に特殊文字が含まれる可能性があるため、sedで使用する特殊文字をエスケープ
    escaped_dir=$(printf '%s\n' "$current_dir" | sed -e 's/[&\\|]/\\&/g')
    if [ -f "n8n-backup.sh" ]; then
        sed -i.bak "s|^N8N_DIR=.*|N8N_DIR=${escaped_dir}|" n8n-backup.sh
        rm -f n8n-backup.sh.bak
        echo "  ✓ n8n-backup.sh のN8N_DIRを設定しました"
    fi
    if [ -f "n8n-restore.sh" ]; then
        sed -i.bak "s|^N8N_DIR=.*|N8N_DIR=${escaped_dir}|" n8n-restore.sh
        rm -f n8n-restore.sh.bak
        echo "  ✓ n8n-restore.sh のN8N_DIRを設定しました"
    fi
fi

echo ""

# Basic認証のパスワードハッシュを生成
if [ -f .env ]; then
    BASIC_AUTH_PASSWORD=$(grep '^BASIC_AUTH_PASSWORD=' .env | cut -d'=' -f2- || true)
    BASIC_AUTH_PASSWORD_HASH=$(grep '^BASIC_AUTH_PASSWORD_HASH=' .env | cut -d'=' -f2- || true)
    if [ -n "$BASIC_AUTH_PASSWORD" ] && [ -z "$BASIC_AUTH_PASSWORD_HASH" ]; then
        echo "▶ Basic認証のパスワードハッシュを生成中..."
        if [ -x ./setup_auth.sh ]; then
            ./setup_auth.sh
            echo "✅ パスワードハッシュを生成しました。"
        else
            echo "⚠️  setup_auth.shが見つからないか実行できません。"
            echo "   手動で ./setup_auth.sh を実行してください。"
        fi
    fi
fi

echo ""

# Dockerボリュームの作成
echo "▶ Dockerボリュームを作成中..."

if docker volume inspect n8n_data &> /dev/null; then
    echo "  - n8n_data: 既に存在します"
else
    docker volume create n8n_data
    echo "  - n8n_data: 作成しました"
fi

if docker volume inspect caddy_data &> /dev/null; then
    echo "  - caddy_data: 既に存在します"
else
    docker volume create caddy_data
    echo "  - caddy_data: 作成しました"
fi

echo ""

# スクリプトに実行権限を付与
echo "▶ スクリプトに実行権限を付与中..."
chmod +x setup_auth.sh 2>/dev/null || true
chmod +x n8n-backup.sh 2>/dev/null || true
chmod +x n8n-restore.sh 2>/dev/null || true
echo "✅ 実行権限を付与しました。"

echo ""
echo "========================================="
echo "  セットアップが完了しました！"
echo "========================================="
echo ""
echo "次のステップ:"
echo "1. DNSレコードを設定してください:"
echo "   タイプ: A"
echo "   名前: ${subdomain:-n8n}"
echo "   値: VPSのIPアドレス"
echo ""
echo "2. ファイアウォールでポート80と443を開放してください:"
echo "   sudo ufw allow 80/tcp"
echo "   sudo ufw allow 443/tcp"
echo ""
echo "3. n8nを起動してください:"
echo "   docker compose up -d"
echo ""
echo "4. ログを確認してください:"
echo "   docker compose logs -f"
echo ""
echo "5. ブラウザでアクセスしてください:"
if [ -n "$subdomain" ] && [ -n "$domain_name" ]; then
    echo "   https://${subdomain}.${domain_name}/"
else
    echo "   https://n8n.example.com/"
fi
echo ""
