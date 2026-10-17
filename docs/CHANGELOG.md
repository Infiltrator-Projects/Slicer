# Changelog

## 0.0.7

- Make the Linux native `.run` installer automatically detect and install missing Debian-family host development prerequisites before compiling, without a separate prerequisite-install option.

## 0.0.4

- Standardise the repository under `.github`, `docs`, `src` and `support`, and update build, package, resource and test paths.
- Replace the embedded-source native installer with a small exact-release HTTPS downloader, retaining native tuning and aggressive two-pass GCC PGO.
- Read the product version from support/VERSION throughout CMake, Linux, Windows and native source packaging.
- Remove private regular-expression parsers for a duplicated CMake version literal.
- Establish maintained philosophy, architecture and validation entry points with explicit engine provenance and qualification scope.

Earlier product and inherited engine history remain in Git and the applicable upstream records.