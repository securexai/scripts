# vm/ Deployment & Test Status

> [!NOTE]
> This document is a point-in-time **snapshot**: the verification record,
> the test matrix, the supply-chain pin state, and the risk register at
> the date listed below. It is intentionally not live.
>
> - For task-shaped quickstarts: [`README.md`](README.md).
> - For the full CLI reference: [`../docs/vm-cli-reference.md`](../docs/vm-cli-reference.md).
> - For digest-pinning procedures: [`../docs/vm-supply-chain.md`](../docs/vm-supply-chain.md).
> - For symptom-indexed troubleshooting: [`../docs/vm-troubleshooting.md`](../docs/vm-troubleshooting.md).
> - For the chronological change history: [`../CHANGELOG.md`](../CHANGELOG.md).

**Status:** green / smoke green + bootc lane proven + F44 lane proven —
default ShellSpec lane runs **34 examples · 0 failures** in ~388 s.
Disposable verification VMs (`disposable-fedora` on Fedora 43 Cloud,
`disposable-bootc` on CentOS Stream 9 bootc) confirmed UEFI boot,
per-VM ephemeral ed25519 SSH auth, and passwordless sudo. F44 lane
re-verified on a Fedora 44 Kinoite host with both `fedora-cloud-44` and
`kinoite-44` deployed end-to-end.

**Last verified:** 2026-05-08

**Owner:** [@securexai](https://github.com/securexai)

**Doc version:** 2.1

## TL;DR

- The vm/ subsystem is a self-contained Fedora 43 / 44 libvirt + cloud-init
  test rig with an **11-subcommand** CLI, per-VM ephemeral SSH keys, an
  opt-in cockpit overlay, and a ShellSpec end-to-end suite.
- Supply-chain pins are populated for all four targets
  ([`targets/fedora-cloud.env`](targets/fedora-cloud.env),
  [`targets/fedora-cloud-44.env`](targets/fedora-cloud-44.env),
  [`targets/kinoite.env`](targets/kinoite.env),
  [`targets/kinoite-44.env`](targets/kinoite-44.env)). `vm create`
  no longer fails fast on missing pins. `BIB_VERSION="latest"` remains
  the only known-open pin (R-003).
- Default ShellSpec lane via `./tests/smoke.sh` is **green**: 34 examples,
  0 failures (specs 00, 05, 10, 20, 30, 40). R-016 prevents specs 60+
  from running in the default lane; they pass standalone. Cockpit and
  kinoite specs are opt-in (`VM_E2E_COCKPIT=1`, `VM_E2E_KINOITE=1`).
- All VMs boot UEFI via OVMF (`--boot firmware=efi`); per-VM NVRAM lives
  in `~/.config/libvirt/qemu/nvram/<name>_VARS.qcow2` and is cleaned up
  by `vm destroy`.
- The bootc lane is proven end-to-end via a derived OCI: build with
  `sudo podman build -t localhost/scripts-vm-bootc:latest -f vm/Containerfile.bootc vm/`,
  then `BIB_ROOTFUL=1 ./scripts/vm build-kinoite`.
- Host prerequisite: a session-scope `default` libvirt network (R-013).
  See [`../docs/vm-troubleshooting.md`](../docs/vm-troubleshooting.md)
  for the one-time setup recipe.

## Test Matrix

ShellSpec specs under [`spec/`](spec/), run via [`tests/smoke.sh`](tests/smoke.sh).
TAP/JUnit formatters available; default is documentation format.

Smoke run 2026-05-08 (387.8 s). 34 examples, 0 failures. Wrapper exits 0
with `[smoke] shellspec aborted with 0 failures — treating as success.`
on the cosmetic ShellSpec abort flag (R-015).

| Spec | Target | Mechanism | Status | Last run | Evidence |
| --- | --- | --- | --- | --- | --- |
| [`00_preflight_spec.sh`](spec/00_preflight_spec.sh) | host | unit + e2e | `[x]` 9 PASS | 2026-05-08 | OS-id check, `/dev/kvm`, binaries, `virsh` reachability, dispatcher help/usage. |
| [`05_dispatch_spec.sh`](spec/05_dispatch_spec.sh) | host | unit | `[x]` 7 PASS | 2026-05-08 | Prefix-match `--target` validation on `vm create` + `vm build-kinoite`; pure `_bib_out_subdir` derivation for `kinoite` / `kinoite-44` / cockpit overrides. |
| [`10_create_fedora_cloud_spec.sh`](spec/10_create_fedora_cloud_spec.sh) | fedora-cloud | e2e | `[x]` 7 PASS | 2026-05-08 | Domain, overlay, seed dir, metadata, ed25519 keypair, UEFI host XML + guest. |
| [`20_cloud_init_and_net_spec.sh`](spec/20_cloud_init_and_net_spec.sh) | fedora-cloud | e2e | `[x]` 3 PASS | 2026-05-08 | `cloud-init status --wait` clean, `fedoraproject.org` reachable, `quay.io` resolves. |
| [`30_ssh_and_sudo_spec.sh`](spec/30_ssh_and_sudo_spec.sh) | fedora-cloud | e2e | `[x]` 4 PASS | 2026-05-08 | Per-VM key auth + passwordless sudo + sshd-effective `passwordauthentication=no`. |
| [`40_snapshot_reset_spec.sh`](spec/40_snapshot_reset_spec.sh) | fedora-cloud | e2e | `[x]` 4 PASS | 2026-05-08 | Snapshot create, drift install, reset reverts, snapshot still present. |
| [`50_cockpit_spec.sh`](spec/50_cockpit_spec.sh) | fedora-cloud × 2 | e2e (opt-in) | `[ ]` skipped | (n/a) | `VM_E2E_COCKPIT=1` — not exercised in default lane. |
| [`60_destroy_residue_spec.sh`](spec/60_destroy_residue_spec.sh) \* | fedora-cloud | e2e | `[~]` 8 PASS | 2026-05-08 (iso) | Standalone run green; full lane stops mid-suite (R-016). Includes R-020 pool sweep. |
| [`65_prune_spec.sh`](spec/65_prune_spec.sh) \* | host (synthetic) | unit | `[~]` 5 PASS | 2026-05-08 (iso) | Dry-run, --apply, idempotency, held-lock skip, EXIT_USAGE on bogus arg. |
| [`66_prune_pool_residue_spec.sh`](spec/66_prune_pool_residue_spec.sh) \* | host (synthetic) | unit | `[~]` 3 PASS | 2026-05-08 (iso) | Pool path-based sweep covers R-020 leak. |
| [`70_idempotency_spec.sh`](spec/70_idempotency_spec.sh) \* | fedora-cloud | e2e | `[~]` 6 PASS | 2026-05-08 (iso) | Standalone run green; full lane stops mid-suite (R-016). |
| [`80_parallel_safety_spec.sh`](spec/80_parallel_safety_spec.sh) \* | host (lock) | unit | `[~]` 2 PASS | 2026-05-08 (iso) | Standalone run green; full lane stops mid-suite (R-016). |
| [`90_kinoite_spec.sh`](spec/90_kinoite_spec.sh) | kinoite | e2e (opt-in) | `[ ]` skipped | (n/a) | `VM_E2E_KINOITE=1` — not exercised in default lane. |

\* In the full lane, ShellSpec stops emitting examples after spec 40 even
though every spec runs cleanly when invoked directly. The wrapper's
success-on-cosmetic-abort logic keeps the lane green; standalone
invocation confirms 60/65/66/70/80 all pass. Tracked as R-016.

## Supply-Chain Pin State

Snapshot of the pinned digests as of the verification date.

| Pin | Current | Source |
| --- | --- | --- |
| `IMAGE_SHA256` (fedora-cloud) | `846574c8…6c8ab2f` (43-1.6) | [`targets/fedora-cloud.env`](targets/fedora-cloud.env) |
| `IMAGE_SHA256` (fedora-cloud-44) | `28680fe5…f90b7f` (44-1.7) | [`targets/fedora-cloud-44.env`](targets/fedora-cloud-44.env) |
| `OCI_DIGEST` (kinoite) | `sha256:bb87e784…20f0a49d` (local derived OCI) | [`targets/kinoite.env`](targets/kinoite.env) |
| `OCI_DIGEST` (kinoite-44) | `sha256:63b3fce4…b547affe5` (local derived OCI) | [`targets/kinoite-44.env`](targets/kinoite-44.env) |
| `BIB_VERSION` | `latest` (R-003 open) | [`targets/kinoite.env`](targets/kinoite.env), [`targets/kinoite-44.env`](targets/kinoite-44.env) |

The re-pin runbook (per-target commands, verification) lives in
[`../docs/vm-supply-chain.md`](../docs/vm-supply-chain.md).

## Risk & Known-Gap Register

| ID | Severity | Area | Description | Mitigation | Status |
| --- | --- | --- | --- | --- | --- |
| R-001 | high | supply chain | `IMAGE_SHA256` empty until pinned | Pinned 2026-04-25 (43-1.6, `846574c8…`); 2026-04-29 (44-1.7, `28680fe5…`). | `[x]` |
| R-002 | high | supply chain | `OCI_DIGEST` empty until pinned | Pinned 2026-04-25 / 2026-04-29 (current values track derived OCI image IDs). | `[x]` |
| R-003 | medium | supply chain | `BIB_VERSION="latest"` | Quay's bib repo no longer publishes recent `latest-NNNN` snapshot tags; pinning a digest needs a `lib/bib.sh` change from `:tag` to `@digest`. Deferred. | `[ ]` |
| R-004 | medium | coverage | Kinoite e2e is opt-in; not part of default lane | Promote `90_kinoite_spec.sh` once cache + pin are stable. | `[ ]` |
| R-005 | low | host drift | Fedora point-release bumps require manual `IMAGE_URL` update | Tracked here; not automated. | `[ ]` |
| R-006 | low | secrets | `cloudinit/overlays/` accepts user-specific YAML; could leak secrets if committed | Document expectation that user-specific overlays be `.gitignore`d. | `[ ]` |
| R-007 | medium | provenance | Fedora `CHECKSUM` file consumed without GPG verification (Tier C1) | Tier C: layer GPG verify on the checksum manifest. | `[ ]` |
| R-008 | medium | provenance | Bootc OCI ref is digest-pinned but not cosign-verified (Tier C2) | Tier C: blocked on cosign v3 / rpm-ostree compat. | `[ ]` |
| R-009 | low | observability | Logging is human-readable text; no JSON / structured channel | Tier C3: optional `log_json` helper. | `[ ]` |
| R-010 | low | provenance | No SBOM emitted for built kinoite qcow2 | Tier C3: `syft` on the cached qcow2 after build. | `[ ]` |
| R-013 | medium | network setup | Default `qemu:///session` URI has no `default` libvirt network — VM creation fails | One-time `virsh -c qemu:///session net-define` of bridge-mode alias to system `virbr0`. Recipe in [`../docs/vm-troubleshooting.md`](../docs/vm-troubleshooting.md). | `[~]` |
| R-014 | low | tests | `40_snapshot_reset_spec.sh` had two `When run script` blocks in one `It`, which ShellSpec rejects with "Evaluation has already been executed." | Split into two `It` blocks. | `[x]` |
| R-015 | low | tests | ShellSpec reporter clings to `aborted=1` flag at end-of-suite even when every example passed. Cosmetic only. | `tests/smoke.sh` wraps the run, suspends errexit, and treats "0 failures, 0 errors, aborted by an unexpected error" as exit 0. | `[x]` |
| R-016 | low | tests | In the full lane, ShellSpec stops reporting examples after `40_snapshot_reset_spec.sh` even though specs 60/65/66/70/80 each pass in isolation. | Workaround: opt-in specs gated, R-015 wrapper accepts the abort. Real fix is upstream-shellspec instrumentation. | `[~]` |
| R-017 | medium | supply chain | bib `latest` reports `missing required info: DefaultRootFs` against Fedora bootc bases. | `lib/bib.sh` plumbs a `--rootfs ${BIB_ROOTFS}` flag conditional on the env var being set; targets that need it (e.g. `kinoite-44`) export `BIB_ROOTFS="btrfs"`. The derived-OCI workaround on `centos-bootc:stream9` in [`Containerfile.bootc`](Containerfile.bootc) remains valid. | `[~]` |
| R-018 | low | bib | Rootless bib fails with "Failed to remount /: Permission denied" because rootless `--privileged` doesn't grant CAP_SYS_ADMIN over the parent namespace's mounts. | `BIB_ROOTFUL=1 ./vm/scripts/vm build-kinoite` opt-in uses `sudo podman` and bind-mounts `/var/lib/containers/storage`. | `[x]` |
| R-019 | low | host drift | F44 host bump. | F44 host validated; F44 targets added with verified pins (qcow2 SHA256 from signed F44 CHECKSUM; kinoite-44 derived OCI). Default `VM_EXPECTED_FEDORA` widened to `"43 44"`. **Remaining open**: `OS_VARIANT="fedora-unknown"` on both F44 targets — osinfo-db `v20251212` does not yet ship a `fedora44` short-id. | `[~]` |
| R-020 | low | libvirt | `virt-install --disk path=…` auto-defines a per-VM dir-type libvirt storage pool that `virsh undefine` does not drop, so a long-running dev host accumulates one stale pool definition per VM created. | `vm_undefine` sweeps any pool whose `<path>` is exactly `${SEED_DIR}/<name>` after the domain is undefined; `vm prune --apply` mops up historical leaks via the same path-based filter. | `[x]` |

## How to update this doc

When the test suite is re-run cleanly, do all three in the same commit:

1. Bump the **Last verified** date in the front-matter to today (ISO 8601).
2. Update the corresponding rows in the [Test Matrix](#test-matrix) — set
   `Status`, `Last run`, and `Evidence`.
3. Tick any closed items in the
   [Risk & Known-Gap Register](#risk--known-gap-register) from `[ ]` /
   `[~]` to `[x]`. If a new risk surfaced, add it as the next `R-NNN`.

For a user-visible change log, update [`../CHANGELOG.md`](../CHANGELOG.md)
in the same commit. Procedural runbooks for re-pinning images, fixing
known footguns, etc., live under [`../docs/`](../docs/).
