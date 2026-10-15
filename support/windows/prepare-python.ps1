# SPDX-License-Identifier: AGPL-3.0-or-later
# Use a repository-owned interpreter in temporary storage. This intentionally
# avoids machine/user installation and Python registry registration.
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne "Arm64") {
    throw "This vendored interpreter is for the ARM64 Windows runner fleet."
}
if (-not $env:RUNNER_TEMP -or -not $env:GITHUB_ENV -or -not $env:GITHUB_PATH) {
    throw "RUNNER_TEMP, GITHUB_ENV, and GITHUB_PATH are required for temporary Python preparation."
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$PythonRoot = Join-Path $env:RUNNER_TEMP ("slicer-python-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $PythonRoot | Out-Null
$Published = $false
try {
    & cmake.exe "-DSLICER_PYTHON_DESTINATION=$PythonRoot" -P (Join-Path $PSScriptRoot "prepare-python.cmake")
    if ($LASTEXITCODE -ne 0) {
        throw "Vendored Windows Python checksum verification or extraction failed."
    }
    $Python = Join-Path $PythonRoot "python.exe"
    $Pth = Join-Path $PythonRoot "python313._pth"
    # build_win.bat configures dependencies in deps/build. ExternalProject's
    # dep_z3 source directory is therefore fixed at this repository-local path.
    # Keep the embedded runtime isolated: no site initialization, registry
    # import paths, environment import paths, or other runner packages.
    $Z3Scripts = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "deps\build\dep_z3-prefix\src\dep_z3\scripts"))
    $PthLines = @(Get-Content -LiteralPath $Pth)
    if ($PthLines -contains 'import site') {
        throw "The vendored interpreter unexpectedly enables site initialization."
    }
    Set-Content -LiteralPath $Pth -Encoding utf8NoBOM -Value ($PthLines + @($Z3Scripts))

    $VersionOutput = (& $Python --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $VersionOutput -ne "Python 3.13.16") {
        throw "Vendored Windows interpreter did not report its pinned version: $VersionOutput"
    }
    Write-Host $VersionOutput
    & $Python (Join-Path $RepoRoot "support\verify-vendor.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Vendored Windows Python failed the repository archive verification."
    }

    $Z3ArchiveMarker = Join-Path $PythonRoot '.slicer-z3-archive'
    $Z3Archive = Get-Content -LiteralPath $Z3ArchiveMarker -Raw
    # Exercise the actual pinned Z3 helper imports using the isolated runtime.
    # The probe's temporary module copy is never added to the persistent _pth.
    $Probe = @'
import argparse, io, logging, os, pathlib, pprint, re, subprocess, sys, tempfile, zipfile
assert sys.flags.isolated and sys.flags.no_site
assert str(pathlib.Path(sys.argv[2])) in sys.path, sys.path
with tempfile.TemporaryDirectory(prefix="z3-import-probe-", dir=sys.prefix) as directory:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        for name in archive.namelist():
            parts = pathlib.PurePosixPath(name).parts
            if len(parts) == 3 and parts[1] == "scripts" and parts[2].endswith(".py"):
                (pathlib.Path(directory) / parts[2]).write_bytes(archive.read(name))
    sys.path.append(directory)
    import mk_genfile_common, mk_util, update_api
print("Isolated standard library and pinned Z3 generator imports passed.")
'@
    & $Python -c $Probe $Z3Archive $Z3Scripts
    if ($LASTEXITCODE -ne 0) {
        throw "Vendored Windows Python could not load the standard library and Z3 generator helpers."
    }
    Remove-Item -LiteralPath $Z3ArchiveMarker

    Add-Content -LiteralPath $env:GITHUB_ENV -Encoding utf8 -Value "SLICER_PYTHON_ROOT=$PythonRoot"
    Add-Content -LiteralPath $env:GITHUB_PATH -Encoding utf8 -Value $PythonRoot
    $Published = $true
    Write-Host "Prepared isolated Windows Python in temporary storage: $PythonRoot"
}
finally {
    if (-not $Published) {
        Remove-Item -LiteralPath $PythonRoot -Recurse -Force
    }
}
