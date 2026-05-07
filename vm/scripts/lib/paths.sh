#!/usr/bin/env bash
# XDG-compliant paths and libvirt URI defaults for the vm/ scripts.
# Source after common.sh.
#
# Honors:
#   XDG_CACHE_HOME, XDG_STATE_HOME (per spec)
#   LIBVIRT_DEFAULT_URI            (defaults to qemu:///session)
#   VM_SSH_PUBKEY                  (optional opt-in to host pubkey;
#                                   default is per-VM ephemeral ed25519)

[[ -n "${_VM_LIB_PATHS_LOADED:-}" ]] && return 0
readonly _VM_LIB_PATHS_LOADED=1

# Cache: read-mostly, regeneratable. Image downloads and bib build outputs.
readonly XDG_CACHE_BASE="${XDG_CACHE_HOME:-${HOME}/.cache}"
readonly IMAGE_CACHE_DIR="${XDG_CACHE_BASE}/scripts-vm/images"

# State: persistent, write-mostly. VM disks and seed ISOs.
readonly XDG_STATE_BASE="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly DISK_DIR="${XDG_STATE_BASE}/scripts-vm/disks"
readonly SEED_DIR="${XDG_STATE_BASE}/scripts-vm/seeds"

# Default libvirt URI: rootless session (no group needed). Override with
# LIBVIRT_DEFAULT_URI=qemu:///system if vm/setup.sh added you to the
# libvirt group.
readonly LIBVIRT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///session}"

# Idempotent mkdirs for the writable dirs.
mkdir -p "${IMAGE_CACHE_DIR}" "${DISK_DIR}" "${SEED_DIR}"
