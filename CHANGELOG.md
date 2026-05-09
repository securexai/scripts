# Changelog

All notable changes to this repository follow [Keep a
Changelog 1.1.1](https://keepachangelog.com/en/1.1.1/) and use ISO 8601
dates.

> [!NOTE]
> Version numbers below are synthetic milestones, not git tags. The repo
> currently has no release tags; versions are assigned to make the history
> easier to scan. See [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) for the
> commit-level evidence trail tied to the verification snapshot.

## [Unreleased]

### Added

- This file.
- Top-level [`README.md`](README.md), [`CONTRIBUTING.md`](CONTRIBUTING.md),
  [`SECURITY.md`](SECURITY.md), [`LICENSE`](LICENSE).
- Per-subsystem READMEs:
  [`.toolbox/README.md`](.toolbox/README.md),
  [`bash/README.md`](bash/README.md).
- `docs/` tree: CLI reference, architecture explanation, supply-chain
  how-to, troubleshooting.
- [`vm/spec/05_dispatch_spec.sh`](vm/spec/05_dispatch_spec.sh) — 7 unit
  examples covering prefix-match dispatch (`vm create --target …`,
  `vm build-kinoite --target …`) and the pure `_bib_out_subdir` helper.
- Repo-root pre-commit enforcement baseline:
  [`.pre-commit-config.yaml`](.pre-commit-config.yaml),
  [`.markdownlint-cli2.yaml`](.markdownlint-cli2.yaml),
  [`.editorconfig`](.editorconfig),
  [`commitlint.config.js`](commitlint.config.js), and `betterleaks`
  hook wired at v1.1.2.

### Changed

- [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) trimmed to status snapshot + test
  matrix + risk register; how-to and historical content moved to `docs/`
  and this file.
- [`CLAUDE.md`](CLAUDE.md) trimmed to agent-relevant guidance only;
  user-facing material extracted to `README.md` and `docs/vm-architecture.md`.
- [`vm/README.md`](vm/README.md) CLI synopsis line updated to list all four
  targets explicitly (`fedora-cloud`, `fedora-cloud-44`, `kinoite`,
  `kinoite-44`).
- Toolbox monthly bump 2026-05: `uv` `0.11.7` → `0.11.8`; `pnpm`
  `10.33.1` → `11.0.3` (major — pnpm 11's launcher embeds Node and
  dynamically links `libatomic.so.1`, so the Containerfile now extracts
  the full tarball and the base image installs `libatomic`).

### Fixed

- `vm build-kinoite` now derives a per-target bib output subdirectory
  (`kinoite-out`, `kinoite-44-out`) so `kinoite` and `kinoite-44`
  qcow2 caches no longer clobber each other.
- `vm build-kinoite --target` now requires a value; previously a
  trailing `--target` could swallow the next argument.
- `vm destroy` and `vm prune --apply` sweep the dir-type libvirt
  storage pools that `virt-install --disk path=…` auto-defines but
  `virsh undefine` does not drop (R-020).
- `build_kinoite_qcow` now redirects bib stdout so it returns a clean
  path; previously the qcow2 path on stdout was prefixed with bib's
  build chatter, breaking callers that captured the value.

## [0.4.0] — 2026-04-29

F44 lane added. Fedora 44 went GA on 2026-04-28; the host bumped to F44
Kinoite 44.20260428.0 the next day. The default smoke lane stayed green
(27 / 0 failures, 411 s) on the F44 host with `VM_EXPECTED_FEDORA="43 44"`.

### Added

- `fedora-cloud-44` target ([`vm/targets/fedora-cloud-44.env`](vm/targets/fedora-cloud-44.env))
  pinned from the signed `Fedora-Cloud-44-1.7-x86_64-CHECKSUM`.
- `kinoite-44` target ([`vm/targets/kinoite-44.env`](vm/targets/kinoite-44.env))
  with derived OCI ([`vm/Containerfile.kinoite-44`](vm/Containerfile.kinoite-44))
  layering cloud-init on `quay.io/fedora-ostree-desktops/kinoite:44`.
- `vm build-kinoite --target <name>` flag for parallel kinoite-class qcow2
  caches.
- `BIB_ROOTFS` plumbing in `lib/bib.sh` for Fedora bootc bases that omit
  `DefaultRootFs` (R-017 fix).
- Default `VM_EXPECTED_FEDORA` widened from `"43"` to `"43 44"`.
- Prefix-match dispatch in `vm create`: any name matching `fedora-cloud*`
  or `kinoite*` with a matching `vm/targets/<name>.env` is recognized.
- Storage-pool sweep in `vm destroy` and `vm prune` (R-020 fix) — drops
  the dir-type pools that `virt-install` auto-defines.

### Fixed

- `lib/bib.sh` no longer drops `BIB_ROOTFS` at the env-file hand-off
  subshell.
- Cloud-init service rename — switched the kinoite-44 Containerfile to
  enable `cloud-init.target` (durable across `cloud-init.service` →
  `cloud-init-main.service` rename in cloud-init 25.x).
- `cloudinit/base/user-data.tmpl` — dropped `users: [- default, ...]`;
  the explicit `name: ${DEFAULT_USER}` entry now covers both Fedora Cloud
  and bib-time `core` users on bases that lack the `adm` /
  `systemd-journal` groups.

## [0.3.0] — 2026-04-26

Bootc lane proven end-to-end via a derived OCI; UEFI by default;
ShellSpec wrapper handles the cosmetic "aborted" flag.

### Added

- [`vm/Containerfile.bootc`](vm/Containerfile.bootc) — derived OCI
  layering cloud-init + systemd enables on `centos-bootc:stream9`.
- `BIB_ROOTFUL=1` opt-in for rootful `podman` under bootc-image-builder
  (rootless `--privileged` cannot remount the parent namespace).
- UEFI by default for all VMs (`--boot firmware=efi`); spec 10 verifies
  host XML uses `firmware='efi'` and that the guest sees
  `/sys/firmware/efi`.
- `tests/smoke.sh` wrapper that exits 0 on the cosmetic ShellSpec
  `aborted=1` flag when failures and errors are both zero.
- `VM_E2E_COCKPIT=1` gate on the cockpit lane (mirroring `VM_E2E_KINOITE`).

### Fixed

- `40_snapshot_reset_spec.sh` — split the double `When run script` block
  that ShellSpec rejects with "Evaluation has already been executed".
- bib `latest` invocation — drop `customizations.services` (rejected by
  bib `latest`); systemd state moves into the derived OCI image.
- POSIX `[ ]` Skip-if predicates on cockpit + kinoite specs (ShellSpec
  evaluates predicates in a POSIX subshell).

## [0.2.0] — 2026-04-25

Supply-chain pins set; ShellSpec absolute-path fix; `_CREATE_VM_ROOT`
pathing fix; libvirt-reachable preflight.

### Added

- `IMAGE_SHA256` pinned to `846574c8…6c8ab2f` (Fedora Cloud Base 43-1.6).
- `OCI_DIGEST` pinned to `sha256:8fae1047…c4a9225c` (`quay.io`
  `kinoite:43`, later overridden by the derived OCI).
- `preflight_check_virsh_reachable` — probes `virsh -c $LIBVIRT_URI
  hostname`, opportunistically enables `virtqemud.socket` /
  `libvirtd.socket` (replaces the rigid `libvirtd.socket` assumption that
  breaks on Fedora 43 modular daemons).
- Pre-commit baseline at the repo root: `.pre-commit-config.yaml`,
  `.betterleaks.toml`, `commitlint.config.js`, `.markdownlint-cli2.yaml`,
  `.editorconfig`, `mise.toml`.

### Changed

- ShellSpec specs use `When run script "${VM_BIN}"` (absolute path) instead
  of `When run command`.
- `_CREATE_VM_ROOT` and `_BK_VM_ROOT` traverse two levels up from
  `vm/scripts/subcommands/` so target env files resolve.
- `get_ipv4` walks agent → lease → ARP and skips `lo` (qemu-guest-agent
  reports `lo` first; bridge-mode networks have no lease table).

### Removed

- `--xtrace-only` from `vm/.shellspec` (non-interactive runs were flooding
  stderr with `/dev/tty: No such device`).

## [0.1.0] — 2026-04-24

Initial vm/ subsystem: CLI dispatcher, libvirt + cloud-init pipeline,
bootc-image-builder pipeline for Kinoite, ShellSpec end-to-end suite.

### Added

- CLI dispatcher [`vm/scripts/vm`](vm/scripts/vm) with 10 subcommands.
  (An 11th, `build-kinoite`, was added later — see
  [`docs/vm-cli-reference.md`](docs/vm-cli-reference.md) for the current
  set.)
- Per-VM ephemeral ed25519 keys with optional `VM_SSH_PUBKEY` override.
- Sysexits-style exit-code taxonomy
  ([`vm/scripts/lib/common.sh`](vm/scripts/lib/common.sh)).
- Cloud-init readiness gate (`cloud-init status --wait` non-fatal).
- `--with-cockpit` overlay for fedora-cloud and kinoite-cockpit.toml for
  kinoite.
- Advisory `flock` parallel-safety
  ([`vm/scripts/lib/locks.sh`](vm/scripts/lib/locks.sh)).
- `vm prune` subcommand with dry-run default.
- Initial [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) status doc.
- Initial [`vm/README.md`](vm/README.md).
- Foundation: `vm/setup.sh`, optional `vm/Containerfile`, lib helpers.
