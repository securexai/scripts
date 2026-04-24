#!/usr/bin/env bash
# vm list — tidy `virsh list --all` plus per-VM target inferred from the
# metadata sidecar when available.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"

require_cmd virsh

# Collect all domain names. virsh list --all --name returns one per line,
# blank-line terminated.
mapfile -t names < <(virsh -c "${LIBVIRT_URI}" list --all --name 2>/dev/null | awk 'NF')

if (( ${#names[@]} == 0 )); then
  printf 'no domains defined on %s\n' "${LIBVIRT_URI}"
  exit 0
fi

printf '%-20s %-12s %-14s %s\n' NAME STATE TARGET DISK
for n in "${names[@]}"; do
  state=$(virsh -c "${LIBVIRT_URI}" domstate "${n}" 2>/dev/null | head -1)
  target="-"
  meta="${SEED_DIR}/${n}/.metadata"
  if [[ -r "${meta}" ]]; then
    target=$(awk -F= '/^TARGET=/ {print $2; exit}' "${meta}")
  fi
  disk="${DISK_DIR}/${n}.qcow2"
  [[ -f "${disk}" ]] || disk="-"
  printf '%-20s %-12s %-14s %s\n' "${n}" "${state}" "${target}" "${disk}"
done
