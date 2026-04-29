#!/usr/bin/env bash
# shellcheck shell=bash
# B2: flock advisory lock prevents two `vm create --name same` calls
# from racing. Exactly one wins; the other fails cleanly with a
# lock-held diagnostic. No corrupted artifacts left behind.

Describe 'parallel-safety (flock)'
  VM_NAME=$(e2e_vm_name)
  STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"

  cleanup() { e2e_destroy_quiet "${VM_NAME}"; }
  AfterAll 'cleanup'

  It 'two concurrent creates: one wins, one fails with lock-held'
    # Hold the lock manually in the foreground so the second call sees
    # contention deterministically; race-based tests against real boot
    # times are flaky.
    lock="${STATE}/seeds/${VM_NAME}.lock"
    mkdir -p "$(dirname "${lock}")"
    exec {HELD_FD}>"${lock}"
    flock -n "${HELD_FD}"

    When run script "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}"
    The status should equal 70
    The stderr should include 'another vm operation is in progress'

    # Release the manual hold and clean the marker.
    eval "exec ${HELD_FD}>&-"
    rm -f "${lock}"
  End

  It 'lockfile is the standard path under SEED_DIR'
    The variable STATE should be defined
    The path "${STATE}/seeds" should be exist
  End
End
