#!/usr/bin/env bash
# Automated end-to-end smoke test for the vm/ workflow.
#
# What it verifies (against the fedora-cloud target):
#   1. create: image acquired, COW disk made, cloud-init seed boots, SSH up
#   2. ssh:    remote command execution works
#   3. snapshot + reset: install package, snap, install drift, revert,
#      verify drift is gone — proves the snapshot lifecycle works
#   4. destroy: clean undefine + storage cleanup, no residue under
#      ${XDG_STATE_HOME}/scripts-vm/{disks,seeds}/
#
# Exit 0 on success; non-zero on any unexpected state.
# Always cleans up the test VM on exit (success, failure, or signal).
#
# Usage:
#   ./vm/tests/smoke.sh                 # default: name vm-smoke-<pid>
#   VM_SMOKE_NAME=foo ./vm/tests/smoke.sh

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s nullglob

if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 3) )); then
  printf 'ERROR: smoke.sh requires Bash 5.3+. Current: %s\n' "$BASH_VERSION" >&2
  exit 1
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VM_BIN="${SCRIPT_DIR}/../scripts/vm"
readonly NAME="${VM_SMOKE_NAME:-vm-smoke-$$}"

readonly XDG_STATE_BASE="${XDG_STATE_HOME:-${HOME}/.local/state}"

step() { printf '\n=== %s ===\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  printf '\n--- cleanup ---\n' >&2
  "${VM_BIN}" destroy "${NAME}" >/dev/null 2>&1 || true
  exit "${rc}"
}
trap cleanup EXIT INT TERM

[[ -x "${VM_BIN}" ]] || fail "vm dispatcher not executable: ${VM_BIN}"

step "create ${NAME} from fedora-cloud"
"${VM_BIN}" create --target fedora-cloud --name "${NAME}"

step "verify /etc/os-release + kernel via ssh"
"${VM_BIN}" ssh "${NAME}" -- 'cat /etc/os-release; uname -r'

step "snapshot 'clean'"
"${VM_BIN}" snapshot "${NAME}" clean

step "install htop (drift)"
"${VM_BIN}" ssh "${NAME}" -- 'sudo dnf install -y htop'
"${VM_BIN}" ssh "${NAME}" -- 'command -v htop >/dev/null' \
  || fail "htop not present after install"

step "revert to 'clean'"
"${VM_BIN}" reset "${NAME}" clean

step "verify htop is gone after revert"
if "${VM_BIN}" ssh "${NAME}" -- 'rpm -q htop >/dev/null 2>&1'; then
  fail "htop still installed after reset — snapshot/revert is broken"
fi

step "destroy ${NAME}"
"${VM_BIN}" destroy "${NAME}"

step "verify no residue under ${XDG_STATE_BASE}/scripts-vm/{disks,seeds}/${NAME}"
[[ -e "${XDG_STATE_BASE}/scripts-vm/disks/${NAME}.qcow2" ]] && fail "overlay disk not cleaned"
[[ -d "${XDG_STATE_BASE}/scripts-vm/seeds/${NAME}"       ]] && fail "seed dir not cleaned"

# Disable cleanup trap on success so we don't print a misleading cleanup banner.
trap - EXIT INT TERM
printf '\n=== smoke test PASSED ===\n' >&2
