<!-- markdownlint-disable MD041 -->
# scripts

Personal collection of operator scripts for a Fedora 43 or 44 host. Three
self-contained subsystems: a libvirt + cloud-init VM test rig, a pinned
toolbox container for dev work, and a small `bash/` directory for one-off
hooks.

> [!NOTE]
> Local-only by design — no Vagrant / Packer / Ansible / Terraform / CI.
> Verification happens on a real Fedora host. See
> [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) for the latest verification snapshot
> and risk register.

## Repository layout

- [`vm/`](vm/README.md) — libvirt + cloud-init VM test rig with an 11-verb
  CLI dispatcher and a ShellSpec end-to-end suite. The substantial
  subsystem.
- [`.toolbox/`](.toolbox/README.md) — Containerfile + bootstrap that
  builds `localhost/scripts-toolbox:fedora-43` and creates the `scripts`
  toolbox. Day-to-day dev happens inside that container.
- [`bash/`](bash/README.md) — one-off bash hook scripts. No shared
  infrastructure; each script is independent.

Repo-level config (pre-commit, commitlint, markdownlint, betterleaks,
editorconfig, mise) lives at the root and is summarized in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Host requirements

| Requirement | Detail |
| --- | --- |
| OS | Fedora 43 or Fedora 44 (Workstation, Kinoite, or Silverblue) |
| Arch | x86_64 only |
| Virtualization | `/dev/kvm` present and writable |
| Container runtime | `podman` + `toolbox` (ships on Kinoite/Silverblue by default) |
| Shell | Bash 5.3+ (checked at runtime) |

Anything else is out of scope on purpose — see [`SECURITY.md`](SECURITY.md)
for the explicit non-goals list.

## Quickstart — fork and run a VM in five minutes

```bash
# 1. Clone
git clone https://github.com/securexai/scripts.git
cd scripts

# 2. Build the dev toolbox (one-time per host, ~3 min)
./.toolbox/setup.sh
toolbox enter scripts

# 3. Bootstrap libvirt on the host (one-time, may stage an rpm-ostree layer)
./vm/setup.sh
# If rpm-ostree staged a deployment, REBOOT before continuing.

# 4. The fedora-cloud digest is already pinned in vm/targets/fedora-cloud.env;
#    re-pinning is only needed at point-release bumps. See
#    docs/vm-supply-chain.md for the runbook.

# 5. Spin up a disposable VM, log in, tear it down
./vm/scripts/vm create --target fedora-cloud --name try1
./vm/scripts/vm ssh    try1 -- 'cat /etc/os-release; uname -r'
./vm/scripts/vm destroy try1
```

For Kinoite (`kinoite`, `kinoite-44`) targets, see the slow-path quickstarts
in [`vm/README.md`](vm/README.md).

## Subsystems

### vm/

The VM rig. Provisions Fedora Cloud or Fedora Kinoite VMs from pinned
upstream digests via `qemu:///session` (rootless) by default, with per-VM
ephemeral SSH keys, snapshot/reset, an opt-in cockpit overlay, and a bootc
image-builder lane for Kinoite. Eleven subcommands (`create`, `start`,
`stop`, `destroy`, `ssh`, `snapshot`, `reset`, `list`, `status`, `prune`,
`build-kinoite`).

See [`vm/README.md`](vm/README.md) for the user guide and
[`docs/vm-cli-reference.md`](docs/vm-cli-reference.md) for the full CLI
reference.

### .toolbox/

A pinned Fedora-toolbox-43 container baked with `git`, `gh`, `pre-commit`,
`uv`, `ruff`, `betterleaks`, `pnpm`, `commitlint`, `jq`, and `ripgrep`. All
versions are sha256-pinned where possible. Idempotent setup; safe to re-run.

See [`.toolbox/README.md`](.toolbox/README.md).

### bash/

Personal Claude Code customizations — currently a single hook installer that
forces Claude to evaluate available skills on every prompt. See
[`bash/README.md`](bash/README.md).

## Documentation index

### Get started

- [`README.md`](README.md) — this file
- [`vm/README.md`](vm/README.md) — VM rig user guide and quickstarts
- [`.toolbox/README.md`](.toolbox/README.md) — dev toolbox image
- [`bash/README.md`](bash/README.md) — Claude Code hook installers

### Reference

- [`docs/vm-cli-reference.md`](docs/vm-cli-reference.md) — every
  subcommand, flag, exit code, and environment variable
- [`docs/vm-architecture.md`](docs/vm-architecture.md) — dispatcher
  pattern, cloud-init seed flow, bib pipeline, invariants

### Operate

- [`docs/vm-supply-chain.md`](docs/vm-supply-chain.md) — digest pinning
  procedure for all four targets
- [`docs/vm-troubleshooting.md`](docs/vm-troubleshooting.md) —
  symptom-indexed fixes for known footguns

### Status and history

- [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) — current verification snapshot
  and risk register (R-001 …)
- [`CHANGELOG.md`](CHANGELOG.md) — chronological history

### Contribute

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — dev environment, pre-commit
  gates, conventional commits, PR checklist
- [`SECURITY.md`](SECURITY.md) — scope, supply-chain pinning policy,
  threat model, vulnerability reporting
- [`CLAUDE.md`](CLAUDE.md) — guidance for AI coding assistants working
  in this repo

## Project conventions

- **Bash 5.3+** — hard requirement, checked at runtime.
- **Strict-mode preamble** in every script: `errexit`, `nounset`,
  `pipefail`, `errtrace`, `inherit_errexit`, `nullglob`.
- **Sysexits-style exit codes** — `0`, `1`, `64`, `69`, `70`, `71`, `72`.
  Defined in
  [`vm/scripts/lib/common.sh`](vm/scripts/lib/common.sh) and tabled in
  [`docs/vm-cli-reference.md`](docs/vm-cli-reference.md).
- **XDG paths only** — `${XDG_CACHE_HOME}/scripts-vm/images/`,
  `${XDG_STATE_HOME}/scripts-vm/disks/`,
  `${XDG_STATE_HOME}/scripts-vm/seeds/`. Never under the repo or `$HOME`
  directly.
- **Conventional commits**, enforced via commitlint.
- **`main` is protected** — direct commits blocked by the
  `no-commit-to-branch` pre-commit hook.

Full contributor contract: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT — see [`LICENSE`](LICENSE).

## Maintainer

[@securexai](https://github.com/securexai)
