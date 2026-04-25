# vm/ Deployment & Test Status

**Status:** yellow / smoke partial — host bootstrap green, four real
bugs fixed end-to-end (modular libvirt daemons, `VM_ROOT` depth in
subcommands, `get_ipv4` ARP fallback, ShellSpec `run command` vs
`run script` for absolute paths). Default-lane smoke 2026-04-25 18:31:
**18 PASS · 2 FAILED · 3 WARNED** out of 23 examples that ran; the
abort in `40_snapshot_reset_spec.sh:23` (multi-`When`, R-014) prevented
specs 50–80 from running. Flip to green is gated on R-014 fix +
the dispatcher EXIT_USAGE expectation (`00_preflight_spec.sh:58`).

**Last verified:** 2026-04-25

**Owner:** [@securexai](https://github.com/securexai)

**Doc version:** 1.3

**Subsystem SHA:** `feat/vm-hardening-e2e-deploy-doc` (branch HEAD `49ecc0a`)

---

## TL;DR

- The vm/ subsystem is a self-contained Fedora 43 libvirt + cloud-init test rig with a 10-subcommand
  CLI, per-VM ephemeral SSH keys, an opt-in cockpit overlay, and a ShellSpec end-to-end suite.
- The two upstream digest pins (`IMAGE_SHA256`, `OCI_DIGEST`) are now **set**
  ([`targets/fedora-cloud.env:17`](targets/fedora-cloud.env),
  [`targets/kinoite.env:21`](targets/kinoite.env)). `vm create` no longer fails fast on
  missing pins. `BIB_VERSION="latest"` remains pending (R-003).
- End-to-end exercise on a real Fedora 43 + Kinoite host surfaced four bugs fixed in
  `2e1c338`, `8e22366`, `08f5405`, `49ecc0a` (`edc201f` for ShellSpec output config). VMs
  now boot, network out via the system bridge, and authenticate over SSH using per-VM keys.
- The default ShellSpec lane runs via `./tests/smoke.sh`; the kinoite lane is opt-in
  (`VM_E2E_KINOITE=1`). Default lane is currently partially green — see Test Matrix.
- New host prerequisite: a session-scope `default` libvirt network (R-013) — the scripts
  default to `qemu:///session` for rootless XDG paths, but libvirt's stock `default` NAT
  network only exists in `qemu:///system`. See Phase 1.5 below for the one-time setup.

## Scope

This document covers the `vm/` subsystem of the `scripts` repo. It does not cover the untracked
`bash/` directory, the deleted `skill-forced-eval-hook.sh`, or the broader repo. Everything
referenced here lives under `vm/`.

Repo-wide enforcement (pre-commit hooks, betterleaks secret scanning, commitlint, markdownlint,
shellcheck/shfmt baseline) ships from sibling branches `chore/bootstrap-pre-commit-baseline` and
`chore/lint-cleanup-shellcheck`. See the root [`CHANGELOG.md`](../CHANGELOG.md) and
[`README.md`](../README.md) for repo-level scope.

## Host Prerequisites

The vm/ workflow targets a Fedora 43 host (Workstation or Kinoite/Silverblue) with KVM. The
[`setup.sh`](setup.sh) script installs the layered packages and runs the full preflight after
the binaries land.

| Requirement                  | Verified by                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------- |
| Fedora 43 (`ID=fedora`)      | [`scripts/lib/preflight.sh`](scripts/lib/preflight.sh) `preflight_check_os_id`         |
| `/dev/kvm` r/w               | `preflight_check_kvm` (host or `usermod -aG kvm`)                                     |
| `virt-host-validate qemu`    | `preflight_check_virt_host_validate`                                                  |
| `virsh -c $LIBVIRT_URI hostname` | `preflight_check_virsh_reachable`                                                  |
| Required binaries on PATH    | `preflight_check_binaries virsh virt-install qemu-img genisoimage curl sha256sum`      |
| Toolbox bind-mount (if used) | `preflight_check_toolbox_socket`                                                      |
| User in `libvirt` group      | `setup.sh` `ensure_libvirt_group` (when `USE_LIBVIRT_GROUP=1`)                        |

The dispatcher [`scripts/vm`](scripts/vm) re-runs the **fast** preflight (env-only, no fork)
before every state-changing subcommand. Set `VM_PREFLIGHT=full` to run the full preflight on
every dispatch, or `VM_PREFLIGHT=none` to suppress it (debugging only).

## Toolbox Bridge

The user's primary dev environment is a Fedora toolbox container; libvirt itself runs on the host.
The bridge works by bind-mounting the per-user libvirt socket into the toolbox and shipping
client-only tooling there. The optional [`Containerfile`](Containerfile) builds a toolbox image
that extends `scripts-toolbox:fedora-43` with `libvirt-client`, `virt-install`, `genisoimage`,
and `podman`.

Concretely:

- The libvirt **daemon** (`virtqemud` under the modular daemon split) runs on the host.
- The toolbox sees `/run/user/$UID/libvirt/virtqemud-sock` via toolbx's default user-runtime
  mount. `preflight_check_toolbox_socket` asserts the socket is reachable.
- Bib (bootc-image-builder) needs *host* podman because it uses `--privileged`.
  [`scripts/lib/bib.sh`](scripts/lib/bib.sh) detects `/run/.containerenv` and prefers
  `flatpak-spawn --host podman` automatically.

Reference: [Fedora Discussion — qemu:///session in toolbox/distrobox](https://discussion.fedoraproject.org/t/using-qemu-session-in-toolbox-or-distrobox/72263)
and [Fedora wiki — Modular Libvirt Daemons](https://fedoraproject.org/wiki/Changes/LibvirtModularDaemons).

## Deployment Readiness Checklist

Status legend: `[ ]` open · `[x]` done · `[~]` in progress · `[!]` blocked

### Phase 1 — Host bootstrap

| #     | Item                                     | Command / file                                              | Status | Notes                                                                                                         |
| ----- | ---------------------------------------- | ----------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------- |
| 1.1   | Layered packages installed               | `./vm/setup.sh`                                             | `[x]`  | Reboot if `rpm-ostree status` shows `staged: true, booted: false`.                                            |
| 1.2   | libvirt reachable on `LIBVIRT_DEFAULT_URI` | `virsh -c $LIBVIRT_DEFAULT_URI hostname`                    | `[x]`  | Fedora 43 ships modular daemons (`virtqemud` auto-launches per-user); `setup.sh` probes reachability directly. |
| 1.3   | User in `libvirt` group                  | `id -nG \| grep -w libvirt`                                 | `[x]`  | Only required for `qemu:///system`; rootless `qemu:///session` flow does not need it.                         |
| 1.4   | Full preflight green                     | `./vm/setup.sh` (re-run post-reboot) prints `preflight: ok` | `[x]`  | Or `VM_PREFLIGHT=full vm list`. Verified `2026-04-25`.                                                        |
| 1.5   | Session-scope `default` network active   | `virsh -c qemu:///session net-list \| grep -w default`       | `[x]`  | One-time `virsh net-define` of a bridge-mode alias to system `virbr0` — see R-013.                            |

### Phase 2 — Digest pinning (supply chain)

| #     | Item                | Source                                                | Status | Notes                                                 |
| ----- | ------------------- | ----------------------------------------------------- | ------ | ----------------------------------------------------- |
| 2.1   | `IMAGE_SHA256` set  | [`targets/fedora-cloud.env:17`](targets/fedora-cloud.env) | `[x]`  | Pinned 2026-04-25 from getfedora.org/releases.json.   |
| 2.2   | `OCI_DIGEST` set    | [`targets/kinoite.env:21`](targets/kinoite.env)            | `[x]`  | Pinned 2026-04-25 via `skopeo inspect`.               |
| 2.3   | `BIB_VERSION` pinned | [`targets/kinoite.env:24`](targets/kinoite.env)           | `[ ]`  | Currently `latest`; pin numeric tag after first build. |

### Phase 3 — First fedora-cloud VM

| #     | Item                                | Command                                                     | Status | Notes                                                                       |
| ----- | ----------------------------------- | ----------------------------------------------------------- | ------ | --------------------------------------------------------------------------- |
| 3.1   | Probe `vm create`                   | `vm create --target fedora-cloud --name probe`              | `[x]`  | Verified manually with diag VMs (2026-04-25); 5/5 spec-10 expectations PASS. |
| 3.2   | Probe `vm ssh` (non-interactive)    | `vm ssh probe -- uname -r`                                  | `[x]`  | Confirms per-VM key (B1) works; `30_ssh_and_sudo_spec.sh` 3/4 PASS, 1 WARNED. |
| 3.3   | Probe `vm destroy` cleanliness      | `vm destroy probe && find ~/.local/state/scripts-vm`        | `[~]`  | Spec 60 in flight; manual diag tear-downs leave `disks/` + `seeds/` empty.   |

### Phase 4 — Cloud-init + internet gate

| #     | Item                                       | Command                                                             | Status | Notes                                                                          |
| ----- | ------------------------------------------ | ------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------ |
| 4.1   | `cloud-init status --wait` exit ≠ 1        | `vm ssh probe -- 'cloud-init status --wait; rc=$?; [[ $rc -ne 1 ]]'` | `[~]`  | Spec 20 reports WARNED (assertion succeeds, stderr unexpected) — not a failure. |
| 4.2   | Outbound HTTPS reaches fedoraproject.org    | `vm ssh probe -- 'curl -fsS --max-time 5 https://fedoraproject.org -o /dev/null'` | `[x]`  | Spec 20 PASS confirmed in current smoke run.                          |
| 4.3   | DNS resolves quay.io                       | `vm ssh probe -- 'getent hosts quay.io'`                            | `[~]`  | Spec 20 reports WARNED — see 4.1. Both gated on cosmetic stderr noise from ssh. |

### Phase 5 — Cockpit (optional, opt-in)

| #     | Item                                            | Command                                                                       | Status | Notes                                  |
| ----- | ----------------------------------------------- | ----------------------------------------------------------------------------- | ------ | -------------------------------------- |
| 5.1   | `--with-cockpit` create succeeds                | `vm create --target fedora-cloud --name cp --with-cockpit`                    | `[ ]`  | Applies overlay `cockpit`.             |
| 5.2   | `cockpit.socket` is active                      | `vm ssh cp -- 'systemctl is-active cockpit.socket'`                           | `[ ]`  | Active in fedora-cloud + kinoite.      |
| 5.3   | Host can reach `https://<vm-ip>:9090`           | `curl -kfsS https://$(virsh domifaddr cp \| awk '$3=="ipv4"{...}'):9090/`     | `[ ]`  | Spec 50 asserts this.                  |

### Phase 6 — Kinoite path (opt-in)

| #     | Item                                | Command                                                          | Status | Notes                                          |
| ----- | ----------------------------------- | ---------------------------------------------------------------- | ------ | ---------------------------------------------- |
| 6.1   | `vm build-kinoite` produces qcow2   | `vm build-kinoite`                                               | `[ ]`  | Slow (10–25 min); cached on success.           |
| 6.2   | `vm create --target kinoite` boots  | `vm create --target kinoite --name k1`                           | `[ ]`  | Requires Phase 2.2 + 2.3.                       |
| 6.3   | `rpm-ostree status` answers via ssh | `vm ssh k1 -- 'rpm-ostree status'`                               | `[ ]`  | Spec 90, gated on `VM_E2E_KINOITE=1`.          |

## Test Matrix

ShellSpec specs under [`spec/`](spec/), run via [`tests/smoke.sh`](tests/smoke.sh). TAP/JUnit
formatters available; default is documentation format.

Smoke run `b1a4l93l1` 2026-04-25 18:31–18:36 (310.6 s). 23 examples, 2 failures, 3 warnings.
The R-014 abort in `40_snapshot_reset_spec.sh` ended the run early — specs 50–80 did not execute.

| Spec                                                                                | Target           | Mechanism    | Status                  | Last run        | Evidence                                                                     |
| ----------------------------------------------------------------------------------- | ---------------- | ------------ | ----------------------- | --------------- | ---------------------------------------------------------------------------- |
| [`00_preflight_spec.sh`](spec/00_preflight_spec.sh)                                  | host             | unit + e2e   | `[~]` 9 PASS / 1 FAIL   | 2026-04-25 18:31 | `dispatcher rejects unknown subcommand` — exit-code or stderr drift.          |
| [`10_create_fedora_cloud_spec.sh`](spec/10_create_fedora_cloud_spec.sh)              | fedora-cloud     | e2e          | `[x]` 5 PASS            | 2026-04-25 18:31 | Domain, overlay, seed dir, metadata sidecar, ed25519 keypair all materialize. |
| [`20_cloud_init_and_net_spec.sh`](spec/20_cloud_init_and_net_spec.sh)                | fedora-cloud     | e2e          | `[~]` 1 PASS / 2 WARN   | 2026-04-25 18:31 | fedoraproject.org reached; cloud-init + DNS warn on cosmetic stderr only.    |
| [`30_ssh_and_sudo_spec.sh`](spec/30_ssh_and_sudo_spec.sh)                            | fedora-cloud     | e2e          | `[~]` 3 PASS / 1 WARN   | 2026-04-25 18:31 | Per-VM key auth + passwordless sudo + per-VM-key-active confirmed.            |
| [`40_snapshot_reset_spec.sh`](spec/40_snapshot_reset_spec.sh)                        | fedora-cloud     | e2e          | `[~]` 1 PASS / 1 FAIL   | 2026-04-25 18:31 | "install drift" `It` has multi-`When` (R-014); fail aborts the rest of the lane. |
| [`50_cockpit_spec.sh`](spec/50_cockpit_spec.sh)                                      | fedora-cloud × 2 | e2e          | `[!]` not run           | (n/a)            | Aborted before reach due to R-014.                                            |
| [`60_destroy_residue_spec.sh`](spec/60_destroy_residue_spec.sh)                      | fedora-cloud     | e2e          | `[!]` not run           | (n/a)            | Aborted before reach due to R-014.                                            |
| [`70_idempotency_spec.sh`](spec/70_idempotency_spec.sh)                              | fedora-cloud     | e2e          | `[!]` not run           | (n/a)            | Aborted before reach due to R-014.                                            |
| [`80_parallel_safety_spec.sh`](spec/80_parallel_safety_spec.sh)                      | host (lock)      | unit         | `[!]` not run           | (n/a)            | Aborted before reach due to R-014.                                            |
| [`90_kinoite_spec.sh`](spec/90_kinoite_spec.sh)                                      | kinoite          | e2e (opt-in) | `[ ]` skipped           | (n/a)            | `VM_E2E_KINOITE=1` — not exercised in default lane.                           |

## Supply-Chain Pin State

| Pin             | Current                       | Source                                                                | How to re-pin                                                                                                                                                       |
| --------------- | ----------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `IMAGE_SHA256`  | `846574c8…6c8ab2f` (43-1.6)   | [`targets/fedora-cloud.env:17`](targets/fedora-cloud.env)              | `curl -fsSL https://getfedora.org/releases.json \| jq -r '.[] \| select(.version=="43" and .arch=="x86_64" and .subvariant=="Cloud_Base") \| .sha256'`              |
| `OCI_DIGEST`    | `sha256:8fae1047…c4a9225c`    | [`targets/kinoite.env:21`](targets/kinoite.env)                        | `skopeo inspect docker://quay.io/fedora-ostree-desktops/kinoite:43 \| jq -r .Digest` (no pull required)                                                              |
| `BIB_VERSION`   | `latest`                      | [`targets/kinoite.env:24`](targets/kinoite.env)                        | Quay's bootc-image-builder no longer publishes recent `latest-NNNN` snapshot tags; pinning a digest needs a `bib.sh` change from `:tag` to `@digest` (deferred — R-003). |

## Verification Runbook

Each block: a fenced shell snippet, expected output, the assertion in plain English.

### Host ready

```bash
./vm/setup.sh
```

Expected: ends with `info  preflight: all checks passed` and `info  vm/ host setup complete`.
Means every Phase-1 check is satisfied on this boot.

### Pins set

```bash
grep -nE '^(IMAGE_SHA256|OCI_DIGEST|BIB_VERSION)=' vm/targets/*.env
```

Expected: every right-hand side is non-empty (and `BIB_VERSION` is a numeric tag, not `latest`).
Means Phase 2 is complete.

### Happy path (default lane)

```bash
./vm/tests/smoke.sh --format documentation
```

Expected: every spec under `vm/spec/` ends with `Examples: N (Total) 0 failures`. Wall clock under
5 min on a warm cache. Means Phases 3 + 4 + 7 (idempotency) + 8 (parallel safety) are green.

### Cockpit lane

The cockpit specs run as part of the default lane (`spec/50_cockpit_spec.sh`) and create two
parallel fedora-cloud VMs to verify the with/without contrast.

### Kinoite lane

```bash
VM_E2E_KINOITE=1 ./vm/tests/smoke.sh spec/90_kinoite_spec.sh
```

Expected: bib produces a qcow2 (cached for 10–25 min on first run), boot succeeds,
`rpm-ostree status` answers, destroy leaves no residue. Means Phase 6 is green.

### Residue check (manual)

```bash
ls "${XDG_STATE_HOME:-$HOME/.local/state}/scripts-vm/"{disks,seeds}/
```

Expected: empty (no overlay disks or seed dirs left after the suite tears down). Means the
`destroy` contract holds.

## Risk & Known-Gap Register

| ID    | Severity | Area          | Description                                                                          | Mitigation                                                            | Status |
| ----- | -------- | ------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------- | ------ |
| R-001 | high     | supply chain  | `IMAGE_SHA256` empty until pinned                                                    | Pinned 2026-04-25 (43-1.6, `846574c8…`).                              | `[x]`  |
| R-002 | high     | supply chain  | `OCI_DIGEST` empty until pinned                                                      | Pinned 2026-04-25 (`sha256:8fae1047…`).                               | `[x]`  |
| R-003 | medium   | supply chain  | `BIB_VERSION="latest"` (FIXME at `targets/kinoite.env:21`)                           | Pin numeric tag after first green build.                              | `[ ]`  |
| R-004 | medium   | coverage      | Kinoite e2e is opt-in; not part of default lane                                      | Promote `90_kinoite_spec.sh` once cache + pin are stable.             | `[ ]`  |
| R-005 | low      | host drift    | Fedora point-release bumps require manual `IMAGE_URL` update                          | Tracked here; not automated.                                          | `[ ]`  |
| R-006 | low      | secrets       | `cloudinit/overlays/` accepts user-specific YAML; could leak secrets if committed     | Document expectation that user-specific overlays be `.gitignore`d.    | `[ ]`  |
| R-007 | medium   | provenance    | Fedora `CHECKSUM` file is consumed without GPG verification (Tier C1)                 | Tier C: layer GPG verify on the checksum manifest.                    | `[ ]`  |
| R-008 | medium   | provenance    | Bootc OCI ref is digest-pinned but not cosign-verified (Tier C2)                      | Tier C: blocked on cosign v3 / rpm-ostree compat.                     | `[ ]`  |
| R-009 | low      | observability | Logging is human-readable text; no JSON / structured channel                          | Tier C3: optional `log_json` helper.                                  | `[ ]`  |
| R-010 | low      | provenance    | No SBOM emitted for built kinoite qcow2                                               | Tier C3: `syft` on the cached qcow2 after build.                      | `[ ]`  |
| R-011 | medium   | enforcement   | Pre-commit baseline ships on `chore/bootstrap-pre-commit-baseline`, not yet on `main` | Merged on remote 2026-04-25; PR pending. Hooks active locally on chore/lint stack and on docs/. | `[~]`  |
| R-012 | low      | enforcement   | Lint cleanup (SC2155/2034/2154/2148) ships on `chore/lint-cleanup-shellcheck`          | Pushed 2026-04-25; PR pending. Feat-only fixup already on feat.        | `[~]`  |
| R-013 | medium   | network setup | Default `qemu:///session` URI has no `default` libvirt network — VM creation fails    | One-time `virsh -c qemu:///session net-define` of bridge-mode alias to system `virbr0`. Document in `setup.sh` or surface as a guided check. Workaround in place on this host. | `[~]`  |
| R-014 | low      | tests         | `40_snapshot_reset_spec.sh` line 23 has two `When run script` blocks in one `It`, which ShellSpec rejects with "Evaluation has already been executed." | Split into two `It` blocks, or move the second invocation to a separate `It`. Mechanical refactor.                                  | `[ ]`  |

## What's Next

- Promote the kinoite spec to the default lane once `OCI_DIGEST` + `BIB_VERSION` are pinned and a
  warm cache makes wall-clock acceptable.
- Land Tier C1 (GPG-verify Fedora `CHECKSUM` before SHA256). Self-contained; no upstream
  dependencies.
- Track [coreos/rpm-ostree#5509](https://github.com/coreos/rpm-ostree/issues/5509) for the cosign
  v3 unblock; revisit Tier C2 when it closes.
- Consider a `vm cockpit <name>` subcommand that prints `https://<ip>:9090` as a one-line
  reachability shortcut (Tier C4).

## Change Log

- **2026-04-25** — `feat/vm-hardening-e2e-deploy-doc` `49ecc0a`: ShellSpec specs use
  `When run script "${VM_BIN}"` instead of `When run command "${VM_BIN}"` so the absolute
  path resolves. Mechanical sed across 9 spec files / 20 call sites.
- **2026-04-25** — `feat/vm-hardening-e2e-deploy-doc` `edc201f`: drop `--xtrace-only` from
  `vm/.shellspec` so non-interactive runs don't flood stderr with "/dev/tty: No such device".
- **2026-04-25** — `feat/vm-hardening-e2e-deploy-doc` `08f5405`: `get_ipv4` walks three
  sources (agent → lease → arp) and skips loopback. Bridge-mode networks need ARP fallback
  because session libvirt has no lease table. qemu-guest-agent ships in Fedora Cloud and
  reports `lo` first, so `$1 != "lo"` is required.
- **2026-04-25** — `feat/vm-hardening-e2e-deploy-doc` `8e22366`: fix `_CREATE_VM_ROOT` and
  `_BK_VM_ROOT` to go up two levels from `vm/scripts/subcommands/` instead of one. Targets
  now resolve at `vm/targets/<name>.env`.
- **2026-04-25** — `feat/vm-hardening-e2e-deploy-doc` `2e1c338`: `setup.sh` probes
  `virsh -c $LIBVIRT_DEFAULT_URI hostname` as the libvirt-reachable check, falling back to
  enabling `virtqemud.socket` / `libvirtd.socket` opportunistically. Drops the rigid
  `libvirtd.socket` assumption that breaks on Fedora 43 modular daemons. Preflight error
  message updated likewise.
- **2026-04-25** — `feat/vm-hardening-e2e-deploy-doc` `121c470`: pin `IMAGE_SHA256` to
  `846574c8…6c8ab2f` (Fedora-Cloud-Base-Generic-43-**1.6**.x86_64.qcow2 from
  `getfedora.org/releases.json`) and pin `OCI_DIGEST` to
  `sha256:8fae1047…c4a9225c` via `skopeo inspect`. Closes R-001 + R-002.
  R-003 (`BIB_VERSION="latest"`) stays open — quay's bib repo no longer publishes
  recent `latest-NNNN` snapshot tags, so digest-pinning would need a code change.
- **2026-04-25** — `feat/vm-hardening-e2e-deploy-doc` HEAD `97e5035`: feat-only lint fixup —
  drop shebang + add `# shellcheck shell=bash` to `preflight.sh`; SC2155 split in
  `preflight.sh::preflight_check_toolbox_socket` and `spec_helper.sh::VM_ROOT`; SC2034
  directives on the `EXIT_*` constants in `common.sh`.
- **2026-04-25** — `chore/lint-cleanup-shellcheck` `e4e7fbb` *(stacked on bootstrap)*: clear
  SC2155/2034/2154/2148 warnings across 20 main-resident files (split `readonly X="$(cmd)"`
  patterns; directives for sourced-library vars and trap `rc=$?`; replace lib shebangs with
  `# shellcheck shell=bash`).
- **2026-04-25** — `chore/bootstrap-pre-commit-baseline` `e1e70ff`: drop the repo enforcement
  baseline at root — `.pre-commit-config.yaml`, `.betterleaks.toml`, `commitlint.config.js`,
  `.markdownlint-cli2.yaml`, `.editorconfig`, `mise.toml`. Materialized by the
  `repo-bootstrap` skill.
- **2026-04-24** — `feat/vm-hardening-e2e-deploy-doc`: lib/preflight, exit-code taxonomy,
  bib cache digest re-verify, per-VM ephemeral SSH keys, `--with-cockpit` overlay, cloud-init
  readiness gate, flock parallel-safety, ShellSpec e2e suite, this document.
- **2026-04-24** — [`790affb`](https://github.com/securexai/scripts/commit/790affb)
  `docs(vm): add README + automated smoke test`.
- **2026-04-24** — [`4a5e9c4`](https://github.com/securexai/scripts/commit/4a5e9c4)
  `feat(vm): add CLI dispatcher + 10 subcommands`.
- **2026-04-24** — [`75be291`](https://github.com/securexai/scripts/commit/75be291)
  `feat(vm): add libvirt helpers + Kinoite bib pipeline`.
- **2026-04-24** — [`e00f893`](https://github.com/securexai/scripts/commit/e00f893)
  `feat(vm): add image acquisition + cloud-init pipeline`.
- **2026-04-24** — [`bbc8d16`](https://github.com/securexai/scripts/commit/bbc8d16)
  `feat(vm): scaffold foundation (setup.sh, Containerfile, lib helpers)`.

## Cross-References

- Repo-wide tracker: [`../STATUS.md`](../STATUS.md) (forward-looking branch queue + verification chain)
- Repo-wide history: [`../CHANGELOG.md`](../CHANGELOG.md)
- Repo-wide overview: [`../README.md`](../README.md)
- Subsystem README: [`README.md`](README.md)
- Setup script: [`setup.sh`](setup.sh)
- Dispatcher: [`scripts/vm`](scripts/vm)
- Preflight library: [`scripts/lib/preflight.sh`](scripts/lib/preflight.sh)
- Cockpit overlay template: [`cloudinit/overlays/cockpit.yaml.tmpl`](cloudinit/overlays/cockpit.yaml.tmpl)
- Cockpit kinoite TOML: [`targets/kinoite-cockpit.toml`](targets/kinoite-cockpit.toml)
- ShellSpec config: [`.shellspec`](.shellspec)
- ShellSpec helper: [`spec/spec_helper.sh`](spec/spec_helper.sh)
- Smoke entrypoint: [`tests/smoke.sh`](tests/smoke.sh)
- libvirt `virt-host-validate`: <https://libvirt.org/manpages/virt-host-validate.html>
- cloud-init return codes: <https://docs.cloud-init.io/en/latest/explanation/return_codes.html>
- ShellSpec docs: <https://shellspec.info/>
- cockpit-machines: <https://github.com/cockpit-project/cockpit-machines>

## How to update this doc

When the test suite is re-run cleanly, do all three in the same commit:

1. Bump the **Last verified** date in the front-matter block to today (ISO 8601).
2. Update the corresponding rows in the [Test Matrix](#test-matrix) — set `Status`, `Last run`, and
   `Evidence` (e.g., a TAP file path or "n=42 ok").
3. Tick any closed items in the [Deployment Readiness Checklist](#deployment-readiness-checklist)
   from `[ ]` to `[x]`, and update the [Risk & Known-Gap Register](#risk--known-gap-register)
   accordingly.

No automation: the smoke entrypoint is hermetic and intentionally does not mutate this file. If
that changes, document the new write-path here.
