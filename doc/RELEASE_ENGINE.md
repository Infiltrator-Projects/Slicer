# Slicer release engineering

Slicer owns its build and release machinery in this repository.

## Release contract

A successful `Verify` workflow is the sole producer and qualifier of release
binaries. It creates exactly two distributable assets:

- `slicer-<version>-windows.exe` — Windows x64 installer.
- `infiltrator-slicer_<version>_amd64.deb` — Debian/Ubuntu amd64 package.

GitHub supplies the source `.zip` and `.tar.gz` automatically from the release
tag, so source archives are deliberately not rebuilt or uploaded as release
assets.

The `Publish release` workflow consumes only the sealed artifacts from the
exact successful `Verify` run. It never rebuilds them. Before publication it
checks the recorded source commit, version, SHA-256 hashes, package identity
and Windows executable signature. A release is created as a draft, the remote
asset bytes are compared with the sealed candidates, and only then is it made
public.

`support/VERSION` is the release authority. It must match `SLIC3R_VERSION` in
`version.inc`. Once a version has been published, changes outside the workflow
files require the version to advance before another release can qualify.

## Why the upstream workflows were removed

The PrusaSlicer 2.9.6 baseline delegated most GitHub Actions work to
`Prusa-Development/PrusaSlicer-Actions`. That made the imported repository
dependent on another project's branch, permissions, workflow interfaces and
release assumptions. Those inherited workflows also attempted macOS and
Flatpak jobs that are not part of Slicer's release contract.

Slicer instead keeps two local workflows:

- `.github/workflows/ci.yml` — verify, build, test and seal exact candidates.
- `.github/workflows/release.yml` — publish the already-qualified bytes.

There is one authority for building release artifacts and one authority for
publishing them.

## Linux native builds

`support/build-native.sh` is intentionally separate from the portable release
build. Hardware-specific binaries are excellent for a machine owner and wrong
for a generally distributed `.deb`.

Examples:

```sh
support/build-native.sh --profile native
support/build-native.sh --profile aggressive
```

`native` uses `-O2` and compiler-probed host CPU tuning (`-march=native` and
`-mtune=native` on x86, or `-mcpu=native` where appropriate).

`aggressive` uses `-O3`, the same host tuning, and a two-pass GCC profile-guided
optimisation build. The first executable is instrumented and trained by the
project test suite plus representative model parsing. The final executable is
then rebuilt using the measured profile. Unsupported optimisation flags are
rejected rather than silently assumed.

The native script does not install packages or alter the host. Build
prerequisites remain an explicit system responsibility.

## Windows packaging

The Windows candidate is built with the repository's existing CMake/MSVC
machinery, then packaged by the repository-owned Inno Setup definition under
`support/windows/installer.iss`. The installer contains the generated
executables and DLLs plus the exact repository resources. Debug symbols and
build-only import libraries are excluded.

## Debian packaging

The Debian candidate is built from the repository's static dependency bundle
with FHS installation enabled. Runtime library dependencies are derived from
the actual built executable with `dpkg-shlibdeps`, then the staged tree is
packed as `infiltrator-slicer`.

The present upstream-derived executable/resource names still overlap
PrusaSlicer, so the transitional Debian package declares a conflict/replacement
relationship with `prusa-slicer`. That should be removed when Slicer's product
identity and installed paths are fully separated from the upstream names.
