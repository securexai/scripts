#!/usr/bin/env bash
# shellcheck shell=bash
# Cloud-init readiness gate (A2) and outbound network probe.

Describe 'cloud-init + internet'
  VM_NAME=$(e2e_vm_name)

  setup()   { "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}" >/dev/null 2>&1; }
  cleanup() { e2e_destroy_quiet "${VM_NAME}"; }
  BeforeAll 'setup'
  AfterAll  'cleanup'

  It 'cloud-init status --wait exits 0 or 2 (not fatal)'
    # The bash subshell forwards rc to ssh, but ssh exits with that code.
    When run command "${VM_BIN}" ssh "${VM_NAME}" -- \
      'cloud-init status --wait; rc=$?; [[ $rc -ne 1 ]]'
    The status should equal 0
  End

  It 'reaches https://fedoraproject.org via NAT'
    When run command "${VM_BIN}" ssh "${VM_NAME}" -- \
      'curl -fsS --max-time 5 https://fedoraproject.org -o /dev/null'
    The status should equal 0
  End

  It 'resolves quay.io (DNS sanity)'
    When run command "${VM_BIN}" ssh "${VM_NAME}" -- \
      'getent hosts quay.io'
    The status should equal 0
  End
End
