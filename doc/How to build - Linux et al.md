# Build Slicer on Linux

The qualified Linux release targets amd64 and uses the repository-owned dependency sources. The public package uses portable CPU settings; local CPU tuning belongs to the native build profiles.

## Prerequisites

The Ubuntu 24.04 build environment uses:

```sh
sudo apt update
sudo apt install --no-install-recommends \
  autoconf automake build-essential cmake dpkg-dev git python3 perl pkg-config \
  libdbus-1-dev libglu1-mesa-dev libgtk-3-dev libhidapi-dev \
  libwebkit2gtk-4.1-dev texinfo xauth xvfb
```

Other distributions may use different package names. Reduce `--jobs` if compilation exhausts available memory.

## Build the release package

```sh
git clone https://github.com/Infiltrator-Projects/Slicer.git
cd Slicer
python3 support/verify-vendor.py
support/linux/build-deb.sh --clean --jobs 4
```

The driver builds dependencies and the application, runs CTest, stages installation, derives runtime dependencies and writes the DEB under `dist`. [support/VERSION](../support/VERSION) is the sole product version source; CMake reads it through `version.inc`.

Install the exact package produced by that checkout:

```sh
version=$(tr -d '[:space:]' < support/VERSION)
sudo apt install "./dist/infiltrator-slicer_${version}_amd64.deb"
```

Open **Slicer** from the application menu. Build and test evidence applies to the exact source revision and package bytes.

## Native builds

From an existing checkout:

```sh
support/build-native.sh --profile native --jobs 4
support/build-native.sh --profile aggressive --jobs 4
```

`native` probes host CPU tuning flags. `aggressive` adds GCC profile-guided optimisation trained by the test suite, model parsing and slicing. These binaries target the build machine and are separate from the portable public DEB.

The downloaded native installer bundles the exact source and pinned archives. Replace `<version>` with the version in the downloaded asset's filename:

```sh
bash "infiltrator-slicer-<version>-native-installer.run" --profile native --jobs 4
```

The installer builds unprivileged, tests, packages the staged application and requests administrative access for final installation. It lists missing host development packages; `--install-prerequisites` explicitly permits their installation. Use `--no-install` to retain the DEB without installing it, `--dry-run` to inspect the plan, or `--extract-only DIR` to inspect the source.

Dependency prefixes can embed absolute paths. Keep a retained prefix in its original location. The release driver validates build-root ownership before cleanup; incompatible native compiler or optimisation settings require a separate build root or `--clean`.

[Release engineering](RELEASE_ENGINE.md) defines qualification and publication. [Validation](VALIDATION.md) defines the complete verification entry points.

