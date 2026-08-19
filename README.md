# Cortex releases

Signed release **artifacts** for the Cortex phone app. This repository holds
**only built, signed APKs** — no source code. Every source repository stays
private; this one is public so that any Cortex hub can fetch a prebuilt app
with no build tools and no repository access.

> This file is the README the integrator seeds into the public releases repo.
> It lives in `cortex-hub/docs/` so it is version-controlled with the code that
> produces and consumes these releases.

## What is in a release

Each GitHub release carries exactly two assets:

| Asset | What it is |
|---|---|
| `cortex.apk` | The signed release APK. |
| `cortex-release.json` | Build metadata, schema `cortex-app-release/v1`: `version_code`, `version_name`, `apk_asset`, `apk_sha256`. |

There is nothing else here — no keystores, no signing secrets, no source, no
personal data. A release is a pair of files and a version tag.

## How to install the app (no build tools)

On the machine running your Cortex hub:

```bash
cortex fetch-apk
```

That pulls the latest release from this repository, verifies the download
against the `apk_sha256` in `cortex-release.json`, **re-signs it with your
hub's own update key**, and serves it. Then, on an Android phone on the same
network as your hub, open the hub's pairing page and install from there.

No JDK, no Android SDK, no Gradle, and no access to any private repository is
required. `cortex build` remains available for anyone who wants to compile the
app locally instead.

## Trust: this repository is **not** a trust root

This is the load-bearing point, and it is deliberate.

- Your phone pinned **your hub's** update-signing key when you paired it. It
  installs a build **only** because your hub signed a statement about that
  build — and for no other reason.
- When your hub fetches an APK from here, it **re-hashes the bytes itself and
  re-signs them with its own pinned key** before serving them. The signature
  the phone verifies is your hub's, over a digest your hub computed, every
  time.
- The `apk_sha256` in `cortex-release.json` is an **integrity** check — it
  catches a truncated or corrupted download and fails loud before those bytes
  go anywhere. It is **not** an authenticity check: it arrives from the same
  place as the bytes, so on its own it authenticates nothing.

The consequence: **a malicious or compromised release cannot forge an
install.** The worst a bad release can do is fail your hub's own integrity
check and be refused before your phone ever sees it. A device trusts only the
hub it paired with — never this repository, and never GitHub.

## How releases are published

The owner's hub already builds and signs the app. Publishing to this repository
is one command, run against the hub's current served build:

```bash
cortex publish-release            # preview first with --dry-run
```

It reads the hub's served `cortex.apk` and its metadata, creates a GitHub
release here carrying the two assets above, and **refuses to republish a
version whose bytes changed** — a released `version_code` names one immutable
APK. To see exactly what it would do without creating anything, add
`--dry-run`.
