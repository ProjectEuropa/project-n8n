#!/bin/bash
# OpenClawリストアスクリプト
# バックアップからOpenClawとCaddyのデータを復元します

set -euo pipefail

# --------------------------------------------------
# !! 重要な警告 !!
# 以下のAPP_DIRを実際のインストールディレクトリに変更する必要があります
# これは compose.yml が配置されている絶対パスである必要があります
# 例: APP_DIR=/home/ubuntu/project-n8n
# このパスが正しくない場合、リストアは失敗します！
# --------------------------------------------------

# バックアップ保存先
BACKUP_DIR=$HOME/openclaw-backups

# !! 重要: これを実際のインストールディレクトリに変更してください !!
APP_DIR=/path/to/your/project-n8n  # このパスを実際のパスに置き換えてください

# カラー出力（ターミナルでない場合は無効化）
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# エラーハンドリング: サービスの再起動を試みる
function error_handler {
    echo -e "\n${RED}エラー: リストアが中断または失敗しました${NC}"
    if [ -d "$APP_DIR" ] && [ -f "$APP_DIR/compose.yml" ]; then
        echo "サービスの起動を試みています..."
        (cd "$APP_DIR" && docker compose up -d) || echo -e "${YELLOW}サービスの起動に失敗しました。手動で確認してください。${NC}"
    fi
    exit 1
}
trap error_handler ERR INT TERM

echo "========================================="
echo "  OpenClaw リストアスクリプト"
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

# バックアップディレクトリの確認
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}エラー: バックアップディレクトリ '$BACKUP_DIR' が存在しません${NC}"
    exit 1
fi

# 利用可能なバックアップを表示
echo "▶ 利用可能なバックアップ:"
echo ""

# OpenClawバックアップのリスト
mapfile -t openclaw_backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'openclaw-data-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)

if [ ${#openclaw_backups[@]} -eq 0 ]; then
    echo -e "${RED}エラー: バックアップが見つかりません${NC}"
    echo "バックアップディレクトリ: $BACKUP_DIR"
    exit 1
fi

echo "番号  日時                    OpenClawデータ  Workspace    Caddyデータ"
echo "----  --------------------  ---------------  -----------  -----------"

declare -A backup_dates
index=1

for backup in "${openclaw_backups[@]}"; do
    basename_val=$(basename "$backup")
    datetime_ext=${basename_val#openclaw-data-}
    datetime=${datetime_ext%.tar.gz}

    # 対応するバックアップの存在確認
    workspace_backup="$BACKUP_DIR/workspace-$datetime.tar.gz"
    caddy_backup="$BACKUP_DIR/caddy-data-$datetime.tar.gz"

    # ファイルサイズを取得
    openclaw_size=$(du -h "$backup" | cut -f1)

    workspace_status="missing"
    if [ -f "$workspace_backup" ]; then
        workspace_status=$(du -h "$workspace_backup" | cut -f1)
    fi

    caddy_status="missing"
    if [ -f "$caddy_backup" ]; then
        caddy_status=$(du -h "$caddy_backup" | cut -f1)
    fi

    # フォーマットされた日時
    formatted_date=$(echo "$datetime" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

    printf "%-4s  %-20s  %-15s  %-11s  %-11s\n" "$index" "$formatted_date" "$openclaw_size" "$workspace_status" "$caddy_status"

    backup_dates[$index]=$datetime
    index=$((index + 1))
done

echo ""

# バックアップの選択
if [ -n "${1:-}" ]; then
    if ! [[ "$1" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        echo -e "${RED}エラー: 日付フォーマットが不正です（期待: YYYYMMDD-HHMMSS）${NC}"
        exit 1
    fi
    RESTORE_DATE="$1"
    echo -e "${BLUE}指定されたバックアップ: $RESTORE_DATE${NC}"
else
    read -p "復元するバックアップの番号を入力してください（1-$((index-1))）: " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge "$index" ]; then
        echo -e "${RED}エラー: 無効な選択です${NC}"
        exit 1
    fi

    RESTORE_DATE="${backup_dates[$selection]}"
    echo -e "${BLUE}選択されたバックアップ: $RESTORE_DATE${NC}"
fi

# バックアップファイルの確認
OPENCLAW_BACKUP="$BACKUP_DIR/openclaw-data-$RESTORE_DATE.tar.gz"
WORKSPACE_BACKUP="$BACKUP_DIR/workspace-$RESTORE_DATE.tar.gz"
CADDY_BACKUP="$BACKUP_DIR/caddy-data-$RESTORE_DATE.tar.gz"

if [ ! -f "$OPENCLAW_BACKUP" ]; then
    echo -e "${RED}エラー: OpenClawバックアップファイルが見つかりません: $OPENCLAW_BACKUP${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}⚠ 警告: この操作は既存のOpenClawデータを上書きします！${NC}"
echo ""
read -p "本当に復元しますか？ (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "復元をキャンセルしました。"
    exit 0
fi

echo ""

# サービスを停止
echo "▶ サービスを停止中..."
if (cd "$APP_DIR" && docker compose down); then
    echo -e "${GREEN}✓${NC} サービスを停止しました"
else
    echo -e "${RED}✗${NC} サービスの停止に失敗しました"
    exit 1
fi
echo ""

# OpenClawボリュームを削除して再作成
echo "▶ OpenClawデータボリュームを再作成中..."
docker volume rm openclaw_data 2>/dev/null || true
docker volume create openclaw_data
echo -e "${GREEN}✓${NC} OpenClawデータボリュームを再作成しました"
echo ""

# OpenClawデータを復元
echo "▶ OpenClawデータを復元中..."
if docker run --rm -v openclaw_data:/data -v "$BACKUP_DIR":/backup alpine \
    tar xzf "/backup/openclaw-data-$RESTORE_DATE.tar.gz" --no-absolute-names -C /data; then
    echo -e "${GREEN}✓${NC} OpenClawデータの復元完了"
else
    echo -e "${RED}✗${NC} OpenClawデータの復元に失敗しました"
    exit 1
fi
echo ""

# ワークスペースを復元（存在する場合）
if [ -f "$WORKSPACE_BACKUP" ]; then
    echo "▶ ワークスペースを復元中..."
    if tar xzf "$WORKSPACE_BACKUP" --no-absolute-names -C "$APP_DIR"; then
        echo -e "${GREEN}✓${NC} ワークスペースの復元完了"
    else
        echo -e "${YELLOW}⚠${NC} ワークスペースの復元に失敗しました"
    fi
else
    echo -e "${YELLOW}⚠${NC} ワークスペースバックアップが見つかりません（スキップ）"
fi
echo ""

# Caddyデータを復元（存在する場合）
if [ -f "$CADDY_BACKUP" ]; then
    echo "▶ Caddyデータを復元中..."
    docker volume rm caddy_data 2>/dev/null || true
    docker volume create caddy_data

    if docker run --rm -v caddy_data:/data -v "$BACKUP_DIR":/backup alpine \
        tar xzf "/backup/caddy-data-$RESTORE_DATE.tar.gz" --no-absolute-names -C /data; then
        echo -e "${GREEN}✓${NC} Caddyデータの復元完了"
    else
        echo -e "${YELLOW}⚠${NC} Caddyデータの復元に失敗しました（SSL証明書は再取得されます）"
    fi
else
    echo -e "${YELLOW}⚠${NC} Caddyバックアップが見つかりません（SSL証明書は再取得されます）"
fi
echo ""

# サービスを再起動
echo "▶ サービスを起動中..."
if (cd "$APP_DIR" && docker compose up -d); then
    echo -e "${GREEN}✓${NC} サービスを起動しました"
else
    echo -e "${RED}✗${NC} サービスの起動に失敗しました"
    exit 1
fi
echo ""

# サービスの状態を確認
echo "▶ サービスの状態を確認中..."
sleep 3
(cd "$APP_DIR" && docker compose ps)
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
echo "3. ブラウザでアクセスして動作確認"
echo ""
