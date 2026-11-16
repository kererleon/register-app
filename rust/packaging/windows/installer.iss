; The setup program for Register Rust on Windows (Inno Setup).
; Installs for the current user only, so no administrator rights are needed.
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{6F0B8C1E-3D5A-4E7B-9C21-52A9E1D4B7F3}
AppName=Register Rust
AppVersion={#AppVersion}
AppPublisher=kererleon
AppPublisherURL=https://github.com/kererleon/register-app
DefaultDirName={localappdata}\Programs\Register Rust
DefaultGroupName=Register Rust
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..
OutputBaseFilename=Register-Rust-Setup
SetupIconFile=..\..\app\windows\icon.ico
UninstallDisplayIcon={app}\Register-Rust.exe
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
Source: "..\..\Register-Rust.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Register Rust"; Filename: "{app}\Register-Rust.exe"
Name: "{autodesktop}\Register Rust"; Filename: "{app}\Register-Rust.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Register-Rust.exe"; Description: "{cm:LaunchProgram,Register Rust}"; Flags: nowait postinstall skipifsilent
