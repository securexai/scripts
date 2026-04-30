#!/usr/bin/env bash
# shellcheck shell=bash
# vm prune — auto-defined libvirt storage pools that virt-install leaks.
# Synthetic libvirt fixtures (pool-define-as on a fake directory) so this
# spec runs in seconds without spinning up a VM. Path-based residue
# detection — name match alone would risk undefining operator pools.
#
# This spec stays out of 65_prune_spec.sh because that one is committed
# to synthetic FILESYSTEM fixtures with no libvirt mutation. Pool
# residue is a separate axis and lives in its own file.

Describe 'vm prune — leaked dir pools'
  STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/scripts-vm"
  SEEDS="${STATE}/seeds"
  ORPHAN_NAME="prune-pool-orphan-$$"
  SAFE_POOL_NAME="prune-pool-safe-$$"
  # Sibling of $SEEDS under $STATE — outside the subtree the sweep
  # is allowed to touch. Operator-defined pools commonly point here.
  SAFE_POOL_DIR="${STATE}/prune-pool-safe-target-$$"

  setup() {
    mkdir -p "${SEEDS}/${ORPHAN_NAME}" "${SAFE_POOL_DIR}"
    # Mimic virt-install's auto-defined pool: dir-type, name == VM
    # name, target == ${SEEDS}/<name>. Inactive is the leak shape.
    virsh -c "${LIBVIRT_DEFAULT_URI}" pool-define-as \
      "${ORPHAN_NAME}" dir --target "${SEEDS}/${ORPHAN_NAME}" \
      >/dev/null 2>&1 || true
    virsh -c "${LIBVIRT_DEFAULT_URI}" pool-define-as \
      "${SAFE_POOL_NAME}" dir --target "${SAFE_POOL_DIR}" \
      >/dev/null 2>&1 || true
  }
  cleanup() {
    rm -rf "${SEEDS}/${ORPHAN_NAME}" "${SAFE_POOL_DIR}"
    # Best-effort: production code is expected to drop ORPHAN_NAME
    # under --apply; SAFE_POOL_NAME is always our responsibility.
    virsh -c "${LIBVIRT_DEFAULT_URI}" pool-destroy   "${ORPHAN_NAME}"    >/dev/null 2>&1 || true
    virsh -c "${LIBVIRT_DEFAULT_URI}" pool-undefine  "${ORPHAN_NAME}"    >/dev/null 2>&1 || true
    virsh -c "${LIBVIRT_DEFAULT_URI}" pool-destroy   "${SAFE_POOL_NAME}" >/dev/null 2>&1 || true
    virsh -c "${LIBVIRT_DEFAULT_URI}" pool-undefine  "${SAFE_POOL_NAME}" >/dev/null 2>&1 || true
  }
  BeforeEach 'setup'
  AfterEach  'cleanup'

  It 'dry-run reports the leaked pool and removes nothing'
    When run script "${VM_BIN}" prune
    The status should equal 0
    The stderr should match pattern "*would remove pool:*${ORPHAN_NAME}*"
    pool_after=$(virsh -c "${LIBVIRT_DEFAULT_URI}" pool-list --all --name 2>/dev/null)
    The variable pool_after should include "${ORPHAN_NAME}"
  End

  It '--apply undefines the leaked pool whose path is under $SEED_DIR'
    When run script "${VM_BIN}" prune --apply
    The status should equal 0
    The stderr should include 'pruned'
    pool_after=$(virsh -c "${LIBVIRT_DEFAULT_URI}" pool-list --all --name 2>/dev/null)
    The variable pool_after should not include "${ORPHAN_NAME}"
  End

  It '--apply leaves pools whose path is OUTSIDE $SEED_DIR untouched'
    When run script "${VM_BIN}" prune --apply
    The status should equal 0
    The stderr should include 'pruned'
    pool_after=$(virsh -c "${LIBVIRT_DEFAULT_URI}" pool-list --all --name 2>/dev/null)
    The variable pool_after should include "${SAFE_POOL_NAME}"
  End
End
