#Requires -Version 5.1
<#
.SYNOPSIS
    Two-button monitor brightness switcher: Normal, and Night (for when your girlfriend has gone to bed).

.DESCRIPTION
    Opens a small window with two big buttons. Each one sets every connected monitor to a saved
    brightness level. The levels and the method are editable in the window and saved next to the
    script in brightness.json.

    How it talks to the monitor, in order, when Method is "auto":
      1. DDC/CI (dxva2.dll). Hardware brightness on external desktop monitors. Needs DDC/CI
         enabled in the monitor's own OSD menu, which it usually is by default.
      2. WMI (WmiMonitorBrightnessMethods). Laptop and all-in-one panels.
      3. Gamma ramp (gdi32.dll). Software dim of the primary display. Always works, but Windows
         won't accept a ramp darker than about 50% unless the GdiICMGammaRange registry value is
         relaxed (see -UnlockGamma), so it gets clamped there.

    Dimmer than the monitor's 0%: a level below 0 means "monitor at 0, then dim the rest in
    software". -30 is monitor 0% plus a 30% gamma dim. Without -UnlockGamma the floor is -50;
    with it, -90. The software part only covers the primary display and a game running in
    exclusive fullscreen may override it (borderless is fine).

.PARAMETER Set
    Apply a preset ("normal" or "night") and exit without showing the window. Handy for a
    hotkey, a Stream Deck button, or Task Scheduler.

.PARAMETER Level
    Apply an explicit level (-90 to 100) and exit without showing the window.

.PARAMETER UnlockGamma
    Set the GdiICMGammaRange registry value so Windows accepts gamma ramps darker than 50%.
    Needs an admin PowerShell and a reboot. Run once, then Night can go down to -90.

.PARAMETER ConfigPath
    Where to keep the saved levels. Defaults to brightness.json next to this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -STA -File .\brightness.ps1
    powershell -ExecutionPolicy Bypass -File .\brightness.ps1 -Set night
    powershell -ExecutionPolicy Bypass -File .\brightness.ps1 -Level -30
    powershell -ExecutionPolicy Bypass -File .\brightness.ps1 -UnlockGamma     # from an admin PowerShell
#>
[CmdletBinding()]
param(
    [ValidateSet('normal', 'night')]
    [string]$Set,

    [ValidateRange(-90, 100)]
    [int]$Level,

    [switch]$UnlockGamma,

    [string]$ConfigPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'brightness.json' }

if (($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows) {
    throw 'brightness.ps1 is Windows-only (it uses dxva2/gdi32 and WinForms).'
}

# The launchers run this with the console hidden, so an error would otherwise vanish.
# Any unhandled error pops a message box instead.
Add-Type -AssemblyName System.Windows.Forms
trap {
    $msg = "$($_.Exception.Message)`r`n`r`nAt line $($_.InvocationInfo.ScriptLineNumber): $("$($_.InvocationInfo.Line)".Trim())"
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'brightness.ps1 crashed', 'OK', 'Error')
    break
}

# ----------------------------------------------------------------------------
# Native monitor access (DDC/CI + gamma ramp)
# ----------------------------------------------------------------------------
if (-not ('Dimmer' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Dimmer
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RAMP
    {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)] public ushort[] Red;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)] public ushort[] Green;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)] public ushort[] Blue;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint count);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetMonitorBrightness(IntPtr hMonitor, out uint min, out uint cur, out uint max);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetMonitorBrightness(IntPtr hMonitor, uint value);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool DestroyPhysicalMonitors(uint count, PHYSICAL_MONITOR[] monitors);
    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool SetDeviceGammaRamp(IntPtr hDC, ref RAMP ramp);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateDC(string driver, string device, string output, IntPtr initData);
    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplayDevices(string device, uint iDevNum, ref DISPLAY_DEVICE dd, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr hWnd, int index, int value);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    // Win32 error from the last failed SetDeviceGammaRamp (0 usually means "ramp out of allowed range").
    public static int LastGammaError = 0;

    // Makes a window click-through and non-activating (for the dim overlay).
    public static void MakeClickThrough(IntPtr hWnd)
    {
        const int GWL_EXSTYLE = -20;
        const int WS_EX_TRANSPARENT = 0x20, WS_EX_LAYERED = 0x80000, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
        int ex = GetWindowLong(hWnd, GWL_EXSTYLE);
        SetWindowLong(hWnd, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
    }

    private static List<IntPtr> GetHMonitors()
    {
        var list = new List<IntPtr>();
        MonitorEnumProc cb = delegate(IntPtr h, IntPtr dc, IntPtr rc, IntPtr d) { list.Add(h); return true; };
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, cb, IntPtr.Zero);
        GC.KeepAlive(cb);
        return list;
    }

    // Runs action on every physical monitor behind every display. Returns how many said yes.
    private static int ForEachPhysical(Func<IntPtr, bool> action)
    {
        int ok = 0;
        foreach (IntPtr hmon in GetHMonitors())
        {
            uint n;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hmon, out n) || n == 0) continue;
            var arr = new PHYSICAL_MONITOR[n];
            if (!GetPhysicalMonitorsFromHMONITOR(hmon, n, arr)) continue;
            try
            {
                foreach (PHYSICAL_MONITOR pm in arr)
                {
                    try { if (action(pm.hPhysicalMonitor)) ok++; } catch { }
                }
            }
            finally { DestroyPhysicalMonitors(n, arr); }
        }
        return ok;
    }

    // Sets hardware brightness (0-100) over DDC/CI. Returns number of monitors that accepted it.
    public static int DdcSet(int percent)
    {
        int p = Math.Max(0, Math.Min(100, percent));
        return ForEachPhysical(delegate(IntPtr h)
        {
            uint min, cur, max;
            if (!GetMonitorBrightness(h, out min, out cur, out max) || max <= min) return false;
            uint v = min + (uint)Math.Round((max - min) * p / 100.0);
            return SetMonitorBrightness(h, v);
        });
    }

    // Current hardware brightness (0-100) of the first monitor that answers, or -1.
    public static int DdcGet()
    {
        int result = -1;
        ForEachPhysical(delegate(IntPtr h)
        {
            uint min, cur, max;
            if (!GetMonitorBrightness(h, out min, out cur, out max) || max <= min) return false;
            if (result < 0) result = (int)Math.Round((cur - min) * 100.0 / (max - min));
            return true;
        });
        return result;
    }

    // Software dim via gamma ramp on every attached display. 100 = identity (undoes any earlier dim).
    // Returns how many displays accepted it.
    public static int GammaSet(int percent)
    {
        double scale = Math.Max(0, Math.Min(100, percent)) / 100.0;
        var ramp = new RAMP { Red = new ushort[256], Green = new ushort[256], Blue = new ushort[256] };
        for (int i = 0; i < 256; i++)
        {
            ushort v = (ushort)Math.Min(65535, (int)Math.Round(i * 256 * scale));
            ramp.Red[i] = v; ramp.Green[i] = v; ramp.Blue[i] = v;
        }
        LastGammaError = 0;
        int ok = 0;
        var dd = new DISPLAY_DEVICE();
        dd.cb = Marshal.SizeOf(dd);
        for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++)
        {
            string name = dd.DeviceName;
            int flags = dd.StateFlags;
            dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
            if ((flags & 1) == 0) continue;   // DISPLAY_DEVICE_ATTACHED_TO_DESKTOP
            IntPtr dc = CreateDC(null, name, null, IntPtr.Zero);
            if (dc == IntPtr.Zero) continue;
            try
            {
                if (SetDeviceGammaRamp(dc, ref ramp)) ok++;
                else LastGammaError = Marshal.GetLastWin32Error();
            }
            finally { DeleteDC(dc); }
        }
        if (ok == 0)
        {
            IntPtr dc = GetDC(IntPtr.Zero);
            try
            {
                if (SetDeviceGammaRamp(dc, ref ramp)) ok++;
                else LastGammaError = Marshal.GetLastWin32Error();
            }
            finally { ReleaseDC(IntPtr.Zero, dc); }
        }
        return ok;
    }
}
'@
}

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
$script:Cfg = [ordered]@{ normal = 70; night = 10; method = 'auto' }
$script:Methods = @('auto', 'ddc', 'wmi', 'gamma')

# Windows rejects gamma ramps below ~50% unless GdiICMGammaRange is set to 256 (then ~10% is safe).
$script:GammaRegKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM'
function Test-GammaUnlocked {
    try {
        $v = (Get-ItemProperty -LiteralPath $script:GammaRegKey -Name GdiICMGammaRange -ErrorAction Stop).GdiICMGammaRange
        return ([int]$v -ge 256)
    } catch { return $false }
}
$script:GammaFloor = if (Test-GammaUnlocked) { 10 } else { 50 }
$script:MinLevel   = $script:GammaFloor - 100   # -90 unlocked, -50 otherwise

function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return }
    try {
        $json = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        foreach ($k in @('normal', 'night')) {
            $p = $json.PSObject.Properties[$k]
            if ($p -and $p.Value -is [ValueType]) { $script:Cfg[$k] = [Math]::Max($script:MinLevel, [Math]::Min(100, [int]$p.Value)) }
        }
        $m = $json.PSObject.Properties['method']
        if ($m -and ($script:Methods -contains [string]$m.Value)) { $script:Cfg.method = [string]$m.Value }
    } catch {
        Write-Warning "Couldn't read $ConfigPath, using defaults. ($($_.Exception.Message))"
    }
}

function Save-Config {
    $script:Cfg | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

# ----------------------------------------------------------------------------
# Brightness backends
# ----------------------------------------------------------------------------
function Set-WmiBrightness([int]$Percent) {
    $targets = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop)
    if ($targets.Count -eq 0) { return $false }
    foreach ($t in $targets) {
        $null = Invoke-CimMethod -InputObject $t -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = [byte]$Percent }
    }
    return $true
}

function Get-WmiBrightness {
    $b = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop | Select-Object -First 1
    if ($b) { return [int]$b.CurrentBrightness }
    return -1
}

# Fallback for when Windows refuses the gamma ramp (HDR on, driver says no): a click-through,
# non-activating black window over the whole desktop whose opacity is the dim amount. Only
# lives while this process does, which is why the window hides to the tray instead of exiting.
$script:Overlay  = $null
$script:MainForm = $null
$script:GuiMode  = $false
function Set-Overlay([int]$DimPercent) {
    if ($DimPercent -le 0) {
        if ($script:Overlay) { $script:Overlay.Close(); $script:Overlay.Dispose(); $script:Overlay = $null }
        return
    }
    if (-not $script:Overlay) {
        $o = New-Object System.Windows.Forms.Form
        $o.FormBorderStyle = 'None'
        $o.ShowInTaskbar   = $false
        $o.TopMost         = $true
        $o.StartPosition   = 'Manual'
        $o.BackColor       = [System.Drawing.Color]::Black
        $o.Bounds          = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $o.Opacity         = 0.01
        $o.Show()
        $script:Overlay = $o
        if ($script:MainForm) { $script:MainForm.Activate() }
    }
    $script:Overlay.Opacity = [Math]::Min(0.95, $DimPercent / 100.0)
    [Dimmer]::MakeClickThrough($script:Overlay.Handle)
}

# Applies the software part of a level: 100 = no dim. Returns a note for the status line.
function Set-SoftDim([int]$Soft) {
    if ($Soft -ge 100) {
        $null = [Dimmer]::GammaSet(100)
        Set-Overlay 0
        return ''
    }
    $p = [Math]::Max($script:GammaFloor, $Soft)
    if ([Dimmer]::GammaSet($p) -gt 0) {
        Set-Overlay 0
        if ($p -ne $Soft) { return " + software dim capped at $(100 - $p)%, run -UnlockGamma for more" }
        return " + $(100 - $p)% software dim"
    }
    $err = [Dimmer]::LastGammaError
    if ($script:GuiMode) {
        Set-Overlay (100 - $Soft)
        return " + $(100 - $Soft)% overlay dim (gamma refused, error $err)"
    }
    return " (software dim failed, gamma error $err; the window has an overlay fallback)"
}

# Returns a short description of the method that worked. Throws if nothing did.
# Percent below 0 means hardware 0 plus a software dim of that much.
function Set-Brightness([int]$Percent, [string]$Method) {
    $hw   = [Math]::Max(0, $Percent)
    $soft = 100 + [Math]::Min(0, $Percent)
    if ($Method -in @('auto', 'ddc')) {
        $n = [Dimmer]::DdcSet($hw)
        if ($n -gt 0) {
            $s = if ($n -eq 1) { '' } else { 's' }
            return "DDC/CI ($n monitor$s)" + (Set-SoftDim $soft)
        }
        if ($Method -eq 'ddc') { throw 'No monitor answered DDC/CI. Turn DDC/CI on in the monitor OSD, or pick another method.' }
    }
    if ($Method -in @('auto', 'wmi')) {
        try {
            if (Set-WmiBrightness $hw) { return 'WMI' + (Set-SoftDim $soft) }
        } catch {
            if ($Method -eq 'wmi') { throw "WMI brightness not available on this machine. ($($_.Exception.Message))" }
        }
    }
    if ($Method -in @('auto', 'gamma')) {
        # No hardware control at all, so the level itself is the software dim (negatives just hit the floor).
        $p = [Math]::Max($script:GammaFloor, $hw)
        if ([Dimmer]::GammaSet($p) -gt 0) {
            Set-Overlay 0
            if ($p -ne $hw) { return "gamma ramp (Windows caps it at $p%, run -UnlockGamma for more)" }
            return 'gamma ramp'
        }
        if ($script:GuiMode) {
            Set-Overlay (100 - $hw)
            return "overlay dim $(100 - $hw)% (gamma refused, error $([Dimmer]::LastGammaError))"
        }
    }
    throw "Couldn't set brightness with method '$Method'."
}

function Get-Brightness {
    $v = [Dimmer]::DdcGet()
    if ($v -ge 0) { return $v }
    try { return Get-WmiBrightness } catch { return -1 }
}

# ----------------------------------------------------------------------------
# CLI mode: apply and exit
# ----------------------------------------------------------------------------
Read-Config

if ($UnlockGamma) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw '-UnlockGamma writes to HKLM. Right-click PowerShell, "Run as administrator", then run this again.' }
    if (-not (Test-Path -LiteralPath $script:GammaRegKey)) { $null = New-Item -Path $script:GammaRegKey -Force }
    Set-ItemProperty -LiteralPath $script:GammaRegKey -Name GdiICMGammaRange -Value 256 -Type DWord
    Write-Host 'GdiICMGammaRange set to 256. Reboot, then Night can go down to -90.'
    return
}

if ($Set -or $PSBoundParameters.ContainsKey('Level')) {
    $target = if ($Set) { [int]$script:Cfg[$Set] } else { $Level }
    $how = Set-Brightness -Percent $target -Method $script:Cfg.method
    Write-Host "Brightness set to $target% via $how"
    return
}

# ----------------------------------------------------------------------------
# GUI
# ----------------------------------------------------------------------------
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:GuiMode = $true
$script:Quit    = $false

$bg       = [System.Drawing.Color]::FromArgb(24, 24, 28)
$panel    = [System.Drawing.Color]::FromArgb(40, 40, 46)
$panelHot = [System.Drawing.Color]::FromArgb(56, 56, 64)
$fg       = [System.Drawing.Color]::FromArgb(235, 235, 240)
$dim      = [System.Drawing.Color]::FromArgb(150, 150, 160)
$sun      = [System.Drawing.Color]::FromArgb(242, 170, 48)
$moon     = [System.Drawing.Color]::FromArgb(92, 120, 220)

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Brightness'
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.ClientSize      = New-Object System.Drawing.Size(380, 212)
$form.BackColor       = $bg
$form.ForeColor       = $fg
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 10)
$form.KeyPreview      = $true
$script:MainForm = $form

function New-BigButton([string]$Text, [int]$X, [System.Drawing.Color]$Accent) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Text
    $b.Location  = New-Object System.Drawing.Point($X, 16)
    $b.Size      = New-Object System.Drawing.Size(166, 112)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 2
    $b.FlatAppearance.BorderColor = $panel
    $b.FlatAppearance.MouseOverBackColor = $panelHot
    $b.BackColor = $panel
    $b.ForeColor = $fg
    $b.Font      = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $b.Tag       = $Accent
    return $b
}

$btnNormal = New-BigButton 'Normal' 16  $sun
$btnNight  = New-BigButton 'Night'  198 $moon

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.Location  = New-Object System.Drawing.Point($X, $Y)
    $l.Size      = New-Object System.Drawing.Size($W, 22)
    $l.TextAlign = 'MiddleLeft'
    $l.ForeColor = $dim
    return $l
}

function New-Spinner([int]$Value, [int]$X, [int]$Y) {
    $n = New-Object System.Windows.Forms.NumericUpDown
    $n.Minimum   = $script:MinLevel   # below 0 = monitor at 0 plus a software dim
    $n.Maximum   = 100
    $n.Value     = $Value
    $n.Location  = New-Object System.Drawing.Point($X, $Y)
    $n.Size      = New-Object System.Drawing.Size(52, 24)
    $n.BackColor = $panel
    $n.ForeColor = $fg
    $n.BorderStyle = 'FixedSingle'
    return $n
}

$rowY      = 144
$lblNormal = New-Label 'Normal' 16 $rowY 50
$numNormal = New-Spinner ([int]$script:Cfg.normal) 66 $rowY
$lblNight  = New-Label 'Night' 134 $rowY 42
$numNight  = New-Spinner ([int]$script:Cfg.night) 176 $rowY

$cmbMethod = New-Object System.Windows.Forms.ComboBox
$cmbMethod.DropDownStyle = 'DropDownList'
$cmbMethod.Location  = New-Object System.Drawing.Point(244, $rowY)
$cmbMethod.Size      = New-Object System.Drawing.Size(120, 24)
$cmbMethod.FlatStyle = 'Flat'
$cmbMethod.BackColor = $panel
$cmbMethod.ForeColor = $fg
[void]$cmbMethod.Items.AddRange(@('auto', 'DDC/CI', 'WMI (laptop)', 'gamma ramp'))
$cmbMethod.SelectedIndex = [Array]::IndexOf($script:Methods, [string]$script:Cfg.method)

$lblStatus = New-Label '' 16 180 348
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$form.Controls.AddRange(@($btnNormal, $btnNight, $lblNormal, $numNormal, $lblNight, $numNight, $cmbMethod, $lblStatus))

function Set-Status([string]$Text, [bool]$IsError = $false) {
    $lblStatus.Text = $Text
    $lblStatus.ForeColor = if ($IsError) { [System.Drawing.Color]::FromArgb(240, 100, 100) } else { $dim }
}

function Update-ButtonText {
    $btnNormal.Text = "Normal`r`n$($script:Cfg.normal)%"
    $btnNight.Text  = "Night`r`n$($script:Cfg.night)%"
}

function Set-Active([System.Windows.Forms.Button]$Active) {
    foreach ($b in @($btnNormal, $btnNight)) {
        if ($b -eq $Active) {
            $b.FlatAppearance.BorderColor = [System.Drawing.Color]$b.Tag
            $b.ForeColor = [System.Drawing.Color]$b.Tag
        } else {
            $b.FlatAppearance.BorderColor = $panel
            $b.ForeColor = $fg
        }
    }
}

function Invoke-Preset([string]$Name) {
    $target = [int]$script:Cfg[$Name]
    $form.UseWaitCursor = $true
    try {
        $how = Set-Brightness -Percent $target -Method $script:Cfg.method
        Set-Status "$target% via $how"
        Set-Active $(if ($Name -eq 'normal') { $btnNormal } else { $btnNight })
    } catch {
        Set-Status $_.Exception.Message $true
    } finally {
        $form.UseWaitCursor = $false
    }
}

$btnNormal.Add_Click({ Invoke-Preset 'normal' })
$btnNight.Add_Click({ Invoke-Preset 'night' })

$numNormal.Add_ValueChanged({ $script:Cfg.normal = [int]$numNormal.Value; Update-ButtonText; Save-Config })
$numNight.Add_ValueChanged({  $script:Cfg.night  = [int]$numNight.Value;  Update-ButtonText; Save-Config })
$cmbMethod.Add_SelectedIndexChanged({
    if ($cmbMethod.SelectedIndex -ge 0) { $script:Cfg.method = $script:Methods[$cmbMethod.SelectedIndex]; Save-Config }
})

# Keyboard: 1 / N = Normal, 2 / G = Night (G for "gone to bed"), Esc closes.
# Shortcuts are ignored while a spinner has focus so you can type a level in peace.
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq 'Escape') { $form.Close(); return }
    $focus = $form.ActiveControl
    if ($focus -is [System.Windows.Forms.NumericUpDown]) { return }
    if ($focus -and $focus.Parent -is [System.Windows.Forms.NumericUpDown]) { return }
    switch ($e.KeyCode) {
        { $_ -in 'D1', 'NumPad1', 'N' } { Invoke-Preset 'normal'; $e.Handled = $true; $e.SuppressKeyPress = $true }
        { $_ -in 'D2', 'NumPad2', 'G' } { Invoke-Preset 'night';  $e.Handled = $true; $e.SuppressKeyPress = $true }
    }
})

Update-ButtonText

# Tray icon. The window hides here instead of exiting while an overlay dim is active,
# because the overlay dies with the process.
function Show-Main { $form.Show(); $form.WindowState = 'Normal'; $form.Activate() }

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Text = 'Brightness'
$tray.Icon = try { [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $PID).Path) } catch { [System.Drawing.SystemIcons]::Application }
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Normal', $null, { Invoke-Preset 'normal' })
[void]$menu.Items.Add('Night',  $null, { Invoke-Preset 'night' })
[void]$menu.Items.Add('Show window', $null, { Show-Main })
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Exit', $null, { $script:Quit = $true; $form.Close() })
$tray.ContextMenuStrip = $menu
$tray.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Show-Main } })
$tray.Visible = $true

$form.Add_FormClosing({
    param($s, $e)
    if (-not $script:Quit -and $script:Overlay -and $e.CloseReason -eq 'UserClosing') {
        $e.Cancel = $true
        $form.Hide()
        $tray.ShowBalloonTip(3000, 'Brightness', 'Still dimming from the tray. Right-click the icon to exit.', 'Info')
    }
})

$form.Add_Shown({
    $btnNormal.Focus() | Out-Null
    $cur = Get-Brightness
    if ($cur -ge 0) {
        Set-Status "Current: $cur%"
        if ($cur -eq [int]$script:Cfg.normal) { Set-Active $btnNormal }
        elseif ($cur -eq [int]$script:Cfg.night) { Set-Active $btnNight }
    } else {
        Set-Status 'No monitor reported its brightness yet. Try a button.'
    }
})

[System.Windows.Forms.Application]::Run($form)
$tray.Visible = $false
$tray.Dispose()
Set-Overlay 0
$form.Dispose()
