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

readonly _CREATE_VM_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly TARGETS_DIR="${_CREATE_VM_ROOT}/targets"

usage() {
  cat <<'EOF' >&2
usage: vm create --target {fedora-cloud|kinoite} --name <vm-name> [options]
  --persistent     accepted for forward compat (no-op — all VMs persist
                   until 'vm destroy' is called)
  --cpus N         override target default
  --mem MIB        override target default
  --disk GIB       override target default (overlay capacity)
  --overlay <n>    per-VM cloudinit overlay name (under cloudinit/overlays/<n>/)
EOF
}

target=""
name=""
cpus=""
mem=""
disk=""
overlay=""

while (( $# > 0 )); do
  case "$1" in
    --target)     target="$2"; shift 2;;
    --name)       name="$2"; shift 2;;
    --persistent) shift;;
    --cpus)       cpus="$2"; shift 2;;
    --mem)        mem="$2"; shift 2;;
    --disk)       disk="$2"; shift 2;;
    --overlay)    overlay="$2"; shift 2;;
    -h|--help)    usage; exit 0;;
    *)            usage; die "unknown arg: $1";;
  esac
done

[[ -n "${target}" ]] || { usage; die "--target required"; }
[[ -n "${name}"   ]] || { usage; die "--name required"; }

target_env="${TARGETS_DIR}/${target}.env"
[[ -r "${target_env}" ]] || die "target not found: ${target_env}"

# shellcheck disable=SC1090
. "${target_env}"

cpus="${cpus:-${DEFAULT_VCPUS}}"
mem="${mem:-${DEFAULT_MEM_MIB}}"
disk_gib="${disk:-${DEFAULT_DISK_GIB}}"

# Acquire base image.
case "${target}" in
  fedora-cloud)
    base=$(ensure_image "${target_env}")
    ;;
  kinoite)
    # shellcheck source=../lib/bib.sh
    . "${SCRIPT_DIR}/../lib/bib.sh"
    base=$(build_kinoite_qcow "${target_env}")
    ;;
  *) die "unknown target: ${target} (no acquisition path)";;
esac

# Refuse to clobber an existing domain of the same name.
if virsh -c "${LIBVIRT_URI}" dominfo "${name}" >/dev/null 2>&1; then
  die "VM '${name}' already exists — 'vm destroy ${name}' first"
fi

require_cmd qemu-img

# Copy-on-write overlay so the base image stays read-only and shareable.
overlay_disk="${DISK_DIR}/${name}.qcow2"
log "creating COW overlay: ${overlay_disk} (backed by ${base}, capacity ${disk_gib}G)"
qemu-img create -f qcow2 -F qcow2 -b "${base}" "${overlay_disk}" "${disk_gib}G" >/dev/null

# Cloud-init seed.
seed=$(render_seed "${name}")

# Sidecar metadata so other subcommands (ssh, status) know which user to use.
mkdir -p "${SEED_DIR}/${name}"
{
  printf 'TARGET=%s\n'        "${target}"
  printf 'DEFAULT_USER=%s\n'  "${DEFAULT_USER}"
  printf 'OS_VARIANT=%s\n'    "${OS_VARIANT}"
} > "${SEED_DIR}/${name}/.metadata"

# Define + start.
vm_define "${name}" "${overlay_disk}" "${seed}" "${OS_VARIANT}" "${cpus}" "${mem}"

# Block until reachable.
ip=$(wait_for_ssh "${name}" 240)
log "VM '${name}' ready at ${ip} (ssh ${DEFAULT_USER}@${ip})"
log "next: 'vm ssh ${name}' or 'vm destroy ${name}'"

# Overlay-name flag accepted but not yet wired through to cloudinit.sh.
# Reserved for the upcoming overlay-merge feature (see cloudinit/overlays/.gitkeep).
[[ -z "${overlay}" ]] || warn "--overlay '${overlay}' acknowledged but not yet implemented (see cloudinit/overlays/.gitkeep)"
