#!/usr/bin/env bash
# vm create — provision a fresh VM from a target.
#
# Flow: ensure base image (download or bib-build) → create COW overlay →
# render cloud-init seed ISO → virt-install --import → wait for SSH.
# Returns when SSH is reachable; the VM keeps running until you 'vm destroy'.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/images.sh
. "${SCRIPT_DIR}/../lib/images.sh"
# shellcheck source=../lib/cloudinit.sh
. "${SCRIPT_DIR}/../lib/cloudinit.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"
# shellcheck source=../lib/locks.sh
. "${SCRIPT_DIR}/../lib/locks.sh"

readonly _CREATE_VM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly TARGETS_DIR="${_CREATE_VM_ROOT}/targets"

usage() {
  cat <<'EOF' >&2
usage: vm create --target <name> --name <vm-name> [options]
       targets: fedora-cloud, fedora-cloud-44, kinoite, kinoite-44
                (any name matching fedora-cloud* or kinoite* with a matching
                 vm/targets/<name>.env is recognized)
  --persistent     accepted for forward compat (no-op — all VMs persist
                   until 'vm destroy' is called)
  --cpus N         override target default
  --mem MIB        override target default
  --disk GIB       override target default (overlay capacity)
  --overlay <n>    cloudinit overlay file (cloudinit/overlays/<n>.yaml.tmpl)
  --with-cockpit   install + enable cockpit on :9090 (combines an
                   overlay for fedora-cloud with kinoite-cockpit.toml
                   for the kinoite target)
EOF
}

target=""
name=""
cpus=""
mem=""
disk=""
overlay=""
with_cockpit=0

while (( $# > 0 )); do
  case "$1" in
    --target)       target="$2"; shift 2;;
    --name)         name="$2"; shift 2;;
    --persistent)   shift;;
    --cpus)         cpus="$2"; shift 2;;
    --mem)          mem="$2"; shift 2;;
    --disk)         disk="$2"; shift 2;;
    --overlay)      overlay="$2"; shift 2;;
    --with-cockpit) with_cockpit=1; shift;;
    -h|--help)      usage; exit 0;;
    *)              usage; die_with "${EXIT_USAGE}" "unknown arg: $1";;
  esac
done

[[ -n "${target}" ]] || { usage; die_with "${EXIT_USAGE}" "--target required"; }
[[ -n "${name}"   ]] || { usage; die_with "${EXIT_USAGE}" "--name required"; }

# --overlay and --with-cockpit are mutually exclusive (a single overlay
# is appended; combining would require a multi-overlay merge we don't
# implement yet). Surface the conflict instead of silently dropping one.
if [[ -n "${overlay}" ]] && (( with_cockpit )); then
  die_with "${EXIT_USAGE}" "--overlay and --with-cockpit cannot be combined (yet)"
fi
if (( with_cockpit )); then
  case "${target}" in
    fedora-cloud|fedora-cloud-*|kinoite|kinoite-*) ;;
    *) die_with "${EXIT_USAGE}" "--with-cockpit only supports fedora-cloud* and kinoite* targets (got: ${target})" ;;
  esac
fi
# For fedora-cloud-class targets, cockpit ships via cloud-init overlay.
# For kinoite-class, cockpit ships baked into the bib qcow2
# (kinoite-cockpit.toml) — no overlay needed.
if (( with_cockpit )) && [[ "${target}" == fedora-cloud* ]]; then
  overlay="cockpit"
fi

target_env="${TARGETS_DIR}/${target}.env"
[[ -r "${target_env}" ]] || die_with "${EXIT_USAGE}" "target not found: ${target_env}"

# Acquired after usage validation so a typo in --target doesn't leave
# an orphan lockfile that destroy.sh would never come back to clean.
vm_lock_acquire "${name}"

# shellcheck disable=SC1090
. "${target_env}"

cpus="${cpus:-${DEFAULT_VCPUS}}"
mem="${mem:-${DEFAULT_MEM_MIB}}"
disk_gib="${disk:-${DEFAULT_DISK_GIB}}"

# Acquire base image.
case "${target}" in
  fedora-cloud|fedora-cloud-*)
    base=$(ensure_image "${target_env}")
    ;;
  kinoite|kinoite-*)
    # shellcheck source=../lib/bib.sh
    . "${SCRIPT_DIR}/../lib/bib.sh"
    if (( with_cockpit )); then
      base=$(build_kinoite_qcow "${target_env}" "kinoite-cockpit.toml")
    else
      base=$(build_kinoite_qcow "${target_env}")
    fi
    ;;
  *) die_with "${EXIT_USAGE}" "unknown target: ${target} (no acquisition path)";;
esac

# Refuse to clobber an existing domain of the same name.
if virsh -c "${LIBVIRT_URI}" dominfo "${name}" >/dev/null 2>&1; then
  die_with "${EXIT_USAGE}" "VM '${name}' already exists — 'vm destroy ${name}' first"
fi

require_cmd qemu-img

# Copy-on-write overlay so the base image stays read-only and shareable.
overlay_disk="${DISK_DIR}/${name}.qcow2"
log "creating COW overlay: ${overlay_disk} (backed by ${base}, capacity ${disk_gib}G)"
qemu-img create -f qcow2 -F qcow2 -b "${base}" "${overlay_disk}" "${disk_gib}G" >/dev/null

# Cloud-init seed (overlay applied if --overlay or --with-cockpit set).
seed=$(render_seed "${name}" "${overlay}")

# Sidecar metadata so other subcommands (ssh, status) know which user to use.
mkdir -p "${SEED_DIR}/${name}"
{
  printf 'TARGET=%s\n'        "${target}"
  printf 'DEFAULT_USER=%s\n'  "${DEFAULT_USER}"
  printf 'OS_VARIANT=%s\n'    "${OS_VARIANT}"
  printf 'OVERLAY=%s\n'       "${overlay}"
  printf 'WITH_COCKPIT=%s\n'  "${with_cockpit}"
} > "${SEED_DIR}/${name}/.metadata"

# Define + start.
vm_define "${name}" "${overlay_disk}" "${seed}" "${OS_VARIANT}" "${cpus}" "${mem}"

# Block until SSH responds.
ip=$(wait_for_ssh "${name}" 240)

# Cloud-init readiness gate. Exit codes per cloud-init upstream:
#   0 = clean, 2 = non-fatal warning, 1 = fatal. Anything other than 1 is
# acceptable — modules may emit warnings on minimal images without
# breaking the seed.
log "waiting for cloud-init to finish on ${name}"
if ! vm_ssh_run "${name}" 'cloud-init status --wait; rc=$?; [[ $rc -ne 1 ]]'; then
  die_with "${EXIT_CLOUDINIT}" "cloud-init reported a fatal error on ${name} — see 'vm ssh ${name} -- sudo cloud-init status --long'"
fi

# Outbound network probe. The libvirt default network is NAT-attached;
# if this fails the VM is up but isolated from the internet.
log "probing outbound network on ${name}"
if ! vm_ssh_run "${name}" 'curl -fsS --max-time 5 https://fedoraproject.org -o /dev/null'; then
  die_with "${EXIT_NET}" "VM cannot reach https://fedoraproject.org — check libvirt default NAT and DNS"
fi

log "VM '${name}' ready at ${ip} (ssh ${DEFAULT_USER}@${ip})"
log "next: 'vm ssh ${name}' or 'vm destroy ${name}'"
