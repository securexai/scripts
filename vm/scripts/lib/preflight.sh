# shellcheck shell=bash
# Host preflight checks for the vm/ workflow. Fails fast with EXIT_PREREQ
# and a one-line diagnostic naming the gap.
#
# Source after common.sh and paths.sh.
#
# Public:
#   preflight_full     — run every check (used by setup.sh + verbose mode)
#   preflight_fast     — env-only (used by the CLI dispatcher; no fork/exec)
#   preflight_check_<name>  — individual checks, useful for unit tests
#
# Each check function returns 0 on success and prints a single-line
# diagnostic on failure (without exiting). The orchestrators (full/fast)
# decide whether to die_with EXIT_PREREQ or just warn.

[[ -n "${_VM_LIB_PREFLIGHT_LOADED:-}" ]] && return 0
readonly _VM_LIB_PREFLIGHT_LOADED=1

# Pure: parse /etc/os-release for ID and VERSION_ID. Returns 0 if
# ID=fedora and VERSION_ID matches one of the expected values
# (whitespace-separated allowlist; default: "43"). Lets a single
# preflight straddle a Fedora version bump (e.g. "43 44") without
# branching the codebase. Tracked under R-019.
# Args: [expected_version_id_allowlist]
preflight_check_os_id() {
  local expected="${1:-43}"
  local os_release="/etc/os-release"
  [[ -r "${os_release}" ]] || { error "no /etc/os-release"; return 1; }
  local id version_id
  id=$(awk -F= '$1=="ID"        { gsub(/"/,"",$2); print $2; exit }' "${os_release}")
  version_id=$(awk -F= '$1=="VERSION_ID" { gsub(/"/,"",$2); print $2; exit }' "${os_release}")
  if [[ "${id}" != "fedora" ]]; then
    error "host OS is '${id}', expected 'fedora'"
    return 1
  fi
  local _allow=() v
  read -ra _allow <<< "${expected}"
  for v in "${_allow[@]}"; do
    [[ "${version_id}" == "${v}" ]] && return 0
  done
  error "host Fedora version is '${version_id}', expected one of: ${expected}"
  return 1
}

# /dev/kvm exists and is read+write by the current user.
preflight_check_kvm() {
  if [[ ! -e /dev/kvm ]]; then
    error "/dev/kvm missing — KVM not loaded; check 'lsmod | grep kvm' and CPU virt extensions"
    return 1
  fi
  if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    error "/dev/kvm not r/w for $(id -un) — add user to 'kvm' group: sudo usermod -aG kvm $(id -un)"
    return 1
  fi
  return 0
}

# Required binaries on PATH. Caller supplies the list.
preflight_check_binaries() {
  local missing=() bin
  for bin in "$@"; do
    command -v "${bin}" >/dev/null 2>&1 || missing+=("${bin}")
  done
  if (( ${#missing[@]} > 0 )); then
    error "missing required binaries on PATH: ${missing[*]}"
    return 1
  fi
  return 0
}

# Libvirt daemon reachable on the configured URI. We use `virsh hostname`
# because it round-trips the daemon socket without enumerating domains.
preflight_check_virsh_reachable() {
  local uri="${LIBVIRT_URI:-qemu:///session}"
  if ! virsh -c "${uri}" hostname >/dev/null 2>&1; then
    error "virsh cannot reach ${uri} — Fedora 43 uses modular daemons; check 'pgrep virtqemud' or 'systemctl --user list-unit-files | grep virt'"
    return 1
  fi
  return 0
}

# virt-host-validate is libvirt's canonical preflight. We run only the
# qemu driver checks. Treat WARN as advisory; only PASS/FAIL gate.
# Skipped (with a warn) if the binary is unavailable.
preflight_check_virt_host_validate() {
  if ! command -v virt-host-validate >/dev/null 2>&1; then
    warn "virt-host-validate not on PATH — skipping (install: rpm-ostree install libvirt-client)"
    return 0
  fi
  if ! virt-host-validate qemu >/dev/null 2>&1; then
    error "virt-host-validate qemu reported failures — run 'virt-host-validate qemu' to see them"
    return 1
  fi
  return 0
}

# SSH pubkey readable. Default mode is per-VM ephemeral keys (B1) — the
# host pubkey is not needed and we silently pass. Only checked when the
# user has explicitly opted in to the host key via VM_SSH_PUBKEY.
preflight_check_ssh_pubkey() {
  [[ -n "${VM_SSH_PUBKEY:-}" ]] || return 0
  if [[ ! -r "${VM_SSH_PUBKEY}" ]]; then
    error "VM_SSH_PUBKEY set but not readable: ${VM_SSH_PUBKEY}"
    return 1
  fi
  return 0
}

# Toolbox bridge: when running inside /run/.containerenv, verify the
# host libvirt socket is bind-mounted and reachable from inside.
preflight_check_toolbox_socket() {
  [[ -e /run/.containerenv ]] || return 0
  local sock
  sock="/run/user/$(id -u)/libvirt/virtqemud-sock"
  if [[ ! -S "${sock}" ]]; then
    error "inside toolbox but libvirt socket not bind-mounted: ${sock} — see DEPLOYMENT.md 'Toolbox Bridge'"
    return 1
  fi
  return 0
}

# Fast path: env-only, no fork/exec. Suitable for the dispatcher to
# gate every subcommand without measurable latency.
preflight_fast() {
  preflight_check_os_id "${VM_EXPECTED_FEDORA:-43}" || die_with "${EXIT_PREREQ}" "preflight_fast: OS check failed"
  preflight_check_kvm                                || die_with "${EXIT_PREREQ}" "preflight_fast: KVM check failed"
}

# Full path: every check. Used by setup.sh and by `vm` when called with
# VM_PREFLIGHT=full (debugging) or before destructive operations.
preflight_full() {
  local rc=0
  preflight_check_os_id "${VM_EXPECTED_FEDORA:-43}" || rc=1
  preflight_check_kvm                               || rc=1
  preflight_check_binaries virsh virt-install qemu-img genisoimage curl sha256sum || rc=1
  preflight_check_virt_host_validate                || rc=1
  preflight_check_virsh_reachable                   || rc=1
  preflight_check_toolbox_socket                    || rc=1
  preflight_check_ssh_pubkey                        || rc=1
  if (( rc != 0 )); then
    die_with "${EXIT_PREREQ}" "preflight_full: one or more checks failed (see above)"
  fi
  log "preflight: all checks passed"
}
