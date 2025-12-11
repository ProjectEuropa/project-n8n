#!/bin/bash
# n8nバックアップスクリプト
# n8nのデータとCaddyのデータ（SSL証明書含む）をバックアップします

set -e

# --------------------------------------------------
# !! 重要な警告 !!
# 以下のN8N_DIRを実際のインストールディレクトリに変更する必要があります
# これは compose.yml が配置されている絶対パスである必要があります
# 例: N8N_DIR=/home/ubuntu/n8n-docker-caddy
# このパスが正しくない場合、バックアップは失敗します！
# --------------------------------------------------

# バックアップ保存先
BACKUP_DIR=$HOME/n8n-backups

# !! 重要: これを実際のインストールディレクトリに変更してください !!
N8N_DIR=/path/to/your/n8n-docker-caddy  # このパスを実際のパスに置き換えてください

# タイムスタンプ
DATE=$(date +%Y%m%d-%H%M%S)

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "  n8n バックアップスクリプト"
echo "========================================="
echo ""

# N8N_DIRの検証
if [ "$N8N_DIR" = "/path/to/your/n8n-docker-caddy" ]; then
    echo -e "${RED}エラー: N8N_DIRが設定されていません${NC}"
    echo ""
    echo "このスクリプトを使用する前に、スクリプト内のN8N_DIR変数を"
    echo "実際のn8nインストールディレクトリに変更してください。"
    echo ""
    echo "例: N8N_DIR=/home/ubuntu/n8n-docker-caddy"
    echo ""
    exit 1
fi

if [ ! -d "$N8N_DIR" ]; then
    echo -e "${RED}エラー: N8N_DIR '$N8N_DIR' が存在しません${NC}"
    echo "正しいディレクトリパスを設定してください。"
    exit 1
fi

if [ ! -f "$N8N_DIR/compose.yml" ]; then
    echo -e "${RED}エラー: '$N8N_DIR/compose.yml' が見つかりません${NC}"
    echo "N8N_DIRが正しいディレクトリを指していることを確認してください。"
    exit 1
fi

# エラーハンドリング: n8nサービスを再開する関数
function error_handler {
    echo -e "${RED}エラー: バックアップが失敗しました${NC}"
    # n8nが停止している可能性があるので、再開を試みる
    if [ -d "$N8N_DIR" ] && [ -f "$N8N_DIR/compose.yml" ]; then
        echo "n8nサービスを再開しようとしています..."
        cd "$N8N_DIR" && docker compose start n8n || echo -e "${YELLOW}n8nサービスの再開に失敗しました。手動で確認してください。${NC}"
    fi
    exit 1
}
trap error_handler ERR INT TERM

# バックアップディレクトリを作成
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}✓${NC} バックアップディレクトリ: $BACKUP_DIR"
echo ""

# ディスクスペースチェック（最低2GBの空き容量が必要）
available_space=$(df -BG "$BACKUP_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$available_space" -lt 2 ]; then
    echo -e "${RED}エラー: ディスクスペースが不足しています${NC}"
    echo "バックアップディレクトリ ($BACKUP_DIR) に最低2GBの空き容量が必要です。"
    echo "現在の空き容量: ${available_space}GB"
    exit 1
fi
echo -e "${GREEN}✓${NC} ディスクスペース確認: ${available_space}GB 利用可能"
echo ""

# n8nサービスを停止（データ整合性のため）
echo "▶ n8nサービスを停止中..."
cd "$N8N_DIR"
if docker compose stop n8n; then
    echo -e "${GREEN}✓${NC} n8nサービスを停止しました"
    # データが完全に書き込まれるまで待機
    sleep 2
else
    echo -e "${RED}✗${NC} n8nサービスの停止に失敗しました"
    exit 1
fi
echo ""

# n8nデータをバックアップ
echo "▶ n8nデータをバックアップ中..."
BACKUP_N8N="$BACKUP_DIR/n8n-data-$DATE.tar.gz"
if docker run --rm -v n8n_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar czf /backup/n8n-data-$DATE.tar.gz -C /data .; then
    chmod 600 "$BACKUP_N8N"
    echo -e "${GREEN}✓${NC} n8nデータのバックアップ完了: $(basename "$BACKUP_N8N")"
    # ファイルサイズを表示
    size=$(du -h "$BACKUP_N8N" | cut -f1)
    echo "  サイズ: $size"
else
    echo -e "${RED}✗${NC} n8nデータのバックアップに失敗しました"
    exit 1
fi
echo ""

# Caddyデータをバックアップ（SSL証明書含む）
echo "▶ Caddyデータをバックアップ中..."
BACKUP_CADDY="$BACKUP_DIR/caddy-data-$DATE.tar.gz"
if docker run --rm -v caddy_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar czf /backup/caddy-data-$DATE.tar.gz -C /data .; then
    chmod 600 "$BACKUP_CADDY"
    echo -e "${GREEN}✓${NC} Caddyデータのバックアップ完了: $(basename "$BACKUP_CADDY")"
    # ファイルサイズを表示
    size=$(du -h "$BACKUP_CADDY" | cut -f1)
    echo "  サイズ: $size"
else
    echo -e "${RED}✗${NC} Caddyデータのバックアップに失敗しました"
    exit 1
fi
echo ""

# n8nサービスを再開
echo "▶ n8nサービスを再開中..."
cd "$N8N_DIR"
if docker compose start n8n; then
    echo -e "${GREEN}✓${NC} n8nサービスを再開しました"
else
    echo -e "${YELLOW}⚠${NC} n8nサービスの再開に失敗しました。手動で起動してください: docker compose start n8n"
fi
echo ""

# 古いバックアップを削除（7日以上古いもの）
echo "▶ 古いバックアップを削除中（7日以上前）..."
deleted_n8n=$(find "$BACKUP_DIR" -name "n8n-data-*.tar.gz" -mtime +7 -delete -print | wc -l)
deleted_caddy=$(find "$BACKUP_DIR" -name "caddy-data-*.tar.gz" -mtime +7 -delete -print | wc -l)
deleted_count=$((deleted_n8n + deleted_caddy))
if [ "$deleted_count" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $deleted_count 個の古いバックアップを削除しました (n8n: $deleted_n8n, caddy: $deleted_caddy)"
else
    echo "  削除対象のバックアップはありませんでした"
fi
echo ""

echo "========================================="
echo -e "${GREEN}  バックアップが完了しました！${NC}"
echo "========================================="
echo ""
echo "バックアップファイル:"
echo "  - $BACKUP_N8N"
echo "  - $BACKUP_CADDY"
echo ""
echo "バックアップ一覧を表示:"
echo "  ls -lh $BACKUP_DIR"
echo ""
echo "復元方法:"
echo "  ./n8n-restore.sh $DATE"
echo ""
