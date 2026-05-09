# Contributing

Thanks for taking the time to look. This is a personal repo, but it's
public-style — patches and forks are welcome. A few rules keep the tree
honest.

## Dev environment

The dev environment is a Fedora-toolbox container baked from
[`.toolbox/Containerfile`](.toolbox/Containerfile). It pins every tool the
pre-commit hooks need (`uv`, `ruff`, `betterleaks`, `pnpm`, `commitlint`,
`shellcheck` via `mise`, `markdownlint-cli2`).

```bash
./.toolbox/setup.sh           # build image + create container, ~3 min
toolbox enter scripts          # land inside
```

Inside the toolbox, install pre-commit hooks once per clone:

```bash
pre-commit install --install-hooks --hook-type commit-msg --hook-type pre-push
```

Outside the toolbox is supported but not the happy path — you'll need to
provide compatible versions of the tools yourself.

See [`.toolbox/README.md`](.toolbox/README.md) for the pinned tool table.

## Branching and commits

- **`main` is protected.** The `no-commit-to-branch` pre-commit hook rejects
  direct commits. Work on a feature branch:

  ```bash
  git checkout -b feat/my-thing
  ```

- **Conventional commits**, enforced by commitlint 19.x. Subject in
  imperative mood, ≤72 chars, no trailing period. Allowed types:

  ```text
  feat fix docs chore refactor test perf ci build revert style
  ```

  Use a scope where it sharpens the message:

  ```text
  feat(vm): add parallel build-kinoite cache
  fix(vm): drop default user from cloud-init user-data on F44
  docs(toolbox): document BUILD_NETWORK override
  ```

- **Atomic commits.** One logical change per commit. Don't bundle a feature
  with a doc sweep with a formatting refactor — those are three commits.
- **Rebase, don't merge.** Prefer `git pull --rebase` to keep history linear.
  Don't amend commits that already shipped to a shared branch.
- **No `--no-verify`.** The hooks are the gate; if one fails, fix the
  underlying problem.

## Pre-commit gates

Configured in [`.pre-commit-config.yaml`](.pre-commit-config.yaml). Every
commit and push runs through these hooks:

| Stage | Hook | What it blocks |
| --- | --- | --- |
| pre-commit | `trailing-whitespace`, `end-of-file-fixer`, `mixed-line-ending` | Whitespace / EOL hygiene |
| pre-commit | `check-merge-conflict`, `check-case-conflict` | Stray conflict markers, case-only filename collisions |
| pre-commit | `check-executables-have-shebangs`, `check-shebang-scripts-are-executable` | Executable bit ↔ shebang must agree |
| pre-commit | `check-added-large-files` (10 MB cap) | Large binaries that should live elsewhere |
| pre-commit | `check-yaml`, `check-json`, `check-toml` | Malformed config files |
| pre-commit | `detect-private-key` | SSH / GPG / PEM private keys |
| pre-commit | `no-commit-to-branch` (`main`/`master`/`develop`/`release/*`) | Direct commits to protected branches |
| pre-commit | `betterleaks` (1.1.2) | Hardcoded secrets — config in `.betterleaks.toml` |
| pre-commit | `shellcheck` (`--severity=error`) | Shell lint errors. Severity bumps to `warning` after the SC2155 cleanup follow-up lands. |
| pre-commit | `markdownlint-cli2` | Markdown structure / accessibility — config in `.markdownlint-cli2.yaml` |
| commit-msg | `commitlint` (config in `commitlint.config.js`) | Non-conventional commit messages |

Manual invocation:

```bash
pre-commit run --all-files                    # everything
pre-commit run shellcheck --all-files         # one hook
pre-commit autoupdate                         # bump pinned hook revs
```

## Coding standards

- **Bash 5.3+ required.** Every script checks `BASH_VERSINFO` at startup.
  `inherit_errexit` is in use; do not break it.
- **Strict-mode preamble** in every entry-point script:

  ```bash
  set -o errexit -o nounset -o pipefail -o errtrace
  shopt -s inherit_errexit
  shopt -s nullglob
  ```

  ShellSpec context is detected via `$SHELLSPEC_VERSION`; the preamble is
  skipped under tests because applied options terminate ShellSpec's own
  executor pipeline on expected non-zero subshell exits. Don't remove that
  gate (see
  [`vm/scripts/lib/common.sh`](vm/scripts/lib/common.sh)).
- **Sysexits-flavored exit codes.** Use `die_with <code> <msg>` rather than
  bare `die` so failures classify. Codes are tabled in
  [`docs/vm-cli-reference.md`](docs/vm-cli-reference.md).
- **`require_cmd <bin>`** at the top of every lib that uses an external
  binary. Fails with `EXIT_PREREQ` if missing.
- **XDG paths only** — write under `${XDG_CACHE_HOME}/scripts-vm/` or
  `${XDG_STATE_HOME}/scripts-vm/`. Never under the repo, never directly
  under `$HOME`.
- **`shopt -s nullglob`** is set repo-wide; loops over empty globs iterate
  zero times. Code relies on this.
- **No hidden side effects in libs.** A `lib/*.sh` file should only define
  functions and constants when sourced; running it should be a no-op
  guarded by `[[ -n "${_VM_LIB_X_LOADED:-}" ]] && return 0`.

The architectural background for these rules lives in
[`docs/vm-architecture.md`](docs/vm-architecture.md).

## Testing

ShellSpec under [`vm/spec/`](vm/spec/), driven by
[`vm/tests/smoke.sh`](vm/tests/smoke.sh).

```bash
./vm/tests/smoke.sh                            # default lane (~5 min)
./vm/tests/smoke.sh --format tap               # TAP output
cd vm && shellspec spec/65_prune_spec.sh       # single spec
VM_E2E_KINOITE=1 ./vm/tests/smoke.sh           # opt-in kinoite (slow)
VM_E2E_COCKPIT=1 ./vm/tests/smoke.sh           # opt-in cockpit
```

> [!IMPORTANT]
> The default lane covers specs `00`–`40`, then ShellSpec emits a cosmetic
> `aborted by an unexpected error` (R-016) — the wrapper handles it. Specs
> `60_destroy_residue`, `65_prune`, `66_prune_pool_residue`,
> `70_idempotency`, and `80_parallel_safety` pass cleanly when invoked
> directly but are silently skipped in the default lane. The same R-016
> abort fires inside the standalone batch right before `80`, so split it
> off into a second invocation:
>
> ```bash
> cd vm && shellspec spec/60_destroy_residue_spec.sh \
>                    spec/65_prune_spec.sh \
>                    spec/66_prune_pool_residue_spec.sh \
>                    spec/70_idempotency_spec.sh
> cd vm && shellspec spec/80_parallel_safety_spec.sh
> ```

There is no CI — nested KVM in GitHub runners is unreliable. All
verification is local. The persistent green-state record lives in
[`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md).

## Documentation

- **Update docs in the same PR as the code change** — drift starts the
  moment they diverge.
- **markdownlint-cli2** runs on every commit (config:
  [`.markdownlint-cli2.yaml`](.markdownlint-cli2.yaml)). Line length 120
  for prose; code blocks, tables, and headings exempt.
- **ATX headings only**, single H1 per file, hyphen bullets, fenced code
  blocks with a language tag (`bash`, `text`, `console`, `toml`, `yaml`,
  `json`, `dockerfile`).
- **Diátaxis split** for `docs/` — tutorial / how-to / reference /
  explanation. Don't mix two types in one file.
- **CHANGELOG entry** for any user-visible change. The
  [`CHANGELOG.md`](CHANGELOG.md) `[Unreleased]` section is the staging
  area.
- **Agent guidance** belongs in [`CLAUDE.md`](CLAUDE.md), not user docs.

## Pull request checklist

- [ ] Tests pass — default smoke lane plus any standalone spec your change
      touches.
- [ ] [`CHANGELOG.md`](CHANGELOG.md) `[Unreleased]` section updated for
      user-visible changes.
- [ ] Documentation touched if the change alters behavior the docs
      describe.
- [ ] No fabricated version numbers, digests, or commit SHAs in docs —
      verify against the actual files.
- [ ] `pre-commit run --all-files` is clean.
- [ ] Commit subject is conventional and ≤72 chars; no trailing period.
- [ ] One logical change per commit (split unrelated work).

## Reporting bugs and proposing features

Use [GitHub Issues on `securexai/scripts`](https://github.com/securexai/scripts/issues).
Before opening a new issue, scan the risk register in
[`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) — a known-gap entry (R-001 …) may
already track the symptom.

For security issues, follow [`SECURITY.md`](SECURITY.md) instead of opening
a public issue.

## See also

- [`README.md`](README.md) — project overview
- [`.toolbox/README.md`](.toolbox/README.md) — dev environment details
- [`docs/vm-architecture.md`](docs/vm-architecture.md) — invariants to
  preserve when editing
- [`docs/vm-cli-reference.md`](docs/vm-cli-reference.md) — CLI surface and
  exit codes
