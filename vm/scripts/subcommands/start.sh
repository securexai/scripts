#!/usr/bin/env bash
# vm start — start a defined-but-stopped domain.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"

require_cmd virsh

(( $# == 1 )) || die "usage: vm start <name>"
name="$1"

state=$(virsh -c "${LIBVIRT_URI}" domstate "${name}" 2>/dev/null || true)
case "${state}" in
  running)   log "${name} already running"; exit 0;;
  "shut off"|paused) ;;
  "")        die "no such domain: ${name}";;
  *)         warn "unexpected state '${state}' — attempting start anyway";;
esac

log "starting ${name}"
virsh -c "${LIBVIRT_URI}" start "${name}" >/dev/null
