# vm/

Spin up real VMs on a Fedora 43 host (Kinoite or Workstation) to test,
validate, and troubleshoot scripts in this repo. Native libvirt + cloud-init,
no Vagrant / Packer / Ansible.

> **Deployment status & test coverage:** see [`DEPLOYMENT.md`](DEPLOYMENT.md).

## Targets

| Target          | Image acquisition           | Default user | RAM     | Disk  |
| --------------- | --------------------------- | ------------ | ------- | ----- |
| `fedora-cloud`  | Fedora 43 Cloud Base qcow2  | `fedora`     | 2 GiB   | 10 G  |
| `kinoite`       | OCI image → bootc-image-builder → qcow2 | `core` | 4 GiB | 20 G |

Defaults live in `vm/targets/<name>.env` and can be overridden per-VM via
`--cpus / --mem / --disk` flags on `vm create`.

## One-time host setup

```bash
./vm/setup.sh
```

This layers the libvirt + qemu + virt-install stack via `rpm-ostree` and
enables the user `libvirtd.socket`. If `rpm-ostree` stages a new deployment,
**reboot before any `vm` subcommand**.

For `qemu:///system` (privileged) instead of the default `qemu:///session`
(rootless), opt in:

```bash
USE_LIBVIRT_GROUP=1 ./vm/setup.sh
```

## One-time per target: pin upstream digests

`vm/targets/*.env` ships with **empty `IMAGE_SHA256` / `OCI_DIGEST`** by
design — the scripts fail loudly until you pin a value, so you never
accidentally use an unverified image.

**Fedora cloud** (do this once per Fedora point release):

```bash
curl -fsSL https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-43-x86_64-CHECKSUM \
  | grep -E '^SHA256.*Fedora-Cloud-Base.*x86_64\.qcow2'
# paste the digest into IMAGE_SHA256 in vm/targets/fedora-cloud.env
```

**Kinoite** (do this once per OCI image bump):

```bash
podman pull quay.io/fedora-ostree-desktops/kinoite:43
podman inspect --format '{{.Digest}}' quay.io/fedora-ostree-desktops/kinoite:43
# paste the sha256:... into OCI_DIGEST in vm/targets/kinoite.env
```

## Quickstart — `fedora-cloud`

```bash
./vm/scripts/vm create --target fedora-cloud --name try1
./vm/scripts/vm ssh    try1 -- 'cat /etc/os-release; uname -r'
./vm/scripts/vm snapshot try1 clean
./vm/scripts/vm ssh    try1 -- 'sudo dnf install -y htop'
./vm/scripts/vm reset  try1 clean
./vm/scripts/vm ssh    try1 -- 'rpm -q htop || echo reverted-ok'
./vm/scripts/vm destroy try1
```

## Quickstart — `kinoite` (slow path, opt-in)

```bash
./vm/scripts/vm build-kinoite                        # 10–20 min, cached
./vm/scripts/vm create --target kinoite --name k1
./vm/scripts/vm ssh    k1 -- 'rpm-ostree status'
./vm/scripts/vm destroy k1
```

## CLI surface

```text
vm create   --target {fedora-cloud|kinoite} --name <n>
            [--cpus N] [--mem MIB] [--disk GIB]
            [--overlay <name>] [--with-cockpit]
vm start    <name>
vm stop     <name>             graceful shutdown (force after 30 s)
vm destroy  <name>             undefine + remove overlay disk + seed
vm ssh      <name> [-- cmd]    open ssh, or run a one-off remote cmd
vm snapshot <name> <snap>
vm reset    <name> <snap>      revert to snapshot
vm list                        tidy table from virsh list --all
vm status   <name>             state, IP, snapshots, disk path
vm prune    [--apply]          remove orphan disks/seeds/locks (dry-run default)
vm build-kinoite               run the bib pipeline (slow, opt-in)
```

`--with-cockpit` adds the cockpit web UI on port 9090. For `fedora-cloud` it
applies a cloud-init overlay (packages + `cockpit.socket` + firewalld);
for `kinoite` it switches the bib config to `kinoite-cockpit.toml` so cockpit
ships in the qcow2.

Every state-changing subcommand runs a fast preflight (env-only, no fork)
on each invocation. Override with `VM_PREFLIGHT={fast|full|none}`.

## Storage layout

All persistent state lives outside the repo, per XDG:

| What        | Path                                              |
| ----------- | ------------------------------------------------- |
| Base images | `${XDG_CACHE_HOME:-~/.cache}/scripts-vm/images/`  |
| Overlay disks | `${XDG_STATE_HOME:-~/.local/state}/scripts-vm/disks/` |
| Cloud-init seeds | `${XDG_STATE_HOME}/scripts-vm/seeds/<vm-name>/` |
| Per-VM metadata sidecar | `${XDG_STATE_HOME}/scripts-vm/seeds/<vm-name>/.metadata` |

`vm destroy <name>` removes the overlay disk and seed dir for that VM
(verified by the smoke test). Base images stay cached until you delete
them explicitly or set `REBUILD=1`.

## Env overrides

Honored everywhere:

| Var                     | Default                          | Effect                                                                          |
| ----------------------- | -------------------------------- | ------------------------------------------------------------------------------- |
| `LIBVIRT_DEFAULT_URI`   | `qemu:///session`                | libvirt connection URI                                                          |
| `XDG_CACHE_HOME`        | `~/.cache`                       | image cache root                                                                |
| `XDG_STATE_HOME`        | `~/.local/state`                 | disks + seeds root                                                              |
| `VM_SSH_PUBKEY`         | unset (per-VM ephemeral keys)    | opt-in: inject this host pubkey instead of generating per-VM keys              |
| `REBUILD=1`             | unset                            | force re-download / bib rebuild                                                 |
| `TRACE=1`               | unset                            | bash xtrace                                                                     |
| `NO_COLOR=1`            | unset                            | suppress ANSI colors in log/warn/error                                          |
| `USE_LIBVIRT_GROUP=1`   | unset (only consumed by setup.sh)| add user to `libvirt` group for `qemu:///system`                                |
| `VM_PREFLIGHT`          | `fast`                           | dispatcher preflight mode: `fast` (env-only), `full`, `none`                    |
| `VM_EXPECTED_FEDORA`    | `43`                             | expected `VERSION_ID` allowlist (whitespace-separated; e.g. `"43 44"`)          |
| `VM_E2E_KINOITE`        | unset                            | opt-in: run the kinoite ShellSpec lane (10–25 min)                              |
| `VM_E2E_COCKPIT`        | unset                            | opt-in: run the cockpit ShellSpec lane (~150 MB extra packages)                 |
| `BIB_ROOTFS`            | unset                            | bib `--rootfs <type>` (e.g. `btrfs`, `xfs`); required for Fedora bootc bases (R-017) |

## Smoke test

`vm/tests/smoke.sh` is a thin wrapper around [ShellSpec](https://shellspec.info/)
running the suites under `vm/spec/`. The default lane (~5 min on a warm
cache) covers specs 00–40 on `fedora-cloud`: preflight, create, cloud-init
readiness, internet, ssh + sudo, snapshot. Specs 60/65/70/80
(destroy-residue, prune, idempotency, parallel-safety) are exercised
**standalone** because the suite hits a cosmetic ShellSpec abort after
spec 40 (R-016 in `DEPLOYMENT.md`); the wrapper handles the abort by
exiting 0 when failures + errors are both zero. Cockpit (50) and kinoite
(90) lanes are opt-in via `VM_E2E_COCKPIT=1` / `VM_E2E_KINOITE=1`.

```bash
./vm/tests/smoke.sh                                # default lane
VM_E2E_KINOITE=1 ./vm/tests/smoke.sh               # include kinoite (slow)
./vm/tests/smoke.sh spec/40_snapshot_reset_spec.sh  # single spec
./vm/tests/smoke.sh --format tap                   # TAP output for CI
```

Install ShellSpec on the host (`rpm-ostree install shellspec` on Fedora,
or vendor under `vm/.shellspec-vendor/` per <https://shellspec.info/>).

## Optional: vm/Containerfile

Extends the main `scripts-toolbox` image with `libvirt-client`,
`virt-install`, `genisoimage`, and a `podman` client (for the bib
pipeline via `flatpak-spawn --host`). Build and use:

```bash
podman build -t localhost/scripts-vm-toolbox:fedora-43 -f vm/Containerfile vm/
toolbox create --image localhost/scripts-vm-toolbox:fedora-43 --container scripts-vm
toolbox enter scripts-vm
```

The libvirt **daemon** still runs on the host (see `vm/setup.sh`) — the
toolbox just ships clients that talk to it over the bind-mounted
`qemu:///session` socket.

## Out of scope (deliberately)

- No Vagrant / Packer / Ansible / Molecule / Terraform / Bats.
- No multi-distro matrix (Debian, Ubuntu, RHEL clones) — Fedora 43 only.
- No aarch64 — x86_64 only.
- No SPICE / virt-viewer wiring — `--graphics none` everywhere.
- No custom libvirt networks — default NAT bridge only.
- No nested virt, PCI passthrough, SR-IOV.
- No CI integration — local-only tool; nested KVM in GitHub runners is
  unreliable.
