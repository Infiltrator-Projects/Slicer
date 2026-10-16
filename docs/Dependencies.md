# Dependency boundaries

Slicer's qualified builds consume repository-owned, pinned dependency inputs. The authoritative source definitions are under [deps](DEPENDENCY_BUILD.md); the [vendor manifest](../support/deps/vendor/manifest.cmake) records archive names, hashes and stored parts.

## Source ownership

- [deps/vendor](../support/deps/vendor/README.md) contains compressed upstream source archives and the Windows WebView2 SDK. Builds verify and extract these inputs locally.
- [bundled_deps](../src/bundled_deps) contains libraries integrated directly into the source tree. Their local build definitions and notices remain with the component.
- [src](../src) contains the application, engine and implementation-specific integrations. A dependency's presence in the checkout does not make every optional platform integration part of the release contract.

## Build and runtime boundaries

The portable Linux build uses the pinned dependency bundle and derives the installed package's runtime dependencies from the actual staged executable with `dpkg-shlibdeps`. The package's metadata is authoritative; a historical list of distribution package names is not a substitute for inspecting the built artifact.

Windows packaging uses the configured Release dependency prefix, generated executables and DLLs, and repository resources. Match architecture, runtime and toolchain before reusing a dependency prefix.

Operating-system development packages, compilers and packaging tools are host prerequisites. They are separate from the bundled dependency source archives.

## Maintenance and evidence

Update the archive, its hash pin and manifest entry together. Preserve the component's source notices, verify local extraction, and qualify the affected build before publishing. [Vendor maintenance](../support/deps/vendor/README.md) defines the procedure; [Validation](VALIDATION.md) defines the evidence required for a product release.



