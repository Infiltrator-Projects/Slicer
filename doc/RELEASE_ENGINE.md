# Infiltrator Slicer release engineering

Slicer owns its build and release machinery in this repository. Product releases start at **0.0.1**, independently of the upstream PrusaSlicer 2.9.6 engine baseline. Upstream profile and file-format compatibility versions remain separate from the product version.

## Release contract

A successful `Verify` workflow is the sole producer and qualifier of release
binaries and the local source installer. It creates exactly three distributable assets:

- `slicer-<version>-windows.exe` — Windows x64 installer.
- `infiltrator-slicer_<version>_amd64.deb` — Debian/Ubuntu amd64 package.
- `infiltrator-slicer-<version>-native-installer.run` — Linux amd64 source installer with native and aggressive CPU compilation modes.

GitHub supplies the source `.zip` and `.tar.gz` automatically from the release
tag. The `.run` separately embeds the exact Git source tree, including the pinned
dependency archives, because it must compile locally without third-party source
downloads. Its header verifies the embedded payload hash before extraction.

The `Publish release` workflow normally consumes the sealed artifacts from the
exact successful push-to-main `Verify` run. It never rebuilds them. Before publication it
checks the recorded source commit, version, SHA-256 hashes, package identity,
native installer identity and Windows PE executable header. The PE header check is not an Authenticode signing claim. A release is created as a draft, the remote
asset bytes are compared with the sealed candidates, and only then is it made
public.

`support/VERSION` is the release authority. CMake reads it directly through `version.inc`; package and installer helpers read the same file. Once a version has been published, changes outside the workflow
files require the version to advance before another release can qualify.

## Recover a failed sealing or publication job

If the source contract and all three asset qualification jobs succeeded but sealing failed, dispatch `Publish release` with `qualified_run_id` set to that original Verify run ID. Recovery checks that the run came from this repository's `ci.yml` push to `main`, validates the latest source/Linux/Windows/native installer job results, downloads the original three candidates, and seals those exact bytes. It does not rebuild them.

A newer main commit is accepted only if it is a descendant with changes confined to workflow files. The release tag must identify the original qualified product commit. Published bytes are compared with the qualified candidates before and after publication; existing public assets are never replaced.

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

`support/native/build-run.py` creates a deterministic self-extracting source
installer from a specified Git commit. The installer invokes
`support/build-native.sh` on the user's machine, stages the tested native build,
and creates a local Debian package. The portable public DEB remains a separate
build.

Examples:

```sh
support/build-native.sh --profile native
support/build-native.sh --profile aggressive
# Or use the downloaded self-contained installer:
bash infiltrator-slicer-<version>-native-installer.run --profile aggressive
```

`native` uses `-O2` and compiler-probed host CPU tuning (`-march=native` and
`-mtune=native` on x86, or `-mcpu=native` where appropriate).

`aggressive` uses `-O3`, the same host tuning, and a two-pass GCC profile-guided
optimisation build. The first executable is instrumented and trained by the
project test suite plus model parsing and G-code slicing. The final executable is
then rebuilt using the measured profile. Unsupported optimisation flags are
rejected rather than silently assumed.

The underlying native driver builds and optionally stages files without
installing system packages. The `.run` reports missing host development tools,
allows their APT installation with `--install-prerequisites`, and requests
administrative access only for that setup and the final local package install.
`--no-install` leaves the package on disk. Its build directory is persistent
because dependency tools can record absolute installation paths.

CI executes the exact generated `.run` in aggressive mode without installing
onto the persistent runner, runs the native application tests, validates the
resulting Debian metadata, menu entries, icons and help banner, and seals that
same `.run` alongside the portable DEB and Windows EXE. Installer fixtures also
exercise extraction, paths containing spaces and corrupt-payload rejection.

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

The desktop entry, product icons, metadata, and resource directory use Infiltrator identity. `slicer` is the canonical launcher. The retained `prusa-slicer` compatibility command overlaps the upstream package, so the Debian package declares a conflict/replacement relationship with `prusa-slicer`. Product versions and upstream profile compatibility versions must not be conflated.

Application updates use Infiltrator releases and the Infiltrator APT repository. The inherited PrusaSlicer application updater and startup usage-report prompt are disabled. Printer profile repositories and optional printer/service integrations remain compatibility features with their original provider names.

## Licence material

The inherited engine's AGPL text is retained in LICENSE-AGPL-3.0.txt. The separately maintained LICENSE.txt does not replace that provenance. CMake staging and the Windows installer include both files. The native source installer verifies the inherited licence file after extraction, and its fixture exercises the same filename.
