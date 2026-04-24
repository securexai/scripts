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

# Pick the right podman invocation: host podman directly when on the host,
# `flatpak-spawn --host podman` from inside a toolbox/flatpak sandbox.
_resolve_podman() {
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
  [[ -r "${target_env}" ]] || die "target env not readable: ${target_env}"

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
    || die "kinoite env missing required vars (OCI_REF/OCI_DIGEST/BIB_VERSION/BIB_CONFIG_REL)"

  local bib_config="${_BIB_VM_ROOT}/targets/${bib_config_rel}"
  [[ -r "${bib_config}" ]] || die "bib config not found: ${bib_config}"

  local out_dir="${IMAGE_CACHE_DIR}/kinoite-out"
  mkdir -p "${out_dir}"

  local qcow="${out_dir}/qcow2/disk.qcow2"
  if [[ "${REBUILD:-0}" != "1" ]] && [[ -f "${qcow}" ]]; then
    log "kinoite qcow2 cache hit: ${qcow} (set REBUILD=1 to rebuild)"
    printf '%s' "${qcow}"
    return 0
  fi

  rm -rf "${out_dir}"
  mkdir -p "${out_dir}"

  # shellcheck disable=SC2086  # _PODMAN may contain space-separated tokens
  local _PODMAN; _PODMAN=$(_resolve_podman)
  log "pulling ${oci_ref}@${oci_digest}"
  ${_PODMAN} pull "${oci_ref}@${oci_digest}" >/dev/null

  log "running bootc-image-builder ${bib_version}"
  # shellcheck disable=SC2086
  ${_PODMAN} run --rm --privileged --security-opt label=disable \
    -v "${bib_config}:/config.toml:ro" \
    -v "${out_dir}:/output" \
    "quay.io/centos-bootc/bootc-image-builder:${bib_version}" \
    --type qcow2 \
    --config /config.toml \
    "${oci_ref}@${oci_digest}"

  [[ -f "${qcow}" ]] || die "bib finished but expected output not found: ${qcow}"
  log "kinoite qcow2 ready: ${qcow}"
  printf '%s' "${qcow}"
}
