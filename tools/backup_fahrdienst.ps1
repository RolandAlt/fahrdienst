param(
    # Projektverzeichnis (Standard: aktuelles Verzeichnis)
    [string]$ProjectRoot = ".",
    # Wurzelordner für Backups
    [string]$BackupRoot = "C:\Backups\Fahrdienst App"
)

# Zeitstempel und Backup-Ordnernamen bauen
$timestamp  = Get-Date -Format "yyyy-MM-dd_HH-mm"
$backupName = "FahrdienstApp_Backup_$timestamp"
$backupPath = Join-Path $BackupRoot $backupName

# Backup-Wurzelordner anlegen
if (-not (Test-Path $BackupRoot)) {
    New-Item -ItemType Directory -Path $BackupRoot | Out-Null
}
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

Push-Location $ProjectRoot

# Verzeichnisse, die für das Projekt wichtig sind
$dirsToBackup = @(
    "android",                          # Android-Projekt
    "ios",                              # iOS (falls vorhanden)
    "assets",                           # Bilder/Fonts/etc.
    "lib",                              # kompletter Dart/Flutter-Code
    "supabase",                         # Supabase-Konfiguration (falls vorhanden)
    ".vscode",                          # VS Code Settings (optional, aber praktisch)
    "build\app\outputs\apk\release"     # fertige Release-APK(s)
)

foreach ($dir in $dirsToBackup) {
    if (Test-Path $dir) {
        Write-Host "Kopiere Verzeichnis: $dir"
        Copy-Item $dir -Destination $backupPath -Recurse -Force
    } else {
        Write-Host "Überspringe (nicht gefunden): $dir"
    }
}

# Einzelne wichtige Dateien im Projektroot
$filesToBackup = @(
    "pubspec.yaml",
    "pubspec.lock",
    "analysis_options.yaml",
    ".metadata",
    "README.md",
    ".gitignore"
)

foreach ($file in $filesToBackup) {
    if (Test-Path $file) {
        Write-Host "Kopiere Datei: $file"
        Copy-Item $file -Destination $backupPath -Force
    }
}

Pop-Location

Write-Host ""
Write-Host "Backup erstellt unter:"
Write-Host "  $backupPath"
