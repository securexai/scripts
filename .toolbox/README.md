# .toolbox/

Pinned Fedora-toolbox container for the `scripts` repo. The container is
the single source of truth for every tool the pre-commit hooks need —
upgrades happen by editing [`Containerfile`](Containerfile) and rebuilding,
not by drifting individual tool versions in `~/.local`.

## Quickstart

```bash
./.toolbox/setup.sh           # build image + create container, ~3 min
toolbox enter scripts          # land inside

# Verify the toolchain is reachable
which uv ruff betterleaks pnpm commitlint shellcheck markdownlint-cli2
```

The script is idempotent: if the image and container already exist, it
exits early. To force a rebuild after editing the `Containerfile`:

```bash
REBUILD=1 ./.toolbox/setup.sh
```

## What ships in the image

Base: `registry.fedoraproject.org/fedora-toolbox:43`. Both Fedora 43 and
Fedora 44 hosts work — toolbox containers don't need to track host
version.

System packages (via `dnf`, with `install_weak_deps=False` to drop
`nodejs-npm` / `nodejs-docs` / `nodejs-full-i18n`):

| Package | Why |
| --- | --- |
| `git` | Version control |
| `gh` | GitHub CLI; also git's credential helper when wired |
| `pre-commit` | Pre-commit framework |
| `nodejs` | Runtime only — pnpm is installed below as a static binary |
| `python3` | Pre-commit hook interpreter |
| `curl`, `ca-certificates` | Installer fetches |
| `jq` | JSON tooling |
| `ripgrep` | Fast grep |
| `libatomic` | Required by some node native modules |

Pinned tools (sha256-verified where the upstream publishes a checksum):

| Tool | Version | Source | Install path |
| --- | --- | --- | --- |
| `uv` | `0.11.8` | astral.sh installer | `/usr/local/bin/uv` |
| `ruff` | latest at build | `uv tool install` | `/opt/uv-tools` (binary on `PATH`) |
| `betterleaks` | `1.1.2` | GitHub release tarball, sha256-pinned | `/usr/local/bin/betterleaks` |
| `pnpm` | `11.0.3` | GitHub release tarball, sha256-pinned | `/opt/pnpm/pnpm` → `/usr/local/bin/pnpm` |
| `@commitlint/cli` | latest at build | `pnpm add -g` | `/usr/local/bin/commitlint` |
| `@commitlint/config-conventional` | latest at build | `pnpm add -g` | (config dependency) |

`uv tool install` and `pnpm add -g` use install-time-resolved versions; they
floats forward on each rebuild. The `uv`, `betterleaks`, and `pnpm`
versions are exact-pinned via `ARG` in the Containerfile.

The pnpm global store lives under `/opt/pnpm-global`; binaries land at
`/usr/local/bin` via `--global-bin-dir` so `$HOME` stays untouched.

> [!NOTE]
> The image is amd64-only. If you fork for Apple Silicon or arm64 Linux,
> add an arm64 branch to the `betterleaks` and `pnpm` install RUNs.

## Environment knobs

| Variable | Default | Purpose |
| --- | --- | --- |
| `REBUILD` | unset | Set to `1` to force `podman build` even if the image exists |
| `TRACE` | unset | Set to `1` for `bash -x` xtrace through `setup.sh` |
| `NO_COLOR` | unset | Set to suppress ANSI colors in `info`/`warn`/`error` |
| `BUILD_NETWORK` | `slirp4netns` | Podman build network backend. Default works around the F43 `passt-selinux` AVC; override to `pasta` once that policy ships upstream. |

`IMAGE_REF` and `CONTAINER_NAME` are constants in `setup.sh` rather than
overrideable env vars. If you need different names — e.g., to ship
parallel toolboxes from a fork — edit the script directly.

## Customization for forks

Common extension points:

- **Bump the base image.** The `FROM` line targets `fedora-toolbox:43`.
  Bump to `:44` if you want F44 stdlib versions inside the toolbox; both
  `:43` and `:44` are valid for an F43 or F44 host because the toolbox
  doesn't need to match host kernel.
- **Add tools via `dnf`** in the first `RUN` block. Keep
  `install_weak_deps=False` to avoid pulling in unneeded recommends.
- **Pin a new sha256-verified binary** by following the `betterleaks` or
  `pnpm` patterns. Always pin the `ARG <NAME>_VERSION` and `ARG
  <NAME>_SHA256` together so a missing checksum fails the build.

## Idempotency

[`setup.sh`](setup.sh) follows the standard Check → Action → Verify
pattern documented in [`CONTRIBUTING.md`](../CONTRIBUTING.md):

1. Check whether the image exists; build only if missing or `REBUILD=1`.
2. Check whether the container exists; create only if missing.
3. Verify with `podman image exists` and `podman container exists` after
   each step.

Re-running with no env overrides is a clean no-op.

## See also

- [`../README.md`](../README.md) — repo overview
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — pre-commit and conventional
  commit rules the toolbox enforces
- [`../vm/Containerfile`](../vm/Containerfile) — optional libvirt-tooling
  extension on top of this image (for the `vm/` subsystem when run from
  inside the toolbox)
