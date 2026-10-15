# SPDX-License-Identifier: AGPL-3.0-or-later
# Exercise the exact installer payload without changing a persistent runner's
# Slicer installation, uninstall registration, or Start menu shortcuts.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Artifact,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Installer = (Resolve-Path -LiteralPath $Artifact).Path
$Bytes = [System.IO.File]::ReadAllBytes($Installer)
if ($Bytes.Length -lt 2 -or $Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) {
    throw "Windows release artifact is not a PE executable: $Installer"
}

$Token = [guid]::NewGuid().ToString("N")
$ScratchBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$SmokeRoot = Join-Path $ScratchBase "slicer-installer-smoke-$Token"
$InstallDir = Join-Path $SmokeRoot "app"
$Log = Join-Path $SmokeRoot "install.log"
New-Item -ItemType Directory -Path $SmokeRoot | Out-Null

try {
    # PowerShell 7's .NET argument list preserves paths containing spaces and
    # provides a process handle for a bounded wait and an exact exit code.
    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $Installer
    $StartInfo.UseShellExecute = $false
    foreach ($Argument in @(
        '/VERYSILENT', '/SP-', '/SUPPRESSMSGBOXES', '/NORESTART',
        '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS', '/CURRENTUSER',
        '/NOICONS', "/CI=$Token", "/DIR=$InstallDir", "/LOG=$Log"
    )) {
        $StartInfo.ArgumentList.Add($Argument)
    }
    $Process = [System.Diagnostics.Process]::Start($StartInfo)
    if (-not $Process.WaitForExit(600000)) {
        $Process.Kill($true)
        $Process.WaitForExit(10000) | Out-Null
        throw "Windows installer smoke test exceeded ten minutes."
    }
    if ($Process.ExitCode -ne 0) {
        throw "Windows installer smoke test failed with exit code $($Process.ExitCode)."
    }

    $Marker = Join-Path $InstallDir '.slicer-ci-smoke'
    if (-not (Test-Path -LiteralPath $Marker -PathType Leaf) -or
        (Get-Content -LiteralPath $Marker -Raw).Trim() -ne $Token) {
        throw "Installer did not run in the required isolated CI smoke mode."
    }
    if (Get-ChildItem -LiteralPath $InstallDir -Filter 'unins*.exe') {
        throw "CI smoke mode unexpectedly created an uninstaller."
    }
    $UninstallKey = "InfiltratorSlicerSmoke-${Token}_is1"
    foreach ($RegistryRoot in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        if (Test-Path -LiteralPath (Join-Path $RegistryRoot $UninstallKey)) {
            throw "CI smoke mode unexpectedly registered an installed application."
        }
    }

    $ConsoleExecutable = Join-Path $InstallDir 'prusa-slicer-console.exe'
    if (-not (Test-Path -LiteralPath $ConsoleExecutable -PathType Leaf)) {
        throw "Installer did not extract the Slicer console executable."
    }
    $HelpOutput = (& $ConsoleExecutable --help 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Installed Slicer console executable failed its --help smoke test."
    }
    $VersionPattern = '(?m)^PrusaSlicer-' + [regex]::Escape($ExpectedVersion) + '(?![\d.])[^\r\n]*'
    $VersionMatch = [regex]::Match($HelpOutput, $VersionPattern)
    if (-not $VersionMatch.Success) {
        throw "Installed Slicer reports an unexpected version: $HelpOutput"
    }
    Write-Host "Qualified exact Windows installer in isolated CI mode: $($VersionMatch.Value)"
}
catch {
    if (Test-Path -LiteralPath $Log -PathType Leaf) {
        Get-Content -LiteralPath $Log -Tail 80 | Write-Host
    }
    throw
}
finally {
    Remove-Item -LiteralPath $SmokeRoot -Recurse -Force
}
