# Build Infiltrator Slicer on Linux

The qualified Linux release targets amd64 and uses the repository-owned dependency sources. The release build is portable; host-specific optimization is a separate developer option.

## Prerequisites

On the Ubuntu 24.04 build environment:

```sh
sudo apt update
sudo apt install --no-install-recommends \
  autoconf build-essential cmake dpkg-dev git python3 perl pkg-config \
  libdbus-1-dev libglu1-mesa-dev libgtk-3-dev libhidapi-dev \
  libwebkit2gtk-4.1-dev texinfo xauth xvfb
```

Other distributions may use different package names. Large C++ builds need sufficient memory; reduce `--jobs` if compilation exhausts it.

## Build the release package

```sh
git clone https://github.com/Infiltrator-Projects/Slicer.git
cd Slicer
python3 support/verify-vendor.py
support/linux/build-deb.sh --clean --jobs 4
```

The script builds the static dependency bundle and application, runs CTest, installs into a staging directory, derives runtime dependencies with `dpkg-shlibdeps`, and creates `dist/infiltrator-slicer_0.0.1_amd64.deb`. `support/VERSION` is authoritative and must match the product version in `version.inc`.

Install and exercise that exact package:

```sh
sudo apt install ./dist/infiltrator-slicer_0.0.1_amd64.deb
slicer --help
```

Dependency archives are pinned and stored under `deps/vendor`. Builds verify their hashes and do not fetch replacement dependency sources. Linux dependency installation prefixes contain build paths, so keep a dependency prefix in its original location.

## Native developer builds

```sh
support/build-native.sh --profile native --jobs 4
support/build-native.sh --profile aggressive --jobs 4
```

`native` probes CPU tuning flags. `aggressive` adds GCC profile-guided optimization and uses the test suite and model parsing for training. These binaries target the build machine and are not used for public DEB packages. The helper prints the executable's output path.

See [release engineering](RELEASE_ENGINE.md) for CI qualification and publication. Preserve legacy executable and profile identifiers when changing product branding; they can be compatibility interfaces.
