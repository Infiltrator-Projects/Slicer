# Repository-owned dependency sources

This directory contains the 28 pinned source archives used by Slicer's dependency project and the pinned WebView2 SDK used by wxWidgets on Windows. A complete Git checkout contains these files directly. No Git LFS, submodules, release-asset fetch, or upstream download is needed to obtain these dependency sources during a build.

The original compressed archives are retained byte for byte. Their existing SHA-256 pins remain authoritative. Boost, CGAL, and OCCT archives are split into ordered 40 MiB parts so every Git blob stays below GitHub's file-size limit. CMake reassembles those parts inside the build directory, verifies the original archive hash, and extracts them locally. Missing or corrupt sources stop the build with a local error; there is no network fallback.

`manifest.cmake` records each archive's original URL, filename, SHA-256, and ordered stored parts. URLs are provenance information. The build passes local paths to CMake's external-project machinery. CMake may still label its local verification/extraction step as a "download" step; that step makes no remote request.

Windows GMP and MPFR headers/libraries already supplied under `deps/+GMP` and `deps/+MPFR` continue to be used. The bundled WebView2 SDK is extracted locally and passed to wxWidgets, covering its otherwise nested NuGet download. The hosted Windows build image supplies Python for z3 code generation.

## Verify the checkout

Run from the repository root:

```sh
python3 support/verify-vendor.py
cmake -S deps -B build/deps -DDEP_WX_GTK3=ON -DCMAKE_BUILD_TYPE=Release
```

The checksum verifier reads all bundled parts without network access. Verify CI runs it before either platform build. CMake 3.18.5 or later is required; this version includes binary-safe `cmake -E cat` on Windows.

Compilers, operating-system development packages, packaging tools, GitHub checkout, and GitHub Actions remain normal build prerequisites. This bundle removes dependency **source-server** requests; it does not bundle an operating system or compiler toolchain.

## Updating a dependency

Obtain the reviewed upstream archive once, retain its license and copyright files, and verify its intended hash. Add the complete archive here, or split it byte for byte into numbered 40 MiB parts. Update both its dependency definition's SHA-256 pin and its manifest entry in the same change. For WebView2, update the SDK pin in `deps/+wxWidgets/wxWidgets.cmake` as well. Run the checksum verifier, configure from a clean build directory, and validate local extraction and the affected build before publishing the change.

See [LICENSES.md](LICENSES.md) for notice locations inside the original archives.
