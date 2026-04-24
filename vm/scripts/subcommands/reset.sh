#!/usr/bin/env bash
# vm reset <name> <snap> — revert to a previously-created snapshot.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"

(( $# == 2 )) || die "usage: vm reset <name> <snap-name>"
vm_revert "$1" "$2"
