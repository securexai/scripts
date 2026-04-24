#!/usr/bin/env bash
# vm stop — graceful shutdown (30s timeout, force destroy on timeout).
# Domain stays defined; use 'vm destroy' to remove it entirely.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"

(( $# == 1 )) || die "usage: vm stop <name>"
name="$1"

vm_destroy "${name}"
log "stopped ${name}"
