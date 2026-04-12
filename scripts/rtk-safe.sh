#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

fail() {
  echo "rtk-safe: $*" >&2
  exit 2
}

if [[ "${CI:-}" == "1" || "${CI:-}" =~ ^[Tt][Rr][Uu][Ee]$ || -n "${GITHUB_ACTIONS:-}" ]]; then
  fail "CI では rtk を使わないでください"
fi

if [[ $# -lt 1 ]]; then
  cat >&2 <<'USAGE'
Usage:
  ./scripts/rtk-safe.sh git diff [args...]
  ./scripts/rtk-safe.sh git status [args...]
  ./scripts/rtk-safe.sh git log [args...]
  ./scripts/rtk-safe.sh git show [args...]
  ./scripts/rtk-safe.sh cargo test [args...]

This wrapper is for local, manual review only. It never installs hooks.
USAGE
  exit 2
fi

if git_root=$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null); then
  [[ "${git_root}" == "${APP_DIR}" ]] || fail "この repo 内でだけ実行してください: ${APP_DIR}"
else
  fail "git repo 内で実行してください"
fi

joined_args=" $* "
if [[ "${joined_args}" == *" init "* ||
      "${joined_args}" == *" --global "* ||
      "${joined_args}" == *" -g "* ||
      "${joined_args}" == *" hook "* ||
      "${joined_args}" == *" hooks "* ]]; then
  fail "global init / hook 操作は禁止です"
fi

case "${1}" in
  aws|curl|wget|docker|kubectl)
    fail "${1} は rtk-safe では禁止です"
    ;;
  gh)
    fail "gh は rtk-safe では禁止です"
    ;;
esac

case "${1}:${2:-}" in
  git:diff|git:status|git:log|git:show|cargo:test)
    ;;
  *)
    fail "許可コマンドは git diff/status/log/show と cargo test のみです"
    ;;
esac

for arg in "$@"; do
  lower_arg=$(printf '%s' "${arg}" | tr '[:upper:]' '[:lower:]')
  case "${lower_arg}" in
    *.env*|*credentials*|*secret*|*token*|*password*)
      fail "secret / .env / credentials を含む引数は禁止です: ${arg}"
      ;;
  esac
done

if [[ -n "${RTK_BIN:-}" ]]; then
  rtk_bin="${RTK_BIN}"
  [[ -x "${rtk_bin}" ]] || fail "RTK_BIN is not executable: ${rtk_bin}"
elif command -v rtk >/dev/null 2>&1; then
  rtk_bin=$(command -v rtk)
else
  fail "rtk が見つかりません。RTK_BIN=/path/to/rtk を指定してください"
fi

export RTK_TELEMETRY_DISABLED=1
export RTK_TEE=0

exec "${rtk_bin}" "$@"
