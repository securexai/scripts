# vm/ architecture

The "why" behind the dispatcher, the cloud-init seed flow, the bib
pipeline, and the invariants that keep the suite green. If you're looking
for what to type, see [`vm-cli-reference.md`](vm-cli-reference.md). If
you're looking for known footguns, see
[`vm-troubleshooting.md`](vm-troubleshooting.md).

## Overview

```text
vm/scripts/vm                       ← entry point; argv[1] = subcommand
  ├── lib/common.sh                 ← strict-mode preamble + log/die/EXIT_* + require_cmd
  ├── lib/paths.sh                  ← XDG dirs + LIBVIRT_URI default
  ├── lib/preflight.sh              ← OS/KVM/binary checks
  └── exec subcommands/<verb>.sh    ← one file per verb (create, destroy, prune, …)
       └── sources lib/* as needed (libvirt, cloudinit, bib, locks, images)
```

Subcommands are not functions inside the dispatcher — they are separate
scripts that the dispatcher `exec`s after preflight. Each subcommand
re-sources the libs it needs. Module-load is guarded by `[[ -n
"${_VM_LIB_X_LOADED:-}" ]] && return 0` so re-sourcing is a no-op.

The trade-off: `exec` replaces the dispatcher's process, which means
errors from a subcommand surface with the subcommand's own exit code and
ERR-trap path. That keeps the exit-code taxonomy clean — every failure
has a single owner.

## Module graph

Eight library modules under
[`../vm/scripts/lib/`](../vm/scripts/lib/):

| File | Responsibility |
| --- | --- |
| `common.sh` | Strict-mode preamble (gated under ShellSpec); `log` / `warn` / `error` / `die` / `die_with`; `require_cmd`; the `EXIT_*` taxonomy; ERR trap |
| `paths.sh` | XDG-derived paths (`IMAGE_CACHE_DIR`, `DISK_DIR`, `SEED_DIR`); `LIBVIRT_URI` default |
| `preflight.sh` | `preflight_fast` (env-only) and `preflight_full` (forks `virsh`, `virt-host-validate`, `osinfo-query`); checks Fedora ID, `/dev/kvm`, required binaries, libvirt reachability, toolbox bind-mount |
| `images.sh` | `ensure_image` — download + sha256-verify Fedora Cloud Base qcow2 to `IMAGE_CACHE_DIR` |
| `cloudinit.sh` | `render_seed` — envsubst over `cloudinit/base/*.tmpl`, optional textual overlay append, `genisoimage` to a NoCloud seed ISO |
| `bib.sh` | `build_kinoite_qcow` — drives bootc-image-builder; consumes target env (`OCI_REF`, `OCI_DIGEST`, `BIB_VERSION`, `BIB_CONFIG_REL`, `BIB_ROOTFS`); honors `BIB_ROOTFUL` |
| `libvirt.sh` | `vm_define`, `vm_destroy`, `vm_undefine`, `vm_snapshot`, `vm_revert`, `vm_list_defined_domains`, `vm_pool_path_of`, `vm_pool_drop`; `wait_for_ssh`, `ssh_to`, `vm_ssh_run`, `get_ipv4` |
| `locks.sh` | `vm_lock_acquire` / `vm_lock_try_acquire` / `vm_lock_release` / `vm_lock_release_and_unlink` — advisory `flock` on `${SEED_DIR}/<name>.lock` |

Subcommands source only what they need. For example, `start` only needs
`common.sh` and `paths.sh`; `create` pulls in all of them.

## Strict-mode and the ShellSpec gate

[`common.sh`](../vm/scripts/lib/common.sh) wraps the strict-mode preamble
in a `$SHELLSPEC_VERSION` guard:

```bash
if [[ -z "${SHELLSPEC_VERSION:-}" ]]; then
  set -o errexit -o nounset -o pipefail -o errtrace
  shopt -s inherit_errexit
fi
shopt -s nullglob
```

The reason is subtle: when `common.sh` is `Include`d into a spec, those
options apply to ShellSpec's own shell. Any non-zero subshell exit (an
expected `EXIT_USAGE` assertion, for example) then terminates ShellSpec's
executor pipeline and the suite stops emitting examples. Detection is via
`$SHELLSPEC_VERSION`, which the runner exports and child processes
inherit. The diagnostic ERR trap is gated the same way for the same
reason.

`nullglob` stays enabled in both contexts because the codebase relies on
empty-glob loops iterating zero times rather than producing the literal
glob string.

> [!WARNING]
> Do not remove the `$SHELLSPEC_VERSION` gate. R-016 in
> [`../vm/DEPLOYMENT.md`](../vm/DEPLOYMENT.md) tracks a separate ShellSpec
> reporter bug that already costs us spec coverage in the default lane;
> breaking strict-mode under tests would compound that.

## Cloud-init seed flow

Seeds are rendered by `lib/cloudinit.sh::render_seed`:

1. Read `cloudinit/base/{user-data,meta-data,network-config}.tmpl`.
2. Run each template through `envsubst` with the variables
   `$VM_NAME $SSH_PUBKEY $DEFAULT_USER $BUILD_DATE`.
3. If `--overlay <name>` was passed, append
   `cloudinit/overlays/<name>.yaml.tmpl` (also envsubst'd) to the rendered
   `user-data`.
4. Pack the three files into a NoCloud-compatible seed ISO via
   `genisoimage`, written to `${SEED_DIR}/<vm-name>/seed.iso`.

> [!IMPORTANT]
> Overlays are **textually appended**, not YAML-merged. PyYAML's loader
> picks the last occurrence of any duplicated top-level key. The base and
> the overlay must keep their top-level keys disjoint, or the overlay's
> key silently wipes the base's. The `_apply_overlay` helper documents
> this inline; preserve it.

The per-VM ephemeral ed25519 keypair is generated alongside the seed
under `${SEED_DIR}/<vm-name>/`. The public key is the value of
`$SSH_PUBKEY` at envsubst time. Setting `VM_SSH_PUBKEY` before
`vm create` overrides this with your host pubkey instead of generating a
fresh keypair.

## bib (bootc-image-builder) pipeline

[`bib.sh::build_kinoite_qcow`](../vm/scripts/lib/bib.sh) consumes a
target env file (`vm/targets/<name>.env`) plus a TOML manifest at
`vm/targets/<config>.toml`.

Required env vars in the target file:

- `OCI_REF` — the bootc image to build from. Must be bare
  `localhost/<name>:<tag>` or `registry/<name>:<tag>`. Transport prefixes
  (`containers-storage:`, `oci:`) are rejected at the top of the
  function.
- `OCI_DIGEST` — pinned image digest (or local image ID for
  `localhost/...` refs). Cache-hit logic compares against this so a
  rebuild of a derived OCI invalidates correctly.
- `BIB_VERSION` — bootc-image-builder release tag. Currently `latest`
  for all targets (R-003); pinning a digest needs a code change to swap
  `:tag` for `@digest`.
- `BIB_CONFIG_REL` — TOML manifest path relative to `vm/targets/`.
  `kinoite.toml` for the default user; `kinoite-cockpit.toml` for the
  cockpit lane.
- `BIB_ROOTFS` — optional. Required for Fedora bootc bases that omit
  `DefaultRootFs` from their image metadata; passed through as
  `--rootfs <type>`. The `kinoite-44` target sets this to `btrfs`.

Rootless `bootc-image-builder` cannot remount the parent namespace's
mounts (the rootless `--privileged` flag does not actually grant
`CAP_SYS_ADMIN` over the parent mounts). `BIB_ROOTFUL=1` falls back to
`sudo podman` and bind-mounts `/var/lib/containers/storage`. This is the
expected mode in this repo.

The output qcow2 is written to a per-target subdirectory of
`${IMAGE_CACHE_DIR}` so `kinoite` and `kinoite-44` can coexist without
clobbering each other.

## Toolbox bridge

The user's primary dev environment is the
[`scripts` toolbox container](../.toolbox/README.md); libvirt itself runs
on the host. The bridge:

- The libvirt **daemon** (`virtqemud` under the modular daemon split) runs
  on the host.
- The toolbox sees `/run/user/$UID/libvirt/virtqemud-sock` via toolbx's
  default user-runtime mount. `preflight_check_toolbox_socket` asserts the
  socket is reachable.
- bib needs **host** podman because it uses `--privileged`. `bib.sh`
  detects `/run/.containerenv` and prefers `flatpak-spawn --host podman`
  when running inside the toolbox.

The optional [`vm/Containerfile`](../vm/Containerfile) extends the base
toolbox image with `libvirt-client`, `virt-install`, `genisoimage`, and a
`podman` client for the bib pipeline. Build and use:

```bash
podman build -t localhost/scripts-vm-toolbox:fedora-43 -f vm/Containerfile vm/
toolbox create --image localhost/scripts-vm-toolbox:fedora-43 --container scripts-vm
toolbox enter scripts-vm
```

## Invariants

These are the load-bearing assumptions the codebase relies on. Preserve
them when editing.

- **Lock fd survives unlink.** `vm_lock_release_and_unlink` closes the fd
  *after* unlinking the file; the `flock` advisory hold persists for the
  lifetime of the fd, which keeps a concurrent destroyer from racing the
  unlink. See `lib/locks.sh`.
- **`shopt -s nullglob` is repo-wide.** Loops over `disks=( "${DISK_DIR}"/*.qcow2 )`
  iterate zero times when the directory is empty. Removing nullglob would
  iterate the literal glob.
- **Cloud-init base + overlay top-level keys must be disjoint** — see the
  seed flow section above.
- **`qemu:///session` is the default.** `qemu:///system` is opt-in via
  `USE_LIBVIRT_GROUP=1 ./vm/setup.sh`. The session URI has no `default`
  NAT network out of the box (R-013).
- **Per-VM ephemeral ed25519 keys.** Generated at create, wiped at
  destroy. The override is `VM_SSH_PUBKEY=<host pubkey>`, not editing the
  template.
- **Subcommand process model: `exec`.** The dispatcher does not call
  subcommands as functions; they replace its process. Every subcommand
  must therefore set its own strict-mode preamble (via `common.sh`).
- **`OCI_REF` shape: bare image:tag.** Transport prefixes are rejected up
  front so cache-key derivation stays unambiguous.
- **Storage-pool sweep is path-based.** `vm destroy` and `vm prune` only
  drop pools whose `<path>` is a direct child of `${SEED_DIR}/`. Pools
  outside that prefix are never touched, even if their name collides with
  a VM name.

## See also

- [`../README.md`](../README.md) — repo overview
- [`vm-cli-reference.md`](vm-cli-reference.md) — CLI surface
- [`vm-troubleshooting.md`](vm-troubleshooting.md) — known footguns and
  their fixes
- [`../vm/DEPLOYMENT.md`](../vm/DEPLOYMENT.md) — verification snapshot
  and full risk register (R-001 …)
- [`../CLAUDE.md`](../CLAUDE.md) — agent-specific guidance
