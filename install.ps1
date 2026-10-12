#Requires -Version 5.1
<#
.SYNOPSIS
    Installs (or removes) the deadlockoptimization config pack for Valve's Deadlock.

.DESCRIPTION
    Does four things, each with a backup first:
      1. Writes cfg\autoexec.cfg (any autoexec you already had becomes autoexec_user.cfg and is still executed).
      2. Patches a marker-delimited ConVars block into game\citadel\gameinfo.gi.
      3. Merges the preset's video settings into every video.txt it can find, leaving your
         resolution, refresh rate, monitor, fullscreen mode and deviceid alone.
      4. Prints the Steam launch options you need to paste.

    Nothing here touches game assets (no VPK edits, no DLLs, no injected code). It is the same
    kind of config that community packs like OptiLock and Skip-eo's config use, which Valve has
    left alone. Run it again after a game update if gameinfo.gi gets overwritten.

.PARAMETER Preset
    balanced (default) or maxfps. See README.md for what each one does.

.PARAMETER DeadlockPath
    Path to the Deadlock install folder (the one containing game\citadel). Auto-detected from
    Steam's library list if omitted.

.PARAMETER Uninstall
    Remove the managed block from gameinfo.gi, remove our autoexec.cfg, restore the original
    video.txt from the first backup.

.PARAMETER LockVideo
    Mark video.txt read-only after writing so Steam Cloud / the game cannot revert it.
    The in-game Video menu will then fail to save; re-run without -LockVideo to undo.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Preset maxfps
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('balanced', 'maxfps')]
    [string]$Preset = 'balanced',

    [string]$DeadlockPath,

    [switch]$Uninstall,
    [switch]$SkipAutoexec,
    [switch]$SkipGameinfo,
    [switch]$SkipVideo,
    [switch]$LockVideo
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------
$script:AppId        = '1422450'
$script:MarkerStart  = '// >>> deadlockoptimization managed block (do not edit this line, install.ps1 owns it)'
$script:MarkerEnd    = '// <<< deadlockoptimization managed block'
$script:AutoexecTag  = '[deadlockoptimization] loading autoexec'
$script:BackupDir    = '_deadlockoptimization_backup'
$script:LaunchOpts   = '-console +exec autoexec.cfg'
$script:Utf8NoBom    = New-Object System.Text.UTF8Encoding($false)
$script:RunStamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:RepoRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:PresetDir    = Join-Path (Join-Path (Join-Path $script:RepoRoot 'cfg') 'presets') $Preset
$script:IsWin        = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "    $Message" -ForegroundColor Green }
function Write-Note([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path)
}

function Write-Text([string]$Path, [string]$Content) {
    if (-not $PSCmdlet.ShouldProcess($Path, 'write')) { return }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($item -and $item.IsReadOnly) { $item.IsReadOnly = $false }
    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function Get-Newline([string]$Content) {
    if ($Content -match "`r`n") { return "`r`n" }
    return "`n"
}

function Get-SteamRoot {
    if ($script:IsWin) {
        foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
            try {
                $props = Get-ItemProperty -Path $key -ErrorAction Stop
                foreach ($name in @('SteamPath', 'InstallPath')) {
                    $v = $props.PSObject.Properties[$name]
                    if ($v -and $v.Value -and (Test-Path -LiteralPath $v.Value)) { return ($v.Value -replace '/', '\') }
                }
            } catch { }
        }
        foreach ($p in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam", 'C:\Steam')) {
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        }
    } else {
        foreach ($p in @("$HOME/.steam/steam", "$HOME/.local/share/Steam", "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam")) {
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

function Get-SteamLibraries([string]$SteamRoot) {
    $libs = New-Object System.Collections.Generic.List[string]
    if ($SteamRoot) { $libs.Add($SteamRoot) }
    $vdf = Join-Path (Join-Path $SteamRoot 'steamapps') 'libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $text = Read-Text $vdf
        foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
            $p = $m.Groups[1].Value -replace '\\\\', '\'
            if ((Test-Path -LiteralPath $p) -and -not $libs.Contains($p)) { $libs.Add($p) }
        }
    }
    return $libs
}

function Find-DeadlockRoot([string]$SteamRoot) {
    foreach ($lib in (Get-SteamLibraries $SteamRoot)) {
        $candidate = Join-Path (Join-Path (Join-Path $lib 'steamapps') 'common') 'Deadlock'
        if (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $candidate 'game') 'citadel') 'gameinfo.gi')) {
            return $candidate
        }
    }
    return $null
}

function Find-VideoFiles([string]$CitadelDir, [string]$SteamRoot) {
    $found = New-Object System.Collections.Generic.List[string]
    $local = Join-Path (Join-Path $CitadelDir 'cfg') 'video.txt'
    if (Test-Path -LiteralPath $local) { $found.Add($local) }
    if ($SteamRoot) {
        $userdata = Join-Path $SteamRoot 'userdata'
        if (Test-Path -LiteralPath $userdata) {
            Get-ChildItem -LiteralPath $userdata -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Join-Path (Join-Path (Join-Path (Join-Path $_.FullName $script:AppId) 'local') 'cfg') 'video.txt'
                if (Test-Path -LiteralPath $p) { $found.Add($p) }
            }
        }
    }
    return $found
}

function Backup-File([string]$Path, [string]$CitadelDir) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $root = Join-Path $CitadelDir $script:BackupDir
    $orig = Join-Path $root 'original'
    $stamp = Join-Path $root $script:RunStamp
    # Keep the file name unique when two video.txt files exist in different places.
    $leaf = (Split-Path -Leaf $Path)
    $tag = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant()))).Replace('-', '').Substring(0, 8)
    $name = "$tag-$leaf"
    foreach ($dir in @($orig, $stamp)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            if ($PSCmdlet.ShouldProcess($dir, 'create backup dir')) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        }
        $dest = Join-Path $dir $name
        if ($dir -eq $orig -and (Test-Path -LiteralPath $dest)) { continue }   # never overwrite the first backup
        if ($PSCmdlet.ShouldProcess($dest, 'backup')) { Copy-Item -LiteralPath $Path -Destination $dest -Force }
    }
    return (Join-Path $orig $name)
}

function Get-OriginalBackup([string]$Path, [string]$CitadelDir) {
    $leaf = (Split-Path -Leaf $Path)
    $tag = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant()))).Replace('-', '').Substring(0, 8)
    $p = Join-Path (Join-Path (Join-Path $CitadelDir $script:BackupDir) 'original') "$tag-$leaf"
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

# ----------------------------------------------------------------------------
# gameinfo.gi
# ----------------------------------------------------------------------------
function Get-ManagedBlock([string]$NewLine) {
    $body = Read-Text (Join-Path $script:PresetDir 'gameinfo_convars.txt')
    $body = $body -replace "`r`n", "`n" -replace "`n", $NewLine
    if (-not $body.EndsWith($NewLine)) { $body += $NewLine }
    return "`t`t$($script:MarkerStart)$NewLine$body`t`t$($script:MarkerEnd)$NewLine"
}

function Install-GameinfoBlock([string]$Path) {
    $text = Read-Text $Path
    $nl = Get-Newline $text
    $block = Get-ManagedBlock $nl
    $rxExisting = [regex]::new('[ \t]*' + [regex]::Escape($script:MarkerStart) + '.*?' + [regex]::Escape($script:MarkerEnd) + '[ \t]*\r?\n?', 'Singleline')

    if ($rxExisting.IsMatch($text)) {
        $text = $rxExisting.Replace($text, $block.Replace('$', '$$'), 1)
        Write-Ok "Replaced existing managed block in gameinfo.gi"
    } else {
        $rxConVars = [regex]::new('(?<![\w"])ConVars\s*\{[ \t]*\r?\n', 'IgnoreCase')
        $m = $rxConVars.Match($text)
        if ($m.Success) {
            $text = $text.Insert($m.Index + $m.Length, $block)
            Write-Ok "Inserted managed block into existing ConVars section"
        } else {
            $last = $text.LastIndexOf('}')
            if ($last -lt 0) { throw "gameinfo.gi does not look like a KeyValues file (no closing brace): $Path" }
            $section = "`tConVars$nl`t{$nl$block`t}$nl"
            $text = $text.Insert($last, $section)
            Write-Ok "Added a new ConVars section with the managed block"
        }
    }
    Write-Text $Path $text
}

function Remove-GameinfoBlock([string]$Path) {
    $text = Read-Text $Path
    $rxExisting = [regex]::new('[ \t]*' + [regex]::Escape($script:MarkerStart) + '.*?' + [regex]::Escape($script:MarkerEnd) + '[ \t]*\r?\n?', 'Singleline')
    if (-not $rxExisting.IsMatch($text)) { Write-Note "No managed block found in gameinfo.gi, nothing to remove"; return }
    $text = $rxExisting.Replace($text, '', 1)
    Write-Text $Path $text
    Write-Ok "Removed managed block from gameinfo.gi"
}

# ----------------------------------------------------------------------------
# video.txt
# ----------------------------------------------------------------------------
$script:RxSetting = [regex]::new('^(\s*)"(setting\.[^"]+)"\s+"([^"]*)"\s*$')

function Get-PresetVideoSettings {
    $ordered = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($line in (Get-Content -LiteralPath (Join-Path $script:PresetDir 'video.txt'))) {
        $m = $script:RxSetting.Match($line)
        if ($m.Success) { $ordered[$m.Groups[2].Value] = $m.Groups[3].Value }
    }
    return $ordered
}

function Merge-VideoFile([string]$Path, $Settings) {
    $text = Read-Text $Path
    $nl = Get-Newline $text
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($text -split "\r?\n")) { $lines.Add($l) }
    # -split leaves a trailing empty element when the file ends with a newline; keep track so we re-add it.
    $trailingNewline = $text.EndsWith("`n")
    if ($trailingNewline -and $lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }

    $done = New-Object System.Collections.Generic.HashSet[string]
    $changed = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $script:RxSetting.Match($lines[$i])
        if (-not $m.Success) { continue }
        $key = $m.Groups[2].Value
        if (-not $Settings.Contains($key)) { continue }
        $want = [string]$Settings[$key]
        if ($m.Groups[3].Value -ne $want) {
            $lines[$i] = "$($m.Groups[1].Value)`"$key`"`t`t`"$want`""
            $changed++
        }
        [void]$done.Add($key)
    }

    # Insert keys that were missing just before the closing brace of the VideoConfig block.
    $closeIdx = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i].Trim() -eq '}') { $closeIdx = $i; break } }
    $added = 0
    foreach ($key in $Settings.Keys) {
        if ($done.Contains($key)) { continue }
        $newLine = "`t`"$key`"`t`t`"$($Settings[$key])`""
        if ($closeIdx -ge 0) { $lines.Insert($closeIdx, $newLine); $closeIdx++ } else { $lines.Add($newLine) }
        $added++
    }
    if ($closeIdx -lt 0) { Write-Note "video.txt had no closing brace; appended settings at the end: $Path" }

    $out = [string]::Join($nl, $lines)
    if ($trailingNewline) { $out += $nl }
    Write-Text $Path $out
    if ($LockVideo -and $PSCmdlet.ShouldProcess($Path, 'set read-only')) { (Get-Item -LiteralPath $Path).IsReadOnly = $true }
    Write-Ok ("video.txt: {0} values changed, {1} added{2}  ({3})" -f $changed, $added, $(if ($LockVideo) { ', locked read-only' } else { '' }), $Path)
}

# ----------------------------------------------------------------------------
# autoexec.cfg
# ----------------------------------------------------------------------------
function Install-Autoexec([string]$CfgDir) {
    if (-not (Test-Path -LiteralPath $CfgDir)) {
        if ($PSCmdlet.ShouldProcess($CfgDir, 'create')) { New-Item -ItemType Directory -Path $CfgDir -Force | Out-Null }
    }
    $target = Join-Path $CfgDir 'autoexec.cfg'
    $userCfg = Join-Path $CfgDir 'autoexec_user.cfg'
    if (Test-Path -LiteralPath $target) {
        $existing = Read-Text $target
        if ($existing -notmatch [regex]::Escape($script:AutoexecTag)) {
            if (Test-Path -LiteralPath $userCfg) {
                Write-Note "autoexec_user.cfg already exists; leaving your current autoexec.cfg in the backup folder only"
            } elseif ($PSCmdlet.ShouldProcess($target, "rename to autoexec_user.cfg")) {
                Move-Item -LiteralPath $target -Destination $userCfg -Force
                Write-Ok "Your previous autoexec.cfg is now autoexec_user.cfg and still gets executed"
            }
        }
    }
    if (-not (Test-Path -LiteralPath $userCfg)) {
        Write-Text $userCfg "// Put your own commands here. deadlockoptimization's autoexec.cfg executes this file last.$([Environment]::NewLine)"
    }
    $content = Read-Text (Join-Path $script:PresetDir 'autoexec.cfg')
    Write-Text $target $content
    Write-Ok "autoexec.cfg written ($Preset)"
}

function Remove-Autoexec([string]$CfgDir) {
    $target = Join-Path $CfgDir 'autoexec.cfg'
    $userCfg = Join-Path $CfgDir 'autoexec_user.cfg'
    if ((Test-Path -LiteralPath $target) -and ((Read-Text $target) -match [regex]::Escape($script:AutoexecTag))) {
        if ($PSCmdlet.ShouldProcess($target, 'delete')) { Remove-Item -LiteralPath $target -Force }
        Write-Ok "Removed our autoexec.cfg"
        if (Test-Path -LiteralPath $userCfg) {
            $body = (Read-Text $userCfg).Trim()
            if ($body -like '// Put your own commands here.*' -and ($body -split "\r?\n").Count -le 1) {
                if ($PSCmdlet.ShouldProcess($userCfg, 'delete placeholder')) { Remove-Item -LiteralPath $userCfg -Force }
            } elseif ($PSCmdlet.ShouldProcess($userCfg, 'rename back to autoexec.cfg')) {
                Move-Item -LiteralPath $userCfg -Destination $target -Force
                Write-Ok "Restored your previous autoexec.cfg"
            }
        }
    } else {
        Write-Note "autoexec.cfg is not ours (or missing), leaving it alone"
    }
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "deadlockoptimization :: $(if ($Uninstall) { 'UNINSTALL' } else { "install preset '$Preset'" })" -ForegroundColor White
Write-Host ""

if (-not (Test-Path -LiteralPath $script:PresetDir)) { throw "Preset folder not found: $script:PresetDir" }

Write-Step "Locating Deadlock"
$steamRoot = Get-SteamRoot
if ($DeadlockPath) {
    $deadlockRoot = (Resolve-Path -LiteralPath $DeadlockPath).Path
} else {
    if (-not $steamRoot) { throw "Steam not found. Pass -DeadlockPath 'X:\...\steamapps\common\Deadlock'." }
    $deadlockRoot = Find-DeadlockRoot $steamRoot
    if (-not $deadlockRoot) { throw "Deadlock not found in any Steam library under $steamRoot. Pass -DeadlockPath." }
}
$citadel = Join-Path (Join-Path $deadlockRoot 'game') 'citadel'
$gameinfo = Join-Path $citadel 'gameinfo.gi'
$cfgDir = Join-Path $citadel 'cfg'
if (-not (Test-Path -LiteralPath $gameinfo)) { throw "Not a Deadlock install (missing $gameinfo)" }
Write-Ok "Deadlock: $deadlockRoot"
if ($steamRoot) { Write-Ok "Steam:    $steamRoot" }

$exe = Get-ChildItem -LiteralPath (Join-Path (Join-Path (Join-Path $deadlockRoot 'game') 'bin') 'win64') -Filter '*.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(project8|deadlock)\.exe$' } | Select-Object -First 1
if ($exe) { Write-Ok "Game exe: $($exe.FullName)" }

if ($Uninstall) {
    if (-not $SkipGameinfo) { Write-Step "gameinfo.gi"; Backup-File $gameinfo $citadel | Out-Null; Remove-GameinfoBlock $gameinfo }
    if (-not $SkipAutoexec) { Write-Step "autoexec.cfg"; Remove-Autoexec $cfgDir }
    if (-not $SkipVideo) {
        Write-Step "video.txt"
        foreach ($v in (Find-VideoFiles $citadel $steamRoot)) {
            $orig = Get-OriginalBackup $v $citadel
            if ($orig) {
                if ($PSCmdlet.ShouldProcess($v, "restore from $orig")) {
                    $item = Get-Item -LiteralPath $v; if ($item.IsReadOnly) { $item.IsReadOnly = $false }
                    Copy-Item -LiteralPath $orig -Destination $v -Force
                }
                Write-Ok "Restored original: $v"
            } else {
                Write-Note "No original backup for $v. Open the in-game Video menu and pick a preset to reset it."
            }
        }
    }
    Write-Host ""
    Write-Host "Done. Remove '$($script:LaunchOpts)' from Deadlock's Steam launch options if you no longer want the console." -ForegroundColor White
    Write-Host ""
    return
}

if (-not $SkipGameinfo) {
    Write-Step "gameinfo.gi"
    Backup-File $gameinfo $citadel | Out-Null
    Install-GameinfoBlock $gameinfo
}

if (-not $SkipAutoexec) {
    Write-Step "autoexec.cfg"
    $existingAutoexec = Join-Path $cfgDir 'autoexec.cfg'
    Backup-File $existingAutoexec $citadel | Out-Null
    Install-Autoexec $cfgDir
}

if (-not $SkipVideo) {
    Write-Step "video.txt"
    $videoFiles = Find-VideoFiles $citadel $steamRoot
    if ($videoFiles.Count -eq 0) {
        Write-Note "No video.txt found. Launch Deadlock once, change any video setting so the file gets created, quit, then re-run this script."
    } else {
        $settings = Get-PresetVideoSettings
        foreach ($v in $videoFiles) {
            Backup-File $v $citadel | Out-Null
            Merge-VideoFile $v $settings
        }
    }
}

Write-Host ""
Write-Host "Install finished." -ForegroundColor White
Write-Host ""
Write-Host "1. Steam > Library > Deadlock > Properties > Launch Options, paste:" -ForegroundColor White
Write-Host ""
Write-Host "       $($script:LaunchOpts)" -ForegroundColor Green
Write-Host ""
try { Set-Clipboard -Value $script:LaunchOpts -ErrorAction Stop; Write-Ok "(copied to clipboard)" } catch { }
Write-Host "2. Backups are in: $(Join-Path $citadel $script:BackupDir)" -ForegroundColor White
Write-Host "3. Optional Windows tweaks (needs admin): powershell -ExecutionPolicy Bypass -File .\windows\system-tweaks.ps1 -Apply" -ForegroundColor White
Write-Host "4. Read docs\adrenalin-9070xt.md and docs\ryzen-5700x.md for the driver and BIOS side." -ForegroundColor White
Write-Host ""
Write-Host "If a game update overwrites gameinfo.gi, just run this script again." -ForegroundColor DarkGray
Write-Host ""
