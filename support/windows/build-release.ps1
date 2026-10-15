# SPDX-License-Identifier: AGPL-3.0-or-later
[CmdletBinding()]
param(
    [string]$OutputDirectory = "dist",
    [string]$DependencyDirectory = "deps\build\release-windows-deps",
    [switch]$UseCachedDependencies,
    [switch]$DependenciesOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

function Fail([string]$Message) {
    throw $Message
}

function Resolve-BuildPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Initialize-VisualStudioEnvironment([string]$DevCmd) {
    $TemporaryRoot = $env:RUNNER_TEMP
    if ([string]::IsNullOrWhiteSpace($TemporaryRoot)) {
        $TemporaryRoot = [System.IO.Path]::GetTempPath()
    }
    $EnvironmentScript = Join-Path $TemporaryRoot ("slicer-vs-env-" + [guid]::NewGuid().ToString("N") + ".cmd")
    $OldDevCmd = $env:SLICER_RELEASE_VSDEVCMD
    try {
        $env:SLICER_RELEASE_VSDEVCMD = $DevCmd
        Set-Content -LiteralPath $EnvironmentScript -Encoding ASCII -Value @'
@echo off
call "%SLICER_RELEASE_VSDEVCMD%" -arch=x64 -host_arch=x64 -app_platform=Desktop >nul
if errorlevel 1 exit /b %errorlevel%
set
'@
        # Capture the environment privately; it may include CI credentials.
        $EnvironmentLines = @(& $env:ComSpec /d /c $EnvironmentScript)
        if ($LASTEXITCODE -ne 0) {
            Fail "Visual Studio environment initialization failed with exit code $LASTEXITCODE."
        }
        foreach ($Line in $EnvironmentLines) {
            if ($Line -match '^([^=]+)=(.*)$') {
                [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
            }
        }
    } finally {
        $env:SLICER_RELEASE_VSDEVCMD = $OldDevCmd
        Remove-Item -LiteralPath $EnvironmentScript -Force -ErrorAction SilentlyContinue
    }
}

$Version = (Get-Content (Join-Path $RepoRoot "support\VERSION") -Raw).Trim()
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Fail "support/VERSION is not a numeric semantic version."
}

$VersionText = Get-Content (Join-Path $RepoRoot "version.inc") -Raw
$Match = [regex]::Match($VersionText, 'set\(SLIC3R_VERSION\s+"([^"]+)"\)')
if (-not $Match.Success) {
    Fail "Could not read SLIC3R_VERSION from version.inc."
}
if ($Match.Groups[1].Value -ne $Version) {
    Fail "support/VERSION ($Version) does not match version.inc ($($Match.Groups[1].Value))."
}

$DependencyPath = Resolve-BuildPath $DependencyDirectory
$AppBuildPath = Resolve-BuildPath "build"
# build_win.bat cleans the app build directory after building dependencies.
# Keep the dependency prefix outside that directory so it survives the cleanup.
if ($DependencyPath.Equals($AppBuildPath, [StringComparison]::OrdinalIgnoreCase) -or
    $DependencyPath.StartsWith($AppBuildPath + [System.IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    Fail "DependencyDirectory must be outside the app build directory: $AppBuildPath"
}
$Toolchain = & (Join-Path $PSScriptRoot "check-runner.ps1") -DiscoverOnly
Write-Host "Building Slicer $Version Windows x64 release with $($Toolchain.Generator) $($Toolchain.Product)..."
$DependencyStamp = Join-Path $DependencyPath '.release-dependencies-complete'
if ($UseCachedDependencies) {
    if (-not (Test-Path -LiteralPath $DependencyStamp -PathType Leaf)) {
        Fail "Cached dependencies are incomplete: $DependencyPath"
    }
    Write-Host 'Reusing the exact cached Windows x64 Release dependencies.'
}
else {
    & (Join-Path $RepoRoot "build_win.bat") `
        -a x64 `
        -v $Toolchain.Major `
        -PRODUCT $Toolchain.Product `
        -c Release `
        -s deps `
        -r none `
        -d $DependencyPath
    if ($LASTEXITCODE -ne 0) {
        Fail "Windows dependency build failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path (Join-Path $DependencyPath 'usr\local\lib') -PathType Container)) {
        Fail "Windows dependency build did not produce its library prefix."
    }
    Set-Content -LiteralPath $DependencyStamp -Value 'Windows x64 Release dependency build completed.'
}
if ($DependenciesOnly) {
    return
}

# CMake find_library also needs the SDK LIB paths supplied by VsDevCmd.
Initialize-VisualStudioEnvironment $Toolchain.DevCmd

# Release dependencies contain no Debug libraries. The developer batch driver
# exposes every configuration, which makes OpenVDB require its missing Debug lib.
if (Test-Path -LiteralPath $AppBuildPath) {
    Remove-Item -LiteralPath $AppBuildPath -Recurse -Force
}
& cmake.exe -S $RepoRoot -B $AppBuildPath `
    -G $Toolchain.Generator -A x64 `
    "-DCMAKE_GENERATOR_INSTANCE=$($Toolchain.InstallationPath)" `
    "-DCMAKE_PREFIX_PATH=$(Join-Path $DependencyPath 'usr\local')" `
    -DCMAKE_CONFIGURATION_TYPES=Release
if ($LASTEXITCODE -ne 0) {
    Fail "Windows Release application configuration failed with exit code $LASTEXITCODE."
}
& cmake.exe --build $AppBuildPath --config Release --parallel ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) {
    Fail "Windows Release application build failed with exit code $LASTEXITCODE."
}

$BuildOutput = Join-Path $RepoRoot "build\src\Release"
$GuiExecutable = Join-Path $BuildOutput "prusa-slicer.exe"
$ConsoleExecutable = Join-Path $BuildOutput "prusa-slicer-console.exe"
if (-not (Test-Path $GuiExecutable -PathType Leaf)) {
    Fail "Windows GUI executable was not produced: $GuiExecutable"
}
if (-not (Test-Path $ConsoleExecutable -PathType Leaf)) {
    Fail "Windows console executable was not produced: $ConsoleExecutable"
}

# Keep legacy launcher filenames for build-driver compatibility while exposing
# the product's own executable names in shortcuts and release qualification.
Copy-Item -LiteralPath $GuiExecutable -Destination (Join-Path $BuildOutput "slicer.exe") -Force
Copy-Item -LiteralPath $ConsoleExecutable -Destination (Join-Path $BuildOutput "slicer-console.exe") -Force
Copy-Item -LiteralPath (Join-Path $BuildOutput "prusa-gcodeviewer.exe") `
    -Destination (Join-Path $BuildOutput "slicer-gcodeviewer.exe") -Force
$ConsoleExecutable = Join-Path $BuildOutput "slicer-console.exe"
$HelpOutput = (& $ConsoleExecutable --help 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    Fail "Built console executable failed its --help smoke test."
}
$VersionPattern = '(?m)^Slicer-' + [regex]::Escape($Version) + '(?![\d.])[^\r\n]*'
$VersionMatch = [regex]::Match($HelpOutput, $VersionPattern)
if (-not $VersionMatch.Success) {
    Fail "Built Slicer reports an unexpected version: $HelpOutput"
}
Write-Host "Built executable reports: $($VersionMatch.Value)"

$IsccPath = $null
$IsccCommand = Get-Command ISCC.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $IsccCommand) {
    $IsccPath = $IsccCommand.Source
}
if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $Candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate -PathType Leaf) {
            $IsccPath = (Resolve-Path $Candidate).Path
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    Fail "Inno Setup 6 (ISCC.exe) is required to create the Windows release .exe."
}

$Dist = Resolve-BuildPath $OutputDirectory
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$InstallerScript = Join-Path $RepoRoot "support\windows\installer.iss"

& $IsccPath `
    "/DRepoRoot=$RepoRoot" `
    "/DAppVersion=$Version" `
    "/DOutputDir=$Dist" `
    $InstallerScript
if ($LASTEXITCODE -ne 0) {
    Fail "Inno Setup failed with exit code $LASTEXITCODE."
}

$Artifact = Join-Path $Dist "slicer-$Version-windows.exe"
if (-not (Test-Path $Artifact -PathType Leaf)) {
    Fail "Expected Windows release artifact was not produced: $Artifact"
}

$Bytes = [System.IO.File]::ReadAllBytes($Artifact)
if ($Bytes.Length -lt 2 -or $Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) {
    Fail "Windows release artifact is not a valid PE executable."
}

Write-Host "Windows release artifact:"
Write-Host "  $Artifact"
