#Requires -Version 5.1
<#
.SYNOPSIS
  Setup GUI for KQ8 Win11 Fix - install and uninstall.
  Launch via Setup KQ8 Fix.bat (STA).
#>
param([string]$PackageRoot = '')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptDir = $PSScriptRoot
if (-not $PackageRoot) {
  $repo = (Resolve-Path (Join-Path $ScriptDir '..')).Path
  $rel = Join-Path $repo 'release\KQ8-Fix'
  if (Test-Path (Join-Path $rel 'runtime\win11')) { $PackageRoot = $rel }
  elseif (Test-Path (Join-Path $ScriptDir '..\runtime\win11')) {
    $PackageRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path
  } else { $PackageRoot = $repo }
}
$CoreInstaller = Join-Path $ScriptDir 'Install-Kq8Hd.ps1'
if (-not (Test-Path $CoreInstaller)) {
  $CoreInstaller = Join-Path $PackageRoot 'tools\Install-Kq8Hd.ps1'
}
if (-not (Test-Path $CoreInstaller)) { throw "Install-Kq8Hd.ps1 not found" }

function Get-GogKq8Path {
  foreach ($k in @(
      'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1207661053',
      'HKLM:\SOFTWARE\GOG.com\Games\1207661053',
      'HKCU:\SOFTWARE\GOG.com\Games\1207661053'
    )) {
    if (-not (Test-Path $k)) { continue }
    $p = (Get-ItemProperty $k -EA SilentlyContinue).PATH
    if ($p -and (Test-Path (Join-Path $p 'Mask.exe'))) { return $p }
    $exe = (Get-ItemProperty $k -EA SilentlyContinue).EXE
    if ($exe -and (Test-Path $exe)) { return (Split-Path $exe -Parent) }
  }
  foreach ($root in @(
      "${env:ProgramFiles(x86)}\GOG Galaxy\Games",
      "$env:ProgramFiles\GOG Galaxy\Games",
      'D:\Games', 'C:\Games'
    ) | Where-Object { $_ -and (Test-Path $_) }) {
    $hit = Get-ChildItem $root -Recurse -Filter 'Mask.exe' -EA SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.DirectoryName }
  }
  return $null
}

function Test-GameDir([string]$path) {
  return ($path -and (Test-Path (Join-Path $path 'Mask.exe')))
}

function Test-IsElevated {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsProgramFilesPath([string]$path) {
  return ($path -and ($path -match '(?i)Program Files'))
}

function Test-FolderWritable([string]$path) {
  if (-not $path -or -not (Test-Path $path)) { return $false }
  $probe = Join-Path $path ('.kq8_write_test_' + [guid]::NewGuid().ToString('N'))
  try {
    [IO.File]::WriteAllText($probe, 'ok')
    Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
    return $true
  } catch { return $false }
}

function Test-MpvInPackageGui {
  $p = Join-Path $PackageRoot 'runtime\win11\mpv.exe'
  return (Test-Path -LiteralPath $p)
}

function Invoke-Core {
  param(
    [string]$GamePath,
    [string]$Action,
    [string]$DirectGlide = 'off',
    [string]$Resolution = '640',
    [string]$Shortcut = 'on',
    [bool]$Elevate = $false
  )
  $argLine = @(
    '-NoProfile -STA -ExecutionPolicy Bypass',
    "-File `"$CoreInstaller`"",
    "-Action $Action",
    "-GamePath `"$GamePath`"",
    "-DirectGlide $DirectGlide",
    "-Resolution $Resolution",
    '-Widescreen off',
    "-Shortcut $Shortcut",
    '-NonInteractive'
  ) -join ' '
  if ($Elevate) {
    return Start-Process powershell.exe -ArgumentList $argLine -Verb RunAs -Wait -PassThru
  }
  return Start-Process powershell.exe -ArgumentList $argLine -Wait -PassThru -NoNewWindow
}

# --- form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'KQ8 Win11 Fix - Setup'
$form.ClientSize = New-Object System.Drawing.Size(560, 820)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.AutoScroll = $true

$y = 12
function Add-L([string]$text, [int]$h = 20) {
  $l = New-Object System.Windows.Forms.Label
  $l.Location = New-Object System.Drawing.Point(16, $script:y)
  $l.Size = New-Object System.Drawing.Size(508, $h)
  $l.Text = $text
  $form.Controls.Add($l)
  $script:y += ($h + 4)
  return $l
}

Add-L "Install the Windows 11 fix and settings launcher into your Mask of Eternity folder.`nDoes not include the game. Safe to run again." 36 | Out-Null
Add-L 'Game folder (must contain Mask.exe)' 18 | Out-Null

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(16, $y)
$txtPath.Size = New-Object System.Drawing.Size(400, 24)
$form.Controls.Add($txtPath)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(424, $y)
$btnBrowse.Size = New-Object System.Drawing.Size(100, 26)
$btnBrowse.Text = 'Browse...'
$form.Controls.Add($btnBrowse)
$y += 34

$btnDetect = New-Object System.Windows.Forms.Button
$btnDetect.Location = New-Object System.Drawing.Point(16, $y)
$btnDetect.Size = New-Object System.Drawing.Size(160, 28)
$btnDetect.Text = 'Detect GOG install'
$form.Controls.Add($btnDetect)
$lblDetect = New-Object System.Windows.Forms.Label
$lblDetect.Location = New-Object System.Drawing.Point(186, $y)
$lblDetect.Size = New-Object System.Drawing.Size(338, 28)
$lblDetect.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblDetect)
$y += 34

$lblAdmin = New-Object System.Windows.Forms.Label
$lblAdmin.Location = New-Object System.Drawing.Point(16, $y)
$lblAdmin.Size = New-Object System.Drawing.Size(508, 56)
$lblAdmin.ForeColor = [System.Drawing.Color]::DarkRed
$form.Controls.Add($lblAdmin)
$y += 60

$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Location = New-Object System.Drawing.Point(16, $y)
$grpMode.Size = New-Object System.Drawing.Size(520, 86)
$grpMode.Text = 'Graphics'
$form.Controls.Add($grpMode)

$rbRec = New-Object System.Windows.Forms.RadioButton
$rbRec.Location = New-Object System.Drawing.Point(12, 22)
$rbRec.Size = New-Object System.Drawing.Size(492, 22)
$rbRec.Text = 'Recommended - Sharper fullscreen; widescreen and textures in Settings'
$rbRec.Checked = $true
$grpMode.Controls.Add($rbRec)

$rbFixOnly = New-Object System.Windows.Forms.RadioButton
$rbFixOnly.Location = New-Object System.Drawing.Point(12, 48)
$rbFixOnly.Size = New-Object System.Drawing.Size(492, 22)
$rbFixOnly.Text = 'Windows fix only - Original GOG graphics (keeps nGlide)'
$grpMode.Controls.Add($rbFixOnly)
$y += 94

$grpStack = New-Object System.Windows.Forms.GroupBox
$grpStack.Location = New-Object System.Drawing.Point(16, $y)
$grpStack.Size = New-Object System.Drawing.Size(520, 214)
$grpStack.Text = 'This install will add or replace'
$form.Controls.Add($grpStack)

$lblStack = New-Object System.Windows.Forms.Label
$lblStack.Location = New-Object System.Drawing.Point(12, 22)
$lblStack.Size = New-Object System.Drawing.Size(492, 182)
$lblStack.ForeColor = [System.Drawing.Color]::DimGray
$grpStack.Controls.Add($lblStack)
$y += 222

function Update-InstallStack {
  if ($rbRec.Checked) {
    $gfx = '- Graphics: DirectGlide glide2x.dll (replaces GOG nGlide)'
  } else {
    $gfx = '- Graphics: keeps your existing GOG glide2x.dll (not replaced)'
  }
  $lblStack.Text = @(
    $gfx,
    '- Win11 fix (NicoDE kq8fix): kq8fix.exe, kq8fix.dll, kq8fix.ini',
    '- Cutscenes: mpv.exe, d3dcompiler_43.dll, w32opn_1.avi, W32mdl_1.avi, W32ndg_1.avi, mpv license files',
    '- Launcher: Launch KQ8.bat, Launch KQ8 Emergency.bat, Launch-Kq8.ps1, icon, settings file',
    '- Backup: replaced game files go under backup_kq8fix_*',
    '- Uninstall: restores your backed-up files and removes all files added by this installer (choices above do not affect Uninstall).'
  ) -join "`n"
}

$rbRec.Add_CheckedChanged({ Update-InstallStack })
$rbFixOnly.Add_CheckedChanged({ Update-InstallStack })
Update-InstallStack

$grpRes = New-Object System.Windows.Forms.GroupBox
$grpRes.Location = New-Object System.Drawing.Point(16, $y)
$grpRes.Size = New-Object System.Drawing.Size(520, 52)
$grpRes.Text = 'Resolution'
$form.Controls.Add($grpRes)

$rb640 = New-Object System.Windows.Forms.RadioButton
$rb640.Location = New-Object System.Drawing.Point(12, 22)
$rb640.Size = New-Object System.Drawing.Size(220, 20)
$rb640.Text = '640x480 (recommended)'
$rb640.Checked = $true
$grpRes.Controls.Add($rb640)
$rb800 = New-Object System.Windows.Forms.RadioButton
$rb800.Location = New-Object System.Drawing.Point(250, 22)
$rb800.Size = New-Object System.Drawing.Size(240, 20)
$rb800.Text = '800x600 (experimental)'
$grpRes.Controls.Add($rb800)
$y += 60

$chkShortcut = New-Object System.Windows.Forms.CheckBox
$chkShortcut.Location = New-Object System.Drawing.Point(16, $y)
$chkShortcut.Size = New-Object System.Drawing.Size(520, 24)
$chkShortcut.Text = 'Create a desktop shortcut to the settings launcher'
$chkShortcut.Checked = $true
$form.Controls.Add($chkShortcut)
$y += 30

if (-not (Test-MpvInPackageGui)) {
  $lblMpv = New-Object System.Windows.Forms.Label
  $lblMpv.Location = New-Object System.Drawing.Point(16, $y)
  $lblMpv.Size = New-Object System.Drawing.Size(520, 36)
  $lblMpv.ForeColor = [System.Drawing.Color]::DarkRed
  $lblMpv.Text = "ERROR: mpv.exe is missing from this package (runtime\win11\mpv.exe).`nAdd it before Install. Setup does not download files."
  $form.Controls.Add($lblMpv)
  $y += 40
}

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(16, $y)
$status.Size = New-Object System.Drawing.Size(520, 22)
$status.Text = "Package: $PackageRoot"
$form.Controls.Add($status)
$y += 28

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Location = New-Object System.Drawing.Point(16, $y)
$btnInstall.Size = New-Object System.Drawing.Size(140, 36)
$btnInstall.Text = 'Install'
$btnInstall.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Location = New-Object System.Drawing.Point(168, $y)
$btnUninstall.Size = New-Object System.Drawing.Size(140, 36)
$btnUninstall.Text = 'Uninstall'
$form.Controls.Add($btnUninstall)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Location = New-Object System.Drawing.Point(320, $y)
$btnCancel.Size = New-Object System.Drawing.Size(120, 36)
$btnCancel.Text = 'Cancel'
$form.Controls.Add($btnCancel)

$form.AcceptButton = $btnInstall
$form.CancelButton = $btnCancel

function Update-AdminBanner {
  $path = $txtPath.Text.Trim().Trim('"')
  if (Test-IsProgramFilesPath $path) {
    $lblAdmin.ForeColor = [System.Drawing.Color]::DarkRed
    $adminBit = if (Test-IsElevated) {
      'Admin OK for writing files.'
    } else {
      'Use Run as administrator (or allow UAC) to write files.'
    }
    $lblAdmin.Text = "Program Files / GOG path: New Game often crashes while copying worlds.`nPrefer a short copy like C:\Games\KQ8. $adminBit"
  } elseif ($path -and (Test-Path (Join-Path $path 'Mask.exe'))) {
    $lblAdmin.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblAdmin.Text = 'Short game path looks good for New Game.'
  } else {
    $lblAdmin.Text = ''
  }
}

$detected = Get-GogKq8Path
if ($detected) {
  $txtPath.Text = $detected
  $lblDetect.Text = 'GOG path found (you can change it).'
  $lblDetect.ForeColor = [System.Drawing.Color]::DarkGreen
} elseif (Test-Path 'D:\Games\KQ8\KQ8\Mask.exe') {
  $txtPath.Text = 'D:\Games\KQ8\KQ8'
  $lblDetect.Text = 'Using D:\Games\KQ8\KQ8 (space-free junction)'
} elseif (Test-Path 'D:\Games\KQ8\Kings Quest 8\Mask.exe') {
  $txtPath.Text = 'D:\Games\KQ8\Kings Quest 8'
  $lblDetect.Text = 'Using D:\Games\KQ8\Kings Quest 8 (prefer D:\Games\KQ8\KQ8)'
} elseif (Test-Path 'D:\Games\KQ8\Mask.exe') {
  $txtPath.Text = 'D:\Games\KQ8'
  $lblDetect.Text = 'Using D:\Games\KQ8'
}
Update-AdminBanner

$txtPath.Add_TextChanged({ Update-AdminBanner })

$btnDetect.Add_Click({
  $p = Get-GogKq8Path
  if ($p) {
    $txtPath.Text = $p
    $lblDetect.Text = 'Detected.'
    $lblDetect.ForeColor = [System.Drawing.Color]::DarkGreen
  } else {
    $lblDetect.Text = 'Not found. Use Browse.'
    $lblDetect.ForeColor = [System.Drawing.Color]::DarkRed
  }
  Update-AdminBanner
})

$btnBrowse.Add_Click({
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = 'Select Mask.exe'
  $dlg.Filter = 'Mask of Eternity|Mask.exe|All files|*.*'
  $dlg.FileName = 'Mask.exe'
  if ($txtPath.Text -and (Test-Path $txtPath.Text)) { $dlg.InitialDirectory = $txtPath.Text }
  if ($dlg.ShowDialog() -eq 'OK') {
    $txtPath.Text = [IO.Path]::GetDirectoryName($dlg.FileName)
  }
  Update-AdminBanner
})

$btnCancel.Add_Click({ $form.Close() })

function Ensure-Elevate([string]$gamePath) {
  if (Test-FolderWritable $gamePath) { return $false }
  if (Test-IsElevated) {
    throw "Cannot write to:`n$gamePath"
  }
  $r = [System.Windows.Forms.MessageBox]::Show(
    "Need Administrator permission to modify:`n$gamePath`n`nContinue (UAC)?",
    'Permission needed', 'YesNo', 'Warning')
  if ($r -ne 'Yes') { return $null }
  return $true
}

$btnInstall.Add_Click({
  try {
    $gamePath = $txtPath.Text.Trim().Trim('"')
    if (-not (Test-GameDir $gamePath)) {
      [System.Windows.Forms.MessageBox]::Show("Mask.exe not found in:`n$gamePath", 'Invalid folder', 'OK', 'Warning') | Out-Null
      return
    }
    $elevate = Ensure-Elevate $gamePath
    if ($null -eq $elevate) { return }

    if (-not (Test-MpvInPackageGui)) {
      [System.Windows.Forms.MessageBox]::Show(
        "mpv.exe is missing from this package.`nExpected: runtime\win11\mpv.exe",
        'Package incomplete', 'OK', 'Error') | Out-Null
      return
    }

    $dg = if ($rbRec.Checked) { 'on' } else { 'off' }
    $res = if ($rb800.Checked) { '800' } else { '640' }
    $short = if ($chkShortcut.Checked) { 'on' } else { 'off' }

    $btnInstall.Enabled = $false; $btnUninstall.Enabled = $false
    $status.Text = 'Installing...'
    $status.ForeColor = [System.Drawing.Color]::DarkBlue
    $form.Refresh()

    $p = Invoke-Core -GamePath $gamePath -Action install -DirectGlide $dg -Resolution $res -Shortcut $short `
      -Elevate:$elevate
    if ($null -eq $p) { throw 'Cancelled at UAC.' }
    if ($p.ExitCode -ne 0) { throw "Installer exited with code $($p.ExitCode)." }

    $status.Text = 'Install complete.'
    $status.ForeColor = [System.Drawing.Color]::DarkGreen
    [System.Windows.Forms.MessageBox]::Show(
      "Installed. Play with Launch KQ8 (desktop shortcut or game folder).",
      'Setup complete', 'OK', 'Information') | Out-Null
    $form.Close()
  } catch {
    $btnInstall.Enabled = $true; $btnUninstall.Enabled = $true
    $status.Text = "Failed: $_"
    $status.ForeColor = [System.Drawing.Color]::DarkRed
    [System.Windows.Forms.MessageBox]::Show("$_", 'Install failed', 'OK', 'Error') | Out-Null
  }
})

$btnUninstall.Add_Click({
  try {
    $gamePath = $txtPath.Text.Trim().Trim('"')
    if (-not (Test-GameDir $gamePath)) {
      [System.Windows.Forms.MessageBox]::Show("Mask.exe not found in:`n$gamePath", 'Invalid folder', 'OK', 'Warning') | Out-Null
      return
    }
    $c = [System.Windows.Forms.MessageBox]::Show(
      "Remove the Win11 fix from this game folder and restore the latest backup?",
      'Uninstall', 'YesNo', 'Warning')
    if ($c -ne 'Yes') { return }

    $elevate = Ensure-Elevate $gamePath
    if ($null -eq $elevate) { return }

    $btnInstall.Enabled = $false; $btnUninstall.Enabled = $false
    $status.Text = 'Uninstalling...'
    $status.ForeColor = [System.Drawing.Color]::DarkBlue
    $form.Refresh()

    $p = Invoke-Core -GamePath $gamePath -Action uninstall -Elevate:$elevate
    if ($null -eq $p) { throw 'Cancelled at UAC.' }
    if ($p.ExitCode -ne 0) { throw "Uninstaller exited with code $($p.ExitCode). Need a backup_kq8fix_* folder." }

    $status.Text = 'Uninstall complete.'
    $status.ForeColor = [System.Drawing.Color]::DarkGreen
    [System.Windows.Forms.MessageBox]::Show('Uninstall finished. Latest backup was restored.', 'Done', 'OK', 'Information') | Out-Null
    $btnInstall.Enabled = $true; $btnUninstall.Enabled = $true
  } catch {
    $btnInstall.Enabled = $true; $btnUninstall.Enabled = $true
    $status.Text = "Failed: $_"
    $status.ForeColor = [System.Drawing.Color]::DarkRed
    [System.Windows.Forms.MessageBox]::Show("$_", 'Uninstall failed', 'OK', 'Error') | Out-Null
  }
})

[void]$form.ShowDialog()
