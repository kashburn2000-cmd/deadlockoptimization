# deadlockoptimization

FPS config pack for Valve's Deadlock, tuned for a **Ryzen 7 5700X + Radeon RX 9070 XT**.

It's a config mod, not a binary mod: an installer script that drops an `autoexec.cfg`, patches a
block of engine convars into `gameinfo.gi`, merges graphics settings into `video.txt`, and an
optional Windows tweaks script. No VPK edits, no DLLs, nothing injected. This is the same category
of thing as the community configs (OptiLock, Skip-eo) that Valve has left alone and that are fine
in matchmaking. Everything is backed up first and `-Uninstall` puts it all back.

## Why this rig needs a CPU-side config

Deadlock is a Source 2 game with 12 heroes, hundreds of minions, and a lot of particles. On a
9070 XT at 1440p the GPU is nowhere near the bottleneck. The 5700X is. You'll see GPU usage sit at
50 to 70 percent in team fights while the frame rate dips, which is the signature of a CPU limit.

So dropping texture quality or render scale, the usual "fps config" advice, does nothing for you.
What helps is cutting work the CPU does per frame:

- Sun shadow cascades. Each cascade is another pass of draw calls. Default is up to 4.
- Local lights casting shadow maps. Same story.
- Particle simulation. The engine can degrade effects under load, but by default it never does.
- Ragdolls, breakable debris, cloth settling.
- The Panorama UI's blur, box shadows and transitions, which are redrawn on the CPU.

That's what the `balanced` preset targets, while leaving the GPU-side stuff (textures, AA,
shader quality) at high because it's free on this card. `maxfps` goes further and also drops
the GPU-side settings and culls props, outlines and decals earlier. It looks noticeably flatter.

## Install

Windows 10/11, PowerShell 5.1 or newer (built in).

```powershell
git clone https://github.com/kashburn2000-cmd/deadlockoptimization
cd deadlockoptimization
powershell -ExecutionPolicy Bypass -File .\install.ps1              # balanced (recommended)
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Preset maxfps
```

Then in Steam: Library > Deadlock > Properties > Launch Options:

```
-console +exec autoexec.cfg
```

The installer copies that line to your clipboard. Close Deadlock before running it.

Switches: `-DeadlockPath "D:\SteamLibrary\steamapps\common\Deadlock"` if auto-detect fails,
`-SkipVideo` / `-SkipGameinfo` / `-SkipAutoexec` to do a partial install, `-LockVideo` to make
`video.txt` read-only so Steam Cloud can't revert it (the in-game Video menu stops saving while
locked), `-WhatIf` for a dry run.

### Optional Windows tweaks (admin)

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Apply
powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Apply -PowerPlan   # also High performance plan
powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Undo
```

Game Mode on, hardware-accelerated GPU scheduling on, fullscreen optimizations off for the game
exe, and the game exe set to High CPU priority through Image File Execution Options (what Process
Lasso does, without Process Lasso). Reboot after, HAGS only applies on restart.

### Driver and BIOS

The scripts can't do these for you. Read:

- [docs/adrenalin-9070xt.md](docs/adrenalin-9070xt.md): Adrenalin settings for the 9070 XT. The
  big one is Anti-Lag on in the driver, because the config enables Anti-Lag 2 in the engine.
- [docs/ryzen-5700x.md](docs/ryzen-5700x.md): DOCP/XMP, PBO, chipset driver, Resizable BAR.
  Memory speed is the single biggest hardware-side win on Zen 3.

## What gets written where

| File | What | Managed how |
|---|---|---|
| `game\citadel\cfg\autoexec.cfg` | fps cap, UI cap, Anti-Lag, raw input, optional glow/shake toggles | Replaced. A pre-existing autoexec becomes `autoexec_user.cfg` and is still executed. |
| `game\citadel\gameinfo.gi` | shadow cascades, light shadows, particle fallback, ragdolls, UI, fog, misc | A marker-delimited block inside the `ConVars` section. Nothing else in the file is touched. |
| `game\citadel\cfg\video.txt` and `userdata\<id>\1422450\local\cfg\video.txt` | the in-game Video menu settings | Values merged in. Resolution, refresh, monitor, fullscreen and deviceid are not changed. |

Backups land in `game\citadel\_deadlockoptimization_backup\original\` (first run, never
overwritten) and a timestamped folder per run.

Why two places? Valve made a lot of these convars unsettable from `autoexec.cfg`, but the
`ConVars` block in `gameinfo.gi` is read before that restriction kicks in. The menu-exposed
settings go in `video.txt` because the game applies that file last and it would override
anything in gameinfo anyway. Keeping each setting in exactly one place avoids fights between them.

Full list with explanations: [docs/convars.md](docs/convars.md).

## After a game update

Patches sometimes overwrite `gameinfo.gi`. Symptom: shadows are back. Fix: run `install.ps1`
again. It's idempotent, you can run it as often as you like.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Undo   # if you ran -Apply
```

Removes the gameinfo block, deletes our autoexec (restores yours), restores the original
`video.txt`. Then remove the launch options in Steam.

## Checking it worked

In game, open the console (F7) and run `cl_showfps 2` for an fps and frametime readout. Play a bot
match, push into a team fight, and compare before and after. Watch the 1% lows more than the
average. The Adrenalin overlay (Ctrl+Shift+O) shows GPU utilisation: if it's well under 90 percent
in fights, you're CPU-bound and the GPU-side settings don't matter.

Things worth A/B testing on your own machine, in the autoexec:

- `fps_max`. Uncapped gives the highest average. A cap you can hold in fights (try 200 or 240)
  gives flatter frametimes. Pick whichever feels better.
- `r_low_latency 1` vs `0`. Anti-Lag 2 helps input lag when CPU-bound, but a few people report
  pacing issues. Try both.
- `-vulkan` in launch options. Source 2's Vulkan path has less driver overhead on AMD and can
  help when CPU-bound, but it's had stability problems in Deadlock. Experiment, don't default to it.

## Linux / Steam Deck

`install.ps1` runs under PowerShell 7 (`pwsh`) on Linux too and knows the usual Steam paths
(`~/.steam/steam`, `~/.local/share/Steam`, Flatpak). `system-tweaks.ps1` is Windows-only. The
Adrenalin doc doesn't apply, Mesa RADV is already fine for RDNA 4.

## Credits and sources

Convar lists and the gameinfo approach come from the community:

- [OptiLock](https://github.com/dacooderr/OptiLock) by dacooderr, including the full cvar dump
  used to check every convar here for the `cheat` flag.
- [Skip-eo/Deadlock-Config](https://github.com/Skip-eo/Deadlock-Config)
- [Deadlock Wiki: console commands](https://deadlock.wiki/Console_commands)

This pack deliberately does less than those: no `sc_disable_baked_lighting`, no `r_directlighting`
(it's cheat-flagged and does nothing in matchmaking anyway), no full `gameinfo.gi` replacement.
