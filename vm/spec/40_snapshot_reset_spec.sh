#!/usr/bin/env bash
# shellcheck shell=bash
# Snapshot create + drift + reset round-trip.

Describe 'snapshot + reset'
  VM_NAME=$(e2e_vm_name)
  SNAP=clean

  setup() {
    "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}" >/dev/null 2>&1
    "${VM_BIN}" snapshot "${VM_NAME}" "${SNAP}" >/dev/null 2>&1
  }
  cleanup() { e2e_destroy_quiet "${VM_NAME}"; }
  BeforeAll 'setup'
  AfterAll  'cleanup'

  It 'snapshot is visible in virsh snapshot-list'
    When run command virsh -c "${LIBVIRT_DEFAULT_URI}" snapshot-list --name "${VM_NAME}"
    The status should equal 0
    The output should include "${SNAP}"
  End

  # Drift + reset is a two-stage assertion: install htop (drift), confirm
  # present, then reset and confirm absent. ShellSpec rejects multiple
  # `When` blocks in one `It`, so the two stages live in adjacent `It`s
  # whose ordering is preserved by ShellSpec within a Describe/Context.
  It 'install drift takes effect (htop present after dnf install)'
    "${VM_BIN}" ssh "${VM_NAME}" -- 'sudo dnf install -y htop' >/dev/null 2>&1
    When run script "${VM_BIN}" ssh "${VM_NAME}" -- 'command -v htop'
    The status should equal 0
  End

  It 'reset reverts the drift (htop absent after snapshot revert)'
    "${VM_BIN}" reset "${VM_NAME}" "${SNAP}" >/dev/null 2>&1
    e2e_wait_ssh "${VM_NAME}" 60
    When run script "${VM_BIN}" ssh "${VM_NAME}" -- 'rpm -q htop'
    The status should not equal 0
  End

  It 'snapshot still present after reset'
    When run command virsh -c "${LIBVIRT_DEFAULT_URI}" snapshot-list --name "${VM_NAME}"
    The output should include "${SNAP}"
  End
End
