#!/usr/bin/env bash
# Per-VM advisory locks. Backed by ${SEED_DIR}/<name>.lock + flock(2);
# released automatically when the holding fd closes (script exit).
#
# Source after common.sh and paths.sh.
#
# Public:
#   vm_lock_path <name>             — print the lock-file path
#   vm_lock_acquire <name>          — acquire non-blocking; sets _VM_LOCK_FD
#                                     on success, exits EXIT_LIBVIRT on contention
#   vm_lock_try_acquire <name>      — same, but returns 1 instead of dying
#   vm_lock_release_and_unlink <name> — release + unlink (destroy/prune lifecycle)

[[ -n "${_VM_LIB_LOCKS_LOADED:-}" ]] && return 0
readonly _VM_LIB_LOCKS_LOADED=1

require_cmd flock

vm_lock_path() {
  printf '%s/%s.lock' "${SEED_DIR}" "$1"
}

# Open + non-blocking flock. The inode reference held by the fd survives
# the file being unlinked, so callers can `rm` the lock under the lock
# without invalidating the fd — the same lifecycle invariant destroy.sh
# has always relied on.
vm_lock_try_acquire() {
  local lock; lock=$(vm_lock_path "$1")
  exec {_VM_LOCK_FD}>"${lock}"
  if flock -n "${_VM_LOCK_FD}"; then
    return 0
  fi
  exec {_VM_LOCK_FD}>&-
  unset _VM_LOCK_FD
  return 1
}

vm_lock_acquire() {
  local name="$1"
  vm_lock_try_acquire "${name}" \
    || die_with "${EXIT_LIBVIRT}" "another vm operation is in progress for '${name}' (lock: $(vm_lock_path "${name}"))"
}

vm_lock_release() {
  if [[ -n "${_VM_LOCK_FD:-}" ]]; then
    exec {_VM_LOCK_FD}>&-
    unset _VM_LOCK_FD
  fi
}

vm_lock_release_and_unlink() {
  local lock; lock=$(vm_lock_path "$1")
  rm -f "${lock}"
  vm_lock_release
}
