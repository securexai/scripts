#!/usr/bin/env bash
# Image acquisition: download + sha256 verify + atomic rename, with REBUILD
# support. Caches under IMAGE_CACHE_DIR (XDG_CACHE_HOME).
#
# Source after common.sh and paths.sh.
#
# Public:
#   ensure_image <target-env-file>
#     Sources the env file (must define IMAGE_URL and IMAGE_SHA256), ensures
#     the cached image matches the pinned sha256, and prints the absolute
#     path to the cached image on stdout. All log lines go to stderr.

[[ -n "${_VM_LIB_IMAGES_LOADED:-}" ]] && return 0
readonly _VM_LIB_IMAGES_LOADED=1

require_cmd curl
require_cmd sha256sum

# Download an image to a .partial file, verify sha256, atomic-rename into place.
# Stdout: absolute path to the verified cached image.
ensure_image() {
  local target_env="$1"
  [[ -r "${target_env}" ]] || die "target env file not readable: ${target_env}"

  # Subshell isolates the sourced variables so the caller's environment is
  # not polluted by IMAGE_URL etc.
  local image_url image_sha256
  # shellcheck disable=SC1090  # dynamic source path is intentional
  read -r image_url image_sha256 < <(
    set -o errexit -o nounset
    # shellcheck disable=SC1090
    . "${target_env}"
    [[ -n "${IMAGE_URL:-}" ]] || { printf 'MISSING_IMAGE_URL ' >&2; exit 1; }
    [[ -n "${IMAGE_SHA256:-}" ]] || { printf 'MISSING_IMAGE_SHA256 ' >&2; exit 1; }
    printf '%s %s\n' "${IMAGE_URL}" "${IMAGE_SHA256}"
  )

  [[ -n "${image_url}" ]]    || die "IMAGE_URL not set in ${target_env}"
  [[ -n "${image_sha256}" ]] || die "IMAGE_SHA256 not set in ${target_env} — fetch the upstream CHECKSUM file and pin the value"

  local cache_path="${IMAGE_CACHE_DIR}/$(basename "${image_url}")"
  local partial="${cache_path}.partial"

  # Check: cached + sha matches and not forced to rebuild.
  if [[ "${REBUILD:-0}" != "1" ]] && [[ -f "${cache_path}" ]]; then
    if printf '%s  %s\n' "${image_sha256}" "${cache_path}" | sha256sum -c --status; then
      log "image cache hit: ${cache_path}"
      printf '%s' "${cache_path}"
      return 0
    fi
    warn "cached image sha256 mismatch — re-downloading"
    rm -f "${cache_path}"
  fi

  # Action: download to .partial.
  log "downloading ${image_url}"
  rm -f "${partial}"
  if ! curl --fail --location --retry 3 --retry-delay 5 --silent --show-error \
       --output "${partial}" "${image_url}"; then
    rm -f "${partial}"
    die "download failed: ${image_url}"
  fi

  # Verify: sha256 against the pinned value.
  if ! printf '%s  %s\n' "${image_sha256}" "${partial}" | sha256sum -c --status; then
    rm -f "${partial}"
    die "sha256 mismatch on freshly downloaded image — pin in ${target_env} may be stale or upstream changed"
  fi

  # Atomic rename — readers never see a half-written file.
  mv -f "${partial}" "${cache_path}"
  log "image ready: ${cache_path}"
  printf '%s' "${cache_path}"
}
