# vm/ CLI reference

Complete surface for the `vm/` dispatcher: all 11 subcommands, every flag,
every exit code, every environment variable, the four targets, and the
on-disk storage layout.

For background on **why** the dispatcher is shaped this way, see
[`vm-architecture.md`](vm-architecture.md). For task-shaped quickstarts,
see [`../vm/README.md`](../vm/README.md).

## Synopsis

```text
vm <subcommand> [args...]
```

Top-level help: `vm --help` or `vm help` prints the usage block listing
all subcommands and the env vars honored across the dispatcher.

## Subcommands

### `create`

Provision a fresh VM from a target. Pulls or builds the base image,
creates a copy-on-write overlay, renders the cloud-init seed ISO, defines
the domain via `virt-install`, then blocks until SSH is reachable and
cloud-init is ready.

```text
usage: vm create --target <name> --name <vm-name> [options]
       targets: fedora-cloud, fedora-cloud-44, kinoite, kinoite-44
                (any name matching fedora-cloud* or kinoite* with a matching
                 vm/targets/<name>.env is recognized)
  --persistent     accepted for forward compat (no-op — all VMs persist
                   until 'vm destroy' is called)
  --cpus N         override target default
  --mem MIB        override target default
  --disk GIB       override target default (overlay capacity)
  --overlay <n>    cloudinit overlay file (cloudinit/overlays/<n>.yaml.tmpl)
  --with-cockpit   install + enable cockpit on :9090 (combines an
                   overlay for fedora-cloud with kinoite-cockpit.toml
                   for the kinoite target)
```

`--overlay` and `--with-cockpit` are mutually exclusive. `--with-cockpit`
on a fedora-cloud target applies the `cockpit` overlay; on a kinoite
target it switches the bib config to `kinoite-cockpit.toml`.

Exit codes: `64` (usage), `69` (preflight / missing binary), `70`
(libvirt — including "domain already exists"), `71` (outbound network
probe failed), `72` (cloud-init reported a fatal error).

### `start`

Start a defined-but-stopped domain. No-op if the domain is already
running; warns and attempts start anyway on unexpected states.

```text
usage: vm start <name>
```

Exit codes: `1` if the domain does not exist.

### `stop`

Graceful shutdown with a 30-second timeout, then force-destroy. The
domain stays defined (use `destroy` for full teardown).

```text
usage: vm stop <name>
```

### `destroy`

Graceful shutdown, undefine the domain, remove the overlay disk, the
cloud-init seed dir, and any auto-defined storage pool whose path points
into `${SEED_DIR}/<name>`. Idempotent.

```text
usage: vm destroy <name>
```

Exit codes: `64` (usage).

### `ssh`

Open an interactive SSH session, or run a one-off remote command. Reads
`DEFAULT_USER` from the per-VM metadata sidecar so the right user
(`fedora` for Fedora Cloud, `core` for Kinoite) is used automatically.

```text
usage: vm ssh <name> [-- <cmd...>]
```

A literal `--` between the VM name and the remote command is accepted and
stripped — useful when the remote command starts with a dash.

### `snapshot`

Create an internal qcow2 snapshot.

```text
usage: vm snapshot <name> <snap-name>
```

### `reset`

Revert the domain to a previously-created snapshot.

```text
usage: vm reset <name> <snap-name>
```

### `list`

Print a tidy table of all defined domains: name, state, target (from
metadata sidecar when present), and overlay disk path.

```text
vm list
```

Output format:

```text
NAME                STATE        TARGET         DISK
try1                running      fedora-cloud   /home/.../scripts-vm/disks/try1.qcow2
```

### `status`

Print state, IPv4, target, default user, OS variant, overlay disk path,
seed dir, and the snapshot list for one domain.

```text
usage: vm status <name>
```

Exit codes: `1` if the domain does not exist.

### `prune`

Remove orphan overlay disks, seed dirs, stale lockfiles, and leaked
storage pools whose path lives under `${SEED_DIR}/`. Live domains and
held lockfiles are always skipped. Dry-run by default.

```text
usage: vm prune [--apply] [--quiet]
  (default)   dry-run: list orphan artifacts, do not remove
  --apply     remove orphan overlay disks, seed dirs, and stale lockfiles
  --quiet     suppress per-item output (still prints the summary)
```

Exit codes: `64` (usage).

The base image cache (`${IMAGE_CACHE_DIR}`) is intentionally never
touched — those files back live overlay disks via qcow2 backing chains.

### `build-kinoite`

Run the bootc-image-builder pipeline ahead of `vm create --target
kinoite*`. Slow (10–25 min on first run; cached afterwards unless
`REBUILD=1` is set).

```text
usage: vm build-kinoite [--target <name>]
  --target  bib target (default: kinoite); points at vm/targets/<name>.env
            and must be a kinoite-class target (sets OCI_REF/OCI_DIGEST/
            BIB_VERSION/BIB_CONFIG_REL/BIB_ROOTFS).
```

Exit codes: `64` (usage / unknown target), `69` (preflight).

Rootless `bootc-image-builder` cannot remount the parent namespace's
mounts. Set `BIB_ROOTFUL=1` to fall back to rootful `podman` (requires
passwordless sudo).

## Targets

Defaults live in [`../vm/targets/<name>.env`](../vm/targets/). Override
per-VM with `--cpus`, `--mem`, and `--disk` on `vm create`.

| Target | Image source | Default user | RAM | Disk | OS_VARIANT | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `fedora-cloud` | Fedora 43 Cloud Base 43-1.6 (qcow2) | `fedora` | 2 GiB | 10 G | `fedora43` | — |
| `fedora-cloud-44` | Fedora 44 Cloud Base 44-1.7 (qcow2) | `fedora` | 2 GiB | 10 G | `fedora-unknown` | osinfo-db lacks `fedora44` short-id (R-019) |
| `kinoite` | Derived OCI ([`Containerfile.bootc`](../vm/Containerfile.bootc)) + bib | `core` | 4 GiB | 20 G | `fedora43` | Slow first build via `vm build-kinoite` |
| `kinoite-44` | Derived OCI ([`Containerfile.kinoite-44`](../vm/Containerfile.kinoite-44)) + bib | `core` | 4 GiB | 20 G | `fedora-unknown` | Requires `BIB_ROOTFS=btrfs` (set in env file); R-019 |

The per-target pinned digests and the re-pin runbook are in
[`vm-supply-chain.md`](vm-supply-chain.md).

## Cloud-init overlays

`vm create --overlay <name>` applies
[`../vm/cloudinit/overlays/<name>.yaml.tmpl`](../vm/cloudinit/overlays/) on
top of the base seed. Currently shipped:

| Overlay | Purpose |
| --- | --- |
| `cockpit` | Install the cockpit web UI; enable `cockpit.socket`; open the firewalld service. Implicitly applied by `--with-cockpit` on fedora-cloud targets. |

> [!IMPORTANT]
> Overlays are textually appended to the base `user-data`, not YAML-merged.
> PyYAML's loader picks the last occurrence of any duplicated top-level
> key. Keep overlay top-level keys disjoint from the base.

## Exit codes

Defined in
[`../vm/scripts/lib/common.sh`](../vm/scripts/lib/common.sh). Sysexits-flavored;
`71`–`72` are local extensions (sysexits.h has no slot for "network
failure" or "guest cloud-init failure").

| Code | Constant | Meaning | Typical recovery |
| --- | --- | --- | --- |
| `0` | `EXIT_OK` | Success | — |
| `1` | `EXIT_GENERIC` | Catch-all error | Read the log line above the exit |
| `64` | `EXIT_USAGE` | Bad CLI args, missing required flag | Re-read `vm <subcmd> --help` |
| `69` | `EXIT_PREREQ` | Missing host capability or binary | Run `./vm/setup.sh`; re-check Fedora 43/44 + KVM |
| `70` | `EXIT_LIBVIRT` | libvirt error (domain conflict, undefine failure) | `virsh list --all`; `vm destroy <name>` to clear |
| `71` | `EXIT_NET` | Outbound network probe failed | Check libvirt default NAT, host firewall, DNS |
| `72` | `EXIT_CLOUDINIT` | cloud-init reported a fatal error on the guest | `vm ssh <name> -- sudo cloud-init status --long` |

## Environment variables

Honored by every state-changing subcommand. Read-only subcommands (`list`,
`status`) skip even the fast preflight.

| Variable | Default | Effect |
| --- | --- | --- |
| `LIBVIRT_DEFAULT_URI` | `qemu:///session` | libvirt connection URI |
| `XDG_CACHE_HOME` | `~/.cache` | Image cache root |
| `XDG_STATE_HOME` | `~/.local/state` | Disks + seeds root |
| `VM_SSH_PUBKEY` | unset | Inject this host pubkey instead of generating per-VM ephemeral ed25519 |
| `REBUILD` | `0` | Force re-download / rebuild (image cache, kinoite qcow2) |
| `TRACE` | `0` | Enable bash xtrace |
| `NO_COLOR` | unset | Suppress ANSI colors in `info`/`warn`/`error` |
| `USE_LIBVIRT_GROUP` | unset | Consumed by `setup.sh`; opt in to `qemu:///system` group |
| `VM_PREFLIGHT` | `fast` | Dispatcher preflight mode: `fast` (env-only), `full` (fork checks), `none` (debug only) |
| `VM_EXPECTED_FEDORA` | `"43 44"` | Whitespace-separated allowlist of Fedora `VERSION_ID` values the host may report |
| `VM_E2E_KINOITE` | unset | Opt-in: include the kinoite ShellSpec lane |
| `VM_E2E_COCKPIT` | unset | Opt-in: include the cockpit ShellSpec lane |
| `BIB_ROOTFUL` | `0` | Run bootc-image-builder via `sudo podman`; required for rootless hosts |
| `BIB_ROOTFS` | (per-target) | Pass through to bib `--rootfs <type>`; required for Fedora bootc bases (R-017) |

## Storage layout

All persistent state lives outside the repo, per the XDG Base Directory
spec:

| What | Path |
| --- | --- |
| Base image cache | `${XDG_CACHE_HOME:-~/.cache}/scripts-vm/images/` |
| Per-VM overlay disks | `${XDG_STATE_HOME:-~/.local/state}/scripts-vm/disks/<name>.qcow2` |
| Per-VM cloud-init seeds | `${XDG_STATE_HOME}/scripts-vm/seeds/<name>/` |
| Per-VM metadata sidecar | `${XDG_STATE_HOME}/scripts-vm/seeds/<name>/.metadata` |
| Per-VM advisory lockfile | `${XDG_STATE_HOME}/scripts-vm/seeds/<name>.lock` |

`vm destroy <name>` removes the overlay disk, the seed dir, the lockfile,
and any auto-defined libvirt storage pool that maps to
`${SEED_DIR}/<name>`. The image cache stays intact unless you delete it
explicitly or set `REBUILD=1` on a future create.

## See also

- [`../README.md`](../README.md) — repo overview
- [`../vm/README.md`](../vm/README.md) — task-shaped user guide
- [`vm-architecture.md`](vm-architecture.md) — design rationale and
  invariants
- [`vm-supply-chain.md`](vm-supply-chain.md) — digest pinning runbook
- [`vm-troubleshooting.md`](vm-troubleshooting.md) — known footguns
