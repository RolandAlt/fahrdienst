# apply-ui.ps1
# - Normalisiert CRLF/UTF-8 (ohne BOM) für main.dart
# - Normalisiert LF/UTF-8 (ohne BOM) für lib\main.patch
# - Erstellt Backup von main.dart
# - Wendet git apply mit whitespace-toleranten Flags an

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg){ Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Ok($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host "[ERR] $msg" -ForegroundColor Red }

# Pfade
$RepoRoot  = Get-Location
$MainPath  = Join-Path $RepoRoot "lib\main.dart"
$PatchPath = Join-Path $RepoRoot "lib\main.patch"

if (-not (Test-Path -LiteralPath $MainPath))  { throw "Datei nicht gefunden: $MainPath" }
if (-not (Test-Path -LiteralPath $PatchPath)) { throw "Patch nicht gefunden: $PatchPath" }

# Hilfsfunktionen: Encodings/Zeilenenden
function Set-Utf8NoBom-CRLF([string]$Path){
  $code = Get-Content -Raw -LiteralPath $Path
  # Nach CRLF normalisieren
  $code = $code -replace "`r?`n", "`r`n"
  # UTF-8 ohne BOM schreiben
  $enc = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Path, $code, $enc)
}

function Set-Utf8NoBom-LF([string]$Path){
  $code = Get-Content -Raw -LiteralPath $Path
  # Nach LF normalisieren (Patchs sind klassisch LF-basiert)
  $code = $code -replace "`r`n", "`n"
  $code = $code -replace "`r(?!`n)", "`n"
  # UTF-8 ohne BOM schreiben
  $enc = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Path, $code, $enc)
}

# 1) Backup anlegen
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupPath = Join-Path $RepoRoot ("lib\main.dart.bak-" + $stamp)
Copy-Item -LiteralPath $MainPath -Destination $BackupPath -Force
Write-Ok "Backup erstellt: $BackupPath"

# 2) Zeilenenden & Encoding normalisieren
Write-Info "main.dart -> CRLF + UTF-8 (ohne BOM)"
Set-Utf8NoBom-CRLF -Path $MainPath

Write-Info "lib\main.patch -> LF + UTF-8 (ohne BOM)"
Set-Utf8NoBom-LF -Path $PatchPath

# 3) Sicherstellen, dass wir in einem Git-Repo sind
try {
  $null = git rev-parse --is-inside-work-tree 2>$null
} catch {
  throw "Kein Git-Repository gefunden (git rev-parse schlug fehl)."
}

# 4) Patch anwenden (Whitespace tolerant)
Write-Info "git apply wird ausgeführt …"
try {
  git apply --ignore-space-change --ignore-whitespace --whitespace=nowarn --index --verbose -- "$PatchPath"
  Write-Ok "Patch angewendet."
} catch {
  Write-Err "git apply fehlgeschlagen."
  Write-Warn "Diagnose:"
  try { git apply --check --ignore-space-change --ignore-whitespace --whitespace=nowarn --verbose -- "$PatchPath" } catch { }
  Write-Err $_.Exception.Message
  Write-Warn "Backup wiederherstellbar: $BackupPath"
  exit 1
}

# 5) Kurzer Statushinweis
Write-Info "Geänderte Dateien:"
git status -s -- lib/main.dart | Out-Host

Write-Ok "Fertig. Falls nötig: vergleichen mit Backup $BackupPath"
