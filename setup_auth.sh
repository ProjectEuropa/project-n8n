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

# 現在の設定を読み込む
source .env

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

# Caddyコンテナを使用してパスワードハッシュを生成
PASSWORD_HASH=$(docker run --rm caddy:2.8.4 caddy hash-password --plaintext "$BASIC_AUTH_PASSWORD")

if [ -z "$PASSWORD_HASH" ]; then
    echo "❌ パスワードハッシュの生成に失敗しました。"
    exit 1
fi

echo "✅ パスワードハッシュを生成しました。"
echo ""

# .envファイルのバックアップを作成
cp .env .env.backup
echo "📁 .envのバックアップを作成しました (.env.backup)"

# .envファイルを更新
if grep -q "^BASIC_AUTH_PASSWORD_HASH=" .env; then
    # 既存の行を更新（macOSとLinux両方で動作）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^BASIC_AUTH_PASSWORD_HASH=.*|BASIC_AUTH_PASSWORD_HASH=$PASSWORD_HASH|" .env
    else
        sed -i "s|^BASIC_AUTH_PASSWORD_HASH=.*|BASIC_AUTH_PASSWORD_HASH=$PASSWORD_HASH|" .env
    fi
else
    # 新しい行を追加
    echo "BASIC_AUTH_PASSWORD_HASH=$PASSWORD_HASH" >> .env
fi

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