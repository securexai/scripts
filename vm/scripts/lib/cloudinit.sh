#!/usr/bin/env bash
# Cloud-init seed builder. Renders the base templates with envsubst and
# packs the result into a NoCloud ISO via genisoimage.
#
# Source after common.sh and paths.sh.
#
# Public:
#   render_seed <vm-name>
#     Reads ${VM_SSH_PUBKEY_PATH}, renders cloudinit/base/*.tmpl, builds
#     ${SEED_DIR}/<vm-name>/seed.iso, and prints its absolute path on stdout.
#     Per-VM customization: drop a YAML overlay at cloudinit/overlays/<vm-name>/
#     (merge semantics are documented in the overlay README — keep it simple
#     until a real second consumer arrives).

[[ -n "${_VM_LIB_CLOUDINIT_LOADED:-}" ]] && return 0
readonly _VM_LIB_CLOUDINIT_LOADED=1

require_cmd envsubst
require_cmd genisoimage

# Resolve vm/ root from this script's location: lib/ -> scripts/ -> vm/
readonly _CLOUDINIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VM_ROOT="$(cd "${_CLOUDINIT_LIB_DIR}/../.." && pwd)"
readonly CLOUDINIT_BASE_DIR="${VM_ROOT}/cloudinit/base"

render_seed() {
  local vm_name="$1"
  [[ -n "${vm_name}" ]] || die "render_seed: vm name required"

  [[ -r "${VM_SSH_PUBKEY_PATH}" ]] \
    || die "SSH pubkey not readable: ${VM_SSH_PUBKEY_PATH} (set VM_SSH_PUBKEY)"

  local pubkey
  pubkey=$(< "${VM_SSH_PUBKEY_PATH}")

  local seed_dir="${SEED_DIR}/${vm_name}"
  mkdir -p "${seed_dir}"

  local f
  for f in meta-data user-data network-config; do
    [[ -r "${CLOUDINIT_BASE_DIR}/${f}.tmpl" ]] \
      || die "missing template: ${CLOUDINIT_BASE_DIR}/${f}.tmpl"
    VM_NAME="${vm_name}" SSH_PUBKEY="${pubkey}" \
      envsubst '$VM_NAME $SSH_PUBKEY' \
      < "${CLOUDINIT_BASE_DIR}/${f}.tmpl" \
      > "${seed_dir}/${f}"
  done

  local seed_iso="${seed_dir}/seed.iso"
  genisoimage -quiet \
    -output "${seed_iso}" \
    -volid cidata -joliet -rock \
    -graft-points \
    "meta-data=${seed_dir}/meta-data" \
    "user-data=${seed_dir}/user-data" \
    "network-config=${seed_dir}/network-config" \
    >/dev/null

  log "seed iso ready: ${seed_iso}"
  printf '%s' "${seed_iso}"
}
