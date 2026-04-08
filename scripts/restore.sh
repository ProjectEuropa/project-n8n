#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${APP_DIR}/.env"
BACKUP_DIR=${BACKUP_DIR:-"${HOME}/openfang-backups"}

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

OPENFANG_DATA_VOLUME=$(get_env_var OPENFANG_DATA_VOLUME openfang_data)
CADDY_DATA_VOLUME=$(get_env_var CADDY_DATA_VOLUME caddy_data)

echo "========================================="
echo "  OpenFang リストア"
echo "========================================="
echo ""

if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}バックアップディレクトリがありません: ${BACKUP_DIR}${NC}"
    exit 1
fi

mapfile -t openfang_backups < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'openfang-data-*.tar.gz' | sort -r)
if [ ${#openfang_backups[@]} -eq 0 ]; then
    echo -e "${RED}openfang-data バックアップが見つかりません。${NC}"
    exit 1
fi

if [ -n "${1:-}" ]; then
    restore_date="$1"
else
    echo "利用可能なバックアップ:"
    for backup in "${openfang_backups[@]}"; do
        echo "  $(basename "$backup" | sed 's/^openfang-data-//; s/\.tar\.gz$//')"
    done
    echo ""
    read -r -p "復元する日時 (YYYYMMDD-HHMMSS): " restore_date
fi

OPENFANG_ARCHIVE="${BACKUP_DIR}/openfang-data-${restore_date}.tar.gz"
WORKSPACE_ARCHIVE="${BACKUP_DIR}/workspace-${restore_date}.tar.gz"
CADDY_ARCHIVE="${BACKUP_DIR}/caddy-data-${restore_date}.tar.gz"

if [ ! -f "$OPENFANG_ARCHIVE" ]; then
    echo -e "${RED}対象バックアップがありません: ${OPENFANG_ARCHIVE}${NC}"
    exit 1
fi

echo -e "${YELLOW}既存データを上書きします。${NC}"
read -r -p "続けますか？ (yes/no): " answer
if [ "$answer" != "yes" ]; then
    echo "中止しました。"
    exit 0
fi

echo "▶ サービス停止"
(cd "$APP_DIR" && docker compose down)
echo ""

echo "▶ OpenFang データを復元"
docker volume rm "$OPENFANG_DATA_VOLUME" >/dev/null 2>&1 || true
docker volume create "$OPENFANG_DATA_VOLUME" >/dev/null
docker run --rm -v "${OPENFANG_DATA_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine \
    tar xzf "/backup/$(basename "$OPENFANG_ARCHIVE")" --no-absolute-names -C /data
echo -e "${GREEN}✓${NC} ${OPENFANG_DATA_VOLUME}"
echo ""

if [ -f "$WORKSPACE_ARCHIVE" ]; then
    echo "▶ workspace を復元"
    mkdir -p "$APP_DIR"
    tar xzf "$WORKSPACE_ARCHIVE" --no-absolute-names -C "$APP_DIR"
    echo -e "${GREEN}✓${NC} workspace"
    echo ""
fi

if [ -f "$CADDY_ARCHIVE" ]; then
    echo "▶ Caddy データを復元"
    docker volume rm "$CADDY_DATA_VOLUME" >/dev/null 2>&1 || true
    docker volume create "$CADDY_DATA_VOLUME" >/dev/null
    docker run --rm -v "${CADDY_DATA_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine \
        tar xzf "/backup/$(basename "$CADDY_ARCHIVE")" --no-absolute-names -C /data
    echo -e "${GREEN}✓${NC} ${CADDY_DATA_VOLUME}"
    echo ""
fi

echo "▶ サービス起動"
(cd "$APP_DIR" && docker compose up -d)
echo ""
(cd "$APP_DIR" && docker compose ps)
