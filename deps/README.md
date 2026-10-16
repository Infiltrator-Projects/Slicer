# Slicer dependencies

This directory is the CMake project for Slicer's pinned dependency sources. Normal release builds use the repository-owned Linux and Windows helpers documented in [Release engineering](../doc/RELEASE_ENGINE.md).

## Source and build ownership

Each dependency has a definition in a directory prefixed with `+`. CMake's ExternalProject machinery verifies, extracts and builds the archives stored under [vendor](vendor/README.md). Source URLs record provenance; builds consume the local archives and have no upstream source-download fallback.

Run from the repository root to verify the archive inventory and prepare a standalone dependency build:

```sh
python3 support/verify-vendor.py
cmake -S deps -B build/deps -DDEP_WX_GTK3=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build/deps --parallel 4
```

The dependency project requires CMake 3.18.5 or newer. Generator and toolchain options belong to the selected build configuration. Keep the configured dependency prefix at its original absolute path because library configuration files can embed that location.

## Windows configurations

MSVC application and dependency builds must use compatible architectures, runtimes and configurations. Libraries whose C++ interfaces expose standard-library types must not mix Debug and Release runtimes.

`DEP_DEBUG` controls the additional Debug dependency pass on MSVC. Public Windows packaging uses the Release helper and its pinned toolchain and cache policy; it does not rely on an arbitrary developer dependency directory.

## Application integration

The root [CMake presets](../CMakePresets.json) describe development configurations. Use `cmake --list-presets` from the repository root to inspect them. Release helpers own the precise dependency and application arguments used for qualified packages.

See the [vendor maintenance procedure](vendor/README.md) for archive updates and [dependency boundaries](../doc/Dependencies.md) for the distinction between source inputs and operating-system runtime libraries.

