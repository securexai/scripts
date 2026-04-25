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

  It 'install drift takes effect, then reset reverts it'
    # Install htop (drift), confirm present, reset, confirm absent.
    "${VM_BIN}" ssh "${VM_NAME}" -- 'sudo dnf install -y htop' >/dev/null 2>&1
    When run script "${VM_BIN}" ssh "${VM_NAME}" -- 'command -v htop'
    The status should equal 0

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
