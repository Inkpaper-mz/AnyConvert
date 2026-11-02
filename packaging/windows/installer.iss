#define MyAppName "万能转码 AnyConvert"
#define MyAppVersion "1.5.0"
#define MyAppPublisher "Inkpaper-mz"
#define MyAppExeName "AnyConvert.exe"

[Setup]
AppId={{7F2C1E54-9A3B-4C21-8E77-5B1D2A9C0F13}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\AnyConvert
DefaultGroupName=万能转码
DisableProgramGroupPage=yes
OutputDir=Z:\Users\inkpaper\Documents\deepseek-harness\default-workspace\AnyConvert\dist
OutputBaseFilename=AnyConvert-1.5.0-Windows-x64-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=lowest

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式:"

[Files]
Source: "Z:\Users\inkpaper\Documents\deepseek-harness\default-workspace\AnyConvert\dist\AnyConvert\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\万能转码"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\万能转码"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动万能转码"; Flags: nowait postinstall skipifsilent
