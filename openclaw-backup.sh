#!/bin/bash
# OpenClawバックアップスクリプト
# OpenClawのデータとCaddyのデータ（SSL証明書含む）をバックアップします

set -euo pipefail

# --------------------------------------------------
# !! 重要な警告 !!
# 以下のAPP_DIRを実際のインストールディレクトリに変更する必要があります
# これは compose.yml が配置されている絶対パスである必要があります
# 例: APP_DIR=/home/ubuntu/project-n8n
# このパスが正しくない場合、バックアップは失敗します！
# --------------------------------------------------

# バックアップ保存先
BACKUP_DIR=$HOME/openclaw-backups

# !! 重要: これを実際のインストールディレクトリに変更してください !!
APP_DIR=/path/to/your/project-n8n  # このパスを実際のパスに置き換えてください

# タイムスタンプ
DATE=$(date +%Y%m%d-%H%M%S)

# カラー出力（ターミナルでない場合は無効化）
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

echo "========================================="
echo "  OpenClaw バックアップスクリプト"
echo "========================================="
echo ""

# APP_DIRの検証
if [ "$APP_DIR" = "/path/to/your/project-n8n" ]; then
    echo -e "${RED}エラー: APP_DIRが設定されていません${NC}"
    echo ""
    echo "このスクリプトを使用する前に、スクリプト内のAPP_DIR変数を"
    echo "実際のインストールディレクトリに変更してください。"
    echo ""
    echo "例: APP_DIR=/home/ubuntu/project-n8n"
    echo ""
    exit 1
fi

if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}エラー: APP_DIR '$APP_DIR' が存在しません${NC}"
    echo "正しいディレクトリパスを設定してください。"
    exit 1
fi

if [ ! -f "$APP_DIR/compose.yml" ]; then
    echo -e "${RED}エラー: '$APP_DIR/compose.yml' が見つかりません${NC}"
    echo "APP_DIRが正しいディレクトリを指していることを確認してください。"
    exit 1
fi

# エラーハンドリング: openclawサービスを再開する関数
function error_handler {
    echo -e "${RED}エラー: バックアップが失敗しました${NC}"
    if [ -d "$APP_DIR" ] && [ -f "$APP_DIR/compose.yml" ]; then
        echo "OpenClawサービスを再開しようとしています..."
        (cd "$APP_DIR" && docker compose start openclaw) || echo -e "${YELLOW}OpenClawサービスの再開に失敗しました。手動で確認してください。${NC}"
    fi
    exit 1
}
trap error_handler ERR INT TERM

# バックアップディレクトリを作成
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}✓${NC} バックアップディレクトリ: $BACKUP_DIR"
echo ""

# ディスクスペースチェック（最低2GBの空き容量が必要）
available_space_kb=$(df -k "$BACKUP_DIR" | tail -1 | awk '{print $4}')
available_space_gb=$((available_space_kb / 1024 / 1024))
if [ "$available_space_gb" -lt 2 ]; then
    echo -e "${RED}エラー: ディスクスペースが不足しています${NC}"
    echo "バックアップディレクトリ ($BACKUP_DIR) に最低2GBの空き容量が必要です。"
    echo "現在の空き容量: ${available_space_gb}GB"
    exit 1
fi
echo -e "${GREEN}✓${NC} ディスクスペース確認: ${available_space_gb}GB 利用可能"
echo ""

# OpenClawサービスを停止（データ整合性のため）
echo "▶ OpenClawサービスを停止中..."
if (cd "$APP_DIR" && docker compose stop openclaw); then
    echo -e "${GREEN}✓${NC} OpenClawサービスを停止しました"
    sleep 2
else
    echo -e "${RED}✗${NC} OpenClawサービスの停止に失敗しました"
    error_handler
fi
echo ""

# OpenClawデータをバックアップ
echo "▶ OpenClawデータをバックアップ中..."
BACKUP_OPENCLAW="$BACKUP_DIR/openclaw-data-$DATE.tar.gz"
if docker run --rm -v openclaw_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar czf "/backup/openclaw-data-$DATE.tar.gz" -C /data .; then
    chmod 600 "$BACKUP_OPENCLAW"
    echo -e "${GREEN}✓${NC} OpenClawデータのバックアップ完了: $(basename "$BACKUP_OPENCLAW")"
    size=$(du -h "$BACKUP_OPENCLAW" | cut -f1)
    echo "  サイズ: $size"
else
    echo -e "${RED}✗${NC} OpenClawデータのバックアップに失敗しました"
    exit 1
fi
echo ""

# ワークスペースをバックアップ
echo "▶ ワークスペースをバックアップ中..."
BACKUP_WORKSPACE="$BACKUP_DIR/workspace-$DATE.tar.gz"
if [ -d "$APP_DIR/workspace" ]; then
    if tar czf "$BACKUP_WORKSPACE" -C "$APP_DIR" workspace; then
        chmod 600 "$BACKUP_WORKSPACE"
        echo -e "${GREEN}✓${NC} ワークスペースのバックアップ完了: $(basename "$BACKUP_WORKSPACE")"
        size=$(du -h "$BACKUP_WORKSPACE" | cut -f1)
        echo "  サイズ: $size"
    else
        echo -e "${YELLOW}⚠${NC} ワークスペースのバックアップに失敗しました"
    fi
else
    echo "  ワークスペースディレクトリが存在しません。スキップします。"
fi
echo ""

# Caddyデータをバックアップ（SSL証明書含む）
echo "▶ Caddyデータをバックアップ中..."
BACKUP_CADDY="$BACKUP_DIR/caddy-data-$DATE.tar.gz"
if docker run --rm -v caddy_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar czf "/backup/caddy-data-$DATE.tar.gz" -C /data .; then
    chmod 600 "$BACKUP_CADDY"
    echo -e "${GREEN}✓${NC} Caddyデータのバックアップ完了: $(basename "$BACKUP_CADDY")"
    size=$(du -h "$BACKUP_CADDY" | cut -f1)
    echo "  サイズ: $size"
else
    echo -e "${RED}✗${NC} Caddyデータのバックアップに失敗しました"
    exit 1
fi
echo ""

# OpenClawサービスを再開
echo "▶ OpenClawサービスを再開中..."
if (cd "$APP_DIR" && docker compose start openclaw); then
    echo -e "${GREEN}✓${NC} OpenClawサービスを再開しました"
else
    echo -e "${YELLOW}⚠${NC} OpenClawサービスの再開に失敗しました。手動で起動してください: docker compose start openclaw"
fi
echo ""

# 古いバックアップを削除（7日以上古いもの）
echo "▶ 古いバックアップを削除中（7日以上前）..."
deleted_openclaw=$(find "$BACKUP_DIR" -name "openclaw-data-*.tar.gz" -mtime +7 -delete -print | wc -l)
deleted_workspace=$(find "$BACKUP_DIR" -name "workspace-*.tar.gz" -mtime +7 -delete -print | wc -l)
deleted_caddy=$(find "$BACKUP_DIR" -name "caddy-data-*.tar.gz" -mtime +7 -delete -print | wc -l)
deleted_count=$((deleted_openclaw + deleted_workspace + deleted_caddy))
if [ "$deleted_count" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $deleted_count 個の古いバックアップを削除しました"
else
    echo "  削除対象のバックアップはありませんでした"
fi
echo ""

echo "========================================="
echo -e "${GREEN}  バックアップが完了しました！${NC}"
echo "========================================="
echo ""
echo "バックアップファイル:"
echo "  - $BACKUP_OPENCLAW"
echo "  - $BACKUP_WORKSPACE"
echo "  - $BACKUP_CADDY"
echo ""
echo "バックアップ一覧を表示:"
echo "  ls -lh $BACKUP_DIR"
echo ""
echo "復元方法:"
echo "  ./openclaw-restore.sh $DATE"
echo ""
