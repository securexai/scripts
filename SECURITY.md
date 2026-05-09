# Security

## Scope

This repo is a personal Fedora 43 / 44 operator toolkit. The intentional
non-goals matter for security review:

- **Fedora only.** No Debian / Ubuntu / RHEL clones.
- **x86_64 only.** No aarch64.
- **Local-only.** No CI; nested KVM in GitHub runners is unreliable. All
  verification is run on a real Fedora host. The current verified state
  lives in [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md).
- **No nested virt, no PCI passthrough, no SR-IOV.**
- **No multi-distro or multi-arch matrix testing** in scope. If you fork
  for another distro, the supply-chain pins, preflight, and bib targets
  must all be revisited.

## Supply-chain pinning policy

Every external image must be digest-pinned before `vm create` will use it.

- `vm/targets/<name>.env` ships with a populated `IMAGE_SHA256` for the
  Fedora Cloud Base targets, and `OCI_DIGEST` for the kinoite-class
  targets. `vm create` fails fast on empty pins.
- `BIB_VERSION="latest"` is a known exception (R-003) — quay.io's
  bootc-image-builder repo no longer publishes the `latest-NNNN` snapshot
  tags this repo originally tracked. Pinning a digest needs a code change
  to swap `:tag` for `@digest` in
  [`vm/scripts/lib/bib.sh`](vm/scripts/lib/bib.sh); deferred.
- The full pinning runbook (per-target re-pin commands, current values,
  verification) is in
  [`docs/vm-supply-chain.md`](docs/vm-supply-chain.md).

## Threat model

**SSH and per-VM identity.** Every `vm create` generates a fresh ed25519
keypair under the seed dir; the public half is injected via cloud-init,
the private half is wiped on `vm destroy`. Cloud-init disables SSH password
auth, and spec `30_ssh_and_sudo_spec.sh` verifies `passwordauthentication
no` is the effective sshd setting. To reuse your host SSH key instead,
export `VM_SSH_PUBKEY` before `vm create`.

**libvirt connection URI.** Default is `qemu:///session` (rootless;
per-user). Privileged `qemu:///system` is opt-in via
`USE_LIBVIRT_GROUP=1 ./vm/setup.sh` plus a re-login. The session URI has no
`default` NAT network out of the box (R-013); the workaround is a one-time
`virsh -c qemu:///session net-define` of a bridge alias to the system
`virbr0`. See
[`docs/vm-troubleshooting.md`](docs/vm-troubleshooting.md).

**Cloud-init overlays.** [`vm/cloudinit/overlays/`](vm/cloudinit/overlays/)
holds optional YAML fragments that are textually appended to the base
`user-data`. A user-specific overlay containing secrets (API tokens,
private keys, passwords) MUST NOT be committed. Recommended pattern:
keep personal overlays out of the repo or under a local
`.gitignore`-only path. R-006 tracks formalizing this.

**Bootc / bib pipeline.** Rootless `bootc-image-builder` cannot remount
the parent namespace's mounts (R-018); `BIB_ROOTFUL=1` opts into rootful
`podman` and bind-mounts `/var/lib/containers/storage`. This requires
passwordless sudo on the host — make that an informed choice for your
environment.

## Reporting a vulnerability

Use the **Security** tab on the GitHub repo to file a private advisory:
<https://github.com/securexai/scripts/security/advisories/new>.

Do not open a public issue for security problems. The repo has no SLA,
but acknowledgements should be quick — this is a small surface.

## Provenance gaps (known)

These are tracked in the [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) risk
register. Listed here for visibility:

- **R-007 (medium).** The Fedora `CHECKSUM` file is consumed without GPG
  signature verification. Tier C1 work item: layer GPG verify on the
  checksum manifest.
- **R-008 (medium).** Bootc OCI references are digest-pinned but not
  cosign-verified. Tier C2 work item; blocked on cosign v3 / rpm-ostree
  compat (tracking
  [coreos/rpm-ostree#5509](https://github.com/coreos/rpm-ostree/issues/5509)).
- **R-010 (low).** No SBOM is emitted for the built kinoite qcow2.
  Tier C3 work item: `syft` over the cached qcow2 after build.
- **R-006 (low).** `cloudinit/overlays/` accepts user-specific YAML; the
  expectation that user-specific overlays live outside the tree is
  documented but not enforced.

The detailed entries (severity, mitigation, status) live in the risk
register section of [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md).

## See also

- [`README.md`](README.md) — repo overview
- [`docs/vm-supply-chain.md`](docs/vm-supply-chain.md) — pinning runbook
- [`vm/DEPLOYMENT.md`](vm/DEPLOYMENT.md) — risk register and verification
  snapshot
