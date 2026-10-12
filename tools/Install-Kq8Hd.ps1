#Requires -Version 5.1
<#
.SYNOPSIS
  KQ8 Win11 Fix - install / uninstall into a Mask of Eternity folder.
  Prefer Setup KQ8 Fix.bat (GUI). This script is the engine behind it.
#>
param(
  [string]$GamePath = '',
  [ValidateSet('install', 'uninstall')]
  [string]$Action = 'install',
  [ValidateSet('', 'gog', 'disc', 'find')]
  [string]$LocationMode = '',
  [ValidateSet('', 'on', 'off')]
  [string]$DirectGlide = '',
  # keep = leave Options.cs alone (stock default is 640x480 / set800mode 0)
  [ValidateSet('', '640', '800', 'keep')]
  [string]$Resolution = '',
  [ValidateSet('', 'on', 'off')]
  [string]$Widescreen = '',
  [ValidateSet('', 'on', 'off')]
  [string]$Shortcut = '',
  [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$PackageRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$releaseRoot = Join-Path $PackageRoot 'release\KQ8-Fix'
if (Test-Path (Join-Path $releaseRoot 'runtime\win11')) {
  $PackageRoot = $releaseRoot
  $ScriptDir = Join-Path $PackageRoot 'tools'
}

$Runtime = Join-Path $PackageRoot 'runtime'
$Win11Src = Join-Path $Runtime 'win11'
$GlideSrc = Join-Path $Runtime 'glide2x.dll'
$ShortcutName = "King's Quest 8"

function Write-Banner {
  Write-Host ''
  Write-Host '========================================'
  Write-Host ' KQ8 Win11 Fix'
  Write-Host ' Install / uninstall into your game folder'
  Write-Host '========================================'
  Write-Host ''
}

function Read-Choice([string]$prompt, [string[]]$valid, [string]$default) {
  if ($NonInteractive -and $default) { return $default }
  while ($true) {
    $suffix = if ($default) { " [$default]" } else { '' }
    $r = Read-Host "$prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($r)) { $r = $default }
    $r = $r.Trim().ToLowerInvariant()
    if ($valid -contains $r) { return $r }
    Write-Host ("Please enter one of: {0}" -f ($valid -join ', '))
  }
}

function Read-YesNo([string]$prompt, [bool]$defaultYes) {
  $def = if ($defaultYes) { 'y' } else { 'n' }
  $r = Read-Choice $prompt @('y', 'n', 'yes', 'no') $def
  return ($r -eq 'y' -or $r -eq 'yes')
}

function Test-PathExistsSafe([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $false }
  try { return [bool](Test-Path -LiteralPath $path -ErrorAction Stop) }
  catch { return $false }
}

function Test-MaskInDir([string]$dir) {
  if ([string]::IsNullOrWhiteSpace($dir)) { return $false }
  try { return Test-PathExistsSafe (Join-Path $dir 'Mask.exe') }
  catch { return $false }
}

function Find-GogInstalls {
  $hits = @()
  foreach ($k in @(
      'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1207661053',
      'HKLM:\SOFTWARE\GOG.com\Games\1207661053',
      'HKCU:\SOFTWARE\GOG.com\Games\1207661053'
    )) {
    if (-not (Test-Path $k)) { continue }
    $prop = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $p = $prop.PATH
    if (-not $p -and $prop.EXE) { $p = Split-Path $prop.EXE -Parent }
    if (Test-MaskInDir $p) {
      $hits += [pscustomobject]@{ Path = $p }
    }
  }
  # Scan common roots only when the drive/folder exists (missing D: must not abort).
  foreach ($root in @(
      "${env:ProgramFiles(x86)}\GOG Galaxy\Games",
      "$env:ProgramFiles\GOG Galaxy\Games",
      'C:\Games',
      'D:\Games'
    ) | Where-Object { Test-PathExistsSafe $_ }) {
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      if (Test-MaskInDir $_.FullName) {
        $hits += [pscustomobject]@{ Path = $_.FullName }
      }
    }
  }
  return @($hits | Sort-Object Path -Unique)
}

function Browse-Folder([string]$description) {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = $description
  $dlg.ShowNewFolderButton = $false
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
  return $null
}

function Assert-GamePath([string]$path) {
  if (-not $path) { throw 'No game path.' }
  $path = $path.Trim().Trim('"')
  if (-not (Test-MaskInDir $path)) {
    throw "Mask.exe not found in: $path"
  }
  return (Resolve-Path -LiteralPath $path).Path
}

function Backup-File([string]$gameDir, [string]$backupDir, [string]$rel) {
  $src = Join-Path $gameDir $rel
  if (-not (Test-Path -LiteralPath $src)) { return }
  $dst = Join-Path $backupDir $rel
  $parent = Split-Path $dst -Parent
  if (-not (Test-Path $parent)) { New-Item $parent -ItemType Directory -Force | Out-Null }
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

function Test-MpvInPackage {
  return (Test-Path -LiteralPath (Join-Path $Win11Src 'mpv.exe'))
}

function Get-CutsceneAviNames {
  @('w32opn_1.avi', 'W32mdl_1.avi', 'W32ndg_1.avi')
}

function Test-PackageHasCutsceneAvis {
  foreach ($n in Get-CutsceneAviNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $Win11Src $n))) { return $false }
  }
  return $true
}

function Get-MissingGameCutsceneAvis([string]$gameDir) {
  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($n in Get-CutsceneAviNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $gameDir $n))) { [void]$missing.Add($n) }
  }
  return @($missing)
}

function Get-CurrentResolution([string]$gameDir) {
  $path = Join-Path $gameDir 'Options.cs'
  if (Test-Path $path) {
    foreach ($line in Get-Content $path) {
      if ($line -match '^\s*set800mode\s+(\d+)') {
        if ([int]$Matches[1] -eq 1) { return 800 }
        return 640
      }
    }
  }
  return 640
}

function Set-OptionsCs([string]$gameDir, [int]$set800, [bool]$forceGlide) {
  $path = Join-Path $gameDir 'Options.cs'
  if (Test-Path $path) { $lines = @(Get-Content $path) }
  else {
    $lines = @(
      'KQSound::setSpeechVol 0.68',
      'KQSound::setSfxVol    0.37',
      'KQSound::setMusicVol  0.5',
      'setShadowMask 15',
      'useDynamicLighting 1',
      'set Options::Captions true',
      'notStartingHelp 0',
      'assignGModeName Glide',
      'setBrightness 50',
      'set800mode 0'
    )
  }
  $has800 = $false
  $hasGlide = $false
  $hasHelp = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    if ($line -match '^\s*set800mode\b') {
      $out.Add("set800mode $set800"); $has800 = $true; continue
    }
    if ($forceGlide -and $line -match '^\s*assignGModeName\b') {
      $out.Add('assignGModeName Glide'); $hasGlide = $true; continue
    }
    # 0 = show starting help popups (1 skips them)
    if ($line -match '^\s*notStartingHelp\b') {
      $out.Add('notStartingHelp 0'); $hasHelp = $true; continue
    }
    $out.Add($line)
  }
  if (-not $has800) { $out.Add("set800mode $set800") }
  if ($forceGlide -and -not $hasGlide) { $out.Add('assignGModeName Glide') }
  if (-not $hasHelp) { $out.Add('notStartingHelp 0') }
  Set-Content -Path $path -Value $out -Encoding ASCII
}

function Install-LauncherFiles([string]$gameDir) {
  $candidates = @(
    (Join-Path $PackageRoot 'runtime\Launch-Kq8.ps1'),
    (Join-Path $PackageRoot '..\..\tools\Launch-Kq8.ps1'),
    (Join-Path $PSScriptRoot 'Launch-Kq8.ps1')
  )
  $srcPs1 = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $srcPs1) { throw 'Launch-Kq8.ps1 not found in package/tools.' }
  Copy-Item $srcPs1 (Join-Path $gameDir 'Launch-Kq8.ps1') -Force

  # Launcher icon (Mask of Eternity artwork from package, or GOG/game copy)
  $icoDst = Join-Path $gameDir 'kq8-launcher.ico'
  $icoCandidates = @(
    (Join-Path $PackageRoot 'runtime\kq8-launcher.ico'),
    (Join-Path $gameDir 'goggame-1207661053.ico'),
    (Join-Path $gameDir 'Mask.exe')
  )
  foreach ($icoSrc in $icoCandidates) {
    if ($icoSrc -match '\.exe$' -and (Test-Path $icoSrc)) { break }
    if ((Test-Path $icoSrc) -and $icoSrc -match '\.ico$') {
      Copy-Item $icoSrc $icoDst -Force
      break
    }
  }

  $batUi = @(
    '@echo off'
    'setlocal'
    'cd /d "%~dp0"'
    'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Launch-Kq8.ps1" %*'
    'if errorlevel 1 ( echo Launcher failed. & pause )'
    'exit /b %ERRORLEVEL%'
  ) -join "`r`n"
  Set-Content (Join-Path $gameDir 'Launch KQ8.bat') $batUi -Encoding ASCII

  $batEm = @(
    '@echo off'
    'setlocal'
    'cd /d "%~dp0"'
    'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Launch-Kq8.ps1" -EmergencySkipUi'
    'if errorlevel 1 ( set __COMPAT_LAYER=! & start "" "%~dp0Mask.exe" )'
    'exit /b 0'
  ) -join "`r`n"
  Set-Content (Join-Path $gameDir 'Launch KQ8 Emergency.bat') $batEm -Encoding ASCII
}

function Write-LauncherJson([string]$gameDir, [int]$resolution, [bool]$widescreen) {
  [pscustomobject]@{
    version     = 1
    resolution  = $resolution
    widescreen  = $widescreen
    textureMode = 'stock'
    remember    = $true
  } | ConvertTo-Json | Set-Content (Join-Path $gameDir 'kq8_launcher.json') -Encoding UTF8
}

function New-DesktopShortcut([string]$targetBat, [string]$name) {
  $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "$name.lnk"
  $gameDir = Split-Path $targetBat -Parent
  # Prefer space-free junction (SegMash video/path bugs with spaces).
  if ($gameDir -match '\s') {
    $junc = Join-Path (Split-Path $gameDir -Parent) 'KQ8'
    $jBat = Join-Path $junc 'Launch KQ8.bat'
    if (Test-Path -LiteralPath $jBat) {
      $targetBat = $jBat
      $gameDir = $junc
    }
  }
  $w = New-Object -ComObject WScript.Shell
  $sc = $w.CreateShortcut($lnkPath)
  $sc.TargetPath = $targetBat
  $sc.WorkingDirectory = $gameDir
  $sc.Description = 'KQ8 settings launcher'
  # Icon from Mask.exe (game), else packaged/copied launcher ico
  $mask = Join-Path $gameDir 'Mask.exe'
  $ico = Join-Path $gameDir 'kq8-launcher.ico'
  if (Test-Path -LiteralPath $mask) {
    $sc.IconLocation = "$mask,0"
  } elseif (Test-Path -LiteralPath $ico) {
    $sc.IconLocation = $ico
  }
  $sc.Save()
  return $lnkPath
}

function Remove-DesktopShortcut([string]$name) {
  foreach ($desktop in @(
      [Environment]::GetFolderPath('Desktop'),
      [Environment]::GetFolderPath('CommonDesktopDirectory')
    )) {
    if (-not $desktop) { continue }
    $lnk = Join-Path $desktop "$name.lnk"
    if (Test-Path -LiteralPath $lnk) {
      Remove-Item -LiteralPath $lnk -Force
      Write-Host "Removed shortcut: $lnk"
    }
  }
}

function Get-LatestBackup([string]$gameDir) {
  Get-ChildItem -LiteralPath $gameDir -Directory -Filter 'backup_kq8fix_*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-OurRelativeFiles {
  # Files the fix may add. Uninstall removes any of these that were not
  # present in the backup (UI checkboxes do not affect uninstall).
  $list = New-Object System.Collections.Generic.List[string]
  if (Test-Path $Win11Src) {
    Get-ChildItem -LiteralPath $Win11Src -Recurse -File | ForEach-Object {
      [void]$list.Add($_.FullName.Substring($Win11Src.Length).TrimStart('\', '/'))
    }
  }
  foreach ($rel in @(
      'Launch KQ8.bat', 'Launch KQ8 Emergency.bat', 'Launch KQ8 Fix.bat',
      'Launch KQ8 DirectGlide.bat', 'Launch-Kq8.ps1', 'kq8_launcher.json',
      'kq8-launcher.ico', 'close_player_after.ps1',
      'kq8fix.dll', 'kq8fix.exe', 'kq8fix.ini',
      'kq8fix.dll.bak_pre_segmash', 'kq8fix.dll.bak_shellexecute',
      'w32opn_1.avi', 'W32opn_1.avi', 'W32mdl_1.avi', 'W32ndg_1.avi',
      'mpv.exe', 'd3dcompiler_43.dll',
      'Copyright', 'LICENSE.GPL', 'LICENSE.LGPL',
      'Mask.kq8fix.log', 'Mask.kq8fix.dmp',
      'hd_textures\widescreen.on', 'hd_textures\autoscale.on',
      'hd_textures\autoscale_soft.on'
    )) { [void]$list.Add($rel) }
  return @($list | Select-Object -Unique)
}

function Uninstall-Kq8Fix([string]$gameDir) {
  # Always full uninstall: restore latest backup, remove our added files,
  # remove ALL backup_kq8fix_* folders, remove desktop shortcut.
  # Screen checkboxes (DirectGlide / resolution) are ignored.
  $backup = Get-LatestBackup $gameDir
  if (-not $backup) {
    throw "No backup_kq8fix_* folder in:`n$gameDir`nCannot uninstall safely."
  }
  Write-Host "Restoring from: $($backup.FullName)"
  Get-ChildItem -LiteralPath $backup.FullName -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($backup.FullName.Length).TrimStart('\', '/')
    $dst = Join-Path $gameDir $rel
    $parent = Split-Path $dst -Parent
    if (-not (Test-Path $parent)) { New-Item $parent -ItemType Directory -Force | Out-Null }
    Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    Write-Host "  restored $rel"
  }
  foreach ($rel in Get-OurRelativeFiles) {
    if (Test-Path -LiteralPath (Join-Path $backup.FullName $rel)) { continue }
    $path = Join-Path $gameDir $rel
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Force
      Write-Host "  removed $rel"
    }
  }
  # Drop empty hd_textures if we created only flag files
  $hd = Join-Path $gameDir 'hd_textures'
  if (Test-Path -LiteralPath $hd) {
    $left = @(Get-ChildItem -LiteralPath $hd -Force -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) {
      Remove-Item -LiteralPath $hd -Force -Recurse -ErrorAction SilentlyContinue
      Write-Host '  removed hd_textures\'
    }
  }
  Remove-DesktopShortcut $ShortcutName
  # Also clear common alternate shortcut name from older installs
  Remove-DesktopShortcut "King's Quest 8"
  Remove-DesktopShortcut 'Launch KQ8'

  $allBackups = @(Get-ChildItem -LiteralPath $gameDir -Directory -Filter 'backup_kq8fix_*' -ErrorAction SilentlyContinue)
  foreach ($b in $allBackups) {
    Write-Host "  removing backup folder $($b.Name)"
    Remove-Item -LiteralPath $b.FullName -Recurse -Force
  }
  Write-Host 'Uninstall complete (backups removed).'
}

function Resolve-GamePathInteractive {
  if ($GamePath) { return (Assert-GamePath $GamePath) }
  if (-not $LocationMode) {
    Write-Host 'Where is Mask of Eternity installed?'
    Write-Host '  1) GOG   2) Disc   3) Browse / paste path'
    $LocationMode = Read-Choice 'Choose 1/2/3 or gog/disc/find' @('1', '2', '3', 'gog', 'disc', 'find') '3'
    if ($LocationMode -eq '1') { $LocationMode = 'gog' }
    elseif ($LocationMode -eq '2') { $LocationMode = 'disc' }
    elseif ($LocationMode -eq '3') { $LocationMode = 'find' }
  }
  switch ($LocationMode) {
    'gog' {
      $hits = @(Find-GogInstalls)
      if ($hits.Count -eq 1) {
        Write-Host "Found: $($hits[0].Path)"
        if (Read-YesNo 'Use this folder? (y/n)' $true) { return (Assert-GamePath $hits[0].Path) }
      } elseif ($hits.Count -gt 1) {
        for ($i = 0; $i -lt $hits.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $hits[$i].Path) }
        $idx = [int](Read-Host 'Enter number') - 1
        if ($idx -lt 0 -or $idx -ge $hits.Count) { throw 'Invalid selection.' }
        return (Assert-GamePath $hits[$idx].Path)
      }
      Write-Host 'No GOG install found automatically.'
    }
    'disc' { Write-Host 'Typical: C:\Sierra\Mask of Eternity' }
  }
  $p = Read-Host 'Paste game folder path (or leave blank to browse)'
  if ([string]::IsNullOrWhiteSpace($p)) { $p = Browse-Folder 'Select folder containing Mask.exe' }
  return (Assert-GamePath $p)
}

# --- main ---
if (-not (Test-Path $Win11Src)) {
  throw "Missing runtime\win11 under $PackageRoot."
}

Write-Banner
$GamePath = Resolve-GamePathInteractive
Write-Host "Game folder: $GamePath"
Write-Host "Action:      $Action"

if ($Action -eq 'uninstall') {
  if (-not $NonInteractive -and -not (Read-YesNo 'Restore latest backup and remove the fix/launcher? (y/n)' $true)) {
    Write-Host 'Cancelled.'; exit 0
  }
  Uninstall-Kq8Fix $GamePath
  exit 0
}

# Install defaults = fix + launcher; DirectGlide off unless requested
if (-not $DirectGlide) {
  $DirectGlide = if ($NonInteractive) { 'off' } elseif (Read-YesNo 'Install Recommended graphics (sharper DirectGlide)? (y/n)' $false) { 'on' } else { 'off' }
}
$useDirectGlide = ($DirectGlide -eq 'on')

if (-not $Resolution) {
  if ($NonInteractive) { $Resolution = 'keep' }
  else {
    Write-Host 'Stock default resolution is 640x480. keep = do not change Options.cs'
    $Resolution = Read-Choice 'Resolution keep/640/800' @('keep', '640', '800') 'keep'
  }
}
$keepResolution = ($Resolution -eq 'keep')
$resForJson = if ($keepResolution) { Get-CurrentResolution $GamePath } else { [int]$Resolution }
$set800 = if ($resForJson -eq 800) { 1 } else { 0 }

# Widescreen defaults off at install; toggle later in Settings (DirectGlide only).
$useWide = $false
if ($useDirectGlide -and $Widescreen -eq 'on') { $useWide = $true }

if (-not $Shortcut) {
  $Shortcut = if ($NonInteractive) { 'on' } elseif (Read-YesNo 'Create desktop shortcut? (y/n)' $true) { 'on' } else { 'off' }
}
$makeShortcut = ($Shortcut -eq 'on')

if (-not (Test-MpvInPackage)) {
  throw 'mpv.exe missing from runtime\win11\. Include it in the KQ8-Fix package before running Setup.'
}

Write-Host ''
Write-Host 'Summary:'
Write-Host "  Win11 fix + launcher: YES"
Write-Host "  DirectGlide:          $(if($useDirectGlide){'YES'}else{'NO'})"
Write-Host "  Resolution:           $(if($keepResolution){"keep ($resForJson)"}else{$resForJson})"
Write-Host "  Shortcut:             $(if($makeShortcut){'YES'}else{'NO'})"
Write-Host "  Cutscene player:      mpv (bundled; install into game folder)"
if (-not (Test-PackageHasCutsceneAvis)) {
  Write-Host '  Cutscene AVIs:        not in this package (add next to Mask.exe after install)'
}
Write-Host ''
if (-not $NonInteractive -and -not (Read-YesNo 'Proceed? (y/n)' $true)) {
  Write-Host 'Cancelled.'; exit 0
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $GamePath "backup_kq8fix_$stamp"
New-Item $backupDir -ItemType Directory -Force | Out-Null
foreach ($rel in @(
    'Mask.exe', 'kqmoevol.exe', 'glide2x.dll', 'Options.cs',
    'kq8fix.exe', 'kq8fix.dll', 'kq8fix.ini',
    'Launch KQ8.bat', 'Launch KQ8 Emergency.bat', 'Launch KQ8 Fix.bat',
    'Launch KQ8 DirectGlide.bat', 'Launch-Kq8.ps1', 'kq8_launcher.json', 'kq8-launcher.ico',
    'close_player_after.ps1', 'play_kq8_avi.cmd',
    'mpv.exe', 'd3dcompiler_43.dll',
    'Copyright', 'LICENSE.GPL', 'LICENSE.LGPL',
    'w32opn_1.cmd', 'W32opn_1.cmd', 'w32opn_1.avi', 'W32opn_1.avi',
    'W32ndg_1.cmd', 'W32ndg_1.avi', 'W32mdl_1.cmd', 'W32mdl_1.avi',
    'hd_textures\widescreen.on', 'hd_textures\autoscale.on',
    'hd_textures\autoscale_soft.on'
  )) { Backup-File $GamePath $backupDir $rel }
Write-Host "Backup: $backupDir"

Copy-Item (Join-Path $Win11Src '*') $GamePath -Force -Recurse
Write-Host 'Copied Win11 fix + cutscene helpers.'

Push-Location $GamePath
try {
  $fixExe = Join-Path $GamePath 'kq8fix.exe'
  if (-not (Test-Path $fixExe)) { throw 'kq8fix.exe missing after copy.' }
  $fixProc = Start-Process -FilePath $fixExe -ArgumentList '--install' -WorkingDirectory $GamePath -Wait -PassThru -NoNewWindow
  if ($fixProc.ExitCode -ne 0) {
    Write-Warning "kq8fix --install exited with code $($fixProc.ExitCode)"
  } else {
    Write-Host 'kq8fix installed OK.'
  }
} finally { Pop-Location }

# kq8fix --install overwrites kq8fix.dll with the stock SegMash build (SW_HIDE
# resume crashes under DirectGlide). Re-apply our softened ShellExecute DLL.
$softDll = Join-Path $Win11Src 'kq8fix.dll'
if (Test-Path -LiteralPath $softDll) {
  Copy-Item -LiteralPath $softDll -Destination (Join-Path $GamePath 'kq8fix.dll') -Force
  Write-Host 'Restored DirectGlide-safe kq8fix.dll (post --install).'
}

Install-LauncherFiles $GamePath

if ($useDirectGlide) {
  if (-not (Test-Path $GlideSrc)) { throw "DirectGlide missing: $GlideSrc" }
  Copy-Item $GlideSrc (Join-Path $GamePath 'glide2x.dll') -Force
  Set-OptionsCs $GamePath $set800 $true
  $hdDir = Join-Path $GamePath 'hd_textures'
  if (-not (Test-Path $hdDir)) { New-Item $hdDir -ItemType Directory -Force | Out-Null }
  $widePath = Join-Path $hdDir 'widescreen.on'
  if ($useWide) { Set-Content $widePath '' -Encoding ASCII }
  elseif (Test-Path $widePath) { Remove-Item $widePath -Force }
  Write-Host 'DirectGlide installed (includes 2x SSAA + anisotropic filtering).'
} else {
  # Always force Glide renderer. Fresh GOG often has assignGModeName D3D-display,
  # which black-screens on Win10/11. Stock nGlide (glide2x.dll) needs Glide mode.
  Set-OptionsCs $GamePath $set800 $true
  $glideDll = Join-Path $GamePath 'glide2x.dll'
  if (-not (Test-Path $glideDll)) {
    Write-Warning 'No glide2x.dll found. Fix-only needs stock nGlide or DirectGlide.'
  } else {
    $glen = (Get-Item $glideDll).Length
    if ($glen -ge 150000 -and $glen -le 400000) {
      Write-Host 'DirectGlide DLL left in place; Options set to Glide.'
    } else {
      Write-Host "Stock Glide wrapper kept ($glen bytes); Options set to Glide (not D3D-display)."
    }
  }
  if ($keepResolution) {
    Write-Host "Resolution left at current ($resForJson)."
  } else {
    Write-Host "Resolution set to $resForJson."
  }
}

Write-LauncherJson $GamePath $resForJson $useWide
if ($makeShortcut) {
  Write-Host "Shortcut: $(New-DesktopShortcut (Join-Path $GamePath 'Launch KQ8.bat') $ShortcutName)"
}

if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'mpv.exe'))) {
  throw 'mpv.exe missing from game folder after install.'
}

Write-Host ''
Write-Host 'Install complete. Run Setup again anytime to change options or uninstall.'
$missingAvis = @(Get-MissingGameCutsceneAvis $GamePath)
if ($missingAvis.Count -gt 0) {
  Write-Host 'Cutscenes: mpv installed. Add these H.264 files next to Mask.exe, then play:'
  foreach ($n in $missingAvis) { Write-Host "  - $n" }
  Write-Host '(Boot intro / mid / ending. See README for details.)'
} else {
  Write-Host 'Cutscenes: mpv + H.264 AVIs.'
}
Write-Host 'Play: desktop shortcut or Launch KQ8.bat'
Write-Host "Backup: $backupDir"
Write-Host ''

