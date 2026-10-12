# King's Quest VIII: Mask of Eternity — Windows 10/11 Fix

**Version 1.2.5** · Requires your own copy of the game (GOG or disc). This package does **not** include the game.

A local, offline fix pack for *King's Quest: Mask of Eternity* on modern Windows. It installs a Win11 compatibility shim, reliable H.264 cutscenes (via **mpv**), an optional sharper Glide renderer (**DirectGlide**), and a small settings launcher.

---

## What it does

| Piece | Purpose |
|-------|---------|
| **Win11 fix (NicoDE kq8fix)** | Compatibility shim so the old game runs more reliably on Windows 10/11 (including cutscene hand-off). Based on NicoDE’s kqmoefix — not original to this pack. |
| **Cutscenes (mpv + H.264 AVIs)** | Intro / mid / ending videos re-encoded as H.264 and played with a small bundled player. Windows Media Player is **not** required. |
| **DirectGlide** (Recommended) | Drop-in `glide2x.dll` that draws Glide through Direct3D 11: sharper fullscreen, with widescreen stretch available in Settings. |
| **Settings launcher** | Simple window to pick resolution, widescreen (DirectGlide), replay intro, then Play. |

**Windows fix only** installs the shim, cutscenes, and launcher, but **leaves GOG’s nGlide** `glide2x.dll` alone (no DirectGlide widescreen option).

Setup never downloads anything. Everything comes from this folder.

---

## Quick start

1. Install Mask of Eternity somewhere short, ideally **without spaces**, e.g. `C:\Games\KQ8`.  
   Deep GOG / Program Files paths often crash on **New Game** (“copying files to hard drive”). That is an engine/path issue, not caused by DirectGlide.
2. Unzip this package and open the **`KQ8-Fix`** folder.
3. Run **`Setup KQ8 Fix.bat`**.
4. Detect GOG or Browse to the folder that contains **`Mask.exe`**.
5. Choose **Recommended** or **Windows fix only**, pick resolution, read the file list, then **Install**.
6. Play with the desktop shortcut (if you created one) or **`Launch KQ8.bat`** in the game folder.

**Uninstall** (same Setup window): restores your backed-up game files and removes everything this installer added.

---

## Package layout (what you unzip)

These files live in the **`KQ8-Fix`** folder you distribute. Players do not need to copy them by hand — Setup does that.

```
KQ8-Fix/
  Setup KQ8 Fix.bat          ← start here (opens the installer UI)
  README.md                  ← this file
  PLAYER_INSTALL.md          ← short checklist / troubleshooting
  tools/                     ← installer scripts (used by the bat)
    Install-Kq8Hd-Gui.ps1
    Install-Kq8Hd.ps1
    Launch-Kq8.ps1
  runtime/                   ← files copied into the game folder
    glide2x.dll              ← DirectGlide (Recommended only)
    kq8-launcher.ico
    Launch KQ8.bat
    Launch KQ8 Emergency.bat
    Launch-Kq8.ps1
    win11/
      kq8fix.exe / .dll / .ini   ← NicoDE Win11 shim
      mpv.exe                    ← cutscene player
      d3dcompiler_43.dll         ← helper for mpv
      w32opn_1.avi               ← boot / replay intro
      W32mdl_1.avi               ← mid-game cutscene
      W32ndg_1.avi               ← ending
      Copyright, LICENSE.GPL, LICENSE.LGPL   ← mpv licenses
      close_player_after.ps1     ← backup helper for old video paths
```

---

## Where files go after Install

Everything Setup installs is placed **next to `Mask.exe`** (your game folder).

| In game folder | Role |
|----------------|------|
| `kq8fix.exe`, `kq8fix.dll`, `kq8fix.ini` | Win11 shim (NicoDE) |
| `mpv.exe`, `d3dcompiler_43.dll` | Cutscene player |
| `w32opn_1.avi`, `W32mdl_1.avi`, `W32ndg_1.avi` | H.264 cutscenes |
| `Copyright`, `LICENSE.GPL`, `LICENSE.LGPL` | mpv license files |
| `Launch KQ8.bat`, `Launch KQ8 Emergency.bat`, `Launch-Kq8.ps1` | Settings launcher |
| `kq8-launcher.ico`, `kq8_launcher.json` | Shortcut icon + saved settings |
| `glide2x.dll` | **Recommended:** DirectGlide. **Windows fix only:** unchanged GOG nGlide |
| `hd_textures\` (optional flags) | DirectGlide options (e.g. widescreen) |
| `backup_kq8fix_*\` | Backup of files Setup replaced — used by Uninstall |
| `close_player_after.ps1` | Optional helper left from the cutscene stack |

**Daily play:** use **`Launch KQ8.bat`** (or the desktop shortcut). Do not rely on the Setup bat every time.

**Emergency:** `Launch KQ8 Emergency.bat` skips the settings UI and starts the game.

---

## Install options (Graphics)

### Recommended
- Win11 fix + cutscenes + launcher  
- Installs **DirectGlide** `glide2x.dll` (replaces GOG nGlide)  
- Widescreen stretch available later in Settings  

### Windows fix only
- Win11 fix + cutscenes + launcher  
- Keeps your existing GOG **nGlide** `glide2x.dll`  
- No widescreen toggle in Settings  

Resolution: **640×480** (recommended) or **800×600** (experimental).

---

## Playing (settings launcher)

| Control | Notes |
|---------|--------|
| Resolution | 640×480 recommended / 800×600 experimental |
| Widescreen stretch | DirectGlide only (under Advanced) |
| Replay intro | Plays `w32opn_1.avi` in mpv, then starts the game |
| Play | Starts Mask (after intro if requested) |

---

## Credits and licenses

- **Win11 shim:** NicoDE kqmoefix (`kq8fix`). Original project: NicoDE / SegMash-era Mask of Eternity fix work.  
- **DirectGlide:** Glide → Direct3D 11 wrapper included in this pack (Recommended).  
- **mpv:** Bundled cutscene player; see `Copyright`, `LICENSE.GPL`, and `LICENSE.LGPL` in the game folder after install (GPLv2+ / LGPLv2.1+ as applicable).  
- **King's Quest / Mask of Eternity:** © Sierra / rights holders. Own a legal copy.

---

## Troubleshooting

- **New Game crash while “copying files”** — Move or reinstall the game to a short path without spaces (e.g. `C:\Games\KQ8`), then run Setup again on that folder.  
- **Black screen / no 3D** — Use the launcher; Recommended/DirectGlide or stock Glide mode (not old D3D-display). Re-run Setup if needed.  
- **Cutscenes don’t resume** — Prefer a path **without spaces**, or a junction such as `C:\Games\KQ8` pointing at the real install.  
- **Missing mpv** — The package must include `runtime\win11\mpv.exe`. Setup does not download it.

---

## Uninstall

1. Run **`Setup KQ8 Fix.bat`** again.  
2. Point at the same game folder.  
3. Click **Uninstall**.  

This restores the latest `backup_kq8fix_*` backup, removes files this installer added, deletes backup folders, and removes the desktop shortcut. Graphics/resolution choices in the window do not change what Uninstall does.
