#!/usr/bin/env bash
# vm ssh <name> [-- <cmd...>] — open ssh, or run a one-off remote command.
# Reads DEFAULT_USER from the per-VM metadata sidecar so it picks the right
# user for the target (fedora vs core).

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/libvirt.sh
. "${SCRIPT_DIR}/../lib/libvirt.sh"

(( $# >= 1 )) || die "usage: vm ssh <name> [-- <cmd...>]"
name="$1"; shift

# Skip leading -- if present (lets users disambiguate from vm flags).
[[ "${1:-}" == "--" ]] && shift

meta="${SEED_DIR}/${name}/.metadata"
if [[ -r "${meta}" ]]; then
  # shellcheck disable=SC1090
  . "${meta}"
fi

# Re-export DEFAULT_USER so libvirt.sh::ssh_to picks it up.
export DEFAULT_USER

ssh_to "${name}" "$@"
