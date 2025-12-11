#!/bin/bash

# n8nリストアスクリプト
# バックアップからn8nのデータとCaddyのSSL証明書を復元します

set -e

echo "==============================================="
echo "n8n リストアスクリプト"
echo "==============================================="
echo ""

# --------------------------------------------------
# 設定
# --------------------------------------------------

BACKUP_DIR=$HOME/n8n-backups
# !! IMPORTANT: Change this to your actual installation directory !!
N8N_DIR=/path/to/your/n8n-docker-caddy  # REPLACE THIS with your actual path

# --------------------------------------------------
# 引数チェック
# --------------------------------------------------

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <backup-date>"
    echo ""
    echo "例: $0 20250101-120000"
    echo ""
    echo "利用可能なバックアップ:"
    echo ""

    if [ -d "$BACKUP_DIR" ]; then
        # バックアップファイルのリストを日付順に表示
        ls -lht "$BACKUP_DIR"/n8n-data-*.tar.gz 2>/dev/null | awk '{print "  " $9}' | sed 's/.*n8n-data-//' | sed 's/.tar.gz//' || echo "  バックアップファイルが見つかりません。"
    else
        echo "  バックアップディレクトリが見つかりません: $BACKUP_DIR"
    fi
    echo ""
    exit 1
fi

BACKUP_DATE=$1

# --------------------------------------------------
# N8N_DIRの確認
# --------------------------------------------------

if [ "$N8N_DIR" = "/path/to/your/n8n-docker-caddy" ]; then
    echo "❌ エラー: N8N_DIRが設定されていません。"
    echo "   このスクリプトのN8N_DIR変数を実際のインストールディレクトリに変更してください。"
    echo "   例: N8N_DIR=/home/ubuntu/n8n-docker-caddy"
    exit 1
fi

if [ ! -d "$N8N_DIR" ]; then
    echo "❌ エラー: N8N_DIR ($N8N_DIR) が存在しません。"
    exit 1
fi

if [ ! -f "$N8N_DIR/compose.yml" ]; then
    echo "❌ エラー: $N8N_DIR/compose.yml が見つかりません。"
    exit 1
fi

# --------------------------------------------------
# バックアップファイルの確認
# --------------------------------------------------

N8N_BACKUP="$BACKUP_DIR/n8n-data-$BACKUP_DATE.tar.gz"
CADDY_BACKUP="$BACKUP_DIR/caddy-data-$BACKUP_DATE.tar.gz"

if [ ! -f "$N8N_BACKUP" ]; then
    echo "❌ エラー: n8nバックアップファイルが見つかりません: $N8N_BACKUP"
    exit 1
fi

if [ ! -f "$CADDY_BACKUP" ]; then
    echo "⚠️  警告: Caddyバックアップファイルが見つかりません: $CADDY_BACKUP"
    echo "   n8nデータのみを復元します。"
    RESTORE_CADDY=false
else
    RESTORE_CADDY=true
fi

# --------------------------------------------------
# Dockerの確認
# --------------------------------------------------

if ! docker info > /dev/null 2>&1; then
    echo "❌ エラー: Dockerが実行されていません。"
    exit 1
fi

# --------------------------------------------------
# 確認プロンプト
# --------------------------------------------------

echo "⚠️  警告: この操作は現在のn8nデータを完全に置き換えます。"
echo ""
echo "復元するバックアップ:"
echo "  📅 日時: $BACKUP_DATE"
echo "  📁 n8nデータ: $N8N_BACKUP"
if [ "$RESTORE_CADDY" = true ]; then
    echo "  📁 Caddyデータ: $CADDY_BACKUP"
fi
echo ""
echo "現在のデータは失われます。続行しますか？ (yes/no)"
read -r CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ リストアをキャンセルしました。"
    exit 0
fi

echo ""

# --------------------------------------------------
# リストア実行
# --------------------------------------------------

# n8nを停止
echo "⏸️  n8nを停止しています..."
cd "$N8N_DIR" && docker compose down || {
    echo "❌ n8nの停止に失敗しました。"
    exit 1
}
echo "✅ n8nを停止しました。"
echo ""

# 既存ボリュームを削除して再作成
echo "🗑️  既存のn8nボリュームを削除しています..."
docker volume rm n8n_data 2>/dev/null || true
docker volume create n8n_data
echo "✅ n8nボリュームを再作成しました。"
echo ""

# n8nデータを復元
echo "💾 n8nデータを復元しています..."
docker run --rm -v n8n_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar xzf /backup/n8n-data-$BACKUP_DATE.tar.gz -C /data || {
    echo "❌ n8nデータの復元に失敗しました。"
    exit 1
}
echo "✅ n8nデータを復元しました。"
echo ""

# Caddyデータを復元（ファイルが存在する場合）
if [ "$RESTORE_CADDY" = true ]; then
    echo "🗑️  既存のCaddyボリュームを削除しています..."
    docker volume rm caddy_data 2>/dev/null || true
    docker volume create caddy_data
    echo "✅ Caddyボリュームを再作成しました。"
    echo ""

    echo "🔐 Caddyデータ（SSL証明書）を復元しています..."
    docker run --rm -v caddy_data:/data -v "$BACKUP_DIR":/backup alpine \
        tar xzf /backup/caddy-data-$BACKUP_DATE.tar.gz -C /data || {
        echo "❌ Caddyデータの復元に失敗しました。"
        exit 1
    }
    echo "✅ Caddyデータを復元しました。"
    echo ""
fi

# n8nを再起動
echo "▶️  n8nを起動しています..."
cd "$N8N_DIR" && docker compose up -d || {
    echo "❌ n8nの起動に失敗しました。"
    exit 1
}
echo "✅ n8nを起動しました。"
echo ""

# 起動状態を確認
echo "⏳ サービスの起動を待っています..."
sleep 10

echo "📊 サービスの状態:"
cd "$N8N_DIR" && docker compose ps
echo ""

echo "==============================================="
echo "✅ リストアが完了しました！"
echo "==============================================="
echo ""
echo "復元されたバックアップ: $BACKUP_DATE"
echo ""
echo "次のステップ:"
echo "1. サービスが正常に起動しているか確認:"
echo "   docker compose logs -f"
echo ""
echo "2. ブラウザでn8nにアクセスして動作確認"
echo ""
