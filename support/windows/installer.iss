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
AppId={code:GetInstallAppId}
UsePreviousLanguage=no
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
PrivilegesRequiredOverridesAllowed=commandline
Uninstallable=not IsCISmoke
CreateUninstallRegKey=not IsCISmoke
UninstallDisplayIcon={app}\prusa-slicer.exe
SetupLogging=yes

[Files]
; The build tree contains generated DLLs beside the launchers. Resources are
; copied from the repository rather than following the build-time junction.
Source: "{#RepoRoot}\build\src\Release\*"; DestDir: "{app}"; Excludes: "resources\*;*.pdb;*.ilk;*.exp;*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\resources\*"; DestDir: "{app}\resources"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Slicer"; Filename: "{app}\prusa-slicer.exe"; Check: not IsCISmoke
Name: "{autodesktop}\Slicer"; Filename: "{app}\prusa-slicer.exe"; Tasks: desktopicon; Check: not IsCISmoke

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked; Check: not IsCISmoke

[Run]
Filename: "{app}\prusa-slicer.exe"; Description: "Launch Slicer"; Flags: nowait postinstall skipifsilent; Check: not IsCISmoke

[Code]
{ CI installs the same payload into a unique temporary directory, without
  registering an application or changing shortcuts on a persistent runner. }
function CISmokeToken: String;
begin
  Result := ExpandConstant('{param:CI|}');
end;

function IsCISmoke: Boolean;
begin
  Result := CISmokeToken <> '';
end;

function GetInstallAppId(Param: String): String;
begin
  if IsCISmoke then
    Result := 'InfiltratorSlicerSmoke-' + CISmokeToken
  else
    Result := '{88BE4658-A3A2-4201-9841-B516AE357B0F}';
end;

function InitializeSetup: Boolean;
var
  Token, InstallDir: String;
  Index: Integer;
begin
  Result := True;
  if not IsCISmoke then
    Exit;

  Token := CISmokeToken;
  if Length(Token) <> 32 then
    RaiseException('CI smoke mode requires a unique 32-character hexadecimal token.');
  for Index := 1 to Length(Token) do
    if Pos(LowerCase(Copy(Token, Index, 1)), '0123456789abcdef') = 0 then
      RaiseException('Invalid CI smoke token.');
  if IsAdminInstallMode then
    RaiseException('CI smoke mode requires /CURRENTUSER.');

  InstallDir := ExpandConstant('{param:DIR|}');
  if (CompareText(ExtractFileName(InstallDir), 'app') <> 0) or
     (CompareText(ExtractFileName(ExtractFileDir(InstallDir)),
       'slicer-installer-smoke-' + Token) <> 0) or
     DirExists(InstallDir) then
    RaiseException('CI smoke mode requires a fresh app directory under slicer-installer-smoke-<token>.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and IsCISmoke then
    if not SaveStringToFile(ExpandConstant('{app}\.slicer-ci-smoke'),
      CISmokeToken, False) then
      RaiseException('Could not record the isolated CI smoke installation.');
end;
