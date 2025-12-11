#!/bin/bash

# n8n自動バックアップスクリプト
# n8nのデータとCaddyのSSL証明書をバックアップします

set -e

# --------------------------------------------------
# !! CRITICAL WARNING !!
# You MUST change N8N_DIR below to your actual installation directory
# This should be the absolute path where your compose.yml is located
# Example: N8N_DIR=/home/ubuntu/n8n-docker-caddy
# The backup will FAIL if this path is incorrect!
# --------------------------------------------------

BACKUP_DIR=$HOME/n8n-backups
# !! IMPORTANT: Change this to your actual installation directory !!
N8N_DIR=/path/to/your/n8n-docker-caddy  # REPLACE THIS with your actual path
DATE=$(date +%Y%m%d-%H%M%S)

echo "==============================================="
echo "n8n バックアップスクリプト"
echo "==============================================="
echo ""

# N8N_DIRが正しく設定されているか確認
if [ "$N8N_DIR" = "/path/to/your/n8n-docker-caddy" ]; then
    echo "❌ エラー: N8N_DIRが設定されていません。"
    echo "   このスクリプトのN8N_DIR変数を実際のインストールディレクトリに変更してください。"
    echo "   例: N8N_DIR=/home/ubuntu/n8n-docker-caddy"
    exit 1
fi

# N8N_DIRが存在するか確認
if [ ! -d "$N8N_DIR" ]; then
    echo "❌ エラー: N8N_DIR ($N8N_DIR) が存在しません。"
    echo "   正しいパスを設定してください。"
    exit 1
fi

# compose.ymlが存在するか確認
if [ ! -f "$N8N_DIR/compose.yml" ]; then
    echo "❌ エラー: $N8N_DIR/compose.yml が見つかりません。"
    echo "   N8N_DIRが正しいパスか確認してください。"
    exit 1
fi

# Dockerが実行中か確認
if ! docker info > /dev/null 2>&1; then
    echo "❌ エラー: Dockerが実行されていません。"
    exit 1
fi

# バックアップディレクトリを作成
mkdir -p "$BACKUP_DIR"

echo "📁 バックアップディレクトリ: $BACKUP_DIR"
echo "📁 n8nインストールディレクトリ: $N8N_DIR"
echo "📅 バックアップ日時: $DATE"
echo ""

# n8nサービスを停止（データ整合性のため）
echo "⏸️  n8nサービスを停止しています..."
cd "$N8N_DIR" && docker compose stop n8n || {
    echo "❌ n8nの停止に失敗しました。"
    exit 1
}

echo "✅ n8nを停止しました。"
echo ""

# n8nデータをバックアップ
echo "💾 n8nデータをバックアップしています..."
docker run --rm -v n8n_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar czf /backup/n8n-data-$DATE.tar.gz -C /data . || {
    echo "❌ n8nデータのバックアップに失敗しました。"
    # n8nを再開してから終了
    cd "$N8N_DIR" && docker compose start n8n
    exit 1
}

echo "✅ n8nデータをバックアップしました: n8n-data-$DATE.tar.gz"
echo ""

# Caddyデータをバックアップ（SSL証明書含む）
echo "🔐 Caddyデータ（SSL証明書）をバックアップしています..."
docker run --rm -v caddy_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar czf /backup/caddy-data-$DATE.tar.gz -C /data . || {
    echo "❌ Caddyデータのバックアップに失敗しました。"
    # n8nを再開してから終了
    cd "$N8N_DIR" && docker compose start n8n
    exit 1
}

echo "✅ Caddyデータをバックアップしました: caddy-data-$DATE.tar.gz"
echo ""

# n8nサービスを再開
echo "▶️  n8nサービスを再開しています..."
cd "$N8N_DIR" && docker compose start n8n || {
    echo "❌ n8nの再開に失敗しました。手動で 'docker compose start n8n' を実行してください。"
    exit 1
}

echo "✅ n8nを再開しました。"
echo ""

# 7日以上古いバックアップを削除
echo "🗑️  古いバックアップを削除しています（7日以上前）..."
DELETED_COUNT=$(find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -type f | wc -l)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -type f -delete

if [ "$DELETED_COUNT" -gt 0 ]; then
    echo "✅ $DELETED_COUNT 個の古いバックアップを削除しました。"
else
    echo "ℹ️  削除する古いバックアップはありませんでした。"
fi
echo ""

# バックアップファイルのサイズを表示
echo "📊 バックアップファイルのサイズ:"
du -sh "$BACKUP_DIR"/n8n-data-$DATE.tar.gz "$BACKUP_DIR"/caddy-data-$DATE.tar.gz

echo ""
echo "==============================================="
echo "✅ バックアップが完了しました！"
echo "==============================================="
echo ""
echo "バックアップファイル:"
echo "  - n8n-data-$DATE.tar.gz"
echo "  - caddy-data-$DATE.tar.gz"
echo ""
echo "バックアップの場所: $BACKUP_DIR"
echo ""
