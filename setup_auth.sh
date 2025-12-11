#!/bin/bash

# Basic認証のセットアップスクリプト
# Caddyで使用するためのパスワードハッシュを生成します

set -e

echo "==============================================="
echo "Basic認証セットアップスクリプト"
echo "==============================================="
echo ""

# .envファイルの存在確認
if [ ! -f .env ]; then
    echo "❌ .envファイルが見つかりません。"
    echo "   .env.exampleをコピーして.envを作成してください:"
    echo "   cp .env.example .env"
    exit 1
fi

# .envから必要な変数を安全に読み込む
get_env_var() {
    grep "^$1=" .env | head -n 1 | cut -d'=' -f2-
}

BASIC_AUTH_USER=$(get_env_var BASIC_AUTH_USER)
BASIC_AUTH_PASSWORD=$(get_env_var BASIC_AUTH_PASSWORD)
SUBDOMAIN=$(get_env_var SUBDOMAIN)
DOMAIN_NAME=$(get_env_var DOMAIN_NAME)

# ユーザー名とパスワードの確認
if [ -z "$BASIC_AUTH_USER" ] || [ -z "$BASIC_AUTH_PASSWORD" ]; then
    echo "❌ .envファイルにBASIC_AUTH_USERとBASIC_AUTH_PASSWORDを設定してください。"
    exit 1
fi

echo "📝 現在の設定:"
echo "   ユーザー名: $BASIC_AUTH_USER"
echo "   パスワード: [非表示]"
echo ""

# Dockerが実行中か確認
if ! docker info > /dev/null 2>&1; then
    echo "❌ Dockerが実行されていません。Dockerを起動してください。"
    exit 1
fi

echo "🔐 パスワードのハッシュを生成しています..."

# compose.ymlからCaddyのバージョンを動的に取得
CADDY_IMAGE=$(grep -E '^\s*image:\s*caddy:' compose.yml | head -n 1 | sed 's/.*image:\s*//' | tr -d ' ')
# Caddyコンテナを使用してパスワードハッシュを生成（標準入力経由で安全に渡す）
PASSWORD_HASH=$(echo "$BASIC_AUTH_PASSWORD" | docker run --rm -i "${CADDY_IMAGE:-caddy:2.8.4}" caddy hash-password)

if [ -z "$PASSWORD_HASH" ]; then
    echo "❌ パスワードハッシュの生成に失敗しました。"
    exit 1
fi

echo "✅ パスワードハッシュを生成しました。"
echo ""

# .envファイルのバックアップを作成
cp .env .env.backup
echo "📁 .envのバックアップを作成しました (.env.backup)"

# .envファイルを更新（より堅牢な方法）
# 一時ファイルを使用して安全に更新
TEMP_ENV=$(mktemp)
# スクリプト終了時に一時ファイルを削除
trap 'rm -f "$TEMP_ENV"' EXIT

# 既存の行を削除して新しい行を追加（簡潔なロジック）
grep -v "^BASIC_AUTH_PASSWORD_HASH=" .env > "$TEMP_ENV"
echo "BASIC_AUTH_PASSWORD_HASH=$PASSWORD_HASH" >> "$TEMP_ENV"

# 一時ファイルを.envに移動
mv "$TEMP_ENV" .env

echo "✅ .envファイルを更新しました。"
echo ""

echo "==============================================="
echo "セットアップ完了！"
echo "==============================================="
echo ""
echo "次のステップ:"
echo "1. Docker Composeを起動:"
echo "   docker compose up -d"
echo ""
echo "2. ブラウザでアクセス:"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}"
echo ""
echo "3. ログイン情報:"
echo "   ユーザー名: $BASIC_AUTH_USER"
echo "   パスワード: [.envファイルのBASIC_AUTH_PASSWORDを確認]"
echo ""
echo "⚠️  注意事項:"
echo "- パスワードを変更した場合は、このスクリプトを再実行してください"
echo "- .envファイルは絶対にGitにコミットしないでください"
echo ""