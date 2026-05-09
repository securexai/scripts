# vm/ supply-chain pinning

How to keep the four `vm/` targets digest-pinned when upstream cuts a new
image. The default state of a freshly-cloned repo already has every
target's pin populated; you only re-pin when bumping to a new upstream.

## Why pinning matters

Targets ship with **populated** `IMAGE_SHA256` (Fedora Cloud) and
`OCI_DIGEST` (Kinoite) values. `vm create` reads them at provision time,
verifies the downloaded image's checksum against the pin, and refuses to
boot an image whose hash doesn't match. An empty pin fails closed: there
is no "use whatever upstream is publishing right now" mode.

The risk register entries that gate this surface live in
[`../vm/DEPLOYMENT.md`](../vm/DEPLOYMENT.md):

- R-001 — `IMAGE_SHA256` empty (closed; pin populated).
- R-002 — `OCI_DIGEST` empty (closed; pin populated).
- R-003 — `BIB_VERSION="latest"` (open; needs a code change in
  [`lib/bib.sh`](../vm/scripts/lib/bib.sh) to swap `:tag` for `@digest`).
- R-007 — Fedora `CHECKSUM` consumed without GPG verify (open).
- R-008 — Bootc OCI not cosign-verified (open; blocked on cosign v3).

## Current pins

Snapshot as of 2026-05-08.

| Target | File | Pin field | Value |
| --- | --- | --- | --- |
| `fedora-cloud` | [`../vm/targets/fedora-cloud.env`](../vm/targets/fedora-cloud.env) | `IMAGE_SHA256` | `846574c8a97cd2d8dc1f231062d73107cc85cbbbda56335e264a46e3a6c8ab2f` |
| `fedora-cloud-44` | [`../vm/targets/fedora-cloud-44.env`](../vm/targets/fedora-cloud-44.env) | `IMAGE_SHA256` | `28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f` |
| `kinoite` | [`../vm/targets/kinoite.env`](../vm/targets/kinoite.env) | `OCI_DIGEST` | `sha256:bb87e7842afaac3c92bb446faae725c1abf930faad5309c41645613120f0a49d` (local image ID for `localhost/scripts-vm-bootc:latest`) |
| `kinoite-44` | [`../vm/targets/kinoite-44.env`](../vm/targets/kinoite-44.env) | `OCI_DIGEST` | `sha256:63b3fce4e344409ffb197f47753e4a453d526b8661c5bb5c28270fdb547affe5` (local image ID for `localhost/scripts-vm-kinoite-44:latest`) |
| all kinoite-class | (same files) | `BIB_VERSION` | `latest` (R-003 open) |

The kinoite-class targets currently track **derived OCI** images built
locally — see the
[Kinoite (re-pin after Containerfile change)](#kinoite-re-pin-after-containerfile-change)
section below for why and how.

## Re-pin: fedora-cloud (Fedora N point release bump)

Run this once per Fedora point release (e.g., 43-1.6 → 43-1.7).

```bash
# 1. Update IMAGE_URL in vm/targets/fedora-cloud.env to point at the new
#    point-release filename, then fetch the signed CHECKSUM:
curl -fsSL https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-43-x86_64-CHECKSUM \
  | grep -E '^SHA256.*Fedora-Cloud-Base.*x86_64\.qcow2'

# Alternate: query getfedora.org's machine-readable index
curl -fsSL https://getfedora.org/releases.json \
  | jq -r '.[] | select(.version=="43" and .arch=="x86_64" and .subvariant=="Cloud_Base") | .sha256'

# 2. Paste the digest into IMAGE_SHA256 in vm/targets/fedora-cloud.env.
# 3. Stage IMAGE_URL + IMAGE_SHA256 together:
git add vm/targets/fedora-cloud.env
git commit -m "chore(vm): pin fedora-cloud to <version>"
```

The same procedure applies to `fedora-cloud-44.env`, swapping the URL and
the CHECKSUM file.

> [!IMPORTANT]
> Always update `IMAGE_URL` and `IMAGE_SHA256` in the same commit. A
> mismatched pair will fail at create-time with a checksum error rather
> than a useful diagnostic.

## Re-pin: kinoite (upstream OCI bump)

When upstream cuts a new
`quay.io/fedora-ostree-desktops/kinoite:43` image. You only do this if
you're switching the kinoite target *back* to upstream — the current pin
points at a locally-derived OCI (see next section).

```bash
# Inspect without pulling:
skopeo inspect docker://quay.io/fedora-ostree-desktops/kinoite:43 \
  | jq -r .Digest

# Or pull and read locally:
podman pull quay.io/fedora-ostree-desktops/kinoite:43
podman inspect --format '{{.Digest}}' quay.io/fedora-ostree-desktops/kinoite:43
```

Paste the resulting `sha256:...` into `OCI_DIGEST` in
`vm/targets/kinoite.env`, and update `OCI_REF` to the upstream ref.

## Kinoite (re-pin after Containerfile change)

The default `kinoite` target uses a derived OCI built from
[`../vm/Containerfile.bootc`](../vm/Containerfile.bootc) on
`centos-bootc:stream9` (the original `quay.io/fedora-ostree-desktops/kinoite:43`
ref hits R-017 — bib `latest` requires `--rootfs` against Fedora bootc
bases). After editing the Containerfile, rebuild and re-pin:

```bash
sudo podman build -t localhost/scripts-vm-bootc:latest \
  -f vm/Containerfile.bootc vm/

# Capture the local image ID and pin it
sudo podman inspect --format '{{.Id}}' localhost/scripts-vm-bootc:latest
# → paste the sha256:... into OCI_DIGEST in vm/targets/kinoite.env
```

The digest is the local image ID; cache-hit logic compares against this
so a rebuild invalidates correctly.

## Kinoite-44 (re-pin after Containerfile change)

The `kinoite-44` target works the same way: stock
`quay.io/fedora-ostree-desktops/kinoite:44` ships without cloud-init, so
[`../vm/Containerfile.kinoite-44`](../vm/Containerfile.kinoite-44) layers
it in. After editing:

```bash
sudo podman build -t localhost/scripts-vm-kinoite-44:latest \
  -f vm/Containerfile.kinoite-44 vm/

sudo podman inspect --format '{{.Id}}' localhost/scripts-vm-kinoite-44:latest
# → paste the sha256:... into OCI_DIGEST in vm/targets/kinoite-44.env

# Then bib the qcow (slow — 10–25 min, cached):
BIB_ROOTFUL=1 ./vm/scripts/vm build-kinoite --target kinoite-44
```

> [!NOTE]
> `kinoite-44.env` keeps `BIB_ROOTFS="btrfs"` set. Fedora bootc bases
> intentionally omit `DefaultRootFs` per upstream policy; without
> `--rootfs`, bib hard-fails with `missing required info: DefaultRootFs`.
> The btrfs choice matches the Fedora 44 Cloud Base default.

## Pending: BIB_VERSION

`BIB_VERSION="latest"` is set on every kinoite-class target. Quay's
bootc-image-builder repo no longer publishes the `latest-NNNN` snapshot
tags this repo originally tracked, so digest pinning needs a code change
in [`lib/bib.sh`](../vm/scripts/lib/bib.sh) to swap `:tag` for `@digest`.
Tracked as R-003; deferred.

If you fork this repo and want immediate pinning, the workaround is to
pull a specific digest, retag it locally, and point `BIB_VERSION` at the
local tag — but the lib will need a one-line change to accept that.

## Verification

After any pin change, confirm the new state:

```bash
# Every right-hand side should be non-empty.
grep -nE '^(IMAGE_SHA256|OCI_DIGEST|BIB_VERSION|BIB_ROOTFS)=' vm/targets/*.env
```

Expected output: a populated value on every `IMAGE_SHA256` and
`OCI_DIGEST` line, with `BIB_VERSION="latest"` showing as the only
known-open pin.

End-to-end smoke after a re-pin:

```bash
./vm/scripts/vm create --target <repinned-target> --name pin-check
./vm/scripts/vm ssh    pin-check -- 'cat /etc/os-release; uname -r'
./vm/scripts/vm destroy pin-check
```

A successful create proves the new digest matches what the script
downloaded or built.

## See also

- [`../README.md`](../README.md) — repo overview
- [`vm-cli-reference.md`](vm-cli-reference.md) — target table and env
  vars
- [`../SECURITY.md`](../SECURITY.md) — supply-chain pinning policy
- [`../vm/DEPLOYMENT.md`](../vm/DEPLOYMENT.md) — risk register entries
  R-001 / R-002 / R-003 / R-007 / R-008
