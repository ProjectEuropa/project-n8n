#!/bin/bash
# n8nリストアスクリプト
# バックアップからn8nとCaddyのデータを復元します

set -e

# --------------------------------------------------
# !! 重要な警告 !!
# 以下のN8N_DIRを実際のインストールディレクトリに変更する必要があります
# これは compose.yml が配置されている絶対パスである必要があります
# 例: N8N_DIR=/home/ubuntu/n8n-docker-caddy
# このパスが正しくない場合、リストアは失敗します！
# --------------------------------------------------

# バックアップ保存先
BACKUP_DIR=$HOME/n8n-backups

# !! 重要: これを実際のインストールディレクトリに変更してください !!
N8N_DIR=/path/to/your/n8n-docker-caddy  # このパスを実際のパスに置き換えてください

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# エラーハンドリング
trap 'echo -e "${RED}エラー: リストアが失敗しました${NC}"; exit 1' ERR

echo "========================================="
echo "  n8n リストアスクリプト"
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

# バックアップディレクトリの確認
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}エラー: バックアップディレクトリ '$BACKUP_DIR' が存在しません${NC}"
    exit 1
fi

# 利用可能なバックアップを表示
echo "▶ 利用可能なバックアップ:"
echo ""

# n8nバックアップのリスト
n8n_backups=($(ls -1t "$BACKUP_DIR"/n8n-data-*.tar.gz 2>/dev/null || true))

if [ ${#n8n_backups[@]} -eq 0 ]; then
    echo -e "${RED}エラー: バックアップが見つかりません${NC}"
    echo "バックアップディレクトリ: $BACKUP_DIR"
    exit 1
fi

echo "番号  日時                    n8nデータ      Caddyデータ"
echo "----  --------------------  -------------  -------------"

declare -A backup_dates
index=1

for backup in "${n8n_backups[@]}"; do
    # ファイル名から日時を抽出（例: n8n-data-20250101-120000.tar.gz -> 20250101-120000）
    basename=$(basename "$backup")
    datetime=$(echo "$basename" | sed 's/^n8n-data-\(.*\)\.tar\.gz$/\1/')

    # 対応するCaddyバックアップの存在確認
    caddy_backup="$BACKUP_DIR/caddy-data-$datetime.tar.gz"

    # ファイルサイズを取得
    n8n_size=$(du -h "$backup" | cut -f1)
    caddy_status="missing"
    if [ -f "$caddy_backup" ]; then
        caddy_size=$(du -h "$caddy_backup" | cut -f1)
        caddy_status="$caddy_size"
    fi

    # フォーマットされた日時（YYYY-MM-DD HH:MM:SS）
    formatted_date=$(echo "$datetime" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

    printf "%-4s  %-20s  %-13s  %-13s\n" "$index" "$formatted_date" "$n8n_size" "$caddy_status"

    backup_dates[$index]=$datetime
    index=$((index + 1))
done

echo ""

# バックアップの選択
if [ -n "$1" ]; then
    # コマンドライン引数で日時が指定された場合
    RESTORE_DATE="$1"
    echo -e "${BLUE}指定されたバックアップ: $RESTORE_DATE${NC}"
else
    # インタラクティブに選択
    read -p "復元するバックアップの番号を入力してください（1-$((index-1))）: " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge "$index" ]; then
        echo -e "${RED}エラー: 無効な選択です${NC}"
        exit 1
    fi

    RESTORE_DATE="${backup_dates[$selection]}"
    echo -e "${BLUE}選択されたバックアップ: $RESTORE_DATE${NC}"
fi

# バックアップファイルの確認
N8N_BACKUP="$BACKUP_DIR/n8n-data-$RESTORE_DATE.tar.gz"
CADDY_BACKUP="$BACKUP_DIR/caddy-data-$RESTORE_DATE.tar.gz"

if [ ! -f "$N8N_BACKUP" ]; then
    echo -e "${RED}エラー: n8nバックアップファイルが見つかりません: $N8N_BACKUP${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}⚠ 警告: この操作は既存のn8nデータを上書きします！${NC}"
echo ""
read -p "本当に復元しますか？ (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "復元をキャンセルしました。"
    exit 0
fi

echo ""

# n8nを停止
echo "▶ n8nサービスを停止中..."
cd "$N8N_DIR"
if docker compose down; then
    echo -e "${GREEN}✓${NC} n8nサービスを停止しました"
else
    echo -e "${RED}✗${NC} n8nサービスの停止に失敗しました"
    exit 1
fi
echo ""

# n8nボリュームを削除して再作成
echo "▶ n8nデータボリュームを再作成中..."
docker volume rm n8n_data 2>/dev/null || true
docker volume create n8n_data
echo -e "${GREEN}✓${NC} n8nデータボリュームを再作成しました"
echo ""

# n8nデータを復元
echo "▶ n8nデータを復元中..."
if docker run --rm -v n8n_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar xzf /backup/n8n-data-$RESTORE_DATE.tar.gz -C /data; then
    echo -e "${GREEN}✓${NC} n8nデータの復元完了"
else
    echo -e "${RED}✗${NC} n8nデータの復元に失敗しました"
    exit 1
fi
echo ""

# Caddyデータを復元（存在する場合）
if [ -f "$CADDY_BACKUP" ]; then
    echo "▶ Caddyデータを復元中..."
    docker volume rm caddy_data 2>/dev/null || true
    docker volume create caddy_data

    if docker run --rm -v caddy_data:/data -v "$BACKUP_DIR":/backup alpine \
        tar xzf /backup/caddy-data-$RESTORE_DATE.tar.gz -C /data; then
        echo -e "${GREEN}✓${NC} Caddyデータの復元完了"
    else
        echo -e "${YELLOW}⚠${NC} Caddyデータの復元に失敗しました（SSL証明書は再取得されます）"
    fi
else
    echo -e "${YELLOW}⚠${NC} Caddyバックアップが見つかりません（SSL証明書は再取得されます）"
fi
echo ""

# n8nを再起動
echo "▶ n8nサービスを起動中..."
cd "$N8N_DIR"
if docker compose up -d; then
    echo -e "${GREEN}✓${NC} n8nサービスを起動しました"
else
    echo -e "${RED}✗${NC} n8nサービスの起動に失敗しました"
    exit 1
fi
echo ""

# サービスの状態を確認
echo "▶ サービスの状態を確認中..."
sleep 3
docker compose ps
echo ""

echo "========================================="
echo -e "${GREEN}  リストアが完了しました！${NC}"
echo "========================================="
echo ""
echo "復元されたバックアップ: $RESTORE_DATE"
echo ""
echo "次のステップ:"
echo "1. サービスが正常に起動しているか確認:"
echo "   docker compose ps"
echo ""
echo "2. ログを確認:"
echo "   docker compose logs -f"
echo ""
echo "3. ブラウザでアクセスして動作確認:"
echo "   https://n8n.example.com"
echo ""
