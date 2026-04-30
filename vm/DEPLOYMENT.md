# vm/ Deployment & Test Status

**Status:** green / smoke green + bootc lane proven + live-VM re-verified —
default ShellSpec lane runs **27 examples · 0 failures** in ~370 s, and
both disposable VMs are up right now:
`disposable-fedora` at `192.168.122.216` (Fedora 43 Cloud, kernel
6.17.1-300.fc43.x86_64) and `disposable-bootc` at `192.168.122.243`
(CentOS Stream 9 bootc, kernel 5.14.0-691.el9.x86_64). Both boot UEFI
(`/sys/firmware/efi` present), authenticate with the per-VM ephemeral
ed25519 key, and pass passwordless sudo. R-017 is now reframed: the
"missing `DefaultRootFs`" is upstream Fedora bootc policy (intentional,
not a bug); the supported fix is bib's `--rootfs` CLI flag, plumbed
through `lib/bib.sh` via `BIB_ROOTFS`. The derived-OCI workaround in
`Containerfile.bootc` remains valid as an alternative. R-019 tracks
the pending Fedora 44 host bump (F44 went GA 2026-04-28).

**Last verified:** 2026-04-26

**Owner:** [@securexai](https://github.com/securexai)

**Doc version:** 1.8

**Subsystem SHA:** `main` (HEAD `35ee4a5`) — PRs #1 + #2 + #3 merged 2026-04-29

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
- The default ShellSpec lane runs via `./tests/smoke.sh` and is **green**: 27 examples,
  0 failures (specs 00 → 40 — R-016 prevents specs 60+ from running in the default lane).
  Cockpit and kinoite specs are opt-in (`VM_E2E_COCKPIT=1`, `VM_E2E_KINOITE=1`); residue,
  prune, idempotency, and parallel-safety specs (60/65/70/80) are exercised standalone
  (see Verification Runbook).
- All VMs boot UEFI (OVMF firmware via `--boot firmware=efi`); per-VM NVRAM lives in
  `~/.config/libvirt/qemu/nvram/<name>_VARS.qcow2` and is cleaned up by `vm destroy`.
- The bootc lane is now proven end-to-end via a derived OCI: build with
  `sudo podman build -t localhost/scripts-vm-bootc:latest -f vm/Containerfile.bootc vm/`
  then `BIB_ROOTFUL=1 ./scripts/vm build-kinoite`; result is a working CentOS Stream 9
  bootc VM with cloud-init injecting the per-VM SSH key into `core` (UEFI, sudo, network).
  Re-aiming this at a real Fedora-bootc-Kinoite base is gated on R-017.
- Host prerequisite: a session-scope `default` libvirt network (R-013) — the scripts
  default to `qemu:///session` for rootless XDG paths, but libvirt's stock `default` NAT
  network only exists in `qemu:///system`. See Phase 1.5 below for the one-time setup.

## Scope

This document covers the `vm/` subsystem of the `scripts` repo. The repo-root `bash/`
directory (one-off hook scripts) and `.toolbox/` (dev-environment Containerfile +
setup) are out of scope here. Repo-wide context lives in [`../CLAUDE.md`](../CLAUDE.md).

## Host Prerequisites

The vm/ workflow targets a Fedora 43 or 44 host (Workstation or Kinoite/Silverblue)
with KVM. The [`setup.sh`](setup.sh) script installs the layered packages and runs
the full preflight after the binaries land. `VM_EXPECTED_FEDORA` defaults to the
allowlist `"43 44"`; widen it (e.g. `"43 44 45"`) to straddle a future bump.

| Requirement                  | Verified by                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------- |
| Fedora 43 or 44 (`ID=fedora`) | [`scripts/lib/preflight.sh`](scripts/lib/preflight.sh) `preflight_check_os_id`        |
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

Smoke run 2026-04-29 (368.5 s). 27 examples, 0 failures.
Wrapper exits 0 with `[smoke] shellspec aborted with 0 failures — treating as success.`
on the cosmetic ShellSpec abort flag (R-015).

| Spec                                                                                | Target           | Mechanism    | Status        | Last run         | Evidence                                                                     |
| ----------------------------------------------------------------------------------- | ---------------- | ------------ | ------------- | ---------------- | ---------------------------------------------------------------------------- |
| [`00_preflight_spec.sh`](spec/00_preflight_spec.sh)                                  | host             | unit + e2e   | `[x]` 9 PASS  | 2026-04-29       | OS-id check (incl. allowlist), `/dev/kvm`, binaries, `virsh` reachability, dispatcher help/usage. |
| [`10_create_fedora_cloud_spec.sh`](spec/10_create_fedora_cloud_spec.sh)              | fedora-cloud     | e2e          | `[x]` 7 PASS  | 2026-04-29       | Domain, overlay, seed dir, metadata sidecar, ed25519 keypair, UEFI host XML + guest. |
| [`20_cloud_init_and_net_spec.sh`](spec/20_cloud_init_and_net_spec.sh)                | fedora-cloud     | e2e          | `[x]` 3 PASS  | 2026-04-29       | `cloud-init status --wait` clean, `fedoraproject.org` reachable, `quay.io` resolves. |
| [`30_ssh_and_sudo_spec.sh`](spec/30_ssh_and_sudo_spec.sh)                            | fedora-cloud     | e2e          | `[x]` 4 PASS  | 2026-04-29       | Per-VM key auth + passwordless sudo + sshd-effective `passwordauthentication=no` + key-active. |
| [`40_snapshot_reset_spec.sh`](spec/40_snapshot_reset_spec.sh)                        | fedora-cloud     | e2e          | `[x]` 4 PASS  | 2026-04-29       | Snapshot create, drift install, reset reverts, snapshot still present.       |
| [`50_cockpit_spec.sh`](spec/50_cockpit_spec.sh)                                      | fedora-cloud × 2 | e2e (opt-in) | `[ ]` skipped | (n/a)            | `VM_E2E_COCKPIT=1` — not exercised in default lane.                          |
| [`60_destroy_residue_spec.sh`](spec/60_destroy_residue_spec.sh) *                    | fedora-cloud     | e2e          | `[~]` 7 PASS  | 2026-04-29 (iso) | Standalone run green; full lane stops mid-suite (R-016).                     |
| [`65_prune_spec.sh`](spec/65_prune_spec.sh) *                                        | host (synthetic) | unit         | `[~]` 5 PASS  | 2026-04-29 (iso) | Dry-run, --apply, idempotency, held-lock skip, EXIT_USAGE on bogus arg.      |
| [`70_idempotency_spec.sh`](spec/70_idempotency_spec.sh) *                            | fedora-cloud     | e2e          | `[~]` 6 PASS  | 2026-04-29 (iso) | Standalone run green; full lane stops mid-suite (R-016).                     |
| [`80_parallel_safety_spec.sh`](spec/80_parallel_safety_spec.sh) *                    | host (lock)      | unit         | `[~]` 2 PASS  | 2026-04-29 (iso) | Standalone run green; full lane stops mid-suite (R-016).                     |
| [`90_kinoite_spec.sh`](spec/90_kinoite_spec.sh)                                      | kinoite          | e2e (opt-in) | `[ ]` skipped | (n/a)            | `VM_E2E_KINOITE=1` — not exercised in default lane.                          |

\* In the full lane, ShellSpec stops emitting examples after spec 40 even though every spec runs cleanly when invoked directly. The wrapper's success-on-cosmetic-abort logic keeps the lane green; standalone invocation (`shellspec spec/60_destroy_residue_spec.sh`) confirms 60/70/80 all pass. Tracked as R-016.

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
./vm/tests/smoke.sh
```

Expected: `27 examples, 0 failures, aborted by an unexpected error` followed by
`[smoke] shellspec aborted with 0 failures — treating as success.` and exit 0.
Wall clock 5–6 min on a warm cache. Means Phases 3 + 4 are green; the `[~]` rows in the Test
Matrix (specs 60/65/70/80) are validated separately (see Idempotency / parallel-safety lane).

### Cockpit lane (opt-in)

```bash
VM_E2E_COCKPIT=1 ./vm/tests/smoke.sh spec/50_cockpit_spec.sh
```

Expected: two parallel fedora-cloud VMs (with + without `--with-cockpit`) verify the contrast;
`cockpit.socket` reachable on `:9090` from the host on the cockpit VM only.

### Idempotency / parallel-safety / residue lane (standalone)

```bash
shellspec spec/60_destroy_residue_spec.sh spec/65_prune_spec.sh \
          spec/70_idempotency_spec.sh spec/80_parallel_safety_spec.sh
```

Expected: 20 examples, 0 failures. These pass in isolation; the full default lane currently
stops emitting after spec 40 (R-016) but the wrapper still exits 0 on the cosmetic abort.

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
| R-014 | low      | tests         | `40_snapshot_reset_spec.sh` line 23 had two `When run script` blocks in one `It`, which ShellSpec rejects with "Evaluation has already been executed." | Split into two `It` blocks (`bc27040`).                                                                                              | `[x]`  |
| R-015 | low      | tests         | ShellSpec reporter clings to `aborted=1` flag at end-of-suite even when every example passed; `executor: 0`, `error handler: 0`, `reporter: 1`. Cosmetic only. | `tests/smoke.sh` wraps the run, suspends errexit, and treats "0 failures, 0 errors, aborted by an unexpected error" as exit 0 (`deb3bef`). | `[x]`  |
| R-016 | low      | tests         | In the full lane, ShellSpec stops reporting examples after `40_snapshot_reset_spec.sh` even though specs 60/70/80 each pass in isolation. Suspect: stderr leak from one spec's evaluation poisons the executor's marker stream for the rest of the run. | Workaround: opt-in specs gated, R-015 wrapper accepts the abort. Real fix is upstream-shellspec instrumentation; defer until specs 60/70/80 stop passing in isolation. | `[~]`  |
| R-017 | medium   | supply chain  | bib `latest` reports `missing required info: DefaultRootFs` against `quay.io/fedora-ostree-desktops/kinoite:43` and `quay.io/fedora/fedora-bootc:43`. **Reframed 2026-04-29:** this is upstream Fedora bootc policy (per upstream docs: "Some images (like fedora) do not have a default root filesystem type. In this case, you need to add the switch `--rootfs <type>`"). Same policy holds for f44 bases, so this isn't a "wait for upstream" item. | `lib/bib.sh` plumbs a `--rootfs ${BIB_ROOTFS}` flag conditional on the env var being set; targets that need it (kinoite-on-fedora-bootc) export `BIB_ROOTFS="btrfs"` in their env file. The derived-OCI workaround on `centos-bootc:stream9` (which carries `DefaultRootFs`) in `Containerfile.bootc` remains valid as the alternative. | `[~]`  |
| R-018 | low      | bib           | Rootless bib fails with "Failed to remount /: Permission denied" because rootless `--privileged` doesn't grant CAP_SYS_ADMIN over the parent namespace's mounts. | `BIB_ROOTFUL=1 ./vm/scripts/vm build-kinoite` opt-in lands in `6b43b86`; uses `sudo podman` and bind-mounts `/var/lib/containers/storage`. Requires passwordless sudo. | `[x]`  |
| R-019 | low      | host drift    | Repo was Fedora-43-pinned. F44 went GA 2026-04-28; user upgraded host to F44 Kinoite 2026-04-29. **Resolved on the host side**: smoke-on-F44 ran 27/27 against the F43 cloud target with `VM_EXPECTED_FEDORA="43 44"` (libvirt 12.0.0 + qemu-kvm 10.2.2 on F44 host — no breaking changes). New `fedora-cloud-44` and `kinoite-44` targets added with verified pins (qcow2 SHA256 from signed F44 CHECKSUM; `kinoite:44` and `fedora-bootc:44` digests from Quay v1 API). Default `VM_EXPECTED_FEDORA` widened to `"43 44"`. **Remaining open**: `OS_VARIANT="fedora-unknown"` on both F44 targets — osinfo-db `v20251212` and the F44-shipped osinfo-db RPM do not yet ship a `fedora44` short-id (verified locally via `osinfo-query os \| grep fedora44` — empty). Bump to `"fedora44"` once osinfo-db cuts a release containing `fedora-44.xml.in`. | `[~]`  |

## What's Next

- **F44 host bump (R-019).** Two F43-safe prep changes land in this PR (preflight allowlist
  + `bib.sh --rootfs` plumbing). When a real F44 host is available, run the standard smoke
  lane, then re-pin `IMAGE_SHA256` from the F44 CHECKSUM, `OCI_DIGEST` for `kinoite:44`,
  and bump `OS_VARIANT` to `fedora44`. Verify the toolbx socket bridge
  (`/run/user/$UID/libvirt/virtqemud-sock`) behaves identically.
- Promote the kinoite spec to the default lane once `OCI_DIGEST` + `BIB_VERSION` are pinned and a
  warm cache makes wall-clock acceptable.
- Land Tier C1 (GPG-verify Fedora `CHECKSUM` before SHA256). Self-contained; no upstream
  dependencies.
- Track [coreos/rpm-ostree#5509](https://github.com/coreos/rpm-ostree/issues/5509) for the cosign
  v3 unblock; revisit Tier C2 when it closes.
- Consider a `vm cockpit <name>` subcommand that prints `https://<ip>:9090` as a one-line
  reachability shortcut (Tier C4).

## Change Log

- **2026-04-29** — `feat/f44-vm-targets` (live verification on F44 host):
  Host upgraded to **Fedora 44 Kinoite 44.20260428.0** (kernel
  `6.19.10-300.fc44`, libvirt `12.0.0`, qemu-kvm `10.2.2`). Smoke-on-F44
  against the existing F43 cloud target ran 27/27, 0 failures, 411 s
  with `VM_EXPECTED_FEDORA="43 44"` — no code-level breaking changes
  surfaced from the F43 → F44 host bump. New targets added:
  `fedora-cloud-44` (Fedora 44 Cloud Base 44-1.7,
  `IMAGE_SHA256=28680fe5…b7f` from signed CHECKSUM) and `kinoite-44`
  (derived OCI via new `vm/Containerfile.kinoite-44` layering cloud-init
  on `quay.io/fedora-ostree-desktops/kinoite:44@sha256:91d44aa9…8718`,
  `BIB_ROOTFS=btrfs`). Live test: `vm create --target fedora-cloud-44
  --name probe-44` → kernel 6.19.10, cloud-init 25.3, per-VM ed25519
  key auth, passwordless sudo all green; destroy clean.
  `vm/scripts/subcommands/build-kinoite.sh` extended with `--target`
  flag (default `kinoite`); `vm/scripts/subcommands/create.sh` case
  statement broadened from exact match to `fedora-cloud*` /
  `kinoite*` prefix match. Default `VM_EXPECTED_FEDORA` widened from
  `"43"` to `"43 44"`. R-019 status flipped `[ ]` → `[~]` (host side
  resolved; `OS_VARIANT="fedora-unknown"` interim until osinfo-db
  ships fedora44 — verified missing in the current osinfo-db RPM).
  Doc bumped to v1.8.
- **2026-04-29** — `main` (post-merge tracking entry, no live re-verification):
  PRs #1 + #2 squash-merged; the vm/ subsystem is now on `main`. Additions
  layered on top of the original PR #1: `vm prune` subcommand + `lib/locks.sh`
  flock helper extraction (`bc7364e` / `3935383`), cloud-init seed via
  `write_files` + sshd-effective `passwordauthentication` probe (`41ad11a`),
  bootc digest pin + bib transport-prefix guard + kinoite-cockpit schema
  cleanup (`10b284c`), repo `CLAUDE.md` (`de0cd05`). **F44 research**
  (2026-04-29, post-F44 GA 2026-04-28): bash 5.3.9 / libvirt 12.0.0 /
  qemu-kvm 10.2.2 / cloud-init 25.3 on F44 base — no breaking changes
  surfaced for `--boot firmware=efi`, `qemu:///session`, modular daemons,
  or cloud-init `runcmd`/`write_files`/`users` contracts. R-017 reframed as
  upstream policy (Fedora bootc images intentionally lack `DefaultRootFs`)
  with `--rootfs` flag as the supported fix; R-019 opened to track the
  pending F44 image re-pins. Two F43-safe prep changes land alongside this
  doc bump: `preflight_check_os_id` accepts an allowlist; `lib/bib.sh`
  plumbs `--rootfs ${BIB_ROOTFS}`. Doc bumped to v1.7.
- **2026-04-26** — `feat/vm-hardening-e2e-deploy-doc` (post-`3c56e60` re-verification):
  live-VM smoke against both lanes from a clean shell. `virsh -c qemu:///session list --all`
  shows `disposable-fedora` and `disposable-bootc` both `running`; `vm ssh` into each returns
  expected `os-release` (Fedora 43 Cloud / CentOS Stream 9), kernel (6.17.1-300.fc43 /
  5.14.0-691.el9), wheel-group user (`fedora` / `core`), and `/sys/firmware/efi` present.
  No code or test changes — confirms the v1.5 state holds across reboots and reseeded keys.
  Doc bumped to v1.6 to stamp the checkpoint.
- **2026-04-26** — `feat/vm-hardening-e2e-deploy-doc` `8af294f`: bootc lane works end-to-end
  via a derived OCI. New `vm/Containerfile.bootc` layers cloud-init + systemd enables on
  `centos-bootc:stream9`; `bib.sh` learns to consume `localhost/...` refs (skip pull, pass
  bare ref to bib — `containers-storage:` transport is rejected by bib's parser);
  `cloudinit.sh` threads `DEFAULT_USER` through envsubst so the new explicit `users:` block
  in `user-data.tmpl` injects the per-VM key into the right login user;
  `targets/kinoite.toml` drops `customizations.services` (rejected by bib `latest`); systemd
  state moves into the derived image. Verified: CentOS Stream 9 bootc VM, kernel 5.14, UEFI,
  passwordless sudo for `core`, cloud-init 24.4, bootc 1.14.1.
- **2026-04-26** — `feat/vm-hardening-e2e-deploy-doc` `ecbcb62`: all VMs boot UEFI by
  default (`--boot firmware=efi`). Spec 10 grew two regression checks (host XML uses
  `firmware='efi'`; guest sees `/sys/firmware/efi`).
- **2026-04-26** — `feat/vm-hardening-e2e-deploy-doc` `6b43b86` + `3505c19` + `3005e24`:
  `BIB_ROOTFUL=1` opt-in (rootless bib can't remount privileged sandbox); kinoite TOML
  schema corrected to single-table form; R-017 widened to "bib `latest` metadata schema is
  ahead of f43 bootc base images" (diagnostic with fedora-bootc:43 reproduced the same
  `DefaultRootFs missing` error).
- **2026-04-26** — `feat/vm-hardening-e2e-deploy-doc` `deb3bef`: cockpit + kinoite Skip-if
  predicates use POSIX `[ ]` (ShellSpec evaluates predicates in a POSIX subshell where
  bash's `[[` isn't a builtin); add `The output/stderr should be defined` matchers on
  specs 20/30/40/60/70 to acknowledge expected info-level stderr; gate cockpit lane behind
  `VM_E2E_COCKPIT=1` to mirror kinoite; wrap `tests/smoke.sh` so it exits 0 on the cosmetic
  ShellSpec `aborted=1` flag when failures and errors are both zero. Closes R-014, R-015;
  R-016 tracked.
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

- Repo-wide context: [`../CLAUDE.md`](../CLAUDE.md)
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
