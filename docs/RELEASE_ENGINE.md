# Slicer release engineering

Slicer owns its build and release machinery in this repository. [support/VERSION](../support/VERSION) is the sole product release authority. Profile and file-format compatibility versions remain separate from the product version.

## Publish a release

Once your changes are on `main`:

1. Open [Release Slicer](https://github.com/Infiltrator-Projects/Slicer/actions/workflows/release-slicer.yml) in GitHub Actions.
2. Click **Run workflow**, keeping `main` selected.
3. Leave **Version** blank for automatic numbering, or enter a specific new version.
4. Click **Run workflow**. Follow the progress link in its summary.

No build-run numbers or asset uploads are needed. If the version in
`support/VERSION` is not tagged yet, it is used as-is. Otherwise the action selects
the next unused patch version and saves it on `main`. Existing tags are never changed.
The ordinary repository token supplied by GitHub performs this work; no additional
secret is required.

A suitable running build is reused. Successful builds with all unexpired release
files go directly to publication; missing, failed or expired builds cause fresh
checks for all platforms. The explicitly requested manual build publishes after
the checks and sealing pass, just like the existing automatic push-to-main flow.
Individual Linux-only or Windows-only verification runs do not publish.

If a request fails, rerun **Release Slicer** after resolving the reported error.
An already prepared, untagged version is retained, so retrying does not keep
incrementing versions or restarting a suitable running build. Published release
files remain immutable.

## Release contract

A successful `Verify` workflow is the sole producer and qualifier of release
binaries and the local source installer. It creates exactly three distributable assets:

- `slicer-<version>-windows.exe` — Windows x64 installer.
- `slicer_<version>_amd64.deb` — Debian/Ubuntu amd64 package.
- `slicer-<version>-native-installer.run` — Linux amd64 source installer with native and aggressive CPU compilation modes.

GitHub supplies the source `.zip` and `.tar.gz` automatically from the release
tag. The small `.run` downloads the archive for that exact release commit over HTTPS, including its pinned dependency archives, then compiles and installs on the target machine. It contains no embedded source archive. Vendor hashes are verified before compilation.

The `Advanced release publishing` workflow normally consumes the sealed artifacts from the
exact successful push-to-main or explicitly release-requested all-platform `Verify` run. It never rebuilds them. Before publication it
checks the recorded source commit, version, SHA-256 hashes, package identity,
native installer identity and Windows PE executable header. The PE header check is not an Authenticode signing claim. A release is created as a draft, the remote
asset bytes are compared with the sealed candidates, and only then is it made
public.

`support/VERSION` is the release authority. CMake reads it directly through `support/version.inc`; package and installer helpers read the same file. Once a version has been published, changes outside the workflow
files require the version to advance before another release can qualify.

## Advanced recovery

Use **Release Slicer** for normal publishing and retries. The underlying recovery
workflows remain available when a maintainer needs to select particular historical
builds or combine separate platform qualifications.

If the source contract and all three asset qualification jobs succeeded but sealing failed, dispatch `Advanced release publishing` with `qualified_run_id` set to that original Verify run ID. Recovery checks that the run came from this repository's `ci.yml` push to `main` or a manual verification, validates the latest source/Linux/Windows/native installer job results, downloads the original three candidates, and seals those exact bytes. It does not rebuild them.

A newer main commit is accepted only if it is a descendant with changes confined to workflow files. The release tag must identify the original qualified product commit. Published bytes are compared with the qualified candidates before and after publication; existing public assets are never replaced.

## Build and publication ownership

Slicer separates release preparation, verification and publication:

- `.github/workflows/release-slicer.yml` and `support/release.py` — select a version and coordinate the existing workflows.
- `.github/workflows/ci.yml` — verify, build, test and seal exact candidates.
- `.github/workflows/release.yml` — publish the already-qualified bytes.

There is one authority for building release artifacts and one authority for
publishing them.

## Linux native builds

`support/native/build-run.py` creates a small deterministic source downloader pinned to a specified Git commit. The installer invokes
`support/build-native.sh` on the user's machine, stages the tested native build,
and creates a local Debian package. The portable public DEB remains a separate
build.

Examples:

```sh
support/build-native.sh --profile native
support/build-native.sh --profile aggressive
# Or download the release source, compile and install:
bash slicer-<version>-native-installer.run --profile aggressive
```

`native` uses `-O2` and compiler-probed host CPU tuning (`-march=native` and
`-mtune=native` on x86, or `-mcpu=native` where appropriate).

`aggressive` uses `-O3`, the same host tuning, and a two-pass GCC profile-guided
optimisation build. The first executable is instrumented and trained by the
project test suite plus model parsing and G-code slicing. The final executable is
then rebuilt using the measured profile. Unsupported optimisation flags are
rejected rather than silently assumed.

The underlying native driver builds and optionally stages files without
installing system packages. The `.run` automatically detects missing Debian-family
host development prerequisites, requests administrative access only for APT,
installs only the missing packages, and then continues the regular-user build.
Administrative access is also requested for the final local package install.
`--no-install` leaves the package on disk. Its build directory is persistent
because dependency tools can record absolute installation paths.

CI executes the exact generated `.run` in aggressive mode without installing
onto the persistent runner, runs the native application tests, validates the
resulting Debian metadata, menu entries, icons and help banner, and seals that
same `.run` alongside the portable DEB and Windows EXE. Installer fixtures also
exercise automatic prerequisite installation, real archive extraction, exact
download URLs, failed/corrupt downloads, paths containing spaces and real ELF
package generation.

## Windows packaging

The Windows candidate is built with the repository's existing CMake/MSVC
machinery, then packaged by the repository-owned Inno Setup definition under
`support/windows/installer.iss`. The installer contains the generated
executables and DLLs plus the exact repository resources. Debug symbols and
build-only import libraries are excluded.

## Debian packaging

The Debian candidate is built from the repository's static dependency bundle
with FHS installation enabled. Runtime library dependencies are derived from the
actual built executable with `dpkg-shlibdeps`, then the staged tree is
packed as `slicer`.

The desktop entry, product icons, metadata, and resource directory use Infiltrator identity. `slicer` is the canonical launcher. The retained `prusa-slicer` compatibility command overlaps the upstream package, so the Debian package declares a conflict/replacement relationship with `prusa-slicer`. Product versions and upstream profile compatibility versions must not be conflated.

Application updates use Infiltrator releases and the Infiltrator APT repository. The inherited application updater and startup usage-report prompt are disabled. Printer profile repositories and optional printer/service integrations remain separate compatibility features.

## Licence material

CMake staging and the Windows installer include the root [LICENSE](../LICENSE). The native source installer retains that same file in the downloaded release source and verifies its presence after extraction. Source checks and installer fixtures use the same canonical filename.

Linux release build roots carry a source-owner marker. Cleanup refuses the source checkout, its ancestors and unrelated nonempty directories. Existing caches can be adopted only when their CMake source identity matches. This boundary applies before removing stage or build state.


The existing upstream licence inventory also retains the inherited engine's AGPL text. CMake staging and the Windows installer include that inventory alongside the canonical root LICENSE. Source archives retain it automatically. Dependency compiler-cache keys exclude maintained Markdown; package/source identity still covers the complete current Git tree.
