#!/usr/bin/env bash
# shellcheck shell=bash
# vm create on the fedora-cloud target — domain definition, overlay
# disk, seed dir, and metadata sidecar all materialize.

Describe 'vm create --target fedora-cloud'
  VM_NAME=$(e2e_vm_name)
  STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"

  setup() {
    "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}" >/dev/null 2>&1
  }
  cleanup() { e2e_destroy_quiet "${VM_NAME}"; }
  BeforeAll 'setup'
  AfterAll  'cleanup'

  It 'creates a libvirt domain visible in virsh list'
    When run command virsh -c "${LIBVIRT_DEFAULT_URI}" list --name --all
    The status should equal 0
    The output should include "${VM_NAME}"
  End

  It 'lays down the COW overlay disk under XDG_STATE_HOME'
    The path "${STATE}/disks/${VM_NAME}.qcow2" should be exist
  End

  It 'lays down the seed dir under XDG_STATE_HOME'
    The path "${STATE}/seeds/${VM_NAME}" should be exist
  End

  It 'writes the metadata sidecar with TARGET and DEFAULT_USER'
    When call cat "${STATE}/seeds/${VM_NAME}/.metadata"
    The status should be success
    The output should include 'TARGET=fedora-cloud'
    The output should include 'DEFAULT_USER=fedora'
  End

  It 'generates a per-VM ed25519 keypair (B1)'
    The path "${STATE}/seeds/${VM_NAME}/ssh_key"     should be exist
    The path "${STATE}/seeds/${VM_NAME}/ssh_key.pub" should be exist
  End
End
