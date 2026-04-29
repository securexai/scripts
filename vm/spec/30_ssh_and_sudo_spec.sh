#!/usr/bin/env bash
# shellcheck shell=bash
# SSH agent-friendliness: key-only, BatchMode, passwordless sudo,
# password auth refused.

Describe 'ssh + sudo'
  VM_NAME=$(e2e_vm_name)
  STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"

  setup()   { "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}" >/dev/null 2>&1; }
  cleanup() { e2e_destroy_quiet "${VM_NAME}"; }
  BeforeAll 'setup'
  AfterAll  'cleanup'

  It 'vm ssh runs a remote command non-interactively'
    When run script "${VM_BIN}" ssh "${VM_NAME}" -- true
    The status should equal 0
  End

  It 'passwordless sudo works for the default user'
    When run script "${VM_BIN}" ssh "${VM_NAME}" -- 'sudo -n id -u'
    The status should equal 0
    The output should equal '0'
  End

  It 'password auth is refused (effective sshd config)'
    # Inspect the live sshd effective config inside the guest. This is
    # the actual security property — a previous client-side ssh probe
    # passed tautologically because BatchMode forbids the client from
    # ever supplying a password, so the connection failed regardless of
    # what the server allowed.
    When run script "${VM_BIN}" ssh "${VM_NAME}" -- 'sudo -n sshd -T 2>/dev/null | awk "/^passwordauthentication / {print \$2}"'
    The status should equal 0
    The output should equal 'no'
  End

  It 'per-VM key (B1) is the active identity'
    # Ensure the per-VM key file exists; without it, `vm ssh` would have
    # fallen back to default identities and this test would pass for the
    # wrong reason.
    The path "${STATE}/seeds/${VM_NAME}/ssh_key" should be exist
  End
End
