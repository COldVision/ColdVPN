; Inno Setup script for ColdVPN. Built by tool\build_installer.ps1, which passes
; the version and the folder with the application files.
#define AppName "ColdVPN"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\installer\app"
#endif

[Setup]
AppId={{8C6C2B6E-4E0B-4C56-9B1F-5A6C7D0E3A21}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=ColdVision
AppPublisherURL=https://github.com/ColdVision/ColdVPN
AppSupportURL=https://github.com/ColdVision/ColdVPN
DefaultDirName={autopf}\ColdVPN
DefaultGroupName=ColdVPN
DisableProgramGroupPage=yes
; The app manages a network tunnel, so both setup and the app run elevated.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=ColdVPN-Setup-{#AppVersion}
SetupIconFile=..\assets\app_icon.ico
; Pictures inside the wizard: without them Inno Setup shows its own.
WizardImageFile=wizard.bmp
WizardSmallImageFile=wizard_small.bmp
; What Windows shows in the file properties and in the administrator prompt.
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup
VersionInfoCompany=ColdVision
VersionInfoCopyright=ColdVision
UninstallDisplayIcon={app}\ColdVPN.exe
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; The running app is closed in PrepareToInstall below (it may sit in the tray).
CloseApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\ColdVPN"; Filename: "{app}\ColdVPN.exe"
Name: "{autodesktop}\ColdVPN"; Filename: "{app}\ColdVPN.exe"; Tasks: desktopicon

[Run]
; runascurrentuser: the app needs administrator rights, and setup already has
; them. Without the flag the launch fails with error 740.
Filename: "{app}\ColdVPN.exe"; Description: "{cm:LaunchProgram,ColdVPN}"; Flags: nowait postinstall skipifsilent runascurrentuser

[Code]
// Closes the running app and takes the tunnel down. The tunnel is removed
// only when its service exists: otherwise the client shows an error box.
procedure StopAppAndTunnel();
var
  ResultCode: Integer;
  Client: String;
begin
  Exec(ExpandConstant('{cmd}'), '/C taskkill /IM ColdVPN.exe /F', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode);
  Client := ExpandConstant('{commonpf64}\AmneziaWG\amneziawg.exe');
  if FileExists(Client) and
     Exec(ExpandConstant('{sys}\sc.exe'), 'query "AmneziaWGTunnel$ColdVPN"', '',
       SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
    Exec(Client, '/uninstalltunnelservice ColdVPN', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
  Sleep(800);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  // An update over a running copy.
  StopAppAndTunnel();
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    StopAppAndTunnel();
    // The autostart task, if the user turned autostart on.
    Exec(ExpandConstant('{sys}\schtasks.exe'), '/Delete /TN ColdVPN /F', '',
      SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
