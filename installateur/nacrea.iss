; =====================================================================
; YDS BEAUTY · Programme d'installation Windows (Inno Setup)
; Fabriqué automatiquement par GitHub (.github/workflows/livraison.yml).
; =====================================================================
#define Version GetEnv("NACREA_VERSION")
#if Version == ""
  #define Version "1.0.0"
#endif

[Setup]
AppId={{8F3C1E52-6A1B-4C7E-9B7A-2D5E4F1A9C30}
AppName=YDS Beauty
AppVersion={#Version}
AppVerName=YDS Beauty {#Version}
AppPublisher=YDS Beauty
DefaultDirName={localappdata}\Programs\YDS Beauty
DefaultGroupName=YDS Beauty
DisableProgramGroupPage=yes
; Installation pour l'utilisateur : pas besoin d'être administrateur
PrivilegesRequired=lowest
OutputDir=..\livraison
OutputBaseFilename=YDS-Beauty-Installation
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\nacrea.exe
UninstallDisplayName=YDS Beauty
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Ferme YDS Beauty si elle est ouverte pendant une mise à jour
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Anciens raccourcis (quand le logiciel s'appelait Nacréa)
Type: files; Name: "{autoprograms}\Nacréa.lnk"
Type: files; Name: "{autodesktop}\Nacréa.lnk"

[Icons]
Name: "{autoprograms}\YDS Beauty"; Filename: "{app}\nacrea.exe"
Name: "{autodesktop}\YDS Beauty"; Filename: "{app}\nacrea.exe"; Tasks: bureau

[Run]
Filename: "{app}\nacrea.exe"; Description: "Ouvrir YDS Beauty maintenant"; Flags: nowait postinstall skipifsilent
