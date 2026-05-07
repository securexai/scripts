# shellcheck shell=bash
# ShellSpec helper — loaded by every spec file via .shellspec.
#
# Conventions:
#   - One shared VM per spec file: BeforeAll creates, AfterAll destroys.
#   - The shared VM name is derived from the spec basename + $$ for
#     parallel safety. Override with VM_E2E_NAME for debugging.
#   - All ssh probes go through `vm_ssh_q` (quiet) for assertions.
#   - Anything that costs >2 seconds (boot, dnf install, snapshot)
#     should live in BeforeAll, not in a per-It setup.

# Resolve VM_ROOT from the spec_helper's own location.
# spec_helper.sh lives at <vm-root>/spec/spec_helper.sh.
SPEC_HELPER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VM_ROOT="$(cd "${SPEC_HELPER_DIR}/.." && pwd)"
export VM_ROOT
export VM_BIN="${VM_ROOT}/scripts/vm"

# Honor the same env knobs as the dispatcher.
export LIBVIRT_DEFAULT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///session}"

# Suite-level VM name. Each spec file gets its own (basename derived).
e2e_vm_name() {
  local spec="${1:-${SHELLSPEC_SPECFILE:-unknown}}"
  local base
  base=$(basename "${spec}" .sh)
  base="${base#*_}"   # strip leading "NN_"
  printf 'e2e-%s-%s' "${base//_/-}" "$$"
}

# Block until the shared VM is reachable; supplies a stable IP for the
# rest of the spec. Returns 0 on success.
e2e_wait_ssh() {
  local name="$1" timeout="${2:-60}"
  local end=$(( SECONDS + timeout ))
  while (( SECONDS < end )); do
    "${VM_BIN}" ssh "${name}" -- true >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# Quiet ssh — exit code only, no stdout/stderr leak into spec logs.
vm_ssh_q() {
  local name="$1"; shift
  "${VM_BIN}" ssh "${name}" -- "$@" >/dev/null 2>&1
}

# Loud ssh — stdout returned to caller; useful for `When call`-style
# assertions that inspect output.
vm_ssh_out() {
  local name="$1"; shift
  "${VM_BIN}" ssh "${name}" -- "$@" 2>/dev/null
}

# Post-destroy cleanliness check used by every spec's AfterAll trail.
# Confirms no overlay disk, no seed dir, no lock file remains for <name>.
assert_no_residue() {
  local name="$1"
  local state="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"
  local rc=0
  [[ -e "${state}/disks/${name}.qcow2" ]] && { echo "RESIDUE: overlay disk still present" >&2; rc=1; }
  [[ -e "${state}/seeds/${name}"       ]] && { echo "RESIDUE: seed dir still present"     >&2; rc=1; }
  [[ -e "${state}/seeds/${name}.lock"  ]] && { echo "RESIDUE: lock file still present"    >&2; rc=1; }
  return "${rc}"
}

# Cheap default-lane create. fedora-cloud unless overridden by spec.
e2e_create_default() {
  local name="$1" target="${2:-fedora-cloud}"
  shift 2 || true
  "${VM_BIN}" create --target "${target}" --name "${name}" "$@"
}

# Always-clean teardown. Best-effort; never errors out the spec.
e2e_destroy_quiet() {
  local name="$1"
  "${VM_BIN}" destroy "${name}" >/dev/null 2>&1 || true
}
