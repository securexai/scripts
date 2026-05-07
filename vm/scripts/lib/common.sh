#!/usr/bin/env bash
# Shared strict-mode preamble, logging, and ERR trap for the vm/ scripts.
# Each subcommand sources this once via:
#   . "${SCRIPT_DIR}/lib/common.sh"
#
# Exposes: log, warn, error, die, die_with, require_cmd, EXIT_* constants.
# Honors: NO_COLOR (suppress color), TRACE=1 (xtrace).

[[ -n "${_VM_LIB_COMMON_LOADED:-}" ]] && return 0
readonly _VM_LIB_COMMON_LOADED=1

# Strict-mode preamble — only when not running under ShellSpec. When
# common.sh is `Include`d into a spec, these options are applied to
# ShellSpec's own shell and any non-zero subshell exit (e.g. an
# expected EXIT_USAGE assertion) terminates the executor pipeline,
# preventing later specs from running. ShellSpec exports
# SHELLSPEC_VERSION so we can detect both the test harness and any
# subprocess it spawns. nullglob is harmless either way and stays.
if [[ -z "${SHELLSPEC_VERSION:-}" ]]; then
  set -o errexit
  set -o nounset
  set -o pipefail
  set -o errtrace
  shopt -s inherit_errexit
fi
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
die()   { error "$*"; exit "${EXIT_GENERIC:-1}"; }

[[ "${TRACE:-0}" == "1" ]] && set -o xtrace

# Diagnostic ERR trap — only register outside ShellSpec. With errtrace
# the trap is inherited into every subshell and function; when common.sh
# is `Include`d into a spec file the trap fires inside ShellSpec's own
# evaluation frames and pollutes spec output with synthetic
# 'return $1 exited NN' messages. SHELLSPEC_VERSION is exported by the
# shellspec runner and inherited by subprocesses it spawns.
if [[ -z "${SHELLSPEC_VERSION:-}" ]]; then
  # shellcheck disable=SC2154 # rc is assigned inside the trap body
  trap 'rc=$?; printf "%serror%s %s:%s: \"%s\" exited %s\n" "${_C_ERR}" "${_C_RESET}" "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "${rc}" >&2' ERR
fi

# Exit-code taxonomy. Values 0/1 are conventional; 64-78 follow sysexits.h.
# 71-72 are local extensions (sysexits.h has no slot for "network failure"
# or "guest cloud-init failure"). Callers prefer die_with over bare exit.
# shellcheck disable=SC2034 # consumed by sourced subcommand scripts
readonly EXIT_OK=0
readonly EXIT_GENERIC=1
# shellcheck disable=SC2034 # consumed by sourced subcommand scripts
readonly EXIT_USAGE=64
readonly EXIT_PREREQ=69
# shellcheck disable=SC2034 # consumed by sourced subcommand scripts
readonly EXIT_LIBVIRT=70
# shellcheck disable=SC2034 # consumed by sourced subcommand scripts
readonly EXIT_NET=71
# shellcheck disable=SC2034 # consumed by sourced subcommand scripts
readonly EXIT_CLOUDINIT=72

require_cmd() {
  command -v "$1" >/dev/null 2>&1 \
    || die_with "${EXIT_PREREQ}" "required command not found on PATH: $1"
}

# die_with <code> <msg…> — log error, exit with the named code.
# die remains a thin shim that exits EXIT_GENERIC for back-compat.
die_with() {
  local code="$1"; shift
  error "$*"
  exit "${code}"
}
