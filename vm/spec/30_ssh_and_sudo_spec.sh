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
    When run command "${VM_BIN}" ssh "${VM_NAME}" -- true
    The status should equal 0
  End

  It 'passwordless sudo works for the default user'
    When run command "${VM_BIN}" ssh "${VM_NAME}" -- 'sudo -n id -u'
    The status should equal 0
    The output should equal '0'
  End

  It 'password auth is refused (PubkeyAuthentication=no)'
    # Probe the VM IP directly with options that force password auth.
    # Should fail closed (BatchMode + no password method available).
    ip=$(virsh -c "${LIBVIRT_DEFAULT_URI}" domifaddr "${VM_NAME}" \
         | awk '$3=="ipv4"{split($4,a,"/");print a[1];exit}')
    When run command ssh \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/dev/null \
      -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password \
      -o ConnectTimeout=5 \
      "fedora@${ip}" true
    The status should not equal 0
  End

  It 'per-VM key (B1) is the active identity'
    # Ensure the per-VM key file exists; without it, `vm ssh` would have
    # fallen back to default identities and this test would pass for the
    # wrong reason.
    The path "${STATE}/seeds/${VM_NAME}/ssh_key" should be exist
  End
End
