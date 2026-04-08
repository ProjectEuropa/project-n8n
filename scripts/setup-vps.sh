#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${APP_DIR}/.env"

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

validate_input() {
    local value="$1"
    local name="$2"
    if [[ "$value" =~ [$'\n\r\t'] ]] || [[ "$value" == *$'\0'* ]]; then
        echo -e "${RED}${name} に改行や制御文字は使えません。${NC}"
        return 1
    fi
    return 0
}

get_env_var() {
    local key="$1"
    local default_value="${2:-}"
    if [ ! -f "$ENV_FILE" ]; then
        printf '%s' "$default_value"
        return 0
    fi
    local value
    value=$(awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$ENV_FILE")
    printf '%s' "${value:-$default_value}"
}

echo "========================================="
echo "  OpenFang + Caddy セットアップ"
echo "========================================="
echo ""

echo "▶ Docker の確認"
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Docker がインストールされていません。${NC}"
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}docker compose が利用できません。${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker / Compose を確認しました"
echo ""

if [ "$(uname -s)" = "Linux" ] && command -v free >/dev/null 2>&1; then
    echo "▶ Swap の確認"
    current_swap=$(free -m | awk '/^Swap:/ {print $2}')
    if [ "${current_swap:-0}" -lt 1024 ] 2>/dev/null; then
        echo "  現在の Swap: ${current_swap:-0}MB"
        read -r -p "Swap を追加しますか？ (y/N): " add_swap
        if [[ "$add_swap" =~ ^[Yy]$ ]]; then
            swap_size=${SWAP_SIZE:-4G}
            sudo fallocate -l "$swap_size" /swapfile
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile
            if ! grep -q '/swapfile' /etc/fstab; then
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
            fi
            echo -e "${GREEN}✓${NC} Swap ${swap_size} を追加しました"
        fi
    else
        echo -e "${GREEN}✓${NC} Swap は十分です (${current_swap}MB)"
    fi
    echo ""
fi

recreate_env=false
if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}.env が既に存在します。${NC}"
    read -r -p ".env を再作成しますか？ (y/N): " recreate_answer
    if [[ "$recreate_answer" =~ ^[Yy]$ ]]; then
        recreate_env=true
    fi
else
    recreate_env=true
fi

if [ "$recreate_env" = true ]; then
    echo "▶ .env を作成"

    while true; do
        read -r -p "ドメイン名 (例: example.com): " domain_name
        [ -n "$domain_name" ] || { echo "必須です。"; continue; }
        validate_input "$domain_name" "ドメイン名" && break
    done

    read -r -p "サブドメイン [ai]: " subdomain
    subdomain=${subdomain:-ai}
    validate_input "$subdomain" "サブドメイン"

    while true; do
        read -r -p "SSL 通知メールアドレス: " ssl_email
        [ -n "$ssl_email" ] || { echo "必須です。"; continue; }
        validate_input "$ssl_email" "メールアドレス" && break
    done

    while true; do
        read -r -p "GCP プロジェクト ID: " gcp_project_id
        [ -n "$gcp_project_id" ] || { echo "必須です。"; continue; }
        validate_input "$gcp_project_id" "GCP プロジェクト ID" && break
    done

    read -r -p "GCP 認証ファイルパス [./credentials/adc.json]: " gcp_cred_path
    gcp_cred_path=${gcp_cred_path:-./credentials/adc.json}
    validate_input "$gcp_cred_path" "GCP 認証ファイルパス"

    read -r -p "Vertex AI リージョン [asia-northeast1]: " vertex_location
    vertex_location=${vertex_location:-asia-northeast1}
    validate_input "$vertex_location" "Vertex AI リージョン"

    echo "対象アーキテクチャの OpenFang SHA-256 を入力してください。"
    echo "未使用アーキテクチャ側は空でも構いません。"
    read -r -p "OPENFANG_SHA256_AMD64: " openfang_sha256_amd64
    validate_input "$openfang_sha256_amd64" "OPENFANG_SHA256_AMD64"
    read -r -p "OPENFANG_SHA256_ARM64: " openfang_sha256_arm64
    validate_input "$openfang_sha256_arm64" "OPENFANG_SHA256_ARM64"

    read -r -p "許可 IP (空で無効): " allowed_ips
    validate_input "$allowed_ips" "許可 IP"

    read -r -p "trusted_proxies (空でデフォルト): " trusted_proxies
    validate_input "$trusted_proxies" "trusted_proxies"

    read -r -p "Basic 認証を有効にしますか？ (Y/n): " enable_basic_auth
    basic_user=""
    basic_auth_hash=""
    if [[ ! "$enable_basic_auth" =~ ^[Nn]$ ]]; then
        read -r -p "Basic 認証ユーザー名 [admin]: " basic_user
        basic_user=${basic_user:-admin}
        validate_input "$basic_user" "Basic 認証ユーザー名"

        while true; do
            read -r -s -p "Basic 認証パスワード: " basic_password
            echo ""
            [ -n "$basic_password" ] || { echo "必須です。"; continue; }
            validate_input "$basic_password" "Basic 認証パスワード" && break
        done

        password_hash=$(printf '%s' "$basic_password" | docker run --rm -i caddy:2.8.4 caddy hash-password)
        basic_auth_hash=$(printf '%s' "$password_hash" | sed 's/\$/\$\$/g')
    fi

    cat > "$ENV_FILE" <<EOF
# OpenFang + Caddy 環境変数設定

DOMAIN_NAME=${domain_name}
SUBDOMAIN=${subdomain}
SSL_EMAIL=${ssl_email}
TRUSTED_PROXIES=${trusted_proxies}
ALLOWED_IPS=${allowed_ips}

GCP_PROJECT_ID=${gcp_project_id}
GCP_CREDENTIALS_PATH=${gcp_cred_path}
VERTEX_AI_LOCATION=${vertex_location}
OPENFANG_SHA256_AMD64=${openfang_sha256_amd64}
OPENFANG_SHA256_ARM64=${openfang_sha256_arm64}

OPENFANG_DATA_VOLUME=openfang_data
CADDY_DATA_VOLUME=caddy_data
CADDY_CONFIG_VOLUME=caddy_config
EOF

    if [ -n "$basic_user" ] && [ -n "$basic_auth_hash" ]; then
        {
            echo ""
            echo "BASIC_AUTH_USER=${basic_user}"
            echo "BASIC_AUTH_PASSWORD_HASH=${basic_auth_hash}"
        } >> "$ENV_FILE"
    fi

    chmod 600 "$ENV_FILE"
    echo -e "${GREEN}✓${NC} .env を作成しました"
    echo ""
fi

echo "▶ ディレクトリ作成"
mkdir -p "${APP_DIR}/workspace"
mkdir -p "${APP_DIR}/credentials"
chmod 700 "${APP_DIR}/credentials"
echo -e "${GREEN}✓${NC} workspace/ credentials/ を確認しました"
echo ""

openfang_volume=$(get_env_var OPENFANG_DATA_VOLUME openfang_data)
caddy_data_volume=$(get_env_var CADDY_DATA_VOLUME caddy_data)

echo "▶ Docker ボリューム作成"
docker volume inspect "$openfang_volume" >/dev/null 2>&1 || docker volume create "$openfang_volume" >/dev/null
docker volume inspect "$caddy_data_volume" >/dev/null 2>&1 || docker volume create "$caddy_data_volume" >/dev/null
echo -e "${GREEN}✓${NC} ${openfang_volume}, ${caddy_data_volume} を確認しました"
echo ""

chmod +x "${APP_DIR}/scripts/"*.sh 2>/dev/null || true

echo "次の手順:"
echo "  1. GCP キーを配置: $(get_env_var GCP_CREDENTIALS_PATH ./credentials/adc.json)"
echo "  2. DNS と 80/443 を開放"
echo "  3. 起動: docker compose up -d --build"
