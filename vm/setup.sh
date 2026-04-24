#!/usr/bin/env bash
#
# One-time host prep for the vm/ workflow on a Fedora 43 host (Kinoite or
# Workstation). Idempotent: safe to re-run.
#
# What it does:
#   1. Layers the libvirt + qemu + virt-install stack via rpm-ostree.
#   2. Enables the user libvirtd.socket so qemu:///session works without sudo.
#   3. Optionally adds the user to the libvirt group (qemu:///system).
#
# If rpm-ostree stages a new deployment, you MUST reboot before any vm
# subcommand will work.
#
# Usage:
#   ./vm/setup.sh                       # install if missing, enable socket
#   USE_LIBVIRT_GROUP=1 ./vm/setup.sh   # also add user to libvirt group
#   TRACE=1 ./vm/setup.sh               # verbose xtrace

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s nullglob

if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 3) )); then
  printf 'ERROR: This script requires Bash 5.3+. Current: %s\n' "$BASH_VERSION" >&2
  exit 1
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

readonly REQUIRED_PACKAGES=(
  libvirt-daemon-kvm
  libvirt-client
  virt-install
  qemu-kvm
  genisoimage
  edk2-ovmf
)

needs_install() {
  local pkg layered
  layered=$(rpm-ostree status --json | jq -r '.deployments[0]."requested-packages"[]?' 2>/dev/null || true)
  for pkg in "$@"; do
    grep -qxF "${pkg}" <<<"${layered}" || return 0
  done
  return 1
}

ensure_packages() {
  if ! needs_install "${REQUIRED_PACKAGES[@]}"; then
    log "all required packages already layered"
    return 0
  fi
  log "layering packages via rpm-ostree: ${REQUIRED_PACKAGES[*]}"
  rpm-ostree install --idempotent --allow-inactive "${REQUIRED_PACKAGES[@]}"
  warn "rpm-ostree may have staged a new deployment — REBOOT REQUIRED before vm subcommands work"
}

ensure_libvirtd_socket() {
  if systemctl --user is-active --quiet libvirtd.socket; then
    log "user libvirtd.socket already active"
    return 0
  fi
  log "enabling user libvirtd.socket"
  systemctl --user enable --now libvirtd.socket \
    || die "failed to enable libvirtd.socket — is libvirt installed and have you rebooted since rpm-ostree install?"
}

ensure_libvirt_group() {
  [[ "${USE_LIBVIRT_GROUP:-0}" == "1" ]] || return 0
  if id -nG "$(id -un)" | grep -qw libvirt; then
    log "user already in libvirt group"
    return 0
  fi
  log "adding user $(id -un) to libvirt group (requires sudo)"
  sudo usermod -aG libvirt "$(id -un)"
  warn "log out and back in (or run 'newgrp libvirt') for group membership to take effect"
}

main() {
  require_cmd rpm-ostree
  require_cmd systemctl
  require_cmd jq

  ensure_packages
  ensure_libvirtd_socket
  ensure_libvirt_group

  log "vm/ host setup complete"
  log "sanity check: virsh -c qemu:///session list --all"
}

main "$@"
