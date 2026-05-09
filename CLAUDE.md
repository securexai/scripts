# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repo. The
user-facing documentation lives elsewhere — pointers below.

## Where to look first

- **User overview & quickstarts:** [`README.md`](README.md).
- **Subsystem entry points:** [`vm/README.md`](vm/README.md),
  [`.toolbox/README.md`](.toolbox/README.md),
  [`bash/README.md`](bash/README.md).
- **CLI surface (every flag, exit code, env var):**
  [`docs/vm-cli-reference.md`](docs/vm-cli-reference.md).
- **Architecture (dispatcher pattern, cloud-init seed flow, bib
  pipeline, invariants):**
  [`docs/vm-architecture.md`](docs/vm-architecture.md).
- **Status snapshot & risk register (R-001 …):**
  [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md).
- **Contributor contract (pre-commit gates, conventional commits, PR
  checklist):** [`CONTRIBUTING.md`](CONTRIBUTING.md).
- **Chronological history:** [`CHANGELOG.md`](CHANGELOG.md).

If a fact is in user-facing docs, link there rather than duplicating it
here.

## What this repo is

A personal collection of operator scripts for a Fedora 43 or 44 host.
Three top-level directories:

- **`vm/`** — the substantial subsystem: a libvirt + cloud-init test rig
  with an 11-verb CLI dispatcher, a ShellSpec e2e suite, and a bootc OCI
  build path.
- **`bash/`** — one-off bash hook scripts; no shared infrastructure.
- **`.toolbox/`** — Containerfile + `setup.sh` that build the
  `localhost/scripts-toolbox:fedora-43` image and create the `scripts`
  toolbox container. Day-to-day dev happens inside that toolbox.

There is **no Python, no Node, no uv/Ruff** invoked from this repo at
runtime — the global template's `[Tool Execution]` section about uv/Ruff
does not apply here. This is a pure Bash 5.3+ repo. The toolbox ships
those tools so the pre-commit hooks have a reproducible environment.

Pre-commit hooks are configured per the global enforcement baseline
([`.pre-commit-config.yaml`](.pre-commit-config.yaml)); shellcheck runs
at `--severity=error` until the SC2155 cleanup follow-up lands. Full
hook table in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Testing pitfalls

ShellSpec under `vm/spec/`. The default smoke lane runs `00_preflight`,
`05_dispatch`, `10_create_fedora_cloud`, `20_cloud_init_and_net`,
`30_ssh_and_sudo`, and `40_snapshot_reset` (~5 min, 34 examples), then
ShellSpec emits a cosmetic `aborted by an unexpected error` (R-016)
which the `tests/smoke.sh` wrapper catches and treats as exit 0 when
`failures=0, errors=0`.

> [!IMPORTANT]
> The abort fires **before** specs `60_destroy_residue`, `65_prune`,
> `66_prune_pool_residue`, `70_idempotency`, and `80_parallel_safety`
> get to run — they pass cleanly when invoked standalone but are
> silently skipped in the default lane. The same abort fires inside a
> single-invocation standalone batch right before `80`, so split it off
> into its own call. After changing anything that touches
> destroy/lock/prune behavior, run those specs explicitly:
>
> ```bash
> cd vm && shellspec spec/60_destroy_residue_spec.sh \
>                    spec/65_prune_spec.sh \
>                    spec/66_prune_pool_residue_spec.sh \
>                    spec/70_idempotency_spec.sh
> cd vm && shellspec spec/80_parallel_safety_spec.sh
> ```

Specs 50 (cockpit) and 90 (kinoite) are gated behind `VM_E2E_COCKPIT=1`
and `VM_E2E_KINOITE=1` respectively and stay opt-in.

`common.sh` skips the strict-mode preamble and the diagnostic ERR trap
when `$SHELLSPEC_VERSION` is set, because the same options applied to
ShellSpec's own shell terminate the executor pipeline on expected
non-zero subshell exits (e.g., `EXIT_USAGE` assertions). Don't remove
that gate. Background:
[`docs/vm-architecture.md`](docs/vm-architecture.md) "Strict-mode and
the ShellSpec gate".

## Out of scope (deliberately)

- No Vagrant / Packer / Ansible / Terraform / Bats.
- No Debian / Ubuntu / RHEL matrix — Fedora 43 / 44 only.
- No aarch64 — x86_64 only.
- No nested virt / PCI passthrough / SR-IOV.
- No CI — nested KVM in GitHub runners is unreliable. All verification
  is local; [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) is the persistent
  green-state record.

## Key files for agents

When asked to implement something, read first:

- [`vm/scripts/lib/common.sh`](vm/scripts/lib/common.sh) — strict-mode
  preamble pattern, `EXIT_*` taxonomy, `die_with`, `require_cmd`. New
  scripts copy this preamble.
- [`vm/scripts/lib/paths.sh`](vm/scripts/lib/paths.sh) — XDG paths;
  never hardcode `$HOME/...` or in-repo paths for state.
- [`vm/scripts/vm`](vm/scripts/vm) — the dispatcher. Subcommands are
  `exec`d, not function-called.
- [`vm/scripts/subcommands/<verb>.sh`](vm/scripts/subcommands/) — one
  file per verb. Match this pattern for new verbs.
- [`vm/targets/<name>.env`](vm/targets/) — when adding a new target,
  follow the existing layout. Pin `IMAGE_SHA256` or `OCI_DIGEST` in the
  same commit; do not ship empty pins.
- [`vm/spec/<NN>_<topic>_spec.sh`](vm/spec/) — every behavior change
  needs a spec, named numerically to fit the smoke-lane ordering.

## Commit conventions for AI-authored work

- Write conventional commits (`feat`, `fix`, `docs`, `chore`,
  `refactor`, `test`, `perf`, `ci`, `build`, `revert`, `style`).
- Never commit a Claude / Anthropic byline. The repo's CLAUDE.md
  inheritance from the user's global template explicitly forbids it.
- Always work on a feature branch — `main` is protected by the
  `no-commit-to-branch` pre-commit hook.
- Update [`CHANGELOG.md`](CHANGELOG.md) `[Unreleased]` for any
  user-visible change in the same PR.
