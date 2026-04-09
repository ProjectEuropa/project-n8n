#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
BUNDLE_DIR="${1:-${APP_DIR}/dist/vps}"

echo "▶ VPS 用バンドルを作成: ${BUNDLE_DIR}"

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
mkdir -p "${BUNDLE_DIR}/credentials"

cp "${APP_DIR}/compose.yml" "${BUNDLE_DIR}/compose.yml"
cp "${APP_DIR}/compose.source-build.yml" "${BUNDLE_DIR}/compose.source-build.yml"
cp "${APP_DIR}/.env.example" "${BUNDLE_DIR}/.env.example"
cp -R "${APP_DIR}/caddy_config" "${BUNDLE_DIR}/caddy_config"
cp -R "${APP_DIR}/openfang_config" "${BUNDLE_DIR}/openfang_config"
cp -R "${APP_DIR}/scripts" "${BUNDLE_DIR}/scripts"
cp -R "${APP_DIR}/workspace" "${BUNDLE_DIR}/workspace"
cp "${APP_DIR}/docs/VPS_BUNDLE.md" "${BUNDLE_DIR}/README.md"

find "${BUNDLE_DIR}/scripts" -type f -name '*.sh' -exec chmod +x {} +
touch "${BUNDLE_DIR}/credentials/.gitkeep"
rm -rf "${BUNDLE_DIR}/openfang_config/upstream-src"
rm -f "${BUNDLE_DIR}/compose.local-fast.yml" "${BUNDLE_DIR}/compose.local-ui.yml"

echo "完了: ${BUNDLE_DIR}"
echo "転送例:"
echo "  rsync -avz ${BUNDLE_DIR}/ user@your-vps:/opt/openfang/"
