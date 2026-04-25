#!/usr/bin/env bash
# shellcheck shell=bash
# Cockpit overlay (A3): with --with-cockpit the socket is active and the
# admin UI answers on :9090. Without the flag, port 9090 is closed.
#
# Two distinct VMs (with + without) so the negative case is real, not
# inferred from a missing-package check on a single image.

Describe 'cockpit overlay'
  VM_WITH=$(e2e_vm_name)-with
  VM_WITHOUT=$(e2e_vm_name)-without

  setup() {
    "${VM_BIN}" create --target fedora-cloud --name "${VM_WITHOUT}" >/dev/null 2>&1
    "${VM_BIN}" create --target fedora-cloud --name "${VM_WITH}" --with-cockpit >/dev/null 2>&1
  }
  cleanup() {
    e2e_destroy_quiet "${VM_WITH}"
    e2e_destroy_quiet "${VM_WITHOUT}"
  }
  BeforeAll 'setup'
  AfterAll  'cleanup'

  Describe 'with --with-cockpit'
    It 'cockpit.socket is active on the VM'
      When run command "${VM_BIN}" ssh "${VM_WITH}" -- \
        'systemctl is-active cockpit.socket'
      The status should equal 0
      The output should equal 'active'
    End

    It 'metadata sidecar records WITH_COCKPIT=1'
      state="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"
      When call grep -F 'WITH_COCKPIT=1' "${state}/seeds/${VM_WITH}/.metadata"
      The status should be success
    End

    It 'host can curl https://<vm-ip>:9090 (cockpit answers)'
      ip=$(virsh -c "${LIBVIRT_DEFAULT_URI}" domifaddr "${VM_WITH}" \
           | awk '$3=="ipv4"{split($4,a,"/");print a[1];exit}')
      When run command curl -kfsS --max-time 8 -o /dev/null \
        -w '%{http_code}' "https://${ip}:9090/"
      The status should equal 0
      # Cockpit answers 200 (login page) or 301/302 to /system.
      The output should match pattern '20[0-9]|30[12]'
    End
  End

  Describe 'without --with-cockpit'
    It 'cockpit package is not installed on the default VM'
      When run command "${VM_BIN}" ssh "${VM_WITHOUT}" -- 'rpm -q cockpit'
      The status should not equal 0
    End

    It 'port 9090 is closed (TCP connect fails)'
      ip=$(virsh -c "${LIBVIRT_DEFAULT_URI}" domifaddr "${VM_WITHOUT}" \
           | awk '$3=="ipv4"{split($4,a,"/");print a[1];exit}')
      # Use bash's /dev/tcp; nc may not be on the host.
      When run command bash -c "exec 9<>/dev/tcp/${ip}/9090 2>/dev/null"
      The status should not equal 0
    End
  End
End
