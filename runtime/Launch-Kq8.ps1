#Requires -Version 5.1
<#
.SYNOPSIS
  KQ8 settings launcher - apply options, then start Mask.exe.
  Run from the game folder or pass -GamePath.
#>
param(
  [string]$GamePath = '',
  [switch]$EmergencySkipUi
)

$ErrorActionPreference = 'Stop'

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
  $arg = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
  if ($GamePath) { $arg += @('-GamePath', "`"$GamePath`"") }
  if ($EmergencySkipUi) { $arg += '-EmergencySkipUi' }
  $p = Start-Process powershell.exe -ArgumentList ($arg -join ' ') -Wait -PassThru -NoNewWindow
  exit $p.ExitCode
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Resolve-GameDir([string]$Hint) {
  if ($Hint -and (Test-Path (Join-Path $Hint 'Mask.exe'))) {
    return (Get-ShortGameDir ((Resolve-Path $Hint).Path))
  }
  # Prefer space-free junction (SegMash truncates paths with spaces after cutscenes).
  foreach ($cand in @(
      'D:\Games\KQ8',
      'D:\Games\KQ8\KQ8',
      (Join-Path (Split-Path -Parent $PSCommandPath) '..\KQ8'),
      (Join-Path (Split-Path -Parent $PSCommandPath) 'KQ8')
    )) {
    if ($cand -and (Test-Path (Join-Path $cand 'Mask.exe'))) {
      return (Resolve-Path -LiteralPath $cand).Path
    }
  }
  $here = Split-Path -Parent $PSCommandPath
  if (Test-Path (Join-Path $here 'Mask.exe')) { return (Get-ShortGameDir ((Resolve-Path $here).Path)) }
  $parent = Split-Path -Parent $here
  if (Test-Path (Join-Path $parent 'Mask.exe')) { return (Get-ShortGameDir ((Resolve-Path $parent).Path)) }
  if (Test-Path (Join-Path (Get-Location) 'Mask.exe')) { return (Get-ShortGameDir ((Resolve-Path (Get-Location)).Path)) }
  throw 'Mask.exe not found. Run this launcher from your game folder (or pass -GamePath).'
}

function Get-DefaultSettings {
  [ordered]@{
    version     = 1
    resolution  = 640
    widescreen  = $false
    textureMode = 'stock'
    remember    = $true
    replayIntro = $false
  }
}

function Read-Settings([string]$gameDir) {
  $path = Join-Path $gameDir 'kq8_launcher.json'
  $s = Get-DefaultSettings
  if (-not (Test-Path $path)) { return $s }
  try {
    $j = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $j.resolution) { $s.resolution = [int]$j.resolution }
    if ($null -ne $j.widescreen) { $s.widescreen = [bool]$j.widescreen }
    if ($j.textureMode) { $s.textureMode = [string]$j.textureMode }
    if ($null -ne $j.remember) { $s.remember = [bool]$j.remember }
  } catch { }
  if ($s.resolution -ne 640 -and $s.resolution -ne 800) { $s.resolution = 640 }
  # selective / soft removed from player UI; map old values to stock/global
  if ($s.textureMode -eq 'selective') { $s.textureMode = 'stock' }
  if (@('stock', 'global') -notcontains $s.textureMode) { $s.textureMode = 'stock' }
  return $s
}

function Write-Settings([string]$gameDir, $settings) {
  [pscustomobject]@{
    version     = 1
    resolution  = [int]$settings.resolution
    widescreen  = [bool]$settings.widescreen
    textureMode = [string]$settings.textureMode
    remember    = [bool]$settings.remember
  } | ConvertTo-Json | Set-Content (Join-Path $gameDir 'kq8_launcher.json') -Encoding UTF8
}

function Set-OptionsResolution([string]$gameDir, [int]$resolution) {
  $path = Join-Path $gameDir 'Options.cs'
  $set800 = if ($resolution -eq 800) { 1 } else { 0 }
  if (Test-Path $path) { $lines = @(Get-Content $path) }
  else {
    $lines = @('assignGModeName Glide', 'setBrightness 50', "set800mode $set800")
  }
  $has800 = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    if ($line -match '^\s*set800mode\b') {
      $out.Add("set800mode $set800"); $has800 = $true
    } else { $out.Add($line) }
  }
  if (-not $has800) { $out.Add("set800mode $set800") }
  Set-Content $path $out -Encoding ASCII
}

function Set-WidescreenFlag([string]$gameDir, [bool]$on) {
  $hd = Join-Path $gameDir 'hd_textures'
  if (-not (Test-Path $hd)) { New-Item $hd -ItemType Directory -Force | Out-Null }
  $flag = Join-Path $hd 'widescreen.on'
  if ($on) {
    if (-not (Test-Path $flag)) { Set-Content $flag '' -Encoding ASCII }
  } elseif (Test-Path $flag) { Remove-Item $flag -Force }
}

function Clear-WindowedFlag([string]$gameDir) {
  $flag = Join-Path $gameDir 'hd_textures\windowed.on'
  if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force }
}

function Set-TextureMode([string]$gameDir, [string]$mode) {
  $hd = Join-Path $gameDir 'hd_textures'
  if (-not (Test-Path $hd)) { New-Item $hd -ItemType Directory -Force | Out-Null }
  $auto = Join-Path $hd 'autoscale.on'
  $soft = Join-Path $hd 'autoscale_soft.on'
  $ovr = Join-Path $hd 'overrides.txt'
  $ovrOff = Join-Path $hd 'overrides.txt.off'
  # Soft bilinear removed from player UI; always clear the flag.
  if (Test-Path $soft) { Remove-Item $soft -Force }
  switch ($mode) {
    'global' {
      if (Test-Path $ovr) { Move-Item $ovr $ovrOff -Force }
      if (-not (Test-Path $auto)) { Set-Content $auto '' -Encoding ASCII }
    }
    default {
      # stock: no HD overrides and no global autoscale
      if (Test-Path $auto) { Remove-Item $auto -Force }
      if (Test-Path $ovr) { Move-Item $ovr $ovrOff -Force }
    }
  }
}

function Set-ReplayIntro([string]$gameDir, [bool]$replay) {
  # aviPlayed=0 => play intro on boot. aviPlayed=1 => skip.
  # Always write the flag so a stuck 0 from a crashed run cannot force intro forever.
  $path = Join-Path $gameDir 'main.kq'
  $flag = if ($replay) { '0' } else { '1' }
  if (-not (Test-Path -LiteralPath $path)) {
    @(
      '[Window]'
      'classType=KQMainWindow'
      'x=0'
      'y=0'
      'numRasters=3000'
      'background=0'
      "aviPlayed=$flag"
      'shutDownOK=1'
    ) | Set-Content -LiteralPath $path -Encoding ASCII
    return
  }
  $lines = @(Get-Content -LiteralPath $path)
  $out = New-Object System.Collections.Generic.List[string]
  $foundAvi = $false
  $foundShut = $false
  foreach ($line in $lines) {
    if ($line -match '^\s*aviPlayed\s*=') {
      $out.Add("aviPlayed=$flag"); $foundAvi = $true
    } elseif ($line -match '^\s*shutDownOK\s*=') {
      $out.Add('shutDownOK=1'); $foundShut = $true
    } else {
      $out.Add($line)
    }
  }
  if (-not $foundAvi) {
    $inserted = $false
    $tmp = New-Object System.Collections.Generic.List[string]
    foreach ($line in $out) {
      $tmp.Add($line)
      if (-not $inserted -and $line -match '^\s*background\s*=') {
        $tmp.Add("aviPlayed=$flag"); $inserted = $true
      }
    }
    if (-not $inserted) { $tmp.Add("aviPlayed=$flag") }
    $out = $tmp
  }
  if (-not $foundShut) { $out.Add('shutDownOK=1') }
  Set-Content -LiteralPath $path $out -Encoding ASCII
}

function Test-HasDirectGlide([string]$gameDir) {
  # Our DirectGlide build is ~200-250KB. Stock GOG nGlide is ~1.3MB and ignores hd_textures flags.
  $dll = Join-Path $gameDir 'glide2x.dll'
  if (-not (Test-Path -LiteralPath $dll)) { return $false }
  $len = (Get-Item -LiteralPath $dll).Length
  return ($len -ge 150000 -and $len -le 400000)
}

function Test-HasNGlide([string]$gameDir) {
  $dll = Join-Path $gameDir 'glide2x.dll'
  if (-not (Test-Path -LiteralPath $dll)) { return $false }
  $len = (Get-Item -LiteralPath $dll).Length
  return ($len -gt 400000)
}

function Apply-Settings([string]$gameDir, $settings) {
  Set-OptionsResolution $gameDir ([int]$settings.resolution)
  # Widescreen stretch is DirectGlide-only (hd_textures\widescreen.on).
  # Stock nGlide ignores our aspect env and stays at its own fullscreen stretch.
  $wide = $false
  if ((Test-HasDirectGlide $gameDir) -and $settings -and [bool]$settings.widescreen) {
    $wide = $true
  }
  Set-WidescreenFlag $gameDir $wide
  # Windowed mode removed from launcher UI; always fullscreen.
  Clear-WindowedFlag $gameDir
  Set-TextureMode $gameDir ([string]$settings.textureMode)
  # Always sync aviPlayed so a crashed run cannot leave intro stuck on.
  $replay = $false
  if ($null -ne $settings.replayIntro) { $replay = [bool]$settings.replayIntro }
  Set-ReplayIntro $gameDir $replay
}

function Get-ShortGameDir([string]$gameDir) {
  # SegMash video + game internals break on spaces in the path
  # (crash log showed Command Line truncated at "Kings Quest").
  if ($gameDir -notmatch '\s') { return $gameDir }
  $parent = Split-Path -Parent $gameDir
  $junction = Join-Path $parent 'KQ8'
  if ((Test-Path -LiteralPath (Join-Path $junction 'Mask.exe'))) {
    return (Resolve-Path -LiteralPath $junction).Path
  }
  return $gameDir
}

function Start-CutsceneWatchdog([string]$gameDir) {
  # Backup for mid-game / ending clips (kq8fix ShellExecuteEx + /close).
  $watch = Join-Path $gameDir 'close_player_after.ps1'
  if (-not (Test-Path -LiteralPath $watch)) { return }
  $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$watch`" -WatchMask"
  Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $argLine | Out-Null
}

function Test-NeedsBootIntro([string]$gameDir, $settings) {
  if ($settings -and $settings.replayIntro) { return $true }
  $path = Join-Path $gameDir 'main.kq'
  if (-not (Test-Path -LiteralPath $path)) { return $true }
  $line = Select-String -LiteralPath $path -Pattern '^\s*aviPlayed\s*=\s*(\d+)' | Select-Object -First 1
  if (-not $line) { return $true }
  return ([int]$line.Matches[0].Groups[1].Value -eq 0)
}

function Get-AviDurationSecondsLocal([string]$path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { return 0 }
  try {
    $shell = New-Object -ComObject Shell.Application
    $dir = Split-Path -LiteralPath $path
    $name = Split-Path -LiteralPath $path -Leaf
    $folder = $shell.NameSpace($dir)
    if (-not $folder) { return 0 }
    $file = $folder.ParseName($name)
    if (-not $file) { return 0 }
    $raw = $folder.GetDetailsOf($file, 27)
    if ($raw -match '^(?:(\d+):)?(\d{1,2}):(\d{2})$') {
      $h = if ($Matches[1]) { [int]$Matches[1] } else { 0 }
      return ($h * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3])
    }
  } catch { }
  return 0
}

function Maximize-WmpWindows {
  Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Kq8MaxWmp {
  public delegate bool Cb(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Cb lp, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public const int SW_SHOWMAXIMIZED = 3;
}
"@ -ErrorAction SilentlyContinue
  [Kq8MaxWmp]::EnumWindows({
    param($h, $l)
    if (-not [Kq8MaxWmp]::IsWindowVisible($h)) { return $true }
    $sb = New-Object Text.StringBuilder 256
    [void][Kq8MaxWmp]::GetWindowText($h, $sb, 256)
    $t = $sb.ToString()
    if ($t -match 'Windows Media Player|\.avi') {
      [void][Kq8MaxWmp]::ShowWindow($h, [Kq8MaxWmp]::SW_SHOWMAXIMIZED)
      [void][Kq8MaxWmp]::SetForegroundWindow($h)
    }
    return $true
  }, [IntPtr]::Zero) | Out-Null
}

function Find-CutscenePlayer([string]$gameDir) {
  foreach ($rel in @('mpv.exe', 'player\mpv.exe')) {
    $p = Join-Path $gameDir $rel
    if (Test-Path -LiteralPath $p) { return @{ Path = $p; Kind = 'mpv' } }
  }
  foreach ($c in @(
      (Join-Path $env:ProgramFiles 'Windows Media Player\wmplayer.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'Windows Media Player\wmplayer.exe')
    )) {
    if ($c -and (Test-Path -LiteralPath $c)) { return @{ Path = $c; Kind = 'wmp' } }
  }
  return $null
}

function Play-BootIntro([string]$gameDir) {
  # H.264 intro via shipped mpv (preferred) before Mask/DirectGlide exists.
  $avi = Join-Path $gameDir 'w32opn_1.avi'
  if (-not (Test-Path -LiteralPath $avi)) {
    $avi = Join-Path $gameDir 'W32opn_1.avi'
  }
  if (-not (Test-Path -LiteralPath $avi)) {
    throw 'Boot intro AVI missing (w32opn_1.avi). Re-run Setup to install cutscene files.'
  }
  $player = Find-CutscenePlayer $gameDir
  if (-not $player) {
    throw 'No cutscene player found (mpv.exe in game folder, or Windows Media Player Legacy).'
  }

  if ($player.Kind -eq 'mpv') {
    $argLine = "--fullscreen --ontop --keep-open=no --force-window=immediate --no-osc --really-quiet --d3d11-exclusive-fs=no `"$avi`""
  } else {
    $argLine = "/play /close `"$avi`""
  }
  $p = Start-Process -FilePath $player.Path -ArgumentList $argLine -WorkingDirectory $gameDir -PassThru
  if (-not $p) { throw "Failed to start cutscene player ($($player.Kind))." }

  $dur = Get-AviDurationSecondsLocal $avi
  if ($dur -le 0) { $dur = 107 }
  $waitMs = [Math]::Min(($dur + 4) * 1000, 200000)

  $t0 = Get-Date
  while (-not $p.HasExited -and (((Get-Date) - $t0).TotalMilliseconds -lt $waitMs)) {
    if ($player.Kind -eq 'wmp' -and (((Get-Date) - $t0).TotalSeconds -lt 6)) {
      Maximize-WmpWindows
    }
    Start-Sleep -Milliseconds 500
    try { $p.Refresh() } catch { }
  }
  if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 300
  if ($player.Kind -eq 'wmp') {
    Get-Process -Name 'wmplayer' -ErrorAction SilentlyContinue |
      Stop-Process -Force -ErrorAction SilentlyContinue
  } else {
    Get-Process -Name 'mpv' -ErrorAction SilentlyContinue |
      Stop-Process -Force -ErrorAction SilentlyContinue
  }
}

function Start-Game([string]$gameDir, $settings) {
  $launchDir = Get-ShortGameDir $gameDir
  $mask = Join-Path $launchDir 'Mask.exe'
  if (-not (Test-Path $mask)) { throw "Mask.exe missing in $launchDir" }

  $playIntro = Test-NeedsBootIntro $launchDir $settings
  if ($playIntro) {
    Play-BootIntro $launchDir
    # Mask must skip its own boot AVI after the launcher played it.
    Set-ReplayIntro $launchDir $false
  }

  $prev = $env:__COMPAT_LAYER
  $env:__COMPAT_LAYER = '!'
  try {
    Start-CutsceneWatchdog $launchDir
    Start-Process -FilePath $mask -WorkingDirectory $launchDir
  } finally {
    if ([string]::IsNullOrEmpty($prev)) {
      Remove-Item Env:\__COMPAT_LAYER -ErrorAction SilentlyContinue
    } else { $env:__COMPAT_LAYER = $prev }
  }
}

# --- main ---
$script:gameDir = Resolve-GameDir $GamePath
$settings = Read-Settings $script:gameDir

if ($EmergencySkipUi) {
  Apply-Settings $script:gameDir $settings
  Start-Game $script:gameDir $settings
  exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "King's Quest 8 - Launcher"
$form.ClientSize = New-Object System.Drawing.Size(500, 510)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'
$bottom.Height = 92
$form.Controls.Add($bottom)

$script:status = New-Object System.Windows.Forms.Label
$script:status.Location = New-Object System.Drawing.Point(12, 8)
$script:status.Size = New-Object System.Drawing.Size(476, 20)
$script:status.Text = 'Choose settings, then click Play.'
$bottom.Controls.Add($script:status)

$btnPlay = New-Object System.Windows.Forms.Button
$btnPlay.Location = New-Object System.Drawing.Point(12, 36)
$btnPlay.Size = New-Object System.Drawing.Size(140, 42)
$btnPlay.Text = 'Play'
$btnPlay.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$bottom.Controls.Add($btnPlay)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Location = New-Object System.Drawing.Point(164, 36)
$btnSave.Size = New-Object System.Drawing.Size(140, 42)
$btnSave.Text = 'Save settings'
$bottom.Controls.Add($btnSave)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Location = New-Object System.Drawing.Point(316, 36)
$btnClose.Size = New-Object System.Drawing.Size(140, 42)
$btnClose.Text = 'Close'
$bottom.Controls.Add($btnClose)

$body = New-Object System.Windows.Forms.Panel
$body.Dock = 'Fill'
$body.AutoScroll = $true
$form.Controls.Add($body)
$body.BringToFront()
$bottom.BringToFront()

$y = 10
function Add-Body([string]$text, [int]$h = 22) {
  $l = New-Object System.Windows.Forms.Label
  $l.Location = New-Object System.Drawing.Point(12, $script:y)
  $l.Size = New-Object System.Drawing.Size(460, $h)
  $l.Text = $text
  $body.Controls.Add($l)
  $script:y += ($h + 6)
}

Add-Body "Game: $($script:gameDir)" 28

$script:hasDg = Test-HasDirectGlide $script:gameDir
$script:hasNGlide = Test-HasNGlide $script:gameDir
if ($script:hasDg) {
  Add-Body 'DirectGlide is active (sharper upscaling). Cutscenes use mpv (a small video player in the game folder).' 36
} elseif ($script:hasNGlide) {
  Add-Body 'Stock GOG nGlide (original graphics). Widescreen and texture options need DirectGlide (re-run Setup, Recommended).' 36
} else {
  Add-Body 'No known Glide wrapper detected. Re-run Setup KQ8 Fix.' 28
}

if ($script:gameDir -match '(?i)Program Files') {
  Add-Body 'Warning: Program Files path often crashes at New Game (copying files). Prefer a short copy like C:\Games\KQ8.' 36
}

Add-Body 'Resolution' 18
$script:rb640 = New-Object System.Windows.Forms.RadioButton
$script:rb640.Location = New-Object System.Drawing.Point(16, $y)
$script:rb640.Size = New-Object System.Drawing.Size(200, 22)
$script:rb640.Text = '640x480 (recommended)'
$script:rb640.Checked = ($settings.resolution -eq 640)
$body.Controls.Add($script:rb640)
$script:rb800 = New-Object System.Windows.Forms.RadioButton
$script:rb800.Location = New-Object System.Drawing.Point(230, $y)
$script:rb800.Size = New-Object System.Drawing.Size(220, 22)
$script:rb800.Text = '800x600 (experimental)'
$script:rb800.Checked = ($settings.resolution -eq 800)
$body.Controls.Add($script:rb800)
$y += 28

$script:chkRemember = New-Object System.Windows.Forms.CheckBox
$script:chkRemember.Location = New-Object System.Drawing.Point(16, $y)
$script:chkRemember.Size = New-Object System.Drawing.Size(450, 22)
$script:chkRemember.Text = 'Remember my settings for next time'
$script:chkRemember.Checked = [bool]$settings.remember
$body.Controls.Add($script:chkRemember)
$y += 26

$script:chkIntro = New-Object System.Windows.Forms.CheckBox
$script:chkIntro.Location = New-Object System.Drawing.Point(16, $y)
$script:chkIntro.Size = New-Object System.Drawing.Size(450, 22)
$script:chkIntro.Text = 'Replay intro this launch (plays in mpv before the game)'
$script:chkIntro.Checked = $false
$body.Controls.Add($script:chkIntro)
$y += 28

$script:lblMpv = New-Object System.Windows.Forms.Label
$script:lblMpv.Location = New-Object System.Drawing.Point(16, $y)
$script:lblMpv.Size = New-Object System.Drawing.Size(450, 28)
$mpvOk = Test-Path -LiteralPath (Join-Path $script:gameDir 'mpv.exe')
if ($mpvOk) {
  $script:lblMpv.ForeColor = [System.Drawing.Color]::DarkGreen
  $script:lblMpv.Text = 'Cutscene player: mpv.exe found.'
} else {
  $script:lblMpv.ForeColor = [System.Drawing.Color]::DarkRed
  $script:lblMpv.Text = 'Cutscene player: mpv.exe missing - re-run Setup KQ8 Fix.'
}
$body.Controls.Add($script:lblMpv)
$y += 34

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Location = New-Object System.Drawing.Point(12, $y)
$grp.Size = New-Object System.Drawing.Size(460, 148)
$grp.Text = 'Advanced'
$body.Controls.Add($grp)

$advY = 20
$lblAdv = New-Object System.Windows.Forms.Label
$lblAdv.Location = New-Object System.Drawing.Point(12, $advY)
$lblAdv.Size = New-Object System.Drawing.Size(430, 20)
if ($script:hasDg) {
  $lblAdv.Text = 'DirectGlide options for this install.'
} else {
  $lblAdv.Text = 'Needs DirectGlide (re-run Setup, Recommended).'
  $lblAdv.ForeColor = [System.Drawing.Color]::DimGray
}
$grp.Controls.Add($lblAdv)
$advY += 24

$script:chkWide = New-Object System.Windows.Forms.CheckBox
$script:chkWide.Location = New-Object System.Drawing.Point(12, $advY)
$script:chkWide.Size = New-Object System.Drawing.Size(430, 22)
$script:chkWide.Text = 'Widescreen stretch'
$script:chkWide.Enabled = $script:hasDg
$script:chkWide.Checked = $script:hasDg -and [bool]$settings.widescreen
$grp.Controls.Add($script:chkWide)
$advY += 26

$script:rbTexStock = New-Object System.Windows.Forms.RadioButton
$script:rbTexStock.Location = New-Object System.Drawing.Point(12, $advY)
$script:rbTexStock.Size = New-Object System.Drawing.Size(430, 20)
$script:rbTexStock.Text = 'Stock textures'
$script:rbTexStock.Enabled = $script:hasDg
$grp.Controls.Add($script:rbTexStock)
$advY += 22

$script:rbTexGlobal = New-Object System.Windows.Forms.RadioButton
$script:rbTexGlobal.Location = New-Object System.Drawing.Point(12, $advY)
$script:rbTexGlobal.Size = New-Object System.Drawing.Size(430, 20)
$script:rbTexGlobal.Text = 'Global 4x autoscale'
$script:rbTexGlobal.Enabled = $script:hasDg
$grp.Controls.Add($script:rbTexGlobal)
$advY += 22

$script:rbTexCustom = New-Object System.Windows.Forms.RadioButton
$script:rbTexCustom.Location = New-Object System.Drawing.Point(12, $advY)
$script:rbTexCustom.Size = New-Object System.Drawing.Size(430, 20)
$script:rbTexCustom.Text = 'Custom textures (coming soon)'
$script:rbTexCustom.Enabled = $false
$grp.Controls.Add($script:rbTexCustom)

if ($script:hasDg -and $settings.textureMode -eq 'global') {
  $script:rbTexGlobal.Checked = $true
} else {
  $script:rbTexStock.Checked = $true
}

$form.AcceptButton = $btnPlay
$form.CancelButton = $btnClose

function Get-UiSettings {
  $tex = 'stock'
  if ($script:hasDg -and $script:rbTexGlobal.Checked) { $tex = 'global' }
  return [ordered]@{
    version     = 1
    resolution  = $(if ($script:rb800.Checked) { 800 } else { 640 })
    widescreen  = [bool]($script:hasDg -and $script:chkWide.Checked)
    textureMode = $tex
    remember    = [bool]$script:chkRemember.Checked
    replayIntro = [bool]$script:chkIntro.Checked
  }
}

$btnSave.Add_Click({
  try {
    $s = Get-UiSettings
    if ($s.remember) { Write-Settings $script:gameDir $s }
    Apply-Settings $script:gameDir $s
    if ($s.replayIntro) {
      $script:status.Text = 'Saved. Play will show the intro in mpv, then start the game.'
    } else {
      $script:status.Text = 'Saved. Click Play to start the game.'
    }
    $script:status.ForeColor = [System.Drawing.Color]::DarkGreen
  } catch {
    [System.Windows.Forms.MessageBox]::Show("$_", 'Save failed', 'OK', 'Error') | Out-Null
  }
})

$btnPlay.Add_Click({
  try {
    if (-not (Test-Path -LiteralPath (Join-Path $script:gameDir 'mpv.exe'))) {
      $ans = [System.Windows.Forms.MessageBox]::Show(
        "mpv.exe is missing from the game folder.`nRe-run Setup KQ8 Fix to install the cutscene player.`n`nPlay anyway?",
        'Cutscene player', 'YesNo', 'Warning')
      if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    $s = Get-UiSettings
    if ($s.remember) { Write-Settings $script:gameDir $s }
    # Skip writing aviPlayed=0 into main.kq when replaying - launcher plays
    # the AVI itself, then forces aviPlayed=1 before Mask starts.
    $apply = [ordered]@{}
    foreach ($k in $s.Keys) { $apply[$k] = $s[$k] }
    if ($apply.replayIntro) { $apply.replayIntro = $false }
    Apply-Settings $script:gameDir $apply
    $script:status.Text = if ($s.replayIntro) { 'Playing intro...' } else { 'Starting...' }
    $script:status.ForeColor = [System.Drawing.Color]::DarkBlue
    [System.Windows.Forms.Application]::DoEvents()
    Start-Game $script:gameDir $s
    $form.Close()
  } catch {
    [System.Windows.Forms.MessageBox]::Show("$_", 'Launch failed', 'OK', 'Error') | Out-Null
  }
})

$btnClose.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
