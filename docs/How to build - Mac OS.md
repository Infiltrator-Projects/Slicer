# macOS development notes

macOS is outside Slicer's current release qualification. The published assets are the Linux DEB, Windows installer and Linux native source installer described in [Release engineering](RELEASE_ENGINE.md). A successful local macOS build does not establish an installable, signed or release-qualified macOS product.

## Development prerequisites

Local development needs Xcode and its command-line tools, CMake, Git and the build tools required by the selected dependencies. The inherited build notes used Homebrew packages including `automake`, `gettext`, `libtool`, `texinfo`, `m4` and `zlib`. Validate the actual toolchain and dependency configuration rather than treating an old OS, SDK or CMake version as a current compatibility guarantee.

## Dependency and application builds

From a prepared checkout, a development build uses separate dependency and application directories:

```sh
cmake -S support/deps -B build/macos-deps -DCMAKE_BUILD_TYPE=Release
cmake --build build/macos-deps --parallel 4
cmake -S . -B build/macos \
  -DCMAKE_PREFIX_PATH="$PWD/build/macos-deps/destdir/usr/local" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build/macos --parallel 4
ctest --test-dir build/macos --output-on-failure
```

Keep the dependency prefix at its original absolute path. For an Xcode generator, configure a separate application build directory with `-G Xcode` and open its generated project. Generator, SDK and configuration changes require compatible dependency builds.

## SDK and test boundaries

`CMAKE_OSX_SYSROOT` selects an SDK and `CMAKE_OSX_DEPLOYMENT_TARGET` selects the deployment target. Use mutually compatible values for dependencies and the application; do not infer compatibility from an SDK number alone.

Debug assertions and the test harness establish different coverage from Release execution. Record the exact source revision, toolchain, SDK, architecture, configuration and test results. Follow [Validation](VALIDATION.md) before making a supported-platform claim.

## Troubleshooting

Check Xcode command-line tool selection, compiler discovery and the effective paths to `m4`, gettext and CMake. Reproduce configuration failures in a clean, separate build directory and record the first failing dependency or target.

Historical workarounds that pin an old CMake release or edit Xcode's SDK metadata are not current product requirements. Diagnose against the selected toolchain and pinned dependency sources.

