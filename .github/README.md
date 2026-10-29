<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Slicer

**Project copyright:** © 2000-2026 Shannon Smith  
**Release identity:** [`support/VERSION`](../support/VERSION)

[![Verify](https://github.com/Infiltrator-Projects/Slicer/actions/workflows/ci.yml/badge.svg)](https://github.com/Infiltrator-Projects/Slicer/actions/workflows/ci.yml)

Slicer is a native C++/wxWidgets desktop application for Linux and Windows. Its graphical workspace prepares 3D models for filament and resin printers, generates G-code or resin print layers, and previews the resulting toolpaths.

## Implementation

The slicing engine owns geometry, model transformation and toolpath generation. The desktop application owns model editing, settings and interaction. Product development retains existing model, printer-profile and file-format compatibility; the current ownership boundaries are documented in [Architecture](../docs/ARCHITECTURE.md).

## Capabilities

- Filament and resin slicing, with printer and material profiles.
- Model arrangement, transformation and repair.
- Supports, variable layer heights and multiple materials.
- G-code and toolpath preview.
- Linux and Windows desktop packages, plus a Linux installer that compiles for the local CPU.

## Build and test

Use the [Linux build instructions](../docs/How%20to%20build%20-%20Linux%20et%20al.md) or [Windows build instructions](../docs/How%20to%20build%20-%20Windows.md) for platform prerequisites and commands. From a prepared Linux development environment:

```bash
git clone https://github.com/Infiltrator-Projects/Slicer.git
cd Slicer
cmake -P support/verify-product.cmake
support/build-native.sh --profile native
```

The native build driver builds the application and runs its tests. Windows builds and installer packaging use `support/windows/build-release.ps1`. [Validation](../docs/VALIDATION.md) defines the fast source checks, regression discipline and evidence required for a release. The repository-owned `Verify` workflow qualifies the Linux package, Windows installer and native source installer.

## Releases

To publish, open [Release Slicer](https://github.com/Infiltrator-Projects/Slicer/actions/workflows/release-slicer.yml), click **Run workflow** on `main`, and leave the version blank for automatic numbering. Builds, tests and publication then run automatically. The workflow summary links to progress. See [Release engineering](../docs/RELEASE_ENGINE.md) for details and advanced recovery.

Development stays on `main`. `support/VERSION` is the sole release-intent source of truth. Releases are produced from the exact tested commit, and published tags and assets are immutable. The latest published release is the repository's GitHub [Latest release](https://github.com/Infiltrator-Projects/Slicer/releases/latest) rather than a second version value maintained in this document.

## Release assets

A published release contains three assets from the same tested source revision:

- `slicer_<version>_amd64.deb` — Debian/Ubuntu amd64 package.
- `slicer-<version>-windows.exe` — Windows x64 installer.
- `slicer-<version>-native-installer.run` — Linux amd64 installer that downloads the exact release source and compiles it locally.

Install the package for your platform and open **Slicer** from the application menu. Linux packages are also available through the [Infiltrator package repository](https://github.com/Infiltrator-Projects/Infiltrator-Repository). The small native `.run` downloads the exact release source and its pinned dependency archives, then compiles and installs on the target machine. It supports `native` and `aggressive` build profiles; its usage and installation options are documented in [Release engineering](../docs/RELEASE_ENGINE.md).

## Technical documentation

- [Engineering philosophy](../docs/PHILOSOPHY.md) — governing engineering and documentation standard.
- [Architecture](../docs/ARCHITECTURE.md) — durable software contracts.
- [Validation](../docs/VALIDATION.md) — compact verification entry point.
- [Release engineering](../docs/RELEASE_ENGINE.md) — builds, qualified assets and publication.
- [Contributing](CONTRIBUTING.md) — verification and repository discipline.
- [Security](SECURITY.md) — security boundaries and reporting.
- [Code of conduct](CODE_OF_CONDUCT.md) — conduct in project spaces.

## Licence and provenance

Shannon Smith-owned Slicer source, documentation and application artwork are licensed under [GPL-3.0-or-later](../LICENSE). Documented dependencies, first-party Common infrastructure and separately licensed assets retain their own identities and licences.

