; SPDX-License-Identifier: AGPL-3.0-or-later
#define MyAppName "Slicer"
#define MyPublisher "Infiltrator Projects"
#define MyURL "https://github.com/Infiltrator-Projects/Slicer"

#ifndef RepoRoot
  #error RepoRoot must be supplied by build-release.ps1
#endif
#ifndef AppVersion
  #error AppVersion must be supplied by build-release.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build-release.ps1
#endif

[Setup]
AppId={88BE4658-A3A2-4201-9841-B516AE357B0F}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyPublisher}
AppPublisherURL={#MyURL}
AppSupportURL={#MyURL}
AppUpdatesURL={#MyURL}
DefaultDirName={autopf}\Slicer
DefaultGroupName=Slicer
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=slicer-{#AppVersion}-windows
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\prusa-slicer.exe
SetupLogging=yes

[Files]
; The build tree contains generated DLLs beside the launchers. Resources are
; copied from the repository rather than following the build-time junction.
Source: "{#RepoRoot}\build\src\Release\*"; DestDir: "{app}"; Excludes: "resources\*;*.pdb;*.ilk;*.exp;*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\resources\*"; DestDir: "{app}\resources"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Slicer"; Filename: "{app}\prusa-slicer.exe"
Name: "{autodesktop}\Slicer"; Filename: "{app}\prusa-slicer.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\prusa-slicer.exe"; Description: "Launch Slicer"; Flags: nowait postinstall skipifsilent
