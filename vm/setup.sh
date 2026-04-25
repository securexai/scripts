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

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/paths.sh
. "${SCRIPT_DIR}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/preflight.sh
. "${SCRIPT_DIR}/scripts/lib/preflight.sh"

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

  # Run preflight only if the libvirt clients are actually present in this
  # boot. After a fresh rpm-ostree install the binaries land on the staged
  # deployment but aren't on $PATH until reboot — running preflight then
  # would mis-report the gap as a hard failure.
  if command -v virsh >/dev/null 2>&1; then
    log "running preflight (full)"
    preflight_full
  else
    warn "virsh not on PATH yet — REBOOT then re-run ./vm/setup.sh to validate preflight"
  fi

  log "vm/ host setup complete"
}

main "$@"
