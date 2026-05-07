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
require_cmd ssh-keygen

# Resolve vm/ root from this script's location: lib/ -> scripts/ -> vm/
readonly _CLOUDINIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VM_ROOT="$(cd "${_CLOUDINIT_LIB_DIR}/../.." && pwd)"
readonly CLOUDINIT_BASE_DIR="${VM_ROOT}/cloudinit/base"
readonly CLOUDINIT_OVERLAYS_DIR="${VM_ROOT}/cloudinit/overlays"

# Resolve the SSH pubkey to inject:
#   - If VM_SSH_PUBKEY is set in the env (explicit opt-in to host key),
#     use that file. Caller is responsible for its lifecycle.
#   - Otherwise, generate a per-VM ephemeral ed25519 keypair under the
#     seed dir and use that pubkey. The private half lives next to the
#     seed and is wiped on `vm destroy`.
# Echoes the absolute path of the pubkey file on stdout. Idempotent.
_resolve_vm_pubkey() {
  local vm_name="$1" seed_dir="$2"
  if [[ -n "${VM_SSH_PUBKEY:-}" ]]; then
    [[ -r "${VM_SSH_PUBKEY}" ]] \
      || die_with "${EXIT_PREREQ}" "VM_SSH_PUBKEY set but not readable: ${VM_SSH_PUBKEY}"
    printf '%s' "${VM_SSH_PUBKEY}"
    return 0
  fi
  local key="${seed_dir}/ssh_key"
  if [[ ! -f "${key}" ]]; then
    log "generating per-VM ed25519 keypair: ${key}"
    ssh-keygen -t ed25519 -N '' -C "vm:${vm_name}" -f "${key}" -q
  fi
  printf '%s' "${key}.pub"
}

# Append a cloud-init overlay fragment to the user-data, keeping the
# rendered base intact. Overlays live at vm/cloudinit/overlays/<name>.yaml.tmpl
# and may use the same envsubst variables as the base.
#
# Lifecycle caveat: this is a textual append, not a YAML merge. If both
# the base and the overlay declare the same top-level mapping key (e.g.
# `runcmd:`, `users:`, `packages:`), cloud-init's PyYAML loader picks
# the last occurrence and the earlier value is silently dropped. Keep
# top-level keys disjoint between base and overlay.
#
# Args: <vm_name> <seed_dir> <overlay_name> <pubkey>
_apply_overlay() {
  local vm_name="$1" seed_dir="$2" overlay="$3" pubkey="$4"
  local tmpl="${CLOUDINIT_OVERLAYS_DIR}/${overlay}.yaml.tmpl"
  [[ -r "${tmpl}" ]] || die_with "${EXIT_USAGE}" "overlay template not found: ${tmpl}"
  log "applying cloud-init overlay: ${overlay}"
  VM_NAME="${vm_name}" SSH_PUBKEY="${pubkey}" DEFAULT_USER="${DEFAULT_USER:-fedora}" \
    envsubst '$VM_NAME $SSH_PUBKEY $DEFAULT_USER' \
    < "${tmpl}" \
    >> "${seed_dir}/user-data"
}

render_seed() {
  local vm_name="$1"
  local overlay="${2:-}"
  [[ -n "${vm_name}" ]] || die_with "${EXIT_USAGE}" "render_seed: vm name required"

  local seed_dir="${SEED_DIR}/${vm_name}"
  mkdir -p "${seed_dir}"

  local pubkey_path pubkey build_date
  pubkey_path=$(_resolve_vm_pubkey "${vm_name}" "${seed_dir}")
  pubkey=$(< "${pubkey_path}")
  build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local f
  for f in meta-data user-data network-config; do
    [[ -r "${CLOUDINIT_BASE_DIR}/${f}.tmpl" ]] \
      || die_with "${EXIT_GENERIC}" "missing template: ${CLOUDINIT_BASE_DIR}/${f}.tmpl"
    VM_NAME="${vm_name}" SSH_PUBKEY="${pubkey}" DEFAULT_USER="${DEFAULT_USER:-fedora}" \
      BUILD_DATE="${build_date}" \
      envsubst '$VM_NAME $SSH_PUBKEY $DEFAULT_USER $BUILD_DATE' \
      < "${CLOUDINIT_BASE_DIR}/${f}.tmpl" \
      > "${seed_dir}/${f}"
  done

  if [[ -n "${overlay}" ]]; then
    _apply_overlay "${vm_name}" "${seed_dir}" "${overlay}" "${pubkey}"
  fi

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
