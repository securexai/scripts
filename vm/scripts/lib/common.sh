#!/usr/bin/env bash
# Shared strict-mode preamble, logging, and ERR trap for the vm/ scripts.
# Each subcommand sources this once via:
#   . "${SCRIPT_DIR}/lib/common.sh"
#
# Exposes: log, warn, error, die, require_cmd.
# Honors: NO_COLOR (suppress color), TRACE=1 (xtrace).

[[ -n "${_VM_LIB_COMMON_LOADED:-}" ]] && return 0
readonly _VM_LIB_COMMON_LOADED=1

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s nullglob

if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 3) )); then
  printf 'ERROR: vm/ scripts require Bash 5.3+. Current: %s\n' "$BASH_VERSION" >&2
  exit 1
fi

if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  readonly _C_RESET=$'\033[0m'
  readonly _C_INFO=$'\033[1;34m'
  readonly _C_WARN=$'\033[1;33m'
  readonly _C_ERR=$'\033[1;31m'
else
  readonly _C_RESET=''
  readonly _C_INFO=''
  readonly _C_WARN=''
  readonly _C_ERR=''
fi

log()   { printf '%sinfo%s  %s\n' "${_C_INFO}" "${_C_RESET}" "$*" >&2; }
warn()  { printf '%swarn%s  %s\n' "${_C_WARN}" "${_C_RESET}" "$*" >&2; }
error() { printf '%serror%s %s\n' "${_C_ERR}"  "${_C_RESET}" "$*" >&2; }
die()   { error "$*"; exit 1; }

[[ "${TRACE:-0}" == "1" ]] && set -o xtrace

trap 'rc=$?; printf "%serror%s %s:%s: \"%s\" exited %s\n" "${_C_ERR}" "${_C_RESET}" "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "${rc}" >&2' ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 \
    || die "required command not found on PATH: $1"
}
