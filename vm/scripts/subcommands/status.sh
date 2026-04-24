#!/usr/bin/env bash
# vm status <name> — domain state, IP, snapshot list, overlay disk path.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"

(( $# == 1 )) || die "usage: vm status <name>"
name="$1"

virsh -c "${LIBVIRT_URI}" dominfo "${name}" >/dev/null 2>&1 \
  || die "no such domain: ${name}"

state=$(virsh -c "${LIBVIRT_URI}" domstate "${name}")
printf 'name:    %s\n' "${name}"
printf 'state:   %s\n' "${state}"

ip=$(get_ipv4 "${name}" || true)
printf 'ipv4:    %s\n' "${ip:--}"

target="-"; user="-"; os_variant="-"
meta="${SEED_DIR}/${name}/.metadata"
if [[ -r "${meta}" ]]; then
  # shellcheck disable=SC1090
  . "${meta}"
  target="${TARGET:-${target}}"
  user="${DEFAULT_USER:-${user}}"
  os_variant="${OS_VARIANT:-${os_variant}}"
fi
printf 'target:  %s\n' "${target}"
printf 'user:    %s\n' "${user}"
printf 'os:      %s\n' "${os_variant}"

disk="${DISK_DIR}/${name}.qcow2"
[[ -f "${disk}" ]] && printf 'disk:    %s (%s)\n' "${disk}" "$(stat -c '%s bytes' "${disk}")" || printf 'disk:    -\n'

printf 'seed:    %s\n' "${SEED_DIR}/${name}"

printf 'snapshots:\n'
snaps=$(virsh -c "${LIBVIRT_URI}" snapshot-list --name "${name}" 2>/dev/null | awk 'NF')
if [[ -z "${snaps}" ]]; then
  printf '  (none)\n'
else
  printf '  %s\n' ${snaps}
fi
