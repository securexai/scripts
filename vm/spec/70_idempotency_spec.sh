#!/usr/bin/env bash
# shellcheck shell=bash
# Idempotency contract — every state-changing subcommand must be safe to
# re-run. Verdicts here back the YES verdict in the audit summary.

Describe 'idempotency'
  VM_NAME=$(e2e_vm_name)
  CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}/scripts-vm/images"

  setup()   { "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}" >/dev/null 2>&1; }
  cleanup() { e2e_destroy_quiet "${VM_NAME}"; }
  BeforeAll 'setup'
  AfterAll  'cleanup'

  Describe 'create'
    It 'refuses to clobber an existing domain'
      When run command "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}"
      The status should not equal 0
      The stderr should include 'already exists'
    End
  End

  Describe 'start (already running)'
    It 'is a no-op when the domain is already running'
      When run command "${VM_BIN}" start "${VM_NAME}"
      The status should equal 0
      The stderr should include 'already running'
    End
  End

  Describe 'stop'
    It 'shuts down the running VM'
      When run command "${VM_BIN}" stop "${VM_NAME}"
      The status should equal 0
    End

    It 'is a no-op when the domain is already stopped'
      When run command "${VM_BIN}" stop "${VM_NAME}"
      The status should equal 0
    End
  End

  Describe 'image cache'
    It 'ensure_image is a no-op on a second create attempt (cache hit)'
      # Re-run create on a second name; the base image must not be
      # re-downloaded (mtime unchanged).
      base_before=$(find "${CACHE}" -maxdepth 1 -type f -name '*.qcow2' \
        -printf '%T@ %p\n' 2>/dev/null | sort)
      "${VM_BIN}" create --target fedora-cloud --name "${VM_NAME}-twin" >/dev/null 2>&1
      base_after=$(find "${CACHE}" -maxdepth 1 -type f -name '*.qcow2' \
        -printf '%T@ %p\n' 2>/dev/null | sort)
      e2e_destroy_quiet "${VM_NAME}-twin"
      When call test "${base_before}" = "${base_after}"
      The status should be success
    End
  End

  Describe 'destroy on missing VM'
    It 'is a no-op (covered also in 60_destroy_residue)'
      When run command "${VM_BIN}" destroy "totally-nonexistent-vm-$$"
      The status should equal 0
    End
  End
End
