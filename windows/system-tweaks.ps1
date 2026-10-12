#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Optional Windows-side tweaks for Deadlock on a Ryzen 7 5700X + RX 9070 XT. Fully reversible.

.DESCRIPTION
    -Apply does, in order:
      1. Game Mode on (lets Windows deprioritise background work while the game has focus).
      2. Hardware-accelerated GPU scheduling (HAGS) on. Supported on RDNA 4 and the AMD driver
         benefits from it; Anti-Lag 2 / frame pacing is a little better with it on.
      3. Disable "fullscreen optimizations" for the Deadlock exe so exclusive fullscreen is
         actually exclusive (lower input latency than the DWM-composited path).
      4. Run the Deadlock exe at High CPU priority through Image File Execution Options.
         Same effect as Process Lasso, no third-party software, persists across reboots.
      5. (only with -PowerPlan) Switch the active power plan to High performance.
         On Zen 3 the AMD chipset driver's Balanced plan is already fine; enable this only if
         you see clocks dropping mid-match.

    -Undo reverses everything the script set (Game Mode and HAGS go back to Windows defaults,
    the exe entries are deleted, the power plan goes back to Balanced).

    Reboot after -Apply or -Undo: HAGS only changes on restart.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Apply
    powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Apply -PowerPlan
    powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Undo
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Apply,
    [switch]$Undo,
    [switch]$PowerPlan,
    [string]$DeadlockPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not ($Apply -xor $Undo)) { throw "Pass exactly one of -Apply or -Undo." }
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) { throw "This script only applies to Windows." }

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "    $Message" -ForegroundColor Green }
function Write-Note([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }

# --- locate the game exe --------------------------------------------------
function Find-DeadlockExe {
    $roots = New-Object System.Collections.Generic.List[string]
    if ($DeadlockPath) { $roots.Add($DeadlockPath) }
    $steam = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($name in @('SteamPath', 'InstallPath')) {
                $v = $props.PSObject.Properties[$name]
                if ($v -and $v.Value -and (Test-Path -LiteralPath $v.Value)) { $steam = ($v.Value -replace '/', '\'); break }
            }
        } catch { }
        if ($steam) { break }
    }
    if ($steam) {
        $roots.Add((Join-Path $steam 'steamapps\common\Deadlock'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $roots.Add((Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common\Deadlock'))
            }
        }
    }
    foreach ($r in $roots) {
        $bin = Join-Path $r 'game\bin\win64'
        if (-not (Test-Path -LiteralPath $bin)) { continue }
        $exe = Get-ChildItem -LiteralPath $bin -Filter '*.exe' | Where-Object { $_.Name -match '^(project8|deadlock)\.exe$' } | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

function Set-RegValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, 'create key')) { New-Item -Path $Path -Force | Out-Null }
    }
    if ($PSCmdlet.ShouldProcess("$Path\$Name", "set to $Value")) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

function Remove-RegValue([string]$Path, [string]$Name) {
    if ((Test-Path -LiteralPath $Path) -and (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess("$Path\$Name", 'remove')) { Remove-ItemProperty -Path $Path -Name $Name -Force }
    }
}

$exePath = Find-DeadlockExe
if ($exePath) { Write-Ok "Deadlock exe: $exePath" } else { Write-Note "Deadlock exe not found; per-exe tweaks (3, 4) will be skipped. Pass -DeadlockPath to fix." }
$exeName = if ($exePath) { Split-Path -Leaf $exePath } else { $null }

$gameBar   = 'HKCU:\Software\Microsoft\GameBar'
$gfx       = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$layers    = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$ifeo      = if ($exeName) { "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exeName\PerfOptions" } else { $null }

if ($Apply) {
    Write-Step "Game Mode"
    Set-RegValue $gameBar 'AutoGameModeEnabled' 1
    Set-RegValue $gameBar 'AllowAutoGameMode' 1
    Write-Ok "on"

    Write-Step "Hardware-accelerated GPU scheduling"
    Set-RegValue $gfx 'HwSchMode' 2
    Write-Ok "on (takes effect after reboot)"

    if ($exePath) {
        Write-Step "Fullscreen optimizations off for $exeName"
        Set-RegValue $layers $exePath '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' 'String'
        Write-Ok "done"

        Write-Step "High CPU priority for $exeName"
        Set-RegValue $ifeo 'CpuPriorityClass' 3      # 3 = High
        Write-Ok "done (applies next time the game starts)"
    }

    if ($PowerPlan) {
        Write-Step "Power plan"
        $high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        if ($PSCmdlet.ShouldProcess('powercfg', "setactive $high")) { & powercfg /setactive $high | Out-Null }
        Write-Ok "High performance active"
    } else {
        Write-Note "Power plan left alone (pass -PowerPlan to switch to High performance)"
    }

    Write-Host ""
    Write-Host "Applied. Reboot once so HAGS takes effect." -ForegroundColor White
    Write-Host "Undo any time: powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Undo" -ForegroundColor DarkGray
}

if ($Undo) {
    Write-Step "Game Mode"
    Remove-RegValue $gameBar 'AutoGameModeEnabled'
    Remove-RegValue $gameBar 'AllowAutoGameMode'
    Write-Ok "back to Windows default"

    Write-Step "Hardware-accelerated GPU scheduling"
    Remove-RegValue $gfx 'HwSchMode'
    Write-Ok "back to driver default (after reboot)"

    if ($exePath) {
        Write-Step "Per-exe entries for $exeName"
        Remove-RegValue $layers $exePath
        if (Test-Path -LiteralPath $ifeo) {
            $parent = Split-Path -Parent $ifeo
            if ($PSCmdlet.ShouldProcess($parent, 'remove key')) { Remove-Item -Path $parent -Recurse -Force }
        }
        Write-Ok "removed"
    }

    Write-Step "Power plan"
    $balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    if ($PSCmdlet.ShouldProcess('powercfg', "setactive $balanced")) { & powercfg /setactive $balanced | Out-Null }
    Write-Ok "Balanced active"

    Write-Host ""
    Write-Host "Undone. Reboot once so HAGS reverts." -ForegroundColor White
}
