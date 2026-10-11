#Requires -Version 5.1
<#
.SYNOPSIS
  Companion for SegMash/NicoDE kq8fix video playback on Win11.

  kq8fix launches Legacy WMP with /play /close and waits until the player
  WINDOW closes. If /close is ignored, this watcher force-closes the player
  shortly after the clip duration so Mask can resume.
#>
param(
  [string]$AviPath = '',
  [int]$Seconds = 0,
  [switch]$WatchMask
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-AviDurationSeconds([string]$path) {
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

function Get-PlayerAviPath {
  try {
    Get-CimInstance Win32_Process -Filter "Name = 'wmplayer.exe'" | ForEach-Object {
      $cl = [string]$_.CommandLine
      if ($cl -match '"([^"]+\.avi)"') { return $Matches[1] }
      if ($cl -match '(\S+\.avi)') { return $Matches[1] }
    }
  } catch { }
  return ''
}

function Test-MediaPlayerRunning {
  if (Get-Process -Name 'wmplayer', 'Microsoft.Media.Player', 'Video.UI' -ErrorAction SilentlyContinue) {
    return $true
  }
  try {
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Kq8FindPlayer {
  public delegate bool Cb(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Cb lp, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static bool Found;
}
"@ -ErrorAction SilentlyContinue
    [Kq8FindPlayer]::Found = $false
    [Kq8FindPlayer]::EnumWindows({
      param($h, $l)
      if (-not [Kq8FindPlayer]::IsWindowVisible($h)) { return $true }
      $sb = New-Object Text.StringBuilder 256
      [void][Kq8FindPlayer]::GetWindowText($h, $sb, 256)
      $t = $sb.ToString()
      if ($t -match 'Windows Media Player|Media Player|\.avi|Films & TV|Movies & TV') {
        [Kq8FindPlayer]::Found = $true
        return $false
      }
      return $true
    }, [IntPtr]::Zero) | Out-Null
    return [Kq8FindPlayer]::Found
  } catch { return $false }
}

function Test-MaskRunning {
  return [bool](Get-Process -Name 'Mask' -ErrorAction SilentlyContinue)
}

function Stop-MediaPlayers {
  Get-Process -Name 'wmplayer', 'Microsoft.Media.Player', 'Video.UI' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

  Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Kq8ClosePlayer3 {
  public delegate bool Cb(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Cb lp, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@ -ErrorAction SilentlyContinue

  $killPids = New-Object 'System.Collections.Generic.HashSet[int]'
  [Kq8ClosePlayer3]::EnumWindows({
    param($h, $l)
    if (-not [Kq8ClosePlayer3]::IsWindowVisible($h)) { return $true }
    $sb = New-Object Text.StringBuilder 256
    [void][Kq8ClosePlayer3]::GetWindowText($h, $sb, 256)
    $t = $sb.ToString()
    if ($t -match 'Windows Media Player|Media Player|\.avi|Films & TV|Movies & TV') {
      $procId = 0
      [void][Kq8ClosePlayer3]::GetWindowThreadProcessId($h, [ref]$procId)
      if ($procId -gt 0) { [void]$killPids.Add([int]$procId) }
      [void][Kq8ClosePlayer3]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    return $true
  }, [IntPtr]::Zero) | Out-Null

  Start-Sleep -Milliseconds 500
  foreach ($procId in $killPids) {
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -match 'wmplayer|Video\.UI|Microsoft\.Media\.Player|ApplicationFrameHost') {
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    }
  }
  Get-Process -Name 'wmplayer', 'Microsoft.Media.Player', 'Video.UI' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
}

function Wait-And-Close([string]$path, [int]$fixedSec) {
  $waitSec = $fixedSec
  if ($waitSec -le 0) { $waitSec = Get-AviDurationSeconds $path }
  if ($waitSec -le 0) {
    if ($path -match '(?i)w32opn') { $waitSec = 107 }
    elseif ($path -match '(?i)w32mdl') { $waitSec = 60 }
    elseif ($path -match '(?i)w32ndg') { $waitSec = 180 }
    else { $waitSec = 110 }
  }
  # Backup only: give /close time to work; do not kill early.
  $waitSec = [Math]::Min([Math]::Max($waitSec, 30) + 5, 600)

  $deadline = (Get-Date).AddSeconds($waitSec)
  $saw = $false
  $t0 = Get-Date
  while ((Get-Date) -lt $deadline) {
    if (Test-MediaPlayerRunning) { $saw = $true }
    elseif ($saw) { break }  # /close (or user) already exited the player
    elseif (((Get-Date) - $t0).TotalSeconds -gt 15 -and -not $saw) { break }
    Start-Sleep -Milliseconds 400
  }
  # Only force-kill if still running after the full clip duration
  if (Test-MediaPlayerRunning) { Stop-MediaPlayers }
}

if (-not $WatchMask) {
  if (-not $AviPath) { $AviPath = Get-PlayerAviPath }
  Wait-And-Close $AviPath $Seconds
  exit 0
}

$idleUntil = (Get-Date).AddHours(2)
while ((Get-Date) -lt $idleUntil) {
  if (-not (Test-MaskRunning)) {
    Start-Sleep -Seconds 2
    if (-not (Test-MaskRunning)) { break }
  }
  if (Test-MediaPlayerRunning) {
    $path = $AviPath
    if (-not $path) { $path = Get-PlayerAviPath }
    if (-not $path) {
      $guess = Join-Path (Split-Path -Parent $PSCommandPath) 'w32opn_1.avi'
      if (Test-Path -LiteralPath $guess) { $path = $guess }
    }
    Wait-And-Close $path $Seconds
    Start-Sleep -Seconds 2
  }
  Start-Sleep -Milliseconds 500
}
exit 0
