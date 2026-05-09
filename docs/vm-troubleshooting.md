# vm/ troubleshooting

Symptom-indexed fixes for known footguns. The risk register entries
(`R-NNN`) referenced below have full context in
[`../vm/DEPLOYMENT.md`](../vm/DEPLOYMENT.md).

## "vm create fails: No network found with name 'default'"

**Cause.** The dispatcher uses `qemu:///session` (rootless, per-user) by
default. libvirt's stock `default` NAT network only exists in
`qemu:///system`. R-013 tracks this; on a fresh host the session URI has
no `default` network at all.

**Fix.** One-time per host: define a session-scope `default` network as a
bridge alias to the system `virbr0`:

```bash
# Make sure the system default network is up first
sudo virsh -c qemu:///system net-start default 2>/dev/null || true
sudo virsh -c qemu:///system net-autostart default

# Define a session-scope alias that bridges into virbr0
cat > /tmp/session-default.xml <<'EOF'
<network>
  <name>default</name>
  <forward mode='bridge'/>
  <bridge name='virbr0'/>
</network>
EOF

virsh -c qemu:///session net-define /tmp/session-default.xml
virsh -c qemu:///session net-start    default
virsh -c qemu:///session net-autostart default
rm /tmp/session-default.xml
```

After this, `virsh -c qemu:///session net-list | grep -w default` should
list the network as active. The fix is persistent.

## "bib fails: missing required info: DefaultRootFs"

**Cause.** Fedora bootc images (`fedora-bootc:NN`,
`fedora-ostree-desktops/kinoite:NN`) intentionally omit a default root
filesystem from their image metadata. Upstream policy directs you to pass
`--rootfs <type>` instead. Tracked as R-017.

**Fix.** Set `BIB_ROOTFS` in the target's env file. The
[`kinoite-44`](../vm/targets/kinoite-44.env) target already sets
`BIB_ROOTFS="btrfs"` (matching the Fedora 44 Cloud Base default). For
forks targeting other Fedora bootc bases, choose `btrfs` or `xfs`:

```bash
# In vm/targets/<target>.env:
BIB_ROOTFS="btrfs"
```

`lib/bib.sh` plumbs this through as `--rootfs ${BIB_ROOTFS}` when
non-empty.

## "bib fails: Failed to remount /: Permission denied"

**Cause.** Rootless `--privileged` does not actually grant
`CAP_SYS_ADMIN` over the parent namespace's mounts, which is what
`bootc-image-builder` needs to assemble its sandbox. Tracked as R-018.

**Fix.** Opt into the rootful path:

```bash
BIB_ROOTFUL=1 ./vm/scripts/vm build-kinoite
# or for a non-default target:
BIB_ROOTFUL=1 ./vm/scripts/vm build-kinoite --target kinoite-44
```

The lib falls back to `sudo podman` and bind-mounts
`/var/lib/containers/storage`. Requires passwordless sudo on the host.
On a host without passwordless sudo, you'll be prompted once at the start
of the build.

## Smoke run reports "aborted by an unexpected error" but exits 0

**Cause.** ShellSpec clings to an `aborted=1` reporter flag at end-of-suite
even when every example passed. Tracked as R-015 (cosmetic, mitigated)
and R-016 (still open — the abort fires *before* specs 60+ get to run in
the default lane).

**Fix.** Use the `tests/smoke.sh` wrapper, which suspends `errexit`
around the ShellSpec invocation and treats "0 failures, 0 errors,
aborted by an unexpected error" as exit 0:

```bash
./vm/tests/smoke.sh
```

Specs `60_destroy_residue`, `65_prune`, `66_prune_pool_residue`,
`70_idempotency`, and `80_parallel_safety` are silently skipped in the
default lane because the abort fires before they run. They pass cleanly
when invoked standalone — run them explicitly after touching
destroy/lock/prune behavior. The R-016 abort also fires inside the
standalone batch right before `80_parallel_safety`, so split it off:

```bash
cd vm && shellspec spec/60_destroy_residue_spec.sh \
                   spec/65_prune_spec.sh \
                   spec/66_prune_pool_residue_spec.sh \
                   spec/70_idempotency_spec.sh
cd vm && shellspec spec/80_parallel_safety_spec.sh
```

## OS_VARIANT=fedora-unknown on kinoite-44 / fedora-cloud-44

**Cause.** osinfo-db `v20251212` (still the latest tagged release as of
2026-05-08, shipped as `osinfo-db-20251212-1.fc44.noarch` on Fedora 44)
does not yet ship a `fedora44` short-id. `fedora-unknown` is the
libosinfo-recommended catch-all in the meantime. Tracked as R-019.

**Fix.** Cosmetic only — there is no functional impact on VM creation,
network, or guest behavior. When osinfo-db cuts a release containing
`fedora-44.xml.in`, bump both `fedora-cloud-44.env` and `kinoite-44.env`
from `OS_VARIANT="fedora-unknown"` to `OS_VARIANT="fedora44"`.

To check whether your osinfo-db has the entry yet:

```bash
osinfo-query os | grep -w fedora44
```

Empty output means it's still missing.

## Long-lived host has 100+ stale libvirt storage pools

**Cause.** `virt-install --disk path=…` auto-defines a per-VM dir-type
storage pool whose `<path>` matches `${SEED_DIR}/<vm-name>`. `virsh
undefine` doesn't drop these, so a long-running dev host accumulates one
stale pool definition per VM created. Tracked as R-020 (closed; current
`vm destroy` no longer leaks).

**Fix.** Run `vm prune` to mop up the historical leaks:

```bash
./vm/scripts/vm prune              # dry-run preview
./vm/scripts/vm prune --apply      # commit the cleanup
```

The sweep is path-based: pools whose `<path>` is a *direct child* of
`${SEED_DIR}/` are dropped if no live domain owns them. Pools outside
that prefix are never touched, even if their name happens to collide
with a VM name.

## VM created but cloud-init reports a fatal error (exit 72)

**Cause.** Cloud-init exit code 1 is a fatal error in the guest.
Anything else — including code 2 (non-fatal warnings) — is treated as
acceptable by `vm create`. A code-1 error usually means the seed ISO had
a YAML syntax problem or a directive cloud-init couldn't satisfy on the
chosen base image.

**Fix.** SSH into the VM and read the long-form status:

```bash
./vm/scripts/vm ssh <name> -- 'sudo cloud-init status --long'
./vm/scripts/vm ssh <name> -- 'sudo journalctl -u cloud-init.target --no-pager'
```

If you authored a custom overlay, the most common pitfall is duplicated
top-level keys between the base and the overlay — see the cloud-init
seed flow note in [`vm-architecture.md`](vm-architecture.md). PyYAML
silently keeps the last duplicate, so a `users:` block in your overlay
will wipe the base's `users:` (which is what installs the per-VM SSH
key).

## Reproduce the green snapshot

The
[`../vm/DEPLOYMENT.md`](../vm/DEPLOYMENT.md) front-matter records the
last verification snapshot. To reproduce it on your own host, in order:

### Host ready

```bash
./vm/setup.sh
```

Expected: ends with `info  preflight: all checks passed` and
`info  vm/ host setup complete`.

### Pins set

```bash
grep -nE '^(IMAGE_SHA256|OCI_DIGEST|BIB_VERSION)=' vm/targets/*.env
```

Expected: every right-hand side non-empty (note `BIB_VERSION="latest"`
remains the known-open pin tracked by R-003).

### Default smoke lane

```bash
./vm/tests/smoke.sh
```

Expected: `34 examples, 0 failures, aborted by an unexpected error`
followed by `[smoke] shellspec aborted with 0 failures — treating as
success.` and exit 0. Wall-clock ~5–6 min on a warm cache.

### Standalone lane (specs 60–80)

```bash
cd vm && shellspec spec/60_destroy_residue_spec.sh \
                   spec/65_prune_spec.sh \
                   spec/66_prune_pool_residue_spec.sh \
                   spec/70_idempotency_spec.sh
cd vm && shellspec spec/80_parallel_safety_spec.sh
```

Expected: 22 examples + cosmetic R-016 abort from the first command,
then 2 examples cleanly from the second. 24 total, 0 failures.

### Cockpit lane (opt-in)

```bash
VM_E2E_COCKPIT=1 ./vm/tests/smoke.sh spec/50_cockpit_spec.sh
```

Expected: two parallel fedora-cloud VMs (with + without `--with-cockpit`)
verify the contrast; `cockpit.socket` reachable on `:9090` from the host
on the cockpit VM only.

### Kinoite lane (opt-in, slow)

```bash
VM_E2E_KINOITE=1 ./vm/tests/smoke.sh spec/90_kinoite_spec.sh
```

Expected: bib produces a qcow2 (10–25 min on first run; cached after),
boot succeeds, `rpm-ostree status` answers, destroy leaves no residue.

### Residue check

```bash
ls "${XDG_STATE_HOME:-$HOME/.local/state}/scripts-vm/"{disks,seeds}/
```

Expected: empty after a successful run, confirming the destroy contract
holds.

## See also

- [`../README.md`](../README.md) — repo overview
- [`../vm/README.md`](../vm/README.md) — quickstarts
- [`vm-cli-reference.md`](vm-cli-reference.md) — flags and exit codes
- [`vm-architecture.md`](vm-architecture.md) — invariants
- [`../vm/DEPLOYMENT.md`](../vm/DEPLOYMENT.md) — full risk register
  (R-001 through R-020)
