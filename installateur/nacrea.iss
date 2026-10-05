; =====================================================================
; NACRÉA · Programme d'installation Windows (Inno Setup)
; Fabriqué automatiquement par GitHub (.github/workflows/livraison.yml).
; =====================================================================
#define Version GetEnv("NACREA_VERSION")
#if Version == ""
  #define Version "1.0.0"
#endif

[Setup]
AppId={{8F3C1E52-6A1B-4C7E-9B7A-2D5E4F1A9C30}
AppName=Nacréa
AppVersion={#Version}
AppVerName=Nacréa {#Version}
AppPublisher=Nacréa
DefaultDirName={localappdata}\Programs\Nacrea
DefaultGroupName=Nacréa
DisableProgramGroupPage=yes
; Installation pour l'utilisateur : pas besoin d'être administrateur
PrivilegesRequired=lowest
OutputDir=..\livraison
OutputBaseFilename=Nacrea-Installation
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\nacrea.exe
UninstallDisplayName=Nacréa
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Ferme Nacréa si elle est ouverte pendant une mise à jour
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Nacréa"; Filename: "{app}\nacrea.exe"
Name: "{autodesktop}\Nacréa"; Filename: "{app}\nacrea.exe"; Tasks: bureau

[Run]
Filename: "{app}\nacrea.exe"; Description: "Ouvrir Nacréa maintenant"; Flags: nowait postinstall skipifsilent
