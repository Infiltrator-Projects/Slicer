<p align="center"><img src="resources/icons/InfiltratorSlicer.svg" width="112" alt="Infiltrator Slicer"></p>

# Infiltrator Slicer

Slicer is Infiltrator Projects' desktop application for preparing 3D models for FFF and resin printers. It converts models into G-code or resin print layers and includes a G-code viewer, multiple material support, model repair, variable layer heights, supports, and a command-line interface.

**Product version: 0.0.3.** Infiltrator's release numbering is independent of the PrusaSlicer 2.9.6 source baseline.

## Install

Download the qualified packages from [Infiltrator Slicer releases](https://github.com/Infiltrator-Projects/Slicer/releases):

- **Linux amd64:** `infiltrator-slicer_0.0.3_amd64.deb` for Debian/Ubuntu systems with the package's runtime dependencies.
- **Windows x64:** `slicer-0.0.3-windows.exe` installer.
- **Linux local CPU build:** `infiltrator-slicer-0.0.3-native-installer.run`, with the application and pinned dependency sources bundled inside.

For a downloaded Debian package:

```sh
sudo apt install ./infiltrator-slicer_0.0.3_amd64.deb
slicer --help
```

For APT installation and updates, configure the [Infiltrator package repository](https://github.com/Infiltrator-Projects/Infiltrator-Repository) using its installation instructions, then run:

```sh
sudo apt update
sudo apt install infiltrator-slicer
```

On Windows, run the installer and open **Slicer** from the Start menu. The installer includes the application, its DLLs, and resources.

For a Linux build optimised for your own CPU:

```sh
bash infiltrator-slicer-0.0.3-native-installer.run --profile native
# GCC two-pass profile-guided optimisation:
bash infiltrator-slicer-0.0.3-native-installer.run --profile aggressive
```

The `.run` builds and tests the application locally, creates a Debian package, and installs that package. Use `--no-install` to retain the package without installing it, or `--dry-run` to inspect the plan. Missing operating-system build tools are reported before compilation; `--install-prerequisites` explicitly allows installing them through APT. Library source archives are bundled and hash-checked, without downloads from third-party build servers.

## Use

Open a model, select a printer and material profile, arrange the plate, slice it, and export the resulting printer instructions. Check the selected profile against your printer before printing. Printer and material names describe compatible hardware; they are not the application's product identity.

Run `slicer --help` for available command-line actions. The help banner reports the product version; `--version` is not a supported option. Existing `prusa-slicer` executable names are retained where needed for compatibility.

Application releases come from this repository or Infiltrator APT. The inherited upstream application updater does not download PrusaSlicer over this product. Printer-profile updates remain a separate compatibility feature.

## Build and contribute

- [Linux release and native builds](doc/How%20to%20build%20-%20Linux%20et%20al.md)
- [Windows release installer](doc/How%20to%20build%20-%20Windows.md)
- [Release qualification and publication](doc/RELEASE_ENGINE.md)
- [Vendored dependency sources and verification](deps/vendor/README.md)
- [Report an issue](https://github.com/Infiltrator-Projects/Slicer/issues)

The supported distributables are the Linux amd64 DEB, Windows x64 EXE, and Linux amd64 native compiler `.run`. Inherited macOS and other platform development notes remain development references.

## Origins and license

Infiltrator Slicer uses the [PrusaSlicer](https://github.com/prusa3d/PrusaSlicer) engine, derived from [Slic3r](https://github.com/Slic3r/Slic3r). Copyright notices are available through **About → Portions copyright**, the source headers, and the dependency license inventory.

The application is licensed under the [GNU Affero General Public License, version 3 or later](LICENSE). Third-party components retain their own licenses; see the source headers and [vendored dependency license inventory](deps/vendor/LICENSES.md).

## Engineering contracts

[Philosophy](PHILOSOPHY.md) · [Architecture](doc/ARCHITECTURE.md) · [Validation](doc/VALIDATION.md) · [Release engineering](doc/RELEASE_ENGINE.md) · [Changes](CHANGELOG.md).

Product identity is authoritative in [support/VERSION](support/VERSION). The inherited engine's compatibility identity is separate.
