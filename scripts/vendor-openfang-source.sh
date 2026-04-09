#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${ROOT_DIR}/openfang_config/upstream-src"
SOURCE_REPO="${OPENFANG_SOURCE_REPO:-https://github.com/RightNow-AI/openfang}"
SOURCE_REF="${OPENFANG_SOURCE_REF:-v0.5.6}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

git clone --depth 1 --branch "${SOURCE_REF}" "${SOURCE_REPO}" "${TMP_DIR}/openfang"
rm -rf "${TMP_DIR}/openfang/.git"
rm -rf "${DEST_DIR}"
mkdir -p "${DEST_DIR}"
cp -R "${TMP_DIR}/openfang"/. "${DEST_DIR}/"

printf 'Vendored OpenFang source to %s (%s @ %s)\n' "${DEST_DIR}" "${SOURCE_REPO}" "${SOURCE_REF}"
