# Build Slicer on Windows

The qualified Windows installer targets x64. CI uses the hosted `windows-2022` image and Visual Studio 2022.

## Prerequisites

Install PowerShell 7, Git, CMake 3.18.5 or newer, Python 3, Visual Studio 2022 with the x64 C++ build tools and Windows SDK, and Inno Setup 6. Repository preflight checks the selected compiler and executable launch before the long build.

## Build the installer

Use a short checkout path, then run from PowerShell 7:

```powershell
git clone https://github.com/Infiltrator-Projects/Slicer.git C:\src\Slicer
Set-Location C:\src\Slicer
python support/verify-vendor.py
./support/windows/check-runner.ps1
./support/windows/build-release.ps1
```

The release helper builds Release dependencies, selects the Visual Studio SDK environment, builds the application, checks its help banner and packages the exact payload with Inno Setup. The output is `dist\slicer-<version>-windows.exe`, with the version read from [support/VERSION](../support/VERSION).

To retain a completed dependency prefix while iterating:

```powershell
./support/windows/build-release.ps1 -DependenciesOnly
./support/windows/build-release.ps1 -UseCachedDependencies
```

Reuse only a prefix built for the same architecture, configuration, toolchain and dependency definitions. CI enforces the matching cache key and saves completed dependencies before application compilation.

## Qualify the exact installer

```powershell
$Version = (Get-Content support/VERSION -Raw).Trim()
./support/windows/qualify-installer.ps1 `
  -Artifact "./dist/slicer-$Version-windows.exe" -ExpectedVersion $Version
```

Qualification installs the real payload into a unique temporary directory, checks the product-version help banner and removes the temporary installation. CI smoke mode avoids normal uninstall registration and shortcuts.

For application tests:

```powershell
ctest --test-dir build -C Release --output-on-failure
```

Public release packaging uses the repository-owned helper. [Release engineering](RELEASE_ENGINE.md) defines publication and recovery; [Validation](VALIDATION.md) defines the scope of the resulting evidence.

