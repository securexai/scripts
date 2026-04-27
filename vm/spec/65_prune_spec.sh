#!/usr/bin/env bash
# shellcheck shell=bash
# vm prune — orphan residue cleanup. Synthetic fixtures (no live VM) so
# this spec stays in the default lane (~seconds) without bringing up a
# real domain. Live-domain protection is exercised by 60_destroy_residue.

Describe 'vm prune'
  STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"
  DISKS="${STATE}/disks"
  SEEDS="${STATE}/seeds"
  ORPHAN_NAME="prune-orphan-$$"

  setup() {
    mkdir -p "${DISKS}" "${SEEDS}/${ORPHAN_NAME}"
    : > "${DISKS}/${ORPHAN_NAME}.qcow2"
    : > "${SEEDS}/${ORPHAN_NAME}.lock"
    : > "${SEEDS}/${ORPHAN_NAME}/.metadata"
  }
  cleanup() {
    rm -f "${DISKS}/${ORPHAN_NAME}.qcow2" \
          "${SEEDS}/${ORPHAN_NAME}.lock"
    rm -rf "${SEEDS}/${ORPHAN_NAME}"
  }
  BeforeEach 'setup'
  AfterEach  'cleanup'

  It 'dry-run lists each orphan kind and removes nothing'
    When run script "${VM_BIN}" prune
    The status should equal 0
    The stderr should match pattern "*would remove disk:*${ORPHAN_NAME}.qcow2*"
    The stderr should match pattern "*would remove seed:*${ORPHAN_NAME}*"
    The stderr should match pattern "*would remove lock:*${ORPHAN_NAME}.lock*"
    The stderr should include 're-run with --apply'
    The path "${DISKS}/${ORPHAN_NAME}.qcow2"  should be exist
    The path "${SEEDS}/${ORPHAN_NAME}"        should be exist
    The path "${SEEDS}/${ORPHAN_NAME}.lock"   should be exist
  End

  It '--apply removes orphan disk, seed dir, and stale lockfile'
    When run script "${VM_BIN}" prune --apply
    The status should equal 0
    The stderr should include 'pruned'
    The path "${DISKS}/${ORPHAN_NAME}.qcow2"  should not be exist
    The path "${SEEDS}/${ORPHAN_NAME}"        should not be exist
    The path "${SEEDS}/${ORPHAN_NAME}.lock"   should not be exist
  End

  It 'is idempotent — second --apply is a no-op'
    "${VM_BIN}" prune --apply >/dev/null 2>&1
    When run script "${VM_BIN}" prune --apply
    The status should equal 0
    The stderr should include 'no orphan artifacts'
  End

  It 'skips lockfiles that are currently held'
    # Sentinel-coordinated lock holder: spawn a subshell that takes the
    # flock then writes a "ready" file; the spec waits on the sentinel
    # so prune never starts until the lock is actually held; the holder
    # exits as soon as we delete the sentinel. No fixed sleeps.
    sentinel="${SEEDS}/${ORPHAN_NAME}.held"
    (
      exec {fd}>"${SEEDS}/${ORPHAN_NAME}.lock"
      flock -n -x "${fd}" || exit 1
      : > "${sentinel}"
      while [[ -e "${sentinel}" ]]; do sleep 0.05; done
    ) &
    holder_pid=$!
    until [[ -e "${sentinel}" ]]; do sleep 0.05; done

    When run script "${VM_BIN}" prune --apply
    The status should equal 0
    The stderr should include 'held lockfile'
    The path "${SEEDS}/${ORPHAN_NAME}.lock" should be exist

    rm -f "${sentinel}"
    wait "${holder_pid}" 2>/dev/null || true
  End

  It 'rejects unknown args with EXIT_USAGE (64)'
    When run script "${VM_BIN}" prune --bogus
    The status should equal 64
    The stderr should include 'unknown arg'
  End
End
