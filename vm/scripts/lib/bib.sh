#!/usr/bin/env bash
# Kinoite qcow2 builder via bootc-image-builder (bib).
#
# Source after common.sh and paths.sh.
#
# bib runs in privileged podman, so this driver is meant to invoke the host
# podman (not a podman-in-podman). When called from inside the toolbox,
# falls back to `flatpak-spawn --host podman` if available.
#
# Public:
#   build_kinoite_qcow <target-env-file>
#     Sources the env file (must define OCI_REF, OCI_DIGEST, BIB_VERSION,
#     BIB_CONFIG_REL). Pulls the OCI image, runs bib with the kinoite.toml
#     config, and prints the absolute path to the produced qcow2 on stdout.

[[ -n "${_VM_LIB_BIB_LOADED:-}" ]] && return 0
readonly _VM_LIB_BIB_LOADED=1

# Resolve VM_ROOT (lib/ -> scripts/ -> vm/) for finding target configs.
readonly _BIB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly _BIB_VM_ROOT="$(cd "${_BIB_LIB_DIR}/../.." && pwd)"

# Pick the right podman invocation. Three contexts:
#   1. BIB_ROOTFUL=1 — use `sudo podman` (rootful). bootc-image-builder
#      needs CAP_SYS_ADMIN to remount its sandbox; rootless privileged
#      podman fails with "Failed to remount /: Permission denied" on
#      Fedora 43+. Requires passwordless sudo (`sudo -n true`).
#   2. Inside a toolbox/flatpak sandbox: `flatpak-spawn --host podman`.
#   3. Default: rootless `podman` on the host.
_resolve_podman() {
  if [[ "${BIB_ROOTFUL:-0}" == "1" ]]; then
    sudo -n true 2>/dev/null \
      || die_with "${EXIT_PREREQ}" "BIB_ROOTFUL=1 needs passwordless sudo for 'sudo podman'"
    printf 'sudo podman'
    return 0
  fi
  if [[ -e /run/.containerenv ]] && command -v flatpak-spawn >/dev/null 2>&1; then
    printf 'flatpak-spawn --host podman'
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    printf 'podman'
    return 0
  fi
  die "no usable podman: install on host (rpm-ostree install podman) or run from a context that exposes flatpak-spawn"
}

build_kinoite_qcow() {
  local target_env="$1"
  local config_override="${2:-}"
  [[ -r "${target_env}" ]] || die_with "${EXIT_USAGE}" "target env not readable: ${target_env}"

  local oci_ref oci_digest bib_version bib_config_rel
  read -r oci_ref oci_digest bib_version bib_config_rel < <(
    set -o errexit -o nounset
    # shellcheck disable=SC1090
    . "${target_env}"
    [[ -n "${OCI_REF:-}" ]]        || { echo "MISSING_OCI_REF" >&2; exit 1; }
    [[ -n "${OCI_DIGEST:-}" ]]     || { echo "MISSING_OCI_DIGEST" >&2; exit 1; }
    [[ -n "${BIB_VERSION:-}" ]]    || { echo "MISSING_BIB_VERSION" >&2; exit 1; }
    [[ -n "${BIB_CONFIG_REL:-}" ]] || { echo "MISSING_BIB_CONFIG_REL" >&2; exit 1; }
    printf '%s %s %s %s\n' "${OCI_REF}" "${OCI_DIGEST}" "${BIB_VERSION}" "${BIB_CONFIG_REL}"
  )

  [[ -n "${oci_ref}" && -n "${oci_digest}" && -n "${bib_version}" && -n "${bib_config_rel}" ]] \
    || die_with "${EXIT_USAGE}" "kinoite env missing required vars (OCI_REF/OCI_DIGEST/BIB_VERSION/BIB_CONFIG_REL)"

  # Override config (e.g. kinoite-cockpit.toml) keeps a separate output
  # cache so a base build and a cockpit build don't clobber each other.
  local effective_config_rel="${config_override:-${bib_config_rel}}"
  local bib_config="${_BIB_VM_ROOT}/targets/${effective_config_rel}"
  [[ -r "${bib_config}" ]] || die_with "${EXIT_USAGE}" "bib config not found: ${bib_config}"

  local out_subdir="kinoite-out"
  if [[ -n "${config_override}" ]]; then
    out_subdir="kinoite-out-${config_override%.toml}"
  fi
  local out_dir="${IMAGE_CACHE_DIR}/${out_subdir}"
  mkdir -p "${out_dir}"

  local qcow="${out_dir}/qcow2/disk.qcow2"
  local digest_sidecar="${out_dir}/.oci_digest"

  # Cache hit only if the qcow2 exists AND was built from the digest
  # currently pinned in the env file. Otherwise, the upstream pin moved
  # and we must rebuild. The sidecar is written atomically after a
  # successful build (see below).
  if [[ "${REBUILD:-0}" != "1" ]] && [[ -f "${qcow}" ]]; then
    if [[ -r "${digest_sidecar}" ]] && [[ "$(< "${digest_sidecar}")" == "${oci_digest}" ]]; then
      log "kinoite qcow2 cache hit: ${qcow} (digest matches; set REBUILD=1 to force)"
      printf '%s' "${qcow}"
      return 0
    fi
    warn "kinoite qcow2 cache present but OCI_DIGEST has drifted — rebuilding"
  fi

  rm -rf "${out_dir}"
  mkdir -p "${out_dir}"

  # shellcheck disable=SC2086  # _PODMAN may contain space-separated tokens
  local _PODMAN; _PODMAN=$(_resolve_podman)

  # Local images (oci_ref starts with localhost/) are already in podman's
  # store — pulling would fail. bib accepts the bare `localhost/<name>:<tag>`
  # reference (NOT `containers-storage:<...>` — bib's parser rejects that)
  # and resolves it against the bind-mounted /var/lib/containers/storage.
  local bib_ref
  if [[ "${oci_ref}" == localhost/* ]]; then
    log "using local OCI: ${oci_ref}"
    bib_ref="${oci_ref}"
  else
    log "pulling ${oci_ref}@${oci_digest}"
    ${_PODMAN} pull "${oci_ref}@${oci_digest}" >/dev/null
    bib_ref="${oci_ref}@${oci_digest}"
  fi

  # Rootful bib needs the host's container storage mounted so it can
  # resolve the OCI ref we just pulled (ref lives in root's libpod store,
  # which the bib container otherwise can't see). Same mount lets it
  # resolve `containers-storage:` refs to locally-built derived images.
  local store_mount=()
  if [[ "${BIB_ROOTFUL:-0}" == "1" ]]; then
    store_mount+=(-v /var/lib/containers/storage:/var/lib/containers/storage)
  fi

  log "running bootc-image-builder ${bib_version}"
  # shellcheck disable=SC2086
  ${_PODMAN} run --rm --privileged --security-opt label=disable \
    "${store_mount[@]}" \
    -v "${bib_config}:/config.toml:ro" \
    -v "${out_dir}:/output" \
    "quay.io/centos-bootc/bootc-image-builder:${bib_version}" \
    --type qcow2 \
    --config /config.toml \
    "${bib_ref}"

  # Rootful bib writes /output as uid 0 on the host. Reclaim ownership
  # so libvirt's session URI can read the qcow2 without escalation.
  if [[ "${BIB_ROOTFUL:-0}" == "1" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "${out_dir}"
  fi

  [[ -f "${qcow}" ]] || die_with "${EXIT_GENERIC}" "bib finished but expected output not found: ${qcow}"

  # Record the digest used for this build so the next cache-hit check can
  # detect upstream drift. Atomic write via mv so a partial sidecar never
  # validates a stale qcow.
  printf '%s' "${oci_digest}" > "${digest_sidecar}.partial"
  mv -f "${digest_sidecar}.partial" "${digest_sidecar}"

  log "kinoite qcow2 ready: ${qcow}"
  printf '%s' "${qcow}"
}
