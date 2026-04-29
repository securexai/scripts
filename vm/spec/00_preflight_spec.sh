#!/usr/bin/env bash
# shellcheck shell=bash
# Host preflight assertions. Pure-function unit tests use `When call`
# (no fork). Integration probes use `When run command`.

Describe 'preflight'
  Include "${VM_ROOT}/scripts/lib/common.sh"
  Include "${VM_ROOT}/scripts/lib/paths.sh"
  Include "${VM_ROOT}/scripts/lib/preflight.sh"

  Describe 'preflight_check_os_id (pure)'
    It 'accepts the host when ID=fedora and VERSION_ID matches'
      When call preflight_check_os_id "${VM_EXPECTED_FEDORA:-43}"
      The status should be success
    End

    It 'rejects a wrong VERSION_ID'
      When call preflight_check_os_id 999
      The status should be failure
      The stderr should include "expected one of: 999"
    End

    It 'accepts a whitespace-separated allowlist (R-019 straddle)'
      When call preflight_check_os_id "${VM_EXPECTED_FEDORA:-43} 999"
      The status should be success
    End
  End

  Describe 'preflight_check_kvm'
    It '/dev/kvm is present and writable'
      When call preflight_check_kvm
      The status should be success
    End
  End

  Describe 'preflight_check_binaries'
    It 'passes when every requested binary is on PATH'
      When call preflight_check_binaries virsh virt-install qemu-img genisoimage
      The status should be success
    End

    It 'fails and names the missing binary'
      When call preflight_check_binaries definitely-not-a-real-cmd-9c8a7b
      The status should be failure
      The stderr should include 'definitely-not-a-real-cmd-9c8a7b'
    End
  End

  Describe 'preflight_check_virsh_reachable'
    It 'virsh hostname round-trips against LIBVIRT_URI'
      When call preflight_check_virsh_reachable
      The status should be success
    End
  End

  Describe 'dispatcher'
    It 'prints help and exits 0 when invoked with help'
      When run script "${VM_BIN}" help
      The status should equal 0
      The stderr should include 'usage: vm <subcommand>'
    End

    It 'rejects an unknown subcommand with EXIT_USAGE'
      When run script "${VM_BIN}" not-a-real-subcommand
      The status should equal 64
      The stderr should include 'unknown subcommand'
    End
  End
End
