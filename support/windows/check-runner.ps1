# SPDX-License-Identifier: AGPL-3.0-or-later
[CmdletBinding()]
param(
    [switch]$DiscoverOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "The Slicer Windows runner check must run on Windows."
}

function Get-SlicerVisualStudio {
    $Vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $Vswhere -PathType Leaf)) {
        $Vswhere = Join-Path $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe"
    }
    if (-not (Test-Path $Vswhere -PathType Leaf)) {
        throw "vswhere.exe is required to locate the installed Visual Studio x64 build tools."
    }

    $Json = (& $Vswhere -latest -products '*' -version '[16.0,19.0)' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json -utf8 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "vswhere.exe failed with exit code $LASTEXITCODE."
    }
    $Installations = @($Json | ConvertFrom-Json)
    if ($Installations.Count -ne 1) {
        throw "Visual Studio 2019, 2022, or 2026 with the x64 C++ build tools is required."
    }
    $Installation = $Installations[0]
    $Major = ([version]$Installation.installationVersion).Major
    $Product = ($Installation.productId -split '\.')[-1]
    $ProductLine = switch ($Major) {
        16 { "2019" }
        17 { "2022" }
        18 { "2026" }
        default { throw "Unsupported Visual Studio major version: $Major" }
    }
    $DevCmd = Join-Path $Installation.installationPath "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path $DevCmd -PathType Leaf)) {
        throw "The selected Visual Studio installation is missing VsDevCmd.bat: $DevCmd"
    }
    return [pscustomobject]@{
        Major = $Major
        Product = $Product
        Version = [string]$Installation.installationVersion
        InstallationPath = [string]$Installation.installationPath
        Generator = "Visual Studio $Major $ProductLine"
        DevCmd = $DevCmd
    }
}

function Get-RequiredCommand([string]$Name) {
    $Command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $Command) {
        throw "The self-hosted Windows runner is missing $Name."
    }
    return $Command
}

function Write-ProbeLaunchDiagnostics(
    [string]$Executable,
    [string]$Directory,
    [System.Management.Automation.ErrorRecord]$Failure
) {
    # Read only the failed probe's permissions and matching recent policy
    # events. Do not change ACLs, execution policy, or application controls.
    $Exception = $Failure.Exception
    while ($null -ne $Exception) {
        Write-Host "Launch exception: $($Exception.GetType().FullName); HResult=0x$($Exception.HResult.ToString('X8')); $($Exception.Message)"
        if ($Exception -is [System.ComponentModel.Win32Exception]) {
            Write-Host "Win32 native error: $($Exception.NativeErrorCode)"
        }
        $Exception = $Exception.InnerException
    }
    foreach ($Path in @($Directory, $Executable)) {
        try {
            & icacls.exe $Path
            if ($LASTEXITCODE -ne 0) {
                Write-Host "icacls returned $LASTEXITCODE for $Path"
            }
        } catch {
            Write-Host "icacls unavailable for ${Path}: $($_.Exception.Message)"
        }
    }
    # The directory contains a per-probe GUID. Matching that token also works
    # when events use a device path rather than a drive-letter path.
    $ProbeToken = Split-Path -Path $Directory -Leaf
    foreach ($LogName in @(
        'Microsoft-Windows-CodeIntegrity/Operational',
        'Microsoft-Windows-AppLocker/EXE and DLL',
        'Microsoft-Windows-Windows Defender/Operational',
        'Application'
    )) {
        try {
            $Events = @(Get-WinEvent -FilterHashtable @{
                LogName = $LogName
                StartTime = (Get-Date).AddMinutes(-5)
            } -MaxEvents 40 -ErrorAction Stop)
            $Matching = @($Events | Where-Object {
                $EventText = [string]$_.Message + "`n" + $_.ToXml()
                $EventText.IndexOf($ProbeToken, [StringComparison]::OrdinalIgnoreCase) -ge 0
            } | Select-Object -First 5)
            Write-Host "Matching probe events in ${LogName}: $($Matching.Count)"
            foreach ($Event in $Matching) {
                Write-Host "Event $($Event.Id); $($Event.TimeCreated.ToString('o')); $($Event.ProviderName)"
                Write-Host $Event.Message
                Write-Host ($Event.ToXml())
            }
        } catch {
            Write-Host "Probe event lookup unavailable for ${LogName}: $($_.Exception.Message)"
        }
    }
}

$Toolchain = Get-SlicerVisualStudio
if ($DiscoverOnly) {
    return $Toolchain
}

Write-Host "Runner: $env:RUNNER_NAME; OS: $([Environment]::OSVersion.VersionString)"
Write-Host "Runner architecture: $env:RUNNER_ARCH; PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "Visual Studio $($Toolchain.Version) $($Toolchain.Product): $($Toolchain.InstallationPath)"
Write-Host "Required product target: x64; CMake generator: $($Toolchain.Generator)"

$Pwsh = Get-RequiredCommand "pwsh.exe"
$Git = Get-RequiredCommand "git.exe"
$Cmake = Get-RequiredCommand "cmake.exe"
& $Pwsh.Source --version
if ($LASTEXITCODE -ne 0) { throw "pwsh.exe could not run." }
& $Git.Source --version
if ($LASTEXITCODE -ne 0) { throw "git.exe could not run." }

$Python = $null
foreach ($Name in @("python3.exe", "python.exe")) {
    $Candidate = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $Candidate) { continue }
    try {
        $PythonVersion = (& $Candidate.Source --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $PythonVersion -match '^Python 3\.') {
            $Python = $Candidate
            Write-Host $PythonVersion
            break
        }
    } catch {
        # A Windows app-execution alias may exist without an installed interpreter.
    }
}
if ($null -eq $Python) {
    throw "Python 3 (python3.exe or python.exe) is required to verify vendored sources."
}

$CmakeVersion = (& $Cmake.Source --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $CmakeVersion -notmatch '^cmake version (\d+\.\d+\.\d+)') {
    throw "cmake.exe did not report a usable version."
}
if ([version]$Matches[1] -lt [version]"3.18.5") {
    throw "CMake 3.18.5 or newer is required for binary-safe vendored archive assembly."
}
Write-Host ($CmakeVersion -split "`r?`n")[0]
$CapabilitiesJson = (& $Cmake.Source -E capabilities | Out-String)
if ($LASTEXITCODE -ne 0) { throw "CMake could not report supported generators." }
$Capabilities = $CapabilitiesJson | ConvertFrom-Json
$MatchingGenerators = @($Capabilities.generators | Where-Object { $_.name -eq $Toolchain.Generator })
if ($MatchingGenerators.Count -eq 0) {
    throw "Installed CMake does not support $($Toolchain.Generator). Install a compatible CMake on this runner before building."
}

$NativeArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($NativeArchitecture.ToLowerInvariant()) {
    "arm64" { $HostArchitecture = "arm64" }
    "x64" { $HostArchitecture = "x64" }
    default { throw "Unsupported Windows host architecture: $NativeArchitecture" }
}
Write-Host "Compiler host: $HostArchitecture; target: x64"

$TemporaryRoot = $env:RUNNER_TEMP
if ([string]::IsNullOrWhiteSpace($TemporaryRoot)) {
    $TemporaryRoot = [System.IO.Path]::GetTempPath()
}
$ProbeDirectory = Join-Path $TemporaryRoot ("slicer-x64-probe-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $ProbeDirectory | Out-Null
$OldDevCmd = $env:SLICER_RUNNER_VSDEVCMD
$OldHostArchitecture = $env:SLICER_RUNNER_HOST_ARCH
try {
    $env:SLICER_RUNNER_VSDEVCMD = $Toolchain.DevCmd
    $env:SLICER_RUNNER_HOST_ARCH = $HostArchitecture
    Set-Content -Path (Join-Path $ProbeDirectory "probe.cpp") -Encoding ASCII -Value @'
#include <iostream>
int main() { std::cout << "Slicer x64 runner probe OK\n"; return 0; }
'@
    Set-Content -Path (Join-Path $ProbeDirectory "compile.cmd") -Encoding ASCII -Value @'
@echo off
call "%SLICER_RUNNER_VSDEVCMD%" -arch=x64 -host_arch=%SLICER_RUNNER_HOST_ARCH% -app_platform=Desktop
if errorlevel 1 exit /b %errorlevel%
cl.exe /nologo /EHsc /std:c++17 /Fe:probe.exe /Fo:probe.obj probe.cpp
exit /b %errorlevel%
'@
    Push-Location $ProbeDirectory
    try {
        & $env:ComSpec /d /c (Join-Path $ProbeDirectory "compile.cmd")
        if ($LASTEXITCODE -ne 0) {
            throw "Visual Studio failed to compile the x64 runner probe (exit $LASTEXITCODE)."
        }
        $ProbeExecutable = Join-Path $ProbeDirectory "probe.exe"
        if (-not (Test-Path $ProbeExecutable -PathType Leaf)) {
            throw "Visual Studio did not produce the x64 runner probe."
        }
        $ProbeBytes = [System.IO.File]::ReadAllBytes($ProbeExecutable)
        $PeOffset = [BitConverter]::ToInt32($ProbeBytes, 0x3c)
        if ([BitConverter]::ToUInt16($ProbeBytes, $PeOffset + 4) -ne 0x8664) {
            throw "The runner probe was not compiled for the required x64 target."
        }
        try {
            & $ProbeExecutable
            if ($LASTEXITCODE -ne 0) {
                throw "Probe exit code: $LASTEXITCODE"
            }
        } catch {
            $LaunchFailure = $_
            try {
                Write-ProbeLaunchDiagnostics -Executable $ProbeExecutable -Directory $ProbeDirectory -Failure $LaunchFailure
            } catch {
                Write-Host "Additional probe diagnostics unavailable: $($_.Exception.Message)"
            }
            Write-Host "The runner cannot launch a freshly compiled x64 executable. The original launch failure follows."
            throw $LaunchFailure
        }
    } finally {
        Pop-Location
    }
} finally {
    $env:SLICER_RUNNER_VSDEVCMD = $OldDevCmd
    $env:SLICER_RUNNER_HOST_ARCH = $OldHostArchitecture
    Remove-Item -LiteralPath $ProbeDirectory -Recurse -Force
}

Write-Host "Windows runner preflight passed for the x64 Slicer build."
