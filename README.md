<p align="center"><img src="resources/icons/InfiltratorSlicer.svg" width="112" alt="Infiltrator Slicer"></p>

# Infiltrator Slicer

Slicer is Infiltrator Projects' desktop application for preparing 3D models for FFF and resin printers. It converts models into G-code or resin print layers and includes a G-code viewer, multiple material support, model repair, variable layer heights, supports, and a command-line interface.

**Product version: 0.0.1.** Infiltrator's release numbering is independent of the PrusaSlicer 2.9.6 source baseline.

## Install

Download the qualified packages from [Infiltrator Slicer releases](https://github.com/Infiltrator-Projects/Slicer/releases):

- **Linux amd64:** `infiltrator-slicer_0.0.1_amd64.deb` for Debian/Ubuntu systems with the package's runtime dependencies.
- **Windows x64:** `slicer-0.0.1-windows.exe` installer.

For a downloaded Debian package:

```sh
sudo apt install ./infiltrator-slicer_0.0.1_amd64.deb
slicer --help
```

For APT installation and updates, configure the [Infiltrator package repository](https://github.com/Infiltrator-Projects/Infiltrator-Repository) using its installation instructions, then run:

```sh
sudo apt update
sudo apt install infiltrator-slicer
```

On Windows, run the installer and open **Slicer** from the Start menu. The installer includes the application, its DLLs, and resources.

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

The supported distributables are currently the Linux amd64 DEB and Windows x64 EXE. Inherited macOS and other platform development notes remain references, not a promise of qualified release packages.

## Origins and license

Infiltrator Slicer is developed from [PrusaSlicer](https://github.com/prusa3d/PrusaSlicer), which is based on [Slic3r](https://github.com/Slic3r/Slic3r) by Alessandro Ranellucci and the RepRap community. Original copyright notices, third-party licenses, and upstream development history are preserved.

The application is licensed under the [GNU Affero General Public License, version 3 or later](LICENSE). Third-party components retain their own licenses; see the source headers and [vendored dependency license inventory](deps/vendor/LICENSES.md).
