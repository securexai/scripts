#!/usr/bin/env bash
# shellcheck shell=bash
# Kinoite path — slow (10–20 min build), opt-in via VM_E2E_KINOITE=1.
# Validates: bib pipeline emits a qcow2, the VM boots, rpm-ostree
# answers via ssh, destroy leaves no residue.

Describe 'kinoite (opt-in)'
  Skip if 'VM_E2E_KINOITE=1 not set' [[ -z "${VM_E2E_KINOITE:-}" ]]

  VM_NAME=$(e2e_vm_name)

  setup() {
    "${VM_BIN}" build-kinoite >/dev/null 2>&1
    "${VM_BIN}" create --target kinoite --name "${VM_NAME}" >/dev/null 2>&1
  }
  cleanup() { e2e_destroy_quiet "${VM_NAME}"; }
  BeforeAll 'setup'
  AfterAll  'cleanup'

  It 'bib produces a qcow2 in the cache'
    cache="${XDG_CACHE_HOME:-${HOME}/.cache}/scripts-vm/images/kinoite-out/qcow2/disk.qcow2"
    The path "${cache}" should be exist
  End

  It 'cache sidecar records the OCI digest used for the build'
    sidecar="${XDG_CACHE_HOME:-${HOME}/.cache}/scripts-vm/images/kinoite-out/.oci_digest"
    The path "${sidecar}" should be exist
  End

  It 'kinoite VM boots and rpm-ostree status responds'
    When run script "${VM_BIN}" ssh "${VM_NAME}" -- 'rpm-ostree status'
    The status should equal 0
    The output should include 'Deployments'
  End

  It 'destroy leaves no residue (parity with fedora-cloud)'
    "${VM_BIN}" destroy "${VM_NAME}" >/dev/null 2>&1
    When call assert_no_residue "${VM_NAME}"
    The status should be success
  End
End
