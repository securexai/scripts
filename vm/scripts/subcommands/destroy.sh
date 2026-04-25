#!/usr/bin/env bash
# vm destroy — graceful shutdown, undefine the domain, remove the overlay
# disk and the cloud-init seed dir. Idempotent.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"

(( $# == 1 )) || die_with "${EXIT_USAGE}" "usage: vm destroy <name>"
name="$1"

# Take the same advisory lock as create.sh so a concurrent create can't
# race the cleanup. Lock is auto-released on exit.
require_cmd flock
readonly LOCK_PATH="${SEED_DIR}/${name}.lock"
exec {LOCK_FD}>"${LOCK_PATH}"
flock -n "${LOCK_FD}" \
  || die_with "${EXIT_LIBVIRT}" "another vm operation is in progress for '${name}' (lock: ${LOCK_PATH})"

vm_destroy   "${name}"
vm_undefine  "${name}"

overlay_disk="${DISK_DIR}/${name}.qcow2"
seed_dir="${SEED_DIR}/${name}"

[[ -f "${overlay_disk}" ]] && { log "removing overlay disk ${overlay_disk}"; rm -f "${overlay_disk}"; }
[[ -d "${seed_dir}"     ]] && { log "removing seed dir ${seed_dir}";        rm -rf "${seed_dir}"; }

# Lock file removed last. Other holders see the file vanish but their
# flock fd remains valid (held by inode); flock semantics are unaffected.
rm -f "${LOCK_PATH}"

log "destroyed ${name}"
