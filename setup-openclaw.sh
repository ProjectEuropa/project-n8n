#!/bin/bash
# OpenClaw + Caddy セットアップスクリプト
# このスクリプトはOpenClawの初期セットアップを対話形式で実行します

set -euo pipefail

echo "========================================="
echo "  OpenClaw + Caddy セットアップスクリプト"
echo "========================================="
echo ""

# 入力値のバリデーション（改行・制御文字を拒否）
validate_input() {
    local value="$1"
    local name="$2"
    if [[ "$value" =~ [$'\n\r\t'] ]] || [[ "$value" == *$'\0'* ]]; then
        echo "❌ ${name}に改行や制御文字を含めることはできません。"
        return 1
    fi
    return 0
}

# ============================================
# Docker のインストール確認
# ============================================
echo "▶ Dockerのインストール状態を確認中..."
if ! command -v docker &> /dev/null; then
    echo "❌ Dockerがインストールされていません。"
    echo ""
    read -p "Dockerをインストールしますか？ (y/N): " install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        echo "▶ Dockerをインストール中..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker "$USER"
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

# ============================================
# Swap の確認と追加（2GB RAM VPS向け）
# ============================================
echo "▶ Swapの状態を確認中..."
current_swap=$(free -m | awk '/^Swap:/ {print $2}')
if [ "$current_swap" -lt 1024 ] 2>/dev/null; then
    echo "  現在のSwap: ${current_swap}MB"
    read -p "Swapを追加しますか？（2GB RAM VPS推奨） (y/N): " add_swap
    if [[ "$add_swap" =~ ^[Yy]$ ]]; then
        SWAP_SIZE=${SWAP_SIZE:-4G}
        echo "▶ ${SWAP_SIZE}のSwapを作成中..."
        sudo fallocate -l "$SWAP_SIZE" /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        if ! grep -q '/swapfile' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        fi
        echo "✅ Swap ${SWAP_SIZE}を追加しました。"
    fi
else
    echo "✅ Swapが十分に設定されています（${current_swap}MB）"
fi

echo ""

# ============================================
# .env ファイルの作成
# ============================================
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
    while true; do
        read -p "ドメイン名を入力してください (例: example.com): " domain_name
        [ -z "$domain_name" ] && echo "❌ ドメイン名は必須です。" && continue
        validate_input "$domain_name" "ドメイン名" && break
    done

    # サブドメインの入力
    read -p "サブドメインを入力してください (例: ai) [デフォルト: ai]: " subdomain
    subdomain=${subdomain:-ai}
    validate_input "$subdomain" "サブドメイン" || exit 1

    # SSL通知用メールアドレスの入力
    while true; do
        read -p "SSL証明書通知用のメールアドレスを入力してください: " ssl_email
        [ -z "$ssl_email" ] && echo "❌ メールアドレスは必須です。" && continue
        validate_input "$ssl_email" "メールアドレス" && break
    done

    # GCP設定
    echo ""
    echo "▶ GCP / Vertex AI 設定"
    while true; do
        read -p "GCPプロジェクトIDを入力してください: " gcp_project_id
        [ -z "$gcp_project_id" ] && echo "❌ GCPプロジェクトIDは必須です。" && continue
        validate_input "$gcp_project_id" "GCPプロジェクトID" && break
    done

    read -p "GCP認証情報ファイルのパス [デフォルト: /root/.config/gcloud/adc.json]: " gcp_cred_path
    gcp_cred_path=${gcp_cred_path:-/root/.config/gcloud/adc.json}
    validate_input "$gcp_cred_path" "GCP認証情報パス" || exit 1

    read -p "Vertex AIリージョン [デフォルト: asia-northeast1]: " vertex_location
    vertex_location=${vertex_location:-asia-northeast1}
    validate_input "$vertex_location" "Vertex AIリージョン" || exit 1

    # Basic認証の設定
    echo ""
    read -p "Basic認証を有効にしますか？ (Y/n): " enable_basic_auth
    if [[ ! "$enable_basic_auth" =~ ^[Nn]$ ]]; then
        read -p "Basic認証のユーザー名を入力してください [デフォルト: admin]: " basic_user
        basic_user=${basic_user:-admin}
        validate_input "$basic_user" "ユーザー名" || exit 1

        while true; do
            read -sp "Basic認証のパスワードを入力してください: " basic_password
            echo ""
            [ -z "$basic_password" ] && echo "❌ パスワードは必須です。" && continue
            validate_input "$basic_password" "パスワード" && break
        done
    else
        basic_user=""
        basic_password=""
    fi

    # Basic認証のパスワードハッシュをメモリ上で生成（平文をディスクに書かない）
    basic_auth_hash=""
    if [ -n "$basic_user" ] && [ -n "$basic_password" ]; then
        echo ""
        echo "▶ Basic認証のパスワードハッシュを生成中..."

        if ! docker info > /dev/null 2>&1; then
            echo "⚠️  Dockerが実行されていません。パスワードハッシュの生成をスキップします。"
            echo "   Docker起動後に再度このスクリプトを実行してください。"
            echo "   平文パスワードはディスクに保存されません。"
            basic_user=""
        else
            CADDY_IMAGE="caddy:2.8.4"
            docker pull "$CADDY_IMAGE" >/dev/null 2>&1

            PASSWORD_HASH=$(printf '%s' "$basic_password" | docker run --rm -i "$CADDY_IMAGE" caddy hash-password)

            if [ -n "$PASSWORD_HASH" ] && [[ "$PASSWORD_HASH" != *"Error"* ]]; then
                # Docker Composeで使用するため、$を$$にエスケープ
                basic_auth_hash=$(echo "$PASSWORD_HASH" | sed 's/\$/\$\$/g')
                echo "✅ パスワードハッシュを生成しました。"
            else
                echo "⚠️  パスワードハッシュの生成に失敗しました。"
                echo "   Basic認証なしで.envを作成します。"
                basic_user=""
            fi
        fi
    fi

    # .envファイルを作成（平文パスワードは書き込まない）
    echo ""
    echo "▶ .envファイルを作成中..."

    cat > .env <<'EOF'
# OpenClaw + Caddy 環境変数設定ファイル
# このファイルは setup-openclaw.sh によって自動生成されました
EOF
    # 各値を安全に追記（シェル展開を防止）
    {
        echo ""
        echo "# ドメイン設定"
        printf 'DOMAIN_NAME=%s\n' "$domain_name"
        printf 'SUBDOMAIN=%s\n' "$subdomain"
        echo ""
        echo "# SSL証明書設定"
        printf 'SSL_EMAIL=%s\n' "$ssl_email"
        echo ""
        echo "# GCP設定（Vertex AI）"
        printf 'GCP_PROJECT_ID=%s\n' "$gcp_project_id"
        printf 'GCP_CREDENTIALS_PATH=%s\n' "$gcp_cred_path"
        printf 'VERTEX_AI_LOCATION=%s\n' "$vertex_location"
    } >> .env

    # Basic認証の設定を追加（ハッシュのみ、平文パスワードは書かない）
    if [ -n "$basic_user" ] && [ -n "$basic_auth_hash" ]; then
        {
            echo ""
            echo "# Basic認証設定"
            printf 'BASIC_AUTH_USER=%s\n' "$basic_user"
            printf 'BASIC_AUTH_PASSWORD_HASH=%s\n' "$basic_auth_hash"
        } >> .env
    fi

    # .envファイルのパーミッションを制限
    chmod 600 .env

    echo "✅ .envファイルを作成しました（パーミッション: 600）"
fi

echo ""

# ============================================
# 既存.envのパスワードハッシュ未生成チェック
# ============================================
if [ -f .env ]; then
    # .envから安全に変数を読み取る関数（regex メタ文字を避けるため awk を使用）
    get_env_var() {
        awk -F= -v key="$1" '$1 == key { print substr($0, index($0,"=")+1); exit }' .env
    }

    # 既存.envに平文パスワードが残っている場合のみハッシュ生成（後方互換性）
    EXISTING_PASSWORD=$(get_env_var BASIC_AUTH_PASSWORD || true)
    EXISTING_HASH=$(get_env_var BASIC_AUTH_PASSWORD_HASH || true)

    if [ -n "$EXISTING_PASSWORD" ] && [ -z "$EXISTING_HASH" ]; then
        echo "⚠️  .envに平文パスワードが検出されました。ハッシュを生成して平文を削除します..."

        if docker info > /dev/null 2>&1; then
            CADDY_IMAGE="caddy:2.8.4"
            docker pull "$CADDY_IMAGE" >/dev/null 2>&1

            PASSWORD_HASH=$(printf '%s' "$EXISTING_PASSWORD" | docker run --rm -i "$CADDY_IMAGE" caddy hash-password)

            if [ -n "$PASSWORD_HASH" ] && [[ "$PASSWORD_HASH" != *"Error"* ]]; then
                cp .env .env.backup
                chmod 600 .env.backup
                ESCAPED_HASH=$(echo "$PASSWORD_HASH" | sed 's/\$/\$\$/g')

                TEMP_ENV=$(mktemp -p "$(pwd)")
                grep -v "^BASIC_AUTH_PASSWORD_HASH=" .env | grep -v "^BASIC_AUTH_PASSWORD=" > "$TEMP_ENV"
                printf 'BASIC_AUTH_PASSWORD_HASH=%s\n' "$ESCAPED_HASH" >> "$TEMP_ENV"
                chmod 600 "$TEMP_ENV"
                mv "$TEMP_ENV" .env

                echo "✅ ハッシュを生成し、平文パスワードを.envから削除しました。"
            else
                echo "⚠️  ハッシュ生成に失敗しました。手動で対応してください。"
            fi
        else
            echo "⚠️  Dockerが実行されていません。Docker起動後に再度実行してください。"
        fi
    fi

    # .envのパーミッションを確認・修正
    chmod 600 .env
fi

echo ""

# ============================================
# ディレクトリの作成
# ============================================
echo "▶ ディレクトリを作成中..."

mkdir -p workspace
echo "  ✓ workspace/"

mkdir -p credentials
chmod 700 credentials
echo "  ✓ credentials/ (パーミッション: 700)"

echo ""

# ============================================
# Docker ボリュームの作成
# ============================================
echo "▶ Dockerボリュームを作成中..."

if docker volume inspect openclaw_data &> /dev/null; then
    echo "  - openclaw_data: 既に存在します"
else
    docker volume create openclaw_data
    echo "  - openclaw_data: 作成しました"
fi

echo "▶ OpenClawの初期設定を作成中..."
docker run --rm -v openclaw_data:/data alpine sh -c 'echo "{\"gateway\": {\"bind\": \"0.0.0.0\", \"port\": 18789}}" > /data/openclaw.json && chown 1000:1000 /data/openclaw.json'
echo "✅ openclaw.json を作成しました"

if docker volume inspect caddy_data &> /dev/null; then
    echo "  - caddy_data: 既に存在します"
else
    docker volume create caddy_data
    echo "  - caddy_data: 作成しました"
fi

echo ""

# ============================================
# スクリプトに実行権限を付与
# ============================================
echo "▶ スクリプトに実行権限を付与中..."
chmod +x openclaw-backup.sh 2>/dev/null || true
chmod +x openclaw-restore.sh 2>/dev/null || true
echo "✅ 実行権限を付与しました。"

echo ""
echo "========================================="
echo "  セットアップが完了しました！"
echo "========================================="
echo ""
echo "次のステップ:"
echo "1. GCPサービスアカウントの鍵ファイルを配置してください:"
echo "   配置先: $(get_env_var GCP_CREDENTIALS_PATH 2>/dev/null || echo '/root/.config/gcloud/adc.json')"
echo ""
echo "2. DNSレコードを設定してください:"
echo "   タイプ: A"
echo "   名前: ${subdomain:-ai}"
echo "   値: VPSのIPアドレス"
echo ""
echo "3. ファイアウォールでポート80と443を開放してください:"
echo "   sudo ufw allow 80/tcp"
echo "   sudo ufw allow 443/tcp"
echo ""
echo "4. OpenClawを起動してください:"
echo "   docker compose up -d"
echo ""
echo "5. ログを確認してください:"
echo "   docker compose logs -f"
echo ""
echo "6. ブラウザでアクセスしてください:"
if [ -n "${subdomain:-}" ] && [ -n "${domain_name:-}" ]; then
    echo "   https://${subdomain}.${domain_name}/"
else
    echo "   https://ai.example.com/"
fi
echo ""
