[Setup]
AppId={{C4B0A27B-1F56-4D18-9C01-PASSDRIVE100}
AppName=PassDrive
AppVersion=1.0.1
AppPublisher=PassDrive
DefaultDirName={autopf}\PassDrive
DefaultGroupName=PassDrive
OutputDir=..\build\installer
OutputBaseFilename=PassDrive-Setup-1.0.1
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\passdrive.exe

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\PassDrive"; Filename: "{app}\passdrive.exe"
Name: "{autodesktop}\PassDrive"; Filename: "{app}\passdrive.exe"

[Run]
Filename: "{app}\passdrive.exe"; Parameters: "--passdrive-skip-update"; Description: "Abrir o PassDrive"; Flags: nowait postinstall
