#!/usr/bin/env bash
# shellcheck shell=bash
# vm destroy leaves no residue under XDG_STATE_HOME and base image cache
# is preserved (not wiped on per-VM destroy).

Describe 'vm destroy — residue'
  VM_NAME=$(e2e_vm_name)
  STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"
  CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}/scripts-vm/images"

  setup() {
    "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}" >/dev/null 2>&1
    # Capture image cache contents pre-destroy so we can compare after.
    cache_before=$(find "${CACHE}" -maxdepth 1 -type f -name '*.qcow2' 2>/dev/null | sort)
    export cache_before
  }
  BeforeAll 'setup'

  It 'vm destroy returns 0 on a created VM'
    When run script "${VM_BIN}" destroy "${VM_NAME}"
    The status should equal 0
  End

  It 'domain is gone from virsh list --all'
    When run command virsh -c "${LIBVIRT_DEFAULT_URI}" list --name --all
    The output should not include "${VM_NAME}"
  End

  It 'overlay disk file is removed'
    The path "${STATE}/disks/${VM_NAME}.qcow2" should not be exist
  End

  It 'seed dir is removed'
    The path "${STATE}/seeds/${VM_NAME}" should not be exist
  End

  It 'lock file is removed'
    The path "${STATE}/seeds/${VM_NAME}.lock" should not be exist
  End

  It 'base image cache is preserved (not wiped on destroy)'
    cache_after=$(find "${CACHE}" -maxdepth 1 -type f -name '*.qcow2' 2>/dev/null | sort)
    When call test "${cache_after}" = "${cache_before}"
    The status should be success
  End

  It 'destroy on a missing VM is a no-op (idempotent)'
    When run script "${VM_BIN}" destroy "${VM_NAME}"
    The status should equal 0
  End
End
