# Ryzen 7 5700X: the hardware side

The 5700X is the bottleneck in this build for Deadlock. A few things in BIOS matter more than any
convar.

## Memory: DOCP / XMP on (biggest win)

Zen 3 fps scales hard with memory speed and latency because the Infinity Fabric clock follows the
memory clock. If your RAM is running at JEDEC 2133 or 2666 because the profile was never enabled,
you're leaving 10 to 20 percent in CPU-bound games on the table.

- BIOS > AI Tweaker (ASUS) / OC Tweaker (ASRock) / Tweaker (Gigabyte) / Overclocking (MSI) >
  DOCP or XMP > Profile 1.
- Sweet spot for Zen 3 is 3600 MT/s with FCLK at 1800 MHz (1:1). 3200 is fine. 3800 can work with
  FCLK 1900 but many 5700X samples won't hold it. Don't go past 3600 unless you know you want to
  tune it.
- Check it took: Task Manager > Performance > Memory shows the speed. CPU-Z > Memory tab shows
  DRAM frequency (shown as half, so 1800 MHz = 3600 MT/s) and timings.
- Dual channel: two sticks, slots A2 and B2. Single stick halves your bandwidth.

## Precision Boost Overdrive

- PBO: Enabled (or Advanced > Motherboard limits). Lets the chip boost above the stock 76 W PPT
  when cooling allows.
- Curve Optimizer: All cores, Negative, 15 to start. Undervolts so the chip boosts higher at the
  same power. Test stability with a few matches and an hour of a stress test (OCCT, CoreCycler).
  If anything crashes, back off to 10. Most 5700X samples do 20 to 30 fine.
- Boost clock override: +100 to +200 MHz is safe. Small gain.
- Leave SMT on. Deadlock uses a lot of threads and the Source 2 job system benefits from 16.

## Resizable BAR (Smart Access Memory)

- BIOS > Advanced > PCI Subsystem Settings: Above 4G Decoding = Enabled, Re-Size BAR Support =
  Enabled.
- Needs CSM disabled (UEFI boot). If Windows was installed in legacy/MBR mode, you'd need to
  convert with `mbr2gpt` first. If CSM is already off, just flip the two settings.
- Confirm in Adrenalin > Performance > Tuning, or Adrenalin > System: Smart Access Memory enabled.

## Chipset driver and power plan

- Install AMD's chipset driver for your board (B550/X570/B450) from amd.com, not Windows Update's
  version. It installs the Ryzen power plan hooks.
- On Zen 3, Windows **Balanced** with the chipset driver is already right. High performance keeps
  cores from parking and costs a few watts idle, and some people find it helps 1% lows. It's a
  switch on `system-tweaks.ps1` (`-PowerPlan`); try it, keep it if it helps.
- In the plan, Minimum processor state 5 percent is fine. Don't set 100, it only burns power.

## Cooling

The 5700X is a 65 W part but under PBO it'll pull 90 to 110 W. If it's on the stock Wraith cooler
and hits 90 C, it's throttling boost. Any decent tower cooler (Peerless Assassin, Freezer 36) keeps
it in the 70s and lets PBO actually do something.

## Things not to bother with

- Core isolation / Memory integrity (VBS). Turning it off gains 3 to 8 percent in some CPU-bound
  games on Zen 3. It's a real security feature, your call. If you do it: Windows Security > Device
  security > Core isolation > Memory integrity off, then reboot.
- Disabling cores, "game boost" BIOS presets, CPPC preferred cores toggles. Leave them default.
- Manual all-core overclock. PBO + Curve Optimizer beats it for gaming on Zen 3 because single
  core boost goes higher.
