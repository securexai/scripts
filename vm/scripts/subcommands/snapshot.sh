#!/usr/bin/env bash
# vm snapshot <name> <snap> — create an internal qcow2 snapshot.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"

(( $# == 2 )) || die "usage: vm snapshot <name> <snap-name>"
vm_snapshot "$1" "$2"
