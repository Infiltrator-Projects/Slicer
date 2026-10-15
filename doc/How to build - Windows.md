# Build Infiltrator Slicer on Windows

The qualified Windows installer targets x64. CI uses the hosted `windows-2022` image and Visual Studio 2022.

## Prerequisites

Install PowerShell 7, Git, CMake 3.18.5 or newer, Python 3, Visual Studio 2022 with the x64 C++ build tools and Windows SDK, and Inno Setup 6. The repository preflight checks the selected compiler and executable launch before the long build.

## Build the installer

Use a short checkout path, such as `C:\src\Slicer`, then run from PowerShell 7:

```powershell
git clone https://github.com/Infiltrator-Projects/Slicer.git C:\src\Slicer
Set-Location C:\src\Slicer
python support/verify-vendor.py
./support/windows/check-runner.ps1
./support/windows/build-release.ps1
```

The release helper builds Release dependencies, initializes the selected Visual Studio SDK environment, configures only the application's Release configuration, builds it, checks its help banner, and packages the exact payload with Inno Setup. The output for product version 0.0.1 is `dist\slicer-0.0.1-windows.exe`.

To retain a completed dependency prefix while iterating on the application:

```powershell
./support/windows/build-release.ps1 -DependenciesOnly
./support/windows/build-release.ps1 -UseCachedDependencies
```

Reuse only the dependency prefix built for the same architecture, configuration, toolchain, and dependency source definitions. CI enforces an exact cache key and saves completed dependencies before application compilation.

## Qualify the exact installer

```powershell
./support/windows/qualify-installer.ps1 `
  -Artifact ./dist/slicer-0.0.1-windows.exe -ExpectedVersion 0.0.1
```

Qualification installs the real payload into a unique temporary directory, checks its product-version help banner, and removes the temporary installation. CI smoke mode avoids normal uninstall registration and shortcuts.

For development test runs:

```powershell
ctest --test-dir build -C Release --output-on-failure
```

The upstream `build_win.bat` remains available for development configurations. Public release packaging uses the repository-owned helper above. See [release engineering](RELEASE_ENGINE.md) for automatic publication and recovery from a failed sealing job.
