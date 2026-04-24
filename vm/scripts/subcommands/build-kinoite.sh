#!/usr/bin/env bash
# vm build-kinoite — explicit subcommand to run the bib pipeline ahead of
# 'vm create --target kinoite'. Slow (10–20 min); idempotent (cache reused
# unless REBUILD=1).

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/paths.sh
. "${SCRIPT_DIR}/../lib/paths.sh"
# shellcheck source=../lib/bib.sh
. "${SCRIPT_DIR}/../lib/bib.sh"

readonly _BK_VM_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
target_env="${_BK_VM_ROOT}/targets/kinoite.env"

qcow=$(build_kinoite_qcow "${target_env}")
log "kinoite image at: ${qcow}"
log "next: vm create --target kinoite --name <vm-name>"
