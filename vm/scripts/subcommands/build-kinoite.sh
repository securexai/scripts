#!/usr/bin/env bash
# vm build-kinoite [--target <name>] — explicit subcommand to run the bib
# pipeline ahead of 'vm create --target <name>'. Slow (10–20 min);
# idempotent (cache reused unless REBUILD=1).
#
# Default target is `kinoite` for backwards compatibility. Pass a different
# kinoite-class env file (e.g. `--target kinoite-44`) to build a parallel
# qcow2 cache without disturbing the default one.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/bib.sh
. "${SCRIPT_DIR}/../lib/bib.sh"

readonly _BK_VM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

target="kinoite"
while (( $# > 0 )); do
  case "$1" in
    --target)   target="$2"; shift 2;;
    -h|--help)
      cat <<'EOF' >&2
usage: vm build-kinoite [--target <name>]
  --target  bib target (default: kinoite); points at vm/targets/<name>.env
            and must be a kinoite-class target (sets OCI_REF/OCI_DIGEST/
            BIB_VERSION/BIB_CONFIG_REL/BIB_ROOTFS).
EOF
      exit 0;;
    *) die_with "${EXIT_USAGE}" "unknown arg: $1";;
  esac
done

target_env="${_BK_VM_ROOT}/targets/${target}.env"
[[ -r "${target_env}" ]] || die_with "${EXIT_USAGE}" "target env not found: ${target_env}"

qcow=$(build_kinoite_qcow "${target_env}")
log "kinoite image at: ${qcow}"
log "next: vm create --target ${target} --name <vm-name>"
