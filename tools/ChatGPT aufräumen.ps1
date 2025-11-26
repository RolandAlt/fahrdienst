# ChatGPT-Fix.ps1
# Deaktiviert GPU-Hardwarebeschleunigung, leert Cache (inkl. LocalCache\Roaming\ChatGPT) und startet ChatGPT neu.

$ErrorActionPreference = 'SilentlyContinue'
Write-Host "== ChatGPT Fix: HW-Acceleration AUS + Cache leeren ==" -ForegroundColor Cyan

function Kill-ChatGPT {
  Write-Host "Beende ChatGPT-Prozesse..."
  Get-Process -Name "ChatGPT*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 600
}

function Remove-ContentIfExists($path) {
  if (Test-Path $path) {
    Write-Host "Leere: $path"
    Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Ensure-Folder($folder) {
  if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
}

function Backup-File($path) {
  if (Test-Path $path) {
    $bak = "$path.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -LiteralPath $path -Destination $bak -Force
    Write-Host "Backup: $bak"
  }
}

function Set-HwAccelFalse-InJson($file) {
  try {
    $json = @{}
    if (Test-Path $file) {
      $content = Get-Content -LiteralPath $file -Raw
      if ($content.Trim().Length -gt 0) { $json = $content | ConvertFrom-Json -ErrorAction Stop }
    }
  } catch {
    Write-Host "Warnung: $file war keine gültige JSON. Erzeuge neu..." -ForegroundColor Yellow
    $json = @{}
  }
  $keys = @("hardwareAcceleration","hardwareAccelerationEnabled","useHardwareAcceleration","enableHardwareAcceleration","hardware_acceleration")
  foreach ($k in $keys) { $json | Add-Member -NotePropertyName $k -NotePropertyValue $false -Force }
  ($json | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $file -Encoding UTF8
  Write-Host "HW-Acceleration = false in: $file"
}

function Clean-StoreApp {
  $pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "OpenAI.ChatGPT-Desktop_*" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pkg) { Write-Host "Store-App: nicht gefunden (OK, evtl. Standalone)." -ForegroundColor Yellow; return $null }
  Write-Host "Store-App: $($pkg.FullName)"
  $base = $pkg.FullName

  # 1) HW-Accel aus
  $candidates = @(
    (Join-Path $base "Settings\settings.json"),
    (Join-Path $base "LocalState\settings.json"),
    (Join-Path $base "LocalState\User\settings.json")
  )
  foreach ($f in $candidates) {
    Ensure-Folder (Split-Path $f -Parent)
    if (Test-Path $f) { Backup-File $f }
    Set-HwAccelFalse-InJson $f
  }

  # 2) Cache/Temp leeren – inkl. LocalCache\Roaming\ChatGPT\*
  $lc = Join-Path $base "LocalCache"
  $lcRoamingChatGPT = Join-Path $lc "Roaming\ChatGPT"

  foreach ($p in @($lc,
                   (Join-Path $lc "Cache"),
                   (Join-Path $lc "GPUCache"),
                   (Join-Path $lc "Code Cache"),
                   (Join-Path $lc "Service Worker"),
                   (Join-Path $lc "IndexedDB"),
                   (Join-Path $lc "Local Storage"),
                   (Join-Path $lc "Session Storage"))) {
    Remove-ContentIfExists $p
  }

  Remove-ContentIfExists $lcRoamingChatGPT
  foreach ($sub in "Cache","GPUCache","Code Cache","Service Worker","IndexedDB","Local Storage","Session Storage") {
    Remove-ContentIfExists (Join-Path $lcRoamingChatGPT $sub)
  }

  Remove-ContentIfExists (Join-Path $base "TempState")
  return $pkg
}

function Clean-Standalone {
  $dirs = @("$env:APPDATA\ChatGPT", "$env:LOCALAPPDATA\ChatGPT", "$env:APPDATA\ChatGPT\User Data", "$env:LOCALAPPDATA\ChatGPT\User Data")
  foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) { continue }
    Write-Host "Standalone-Pfad: $dir"
    $settings = Join-Path $dir "settings.json"
    if (Test-Path (Split-Path $settings -Parent)) {
      if (Test-Path $settings) { Backup-File $settings }
      Set-HwAccelFalse-InJson $settings
    }

    # alter kompatibler Ersatz für '? :' Operator
    foreach ($sub in "", "Cache","GPUCache","Code Cache","Service Worker","IndexedDB","Local Storage","Session Storage") {
      $target = $dir
      if ($sub -ne "") { $target = Join-Path $dir $sub }
      Remove-ContentIfExists $target
    }
  }

  # Desktop-Shortcut mit --disable-gpu (nur sinnvoll bei Standalone)
  $exe = "$env:LOCALAPPDATA\Programs\ChatGPT\ChatGPT.exe"
  if (Test-Path $exe) {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "ChatGPT (GPU aus).lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $exe
    $sc.Arguments  = "--disable-gpu"
    $sc.WorkingDirectory = Split-Path $exe -Parent
    $sc.IconLocation = "$exe,0"
    $sc.Save()
    Write-Host "Shortcut erstellt: $lnk"
  }
}

function Clean-Temp {
  Write-Host "Windows-Temp: ChatGPT/OpenAI/Electron-Reste entfernen..."
  Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "chatgpt|openai|electron" } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Start-ChatGPT {
  Write-Host "Starte ChatGPT..."
  $pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "OpenAI.ChatGPT-Desktop_*" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($pkg) {
    $aumid = "$($pkg.Name)!App"
    Start-Process explorer.exe "shell:AppsFolder\$aumid" -ErrorAction SilentlyContinue
    return
  }
  $exe1 = "$env:LOCALAPPDATA\Programs\ChatGPT\ChatGPT.exe"
  $exe2 = "$env:ProgramFiles\ChatGPT\ChatGPT.exe"
  foreach ($exe in @($exe1,$exe2)) { if (Test-Path $exe) { Start-Process $exe; return } }
  Write-Host "Hinweis: ChatGPT konnte nicht automatisch gestartet werden." -ForegroundColor Yellow
}

# ---------- Ablauf ----------
Kill-ChatGPT
$store = Clean-StoreApp
Clean-Standalone
Clean-Temp
Write-Host "Fertig: HW-Beschleunigung AUS + Cache geleert." -ForegroundColor Green
Start-ChatGPT
