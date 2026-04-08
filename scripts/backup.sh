#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${APP_DIR}/.env"
BACKUP_DIR=${BACKUP_DIR:-"${HOME}/openfang-backups"}
DATE=$(date +%Y%m%d-%H%M%S)

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

OPENFANG_ARCHIVE="${BACKUP_DIR}/openfang-data-${DATE}.tar.gz"
WORKSPACE_ARCHIVE="${BACKUP_DIR}/workspace-${DATE}.tar.gz"
CADDY_ARCHIVE="${BACKUP_DIR}/caddy-data-${DATE}.tar.gz"

echo "========================================="
echo "  OpenFang バックアップ"
echo "========================================="
echo ""

if [ ! -f "${APP_DIR}/compose.yml" ]; then
    echo -e "${RED}compose.yml が見つかりません: ${APP_DIR}${NC}"
    exit 1
fi

restart_openfang() {
    (cd "$APP_DIR" && docker compose start openfang >/dev/null 2>&1) || true
}

trap restart_openfang ERR INT TERM

mkdir -p "$BACKUP_DIR"

available_space_kb=$(df -k "$BACKUP_DIR" | tail -1 | awk '{print $4}')
available_space_gb=$((available_space_kb / 1024 / 1024))
if [ "$available_space_gb" -lt 2 ]; then
    echo -e "${RED}バックアップ先の空き容量が不足しています: ${available_space_gb}GB${NC}"
    exit 1
fi

echo "▶ openfang を停止"
(cd "$APP_DIR" && docker compose stop openfang)
echo ""

echo "▶ OpenFang データを保存"
docker run --rm -v "${OPENFANG_DATA_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine \
    tar czf "/backup/$(basename "$OPENFANG_ARCHIVE")" -C /data .
chmod 600 "$OPENFANG_ARCHIVE"
echo -e "${GREEN}✓${NC} $(basename "$OPENFANG_ARCHIVE")"
echo ""

if [ -d "${APP_DIR}/workspace" ]; then
    echo "▶ workspace を保存"
    tar czf "$WORKSPACE_ARCHIVE" -C "$APP_DIR" workspace
    chmod 600 "$WORKSPACE_ARCHIVE"
    echo -e "${GREEN}✓${NC} $(basename "$WORKSPACE_ARCHIVE")"
    echo ""
fi

echo "▶ Caddy データを保存"
docker run --rm -v "${CADDY_DATA_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine \
    tar czf "/backup/$(basename "$CADDY_ARCHIVE")" -C /data .
chmod 600 "$CADDY_ARCHIVE"
echo -e "${GREEN}✓${NC} $(basename "$CADDY_ARCHIVE")"
echo ""

echo "▶ openfang を再開"
(cd "$APP_DIR" && docker compose start openfang)
trap - ERR INT TERM
echo ""

find "$BACKUP_DIR" -name 'openfang-data-*.tar.gz' -mtime +7 -delete >/dev/null 2>&1 || true
find "$BACKUP_DIR" -name 'workspace-*.tar.gz' -mtime +7 -delete >/dev/null 2>&1 || true
find "$BACKUP_DIR" -name 'caddy-data-*.tar.gz' -mtime +7 -delete >/dev/null 2>&1 || true

echo "完了:"
echo "  ${OPENFANG_ARCHIVE}"
echo "  ${WORKSPACE_ARCHIVE}"
echo "  ${CADDY_ARCHIVE}"
