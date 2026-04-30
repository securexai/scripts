#!/usr/bin/env bash
# vm prune — remove orphan disks, seed dirs, and stale lockfiles whose
# backing libvirt domain is gone. Idempotent (Check → Action → Verify);
# dry-run by default so you see the plan before anything is removed.
#
# Live domains and currently-held lockfiles are always skipped — prune
# never races a concurrent create/destroy. The base image cache
# (${IMAGE_CACHE_DIR}) is intentionally untouched: those files back live
# overlay disks via qcow2 backing chains and re-fetching is slow.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"
# shellcheck source=../lib/locks.sh
. "${SCRIPT_DIR}/../lib/locks.sh"

usage() {
  cat <<'EOF' >&2
usage: vm prune [--apply] [--quiet]
  (default)   dry-run: list orphan artifacts, do not remove
  --apply     remove orphan overlay disks, seed dirs, and stale lockfiles
  --quiet     suppress per-item output (still prints the summary)

Safety:
  - never touches a domain that is defined in libvirt
  - never removes a lockfile whose flock is currently held
  - the base image cache is out of scope
EOF
}

apply=0
quiet=0
while (( $# > 0 )); do
  case "$1" in
    --apply)        apply=1; shift;;
    --quiet|-q)     quiet=1; shift;;
    -h|--help)      usage; exit 0;;
    *)              usage; die_with "${EXIT_USAGE}" "unknown arg: $1";;
  esac
done

declare -A live_vms=()
while IFS= read -r n; do live_vms["${n}"]=1; done < <(vm_list_defined_domains)

disks=( "${DISK_DIR}"/*.qcow2 )
seeds=( "${SEED_DIR}"/*/ )
locks=( "${SEED_DIR}"/*.lock )

plan=()
for d in "${disks[@]}"; do
  n="${d##*/}"; n="${n%.qcow2}"
  [[ -z "${live_vms[${n}]:-}" ]] && plan+=( "disk|${d}" )
done
for s in "${seeds[@]}"; do
  s="${s%/}"; n="${s##*/}"
  [[ -z "${live_vms[${n}]:-}" ]] && plan+=( "seed|${s}" )
done
for l in "${locks[@]}"; do
  n="${l##*/}"; n="${n%.lock}"
  [[ -z "${live_vms[${n}]:-}" ]] && plan+=( "lock|${l}" )
done
# Pool sweep: any dir-type pool whose <path> is a *direct child* of
# ${SEED_DIR} and is not owned by a live domain is a virt-install leak.
# Path is the source of truth — pool name is just a label virt-install
# happens to set to the VM name.
while IFS= read -r p; do
  [[ -z "${p}" ]] && continue
  path=$(vm_pool_path_of "${p}") || continue
  [[ "${path}" == "${SEED_DIR}/"*  &&  "${path#"${SEED_DIR}/"}" != */* ]] || continue
  n="${path##*/}"
  [[ -z "${live_vms[${n}]:-}" ]] && plan+=( "pool|${p}|${path}" )
done < <(virsh -c "${LIBVIRT_URI}" pool-list --all --name 2>/dev/null | awk 'NF')
# Trailing `:` keeps $? = 0 if the last loop's final `&&` short-circuited
# false — otherwise errexit would treat the orphan-free case as a fault.
:

if (( ${#plan[@]} == 0 )); then
  log "no orphan artifacts under ${DISK_DIR} / ${SEED_DIR}"
  exit 0
fi

removed=0
held_locks=()
for entry in "${plan[@]}"; do
  kind="${entry%%|*}"
  rest="${entry#*|}"
  # disk/seed/lock entries are 2-field (kind|path); pool is
  # 3-field (kind|pool-name|pool-path) so the dry-run message can
  # name what's actually visible in `virsh pool-list`.
  if [[ "${kind}" == "pool" ]]; then
    pool_name="${rest%%|*}"
    path="${rest#*|}"
    label="${pool_name}"
  else
    path="${rest}"
    label="${path}"
  fi

  if [[ "${kind}" == "lock" ]]; then
    name="${path##*/}"; name="${name%.lock}"
    if ! vm_lock_try_acquire "${name}"; then
      held_locks+=( "${path}" )
      continue
    fi
  fi

  if (( apply )); then
    (( quiet )) || log "removing ${kind}: ${label}"
    case "${kind}" in
      disk) rm -f  "${path}";;
      seed) rm -rf "${path}";;
      lock) vm_lock_release_and_unlink "${name}";;
      pool) vm_pool_drop "${pool_name}";;
    esac
  else
    (( quiet )) || log "would remove ${kind}: ${label}"
    [[ "${kind}" == "lock" ]] && vm_lock_release
  fi
  (( removed++ )) || true
done

if (( apply )); then
  log "pruned ${removed} artifact(s) (skipped ${#held_locks[@]} held lockfile(s))"
else
  log "would prune ${removed} artifact(s) — re-run with --apply to commit"
fi

for h in "${held_locks[@]}"; do
  warn "held lockfile (skipped): ${h}"
done
