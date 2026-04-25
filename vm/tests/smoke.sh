#!/usr/bin/env bash
# Thin entrypoint for the vm/ end-to-end suite. Delegates to ShellSpec,
# which materializes every assertion in vm/spec/ as a TAP test.
#
# Default lane (fedora-cloud, ~5 min):
#   ./vm/tests/smoke.sh
#
# Include the kinoite lane (slow, +15-25 min):
#   VM_E2E_KINOITE=1 ./vm/tests/smoke.sh
#
# Run a single spec file (debugging):
#   ./vm/tests/smoke.sh spec/40_snapshot_reset_spec.sh
#
# JUnit XML output (CI consumption):
#   ./vm/tests/smoke.sh --format junit --output junit.xml

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit

if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 3) )); then
  printf 'ERROR: smoke.sh requires Bash 5.3+. Current: %s\n' "$BASH_VERSION" >&2
  exit 1
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v shellspec >/dev/null 2>&1; then
  cat >&2 <<'EOF'
shellspec not on PATH. Install one of:

  # Fedora 43:
  rpm-ostree install shellspec        # then reboot

  # Or vendored under vm/.shellspec-vendor/:
  curl -fsSL https://git.io/shellspec | sh -s -- --prefix vm/.shellspec-vendor --yes
  export PATH="vm/.shellspec-vendor/bin:$PATH"

See https://shellspec.info/ for other install paths.
EOF
  exit 69  # EXIT_PREREQ
fi

cd "${VM_DIR}"
exec shellspec "$@"
