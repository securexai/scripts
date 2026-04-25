#!/usr/bin/env bash
# libvirt helpers — domain define/destroy, snapshot/revert, IP discovery,
# SSH wait. All operations target ${LIBVIRT_URI} (qemu:///session by default).
#
# Source after common.sh and paths.sh.
#
# Public:
#   vm_define   <name> <disk> <seed_iso> <os_variant> <vcpus> <mem_mib>
#   vm_destroy  <name>           — graceful shutdown then virsh destroy
#   vm_undefine <name>           — undefine domain (caller cleans disks)
#   vm_snapshot <name> <snap>    — internal qcow2 snapshot
#   vm_revert   <name> <snap>    — revert to snapshot
#   get_ipv4    <name>           — print first IPv4 from libvirt's lease/ARP
#   wait_for_ssh <name> [<timeout-seconds>]  — block until SSH is reachable
#   ssh_to      <name> [args…]   — exec ssh with the standard option set

[[ -n "${_VM_LIB_LIBVIRT_LOADED:-}" ]] && return 0
readonly _VM_LIB_LIBVIRT_LOADED=1

require_cmd virsh
require_cmd virt-install
require_cmd ssh

vm_define() {
  local name="$1" disk="$2" seed="$3" os_variant="$4" vcpus="$5" mem_mib="$6"
  log "defining domain ${name} (vcpus=${vcpus}, mem=${mem_mib}MiB, disk=${disk})"
  virt-install --connect "${LIBVIRT_URI}" \
    --name "${name}" \
    --memory "${mem_mib}" \
    --vcpus "${vcpus}" \
    --import \
    --disk "path=${disk},bus=virtio,format=qcow2" \
    --disk "path=${seed},device=cdrom,readonly=on" \
    --os-variant "${os_variant}" \
    --network "network=default,model=virtio" \
    --graphics none \
    --noautoconsole \
    --quiet \
    >/dev/null
}

vm_destroy() {
  local name="$1"
  if virsh -c "${LIBVIRT_URI}" domstate "${name}" 2>/dev/null | grep -q '^running$'; then
    log "shutting down ${name} (graceful, 30s timeout)"
    virsh -c "${LIBVIRT_URI}" shutdown "${name}" >/dev/null 2>&1 || true
    local end=$(( SECONDS + 30 ))
    while (( SECONDS < end )); do
      virsh -c "${LIBVIRT_URI}" domstate "${name}" 2>/dev/null | grep -q '^shut off$' && break
      sleep 2
    done
    if virsh -c "${LIBVIRT_URI}" domstate "${name}" 2>/dev/null | grep -q '^running$'; then
      warn "graceful shutdown timed out — forcing destroy"
      virsh -c "${LIBVIRT_URI}" destroy "${name}" >/dev/null 2>&1 || true
    fi
  fi
}

vm_undefine() {
  local name="$1"
  virsh -c "${LIBVIRT_URI}" undefine "${name}" --nvram >/dev/null 2>&1 || true
}

vm_snapshot() {
  local name="$1" snap="$2"
  log "creating snapshot '${snap}' on ${name}"
  virsh -c "${LIBVIRT_URI}" snapshot-create-as "${name}" "${snap}" --atomic >/dev/null
}

vm_revert() {
  local name="$1" snap="$2"
  log "reverting ${name} to snapshot '${snap}'"
  virsh -c "${LIBVIRT_URI}" snapshot-revert "${name}" "${snap}" --running --force >/dev/null
}

# Print first IPv4. Walks three sources in order:
#   agent — qemu-guest-agent (only if installed in guest)
#   lease — libvirt's DHCP lease table (works for NAT forward mode)
#   arp   — host neighbor cache (required for 'bridge' forward mode where
#           session libvirt has no lease table — the VM's MAC shows up via
#           the host bridge's tap interface even though dnsmasq lives on
#           the system network)
# Returns 0 on first successful match; 1 if no source has an IPv4 yet.
get_ipv4() {
  local name="$1"
  local out ip source
  for source in agent lease arp; do
    out=$(virsh -c "${LIBVIRT_URI}" domifaddr "${name}" --source "${source}" 2>/dev/null) \
      || continue
    ip=$(awk '$3 == "ipv4" && $1 != "lo" { split($4, a, "/"); print a[1]; exit }' <<<"${out}")
    if [[ -n "${ip}" ]]; then
      printf '%s' "${ip}"
      return 0
    fi
  done
  return 1
}

# Standard ssh option set for ephemeral test VMs:
#   - skip strict host key checking and known_hosts pollution
#   - batch mode (no password prompts)
#   - short connect timeout so probes fail fast
_ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=5
)

# Compose identity args for a VM. If a per-VM ephemeral key was generated
# at create time (by cloudinit.sh::_resolve_vm_pubkey), use it explicitly
# with IdentitiesOnly=yes so the agent or other configured identities
# don't shadow it. Empty array if no per-VM key exists (user opted in to
# host key via VM_SSH_PUBKEY, or this is a legacy VM created pre-B1).
_vm_identity_args() {
  local name="$1"
  local key="${SEED_DIR}/${name}/ssh_key"
  if [[ -f "${key}" ]]; then
    printf -- '-i\n%s\n-o\nIdentitiesOnly=yes\n' "${key}"
  fi
}

ssh_to() {
  local name="$1"; shift
  local user="${DEFAULT_USER:-fedora}" ip
  ip=$(get_ipv4 "${name}") || die_with "${EXIT_LIBVIRT}" "no IPv4 address yet for ${name}"
  local id_args=()
  mapfile -t id_args < <(_vm_identity_args "${name}")
  exec ssh "${_ssh_opts[@]}" "${id_args[@]}" "${user}@${ip}" "$@"
}

# Non-exec variant for callers that need to keep running after the
# remote command finishes (readiness gates, probes, internal scripts).
# Returns the remote exit code.
vm_ssh_run() {
  local name="$1"; shift
  local user="${DEFAULT_USER:-fedora}" ip
  ip=$(get_ipv4 "${name}") || die_with "${EXIT_LIBVIRT}" "no IPv4 address yet for ${name}"
  local id_args=()
  mapfile -t id_args < <(_vm_identity_args "${name}")
  ssh "${_ssh_opts[@]}" "${id_args[@]}" "${user}@${ip}" "$@"
}

wait_for_ssh() {
  local name="$1" timeout="${2:-180}"
  local user="${DEFAULT_USER:-fedora}" ip
  log "waiting up to ${timeout}s for SSH on ${name}"
  local id_args=()
  mapfile -t id_args < <(_vm_identity_args "${name}")
  local end=$(( SECONDS + timeout ))
  while (( SECONDS < end )); do
    if ip=$(get_ipv4 "${name}") && [[ -n "${ip}" ]]; then
      if ssh "${_ssh_opts[@]}" "${id_args[@]}" "${user}@${ip}" true 2>/dev/null; then
        log "SSH ready: ${user}@${ip}"
        printf '%s' "${ip}"
        return 0
      fi
    fi
    sleep 3
  done
  die_with "${EXIT_NET}" "timed out waiting for SSH to ${name} (${timeout}s)"
}
