# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal collection of operator scripts for a Fedora 43 or 44 host.
Currently two top-level directories:

- **`vm/`** — the only substantial subsystem: a libvirt + cloud-init test
  rig with a 11-verb CLI dispatcher, a ShellSpec e2e suite, and a bootc
  OCI build path. Self-contained; everything below is about it.
- **`bash/`** — one-off bash hook scripts; no shared infrastructure.
- **`.toolbox/`** — Containerfile + `setup.sh` that build the
  `localhost/scripts-toolbox:fedora-43` image and create the `scripts`
  toolbox container. Day-to-day dev happens inside that toolbox.

There is **no Python, no Node, no uv/Ruff** in this repo — the global
template's `[Tool Execution]` section about uv/Ruff does not apply here.
This is a pure Bash 5.3+ repo. Pre-commit hooks are configured per the
global enforcement baseline (`.pre-commit-config.yaml`); shellcheck runs
at `--severity=error` until the SC2155 cleanup follow-up lands.

## Common commands

```bash
# Toolbox bootstrap (one-time per host)
./.toolbox/setup.sh                            # build image + create container
REBUILD=1 ./.toolbox/setup.sh                  # force image rebuild

# vm/ host bootstrap (one-time on a new Fedora 43 host)
./vm/setup.sh                                  # rpm-ostree layer + preflight
USE_LIBVIRT_GROUP=1 ./vm/setup.sh              # opt in to qemu:///system

# Day-to-day VM lifecycle
./vm/scripts/vm create --target fedora-cloud --name X   # ~60 s
./vm/scripts/vm ssh X -- 'uname -r'                     # one-off remote cmd
./vm/scripts/vm snapshot X clean                        # internal qcow2 snapshot
./vm/scripts/vm reset X clean                           # revert to snapshot
./vm/scripts/vm prune                                   # dry-run orphan cleanup
./vm/scripts/vm prune --apply                           # commit cleanup
./vm/scripts/vm destroy X                               # full teardown

# bootc / kinoite lane (slow, opt-in)
sudo podman build -t localhost/scripts-vm-bootc:latest -f vm/Containerfile.bootc vm/
BIB_ROOTFUL=1 ./vm/scripts/vm build-kinoite             # 10–25 min, cached

# Tests (ShellSpec)
./vm/tests/smoke.sh                            # default lane, ~5 min
./vm/tests/smoke.sh --format tap               # TAP for tooling
cd vm && shellspec spec/65_prune_spec.sh       # single spec
VM_E2E_KINOITE=1 ./vm/tests/smoke.sh           # opt-in kinoite lane
VM_E2E_COCKPIT=1 ./vm/tests/smoke.sh           # opt-in cockpit lane

# Status doc
vm/DEPLOYMENT.md                               # risk register, test matrix, runbook
```

## Architecture

### vm/ dispatcher pattern

```text
vm/scripts/vm                       ← entry point; argv[1] = subcommand
  ├── lib/common.sh                 ← strict-mode preamble + log/die/EXIT_* + require_cmd
  ├── lib/paths.sh                  ← XDG dirs + LIBVIRT_URI default
  ├── lib/preflight.sh              ← OS/KVM/binary checks
  └── exec subcommands/<verb>.sh    ← one file per verb (create, destroy, prune, …)
       └── sources lib/* as needed (libvirt, cloudinit, bib, locks, images)
```

Subcommands are not functions — they're separate scripts that the
dispatcher `exec`s after preflight. Each subcommand re-sources the
libs it needs. Module-load is guarded by `[[ -n "${_VM_LIB_X_LOADED:-}" ]]
&& return 0` so re-sourcing is a no-op.

### Conventions enforced across vm/

- **Bash 5.3+ required** — checked at runtime in `common.sh` and
  `tests/smoke.sh`. `inherit_errexit` is used; do not break it.
- **Exit-code taxonomy** (sysexits-flavored):
  `EXIT_OK=0 / EXIT_GENERIC=1 / EXIT_USAGE=64 / EXIT_PREREQ=69 /
  EXIT_LIBVIRT=70 / EXIT_NET=71 / EXIT_CLOUDINIT=72`. Use
  `die_with <code> <msg>` rather than bare `die` so failures classify.
- **`require_cmd <bin>`** — guard every external dependency at the top
  of each lib, fails with `EXIT_PREREQ` if missing.
- **`shopt -s nullglob`** is set repo-wide; loops over empty globs
  iterate zero times instead of literal patterns. Code relies on this.
- **XDG paths only** — base images at `${XDG_CACHE_HOME}/scripts-vm/images/`,
  overlay disks at `${XDG_STATE_HOME}/scripts-vm/disks/`, cloud-init seeds
  at `${XDG_STATE_HOME}/scripts-vm/seeds/<vm-name>/`. Never write under
  the repo or `$HOME/.scripts-vm/` etc.
- **`qemu:///session` by default** — rootless, no group needed. The
  one host caveat is R-013: session libvirt has no `default` NAT network
  out of the box; a one-time `virsh net-define` of a bridge alias to
  `virbr0` is needed (documented in DEPLOYMENT.md Phase 1.5).
- **Per-VM ephemeral ed25519 keys** — generated at create, wiped at
  destroy. Override with `VM_SSH_PUBKEY=<host pubkey>` to inject your
  host key instead.
- **Advisory `flock`** on `${SEED_DIR}/<name>.lock` for create/destroy
  parallel-safety. Helpers live in `lib/locks.sh` —
  `vm_lock_acquire / vm_lock_try_acquire / vm_lock_release{,_and_unlink}`.
  The fd-survives-unlink invariant is load-bearing; preserve it.
- **ShellSpec context detection** — `common.sh` skips the strict-mode
  preamble when `$SHELLSPEC_VERSION` is set, because the same options
  applied to ShellSpec's own shell terminate the executor pipeline on
  expected non-zero subshell exits (e.g. EXIT_USAGE assertions). Don't
  remove that gate.

### Cloud-init seed flow

Seeds are rendered by `lib/cloudinit.sh::render_seed`:
`vm/cloudinit/base/{user-data,meta-data,network-config}.tmpl` go through
`envsubst` (variables: `$VM_NAME $SSH_PUBKEY $DEFAULT_USER $BUILD_DATE`)
and land under `${SEED_DIR}/<vm-name>/`. Optional overlays from
`vm/cloudinit/overlays/<name>.yaml.tmpl` are **textually appended** —
not YAML-merged. PyYAML's loader picks the last occurrence of any
duplicated top-level key, so base + overlay must keep top-level keys
disjoint. This is documented inline in `_apply_overlay`; respect it.

### bib (bootc-image-builder) pipeline

`lib/bib.sh::build_kinoite_qcow` consumes `vm/targets/kinoite.env`
(`OCI_REF`, `OCI_DIGEST`, `BIB_VERSION`, `BIB_CONFIG_REL`) plus a TOML
manifest at `vm/targets/<config>.toml`. `OCI_REF` must be a bare
`localhost/<name>:<tag>` or `registry/<name>:<tag>` form — transport
prefixes (`containers-storage:`, `oci:`, etc.) are rejected up front.
Rootless bib usually needs `BIB_ROOTFUL=1` (CAP_SYS_ADMIN over the
parent namespace's mounts is unobtainable rootless).

## Testing

ShellSpec under `vm/spec/`. The default smoke lane runs `00_preflight`
through `40_snapshot_reset` (~5 min, 26 examples), then ShellSpec
emits a cosmetic `aborted by an unexpected error` (R-016) which the
`tests/smoke.sh` wrapper catches and treats as exit 0 when
`failures=0, errors=0`.

**Crucial pitfall:** the abort fires *before* specs `60_destroy_residue`,
`65_prune_spec`, `70_idempotency`, and `80_parallel_safety` get to run —
they pass cleanly when invoked standalone but are silently skipped in
the default lane. After changing anything that touches destroy/lock/prune
behavior, run those specs explicitly:

```bash
cd vm && shellspec spec/60_destroy_residue_spec.sh \
                   spec/65_prune_spec.sh \
                   spec/70_idempotency_spec.sh \
                   spec/80_parallel_safety_spec.sh
```

Specs 50 (cockpit) and 90 (kinoite) are gated behind `VM_E2E_COCKPIT=1`
and `VM_E2E_KINOITE=1` respectively and stay opt-in.

## Out of scope (deliberately)

- No Vagrant / Packer / Ansible / Terraform / Bats.
- No Debian/Ubuntu/RHEL matrix — Fedora 43 only.
- No aarch64 — x86_64 only.
- No nested virt / PCI passthrough / SR-IOV.
- No CI — nested KVM in GitHub runners is unreliable. All verification
  is local; `vm/DEPLOYMENT.md` is the persistent green-state record.

## Status doc

`vm/DEPLOYMENT.md` is the source of truth for what's verified, what's
pinned, and the risk register (R-001 through R-019, with R-003
`BIB_VERSION="latest"` and R-013 session-network setup as the
currently-open ones worth knowing about; R-019 (F44 host bump) is in
progress — F44 host validated, F44 targets added, but `OS_VARIANT` is
`fedora-unknown` pending osinfo-db). It has its own "How to update this
doc" section near the bottom.
