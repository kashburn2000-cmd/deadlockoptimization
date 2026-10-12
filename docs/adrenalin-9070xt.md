# Adrenalin settings for the RX 9070 XT in Deadlock

Adrenalin > Gaming > Deadlock (add it manually if it's not listed: Add a game > browse to
`Deadlock\game\bin\win64\project8.exe`). Set these per-game so your other games aren't affected.

## Driver

Use the latest WHQL Adrenalin. RDNA 4 drivers improved a lot through 2025; don't sit on an old one.
If this card replaced an Nvidia card, do a DDU clean install once. Leftover Nvidia driver
components are a classic source of stutter.

## Per-game graphics settings

| Setting | Value | Why |
|---|---|---|
| Radeon Anti-Lag | **On** | The config sets `r_low_latency 1`, which the engine describes as "NVIDIA Low Latency / AMD Anti-Lag 2". The driver toggle has to be on for Anti-Lag 2 to engage. |
| Radeon Boost | Off | Lowers render resolution during fast mouse movement. Pointless when CPU-bound, and it makes the image shimmer. |
| Radeon Chill | Off | Frame limiter that targets power savings. Adds latency. Use `fps_max` instead if you want a cap. |
| Radeon Image Sharpening | Optional | Costs nothing on this GPU. On at 50-70% if you like a crisper image, off if you don't. |
| Radeon Super Resolution | Off | Driver-level upscaling. You don't need upscaling on a 9070 XT at 1440p. |
| AMD Fluid Motion Frames (AFMF) | **Off** | Frame generation. Adds a frame of latency and interpolates HUD elements. Not for a competitive shooter. |
| HYPR-RX | Off | It's a bundle of Boost + AFMF + RSR. Off for the same reasons. |
| Wait for Vertical Refresh | Always off | V-sync in the driver. The config already disables it in the game. |
| Enhanced Sync | Off | Tearing-free uncapped mode. Causes frame pacing problems in Source 2 for a lot of people. |
| Texture Filtering Quality | Performance | Tiny GPU saving, invisible difference. Doesn't matter on this card, but free. |
| Surface Format Optimization | On | Driver picks cheaper surface formats where it can. |
| Tessellation Mode | AMD optimized | Default. Leave it. |
| Shader Cache | AMD optimized | Default. Leave it. If you get stutter after a driver update, Reset Shader Cache once. |
| Anisotropic Filtering | Use application settings | The game handles it. |
| Anti-aliasing | Use application settings | Don't force driver AA on a deferred renderer. |

## Display

- FreeSync / Adaptive Sync: on, if your monitor supports it. With an uncapped frame rate above
  the refresh you'll still get tearing. If you'd rather have no tearing, cap with `fps_max` at
  refresh minus 3 (e.g. 162 on a 165 Hz panel) and keep V-sync off everywhere.
- Set the refresh rate in Windows > Display > Advanced, not just the monitor OSD. A lot of
  "the game feels capped" reports are a 60 Hz desktop.
- GPU scaling: off. Let the monitor scale, or run native.

## Performance tab

- Tuning > leave at default unless you know what you're doing. The 9070 XT's stock boost is fine
  for a game that doesn't load it. An undervolt (-50 to -80 mV) lowers temps and fan noise with no
  fps cost, if you want to tinker.
- Metrics overlay (Ctrl+Shift+O): enable GPU utilisation and frametime. This is how you confirm
  you're CPU-bound. GPU under 90 percent in fights means the CPU is the limit.

## Windows side, GPU related

- Settings > System > Display > Graphics > Default graphics settings: Hardware-accelerated GPU
  scheduling **on** (the `system-tweaks.ps1 -Apply` script sets this). Optimizations for
  windowed games: on is fine, it only affects windowed/borderless.
- Resizable BAR / Smart Access Memory: enable in BIOS (see the Ryzen doc). Adrenalin > System
  shows "Smart Access Memory: Enabled" when it's working. Small but free gain on AMD GPUs.
- Multi-plane overlay (MPO) is a common source of flicker and stutter on AMD with multiple
  monitors. If you see it, exclusive fullscreen (which the config leaves as whatever you have set)
  bypasses it. Don't disable MPO globally unless you have the problem.
