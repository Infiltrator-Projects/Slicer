# SPDX-License-Identifier: AGPL-3.0-or-later
[CmdletBinding()]
param(
    [string]$OutputDirectory = "dist",
    [string]$DependencyDirectory = "build\release-windows-deps"
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
Write-Host "Building Slicer $Version Windows release..."
& (Join-Path $RepoRoot "build_win.bat") `
    -c Release `
    -s all `
    -r none `
    -d $DependencyPath
if ($LASTEXITCODE -ne 0) {
    Fail "build_win.bat failed with exit code $LASTEXITCODE."
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

$VersionOutput = (& $ConsoleExecutable --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    Fail "Built console executable failed its --version smoke test."
}
Write-Host "Built executable reports: $VersionOutput"

$IsccPath = $null
$IsccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
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
