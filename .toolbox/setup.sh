#!/usr/bin/env bash
#
# Build the pinned toolbox image and create the `scripts` toolbox container.
# Idempotent: safe to re-run. Set REBUILD=1 to force an image rebuild.
#
# Usage:
#   ./.toolbox/setup.sh              # build if missing, create container if missing
#   REBUILD=1 ./.toolbox/setup.sh    # rebuild image even if present
#   TRACE=1  ./.toolbox/setup.sh     # verbose xtrace

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s nullglob

if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 3) )); then
  printf 'ERROR: This script requires Bash 5.3+. Current: %s\n' "$BASH_VERSION" >&2
  exit 1
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONTAINERFILE="${SCRIPT_DIR}/Containerfile"
readonly IMAGE_REF="localhost/scripts-toolbox:fedora-43"
readonly CONTAINER_NAME="scripts"

if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  readonly _C_RESET=$'\033[0m'
  readonly _C_INFO=$'\033[1;34m'
  readonly _C_WARN=$'\033[1;33m'
  readonly _C_ERR=$'\033[1;31m'
else
  readonly _C_RESET=''
  readonly _C_INFO=''
  readonly _C_WARN=''
  readonly _C_ERR=''
fi

log()   { printf '%sinfo%s  %s\n' "${_C_INFO}" "${_C_RESET}" "$*" >&2; }
warn()  { printf '%swarn%s  %s\n' "${_C_WARN}" "${_C_RESET}" "$*" >&2; }
error() { printf '%serror%s %s\n' "${_C_ERR}"  "${_C_RESET}" "$*" >&2; }
die()   { error "$*"; exit 1; }

[[ "${TRACE:-0}" == "1" ]] && set -o xtrace

trap 'rc=$?; printf "%serror%s %s:%s: \"%s\" exited %s\n" "${_C_ERR}" "${_C_RESET}" "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "${rc}" >&2' ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 \
    || die "required command not found on PATH: $1"
}

image_exists() {
  podman image exists "${IMAGE_REF}"
}

container_exists() {
  podman container exists "${CONTAINER_NAME}"
}

build_image() {
  if image_exists && [[ "${REBUILD:-0}" != "1" ]]; then
    log "image ${IMAGE_REF} already present (set REBUILD=1 to force rebuild)"
    return 0
  fi
  log "building ${IMAGE_REF} from ${CONTAINERFILE}"
  # Force slirp4netns for the build network. The default pasta backend is
  # blocked by the passt-selinux policy shipped in Fedora 43 (AVC: pasta_t
  # cannot mounton tmpfs_t); slirp4netns sidesteps that without giving up
  # rootless network isolation. Override with BUILD_NETWORK=pasta once the
  # policy is fixed upstream.
  podman build \
    --network "${BUILD_NETWORK:-slirp4netns}" \
    --tag "${IMAGE_REF}" \
    --file "${CONTAINERFILE}" \
    "${SCRIPT_DIR}"
  image_exists || die "build reported success but image ${IMAGE_REF} is not present"
  log "image ${IMAGE_REF} ready"
}

create_container() {
  if container_exists; then
    log "toolbox container '${CONTAINER_NAME}' already exists"
    return 0
  fi
  log "creating toolbox '${CONTAINER_NAME}' from ${IMAGE_REF}"
  toolbox create --image "${IMAGE_REF}" --container "${CONTAINER_NAME}"
  container_exists \
    || die "toolbox create succeeded but container '${CONTAINER_NAME}' is not listed"
  log "toolbox '${CONTAINER_NAME}' ready"
}

main() {
  require_cmd podman
  require_cmd toolbox
  [[ -f "${CONTAINERFILE}" ]] || die "Containerfile not found: ${CONTAINERFILE}"

  build_image
  create_container

  log "done. enter the toolbox with:"
  printf '        toolbox enter %s\n' "${CONTAINER_NAME}" >&2
}

main "$@"
