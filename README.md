# King's Quest VIII: Mask of Eternity — Windows 10/11 Fix (Nexus)

**Version 1.2.4** · Requires your own copy of the game (GOG or disc). This package does **not** include the game.

Nexus-safe build: same Win11 fix, **mpv** cutscene player, optional **DirectGlide**, and settings launcher. **Cutscene AVI files are not included** (copyrighted game video). Add them yourself after install (see below).

---

## What it does

| Piece | Purpose |
|-------|---------|
| **Win11 fix (NicoDE kq8fix)** | Compatibility shim for Windows 10/11. Based on NicoDE’s kqmoefix — not original to this pack. |
| **Cutscene player (mpv)** | Bundled player + licenses. Plays H.264 intros/endings once you supply the AVI files. |
| **DirectGlide** (Recommended) | Glide → Direct3D 11 wrapper (`glide2x.dll`): sharper fullscreen; widescreen in Settings. |
| **Settings launcher** | Resolution, widescreen (DirectGlide), replay intro, Play. |

**Windows fix only** keeps GOG’s nGlide `glide2x.dll` (no DirectGlide widescreen).

---

## Quick start

1. Install Mask of Eternity to a short path, ideally **without spaces**, e.g. `C:\Games\KQ8`.
2. Unzip this package and open **`KQ8-Fix-Nexus`**.
3. Run **`Setup KQ8 Fix.bat`**.
4. Point it at the folder with **`Mask.exe`**, choose Recommended or Windows fix only, **Install**.
5. **Add cutscene videos** (required for intros / mid / ending) — see next section.
6. Play with **`Launch KQ8.bat`** or the desktop shortcut.

---

## Cutscene AVIs (add after install)

Copy these three H.264 files into the **same folder as `Mask.exe`** (your game folder), not into this Nexus zip:

| File | When |
|------|------|
| `w32opn_1.avi` | Boot / Replay intro |
| `W32mdl_1.avi` | Mid-game |
| `W32ndg_1.avi` | Ending |

Obtain them from a legal source that provides re-encoded Mask of Eternity cutscenes (for example the full offline pack / Git release that includes videos), or re-encode from your own game files. This Nexus package deliberately omits them.

Example game folder after install + AVIs:

```
C:\Games\KQ8\
  Mask.exe
  mpv.exe
  kq8fix.exe
  ...
  w32opn_1.avi
  W32mdl_1.avi
  W32ndg_1.avi
```

---

## Package layout

```
KQ8-Fix-Nexus/
  Setup KQ8 Fix.bat
  README.md
  PLAYER_INSTALL.md
  tools/          ← installer scripts
  runtime/
    glide2x.dll   ← DirectGlide (Recommended)
    Launch KQ8.bat, Launch KQ8 Emergency.bat, Launch-Kq8.ps1, icon
    win11/
      kq8fix.* , mpv.exe, d3dcompiler_43.dll, licenses
      (no .avi cutscene files)
```

---

## Install options

### Recommended
- Win11 fix + mpv + launcher + DirectGlide `glide2x.dll`

### Windows fix only
- Win11 fix + mpv + launcher; keeps GOG nGlide

Resolution: **640×480** (recommended) or **800×600** (experimental).

---

## Credits

- **Win11 shim:** NicoDE kqmoefix (`kq8fix`)
- **DirectGlide:** Glide → D3D11 wrapper in this pack
- **mpv:** see `Copyright`, `LICENSE.GPL`, `LICENSE.LGPL` after install
- **King's Quest / Mask of Eternity:** © rights holders — own a legal copy

---

## Uninstall

Run Setup again → **Uninstall**. Restores backups and removes files this installer added. (AVIs you copied by hand are left alone unless they were already backed up as replacements.)
