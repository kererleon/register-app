; Inno Setup script for the Windows installer of Register.
; Built by GitHub Actions (.github/workflows/release.yml) after
; `flutter build windows --release`.

#define AppName "Register"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8F2C1E7A-4B5D-4C3A-9E21-7D6B5A4F3C2E}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=kererleon
AppPublisherURL=https://github.com/kererleon/register-app
AppSupportURL=https://github.com/kererleon/register-app
; Installs for the current user, so no administrator rights are needed.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=Register-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Register.exe
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\Register.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\Register.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Register.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
