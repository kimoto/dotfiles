# Print what this Windows PC starts on its own, what it exposes to the network,
# and its security settings, one `kind<TAB>key<TAB>detail` line each, sorted.
# bin/machine_audit_diff.sh compares the output to a list of what is allowed; the
# machine-audit skill decides what to do with the rest. Read-only: changes nothing.
#
# Keys carry only what should stay stable between runs (no PIDs, no dynamic
# ports), so a diff shows real change instead of noise. Detail is for the
# reader and never compared.
#
# Takes ~10 s, mostly Get-ScheduledTask and the CIM service query; it runs
# monthly and unattended, so nobody waits on it.
#
# Runs without admin. A check that needs admin prints `unknown` instead of
# failing, so a missing value shows up as a diff rather than as silence.

$ErrorActionPreference = 'SilentlyContinue'
# One line per kind+key: a port open on both IPv4 and IPv6 is one finding.
$lines = @{}
function Add-Line($kind, $key, $detail) {
    $clean = ($detail -replace '[\t\r\n]+', ' ').Trim()
    $id = "$kind`t$key"
    if (-not $lines.ContainsKey($id)) { $lines[$id] = New-Object System.Collections.Generic.SortedSet[string] }
    if ($clean) { [void]$lines[$id].Add($clean) }
}

# --- login: things that start without being asked ---

# Task Manager's "Disabled" leaves the Run entry in place and records the
# choice under StartupApproved: an odd first byte means off. Without this, an
# item already switched off is reported as running.
function Test-StartupDisabled($hive, $kind, $name) {
    $key = "${hive}:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$kind"
    $v = (Get-ItemProperty -Path $key -Name $name).$name
    return ($v -and ($v[0] % 2) -eq 1)
}

foreach ($hive in 'HKCU', 'HKLM') {
    foreach ($sub in 'Run', 'RunOnce') {
        $path = "${hive}:\Software\Microsoft\Windows\CurrentVersion\$sub"
        $item = Get-ItemProperty -Path $path
        if (-not $item) { continue }
        foreach ($p in $item.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            if ($sub -eq 'Run' -and (Test-StartupDisabled $hive 'Run' $p.Name)) { continue }
            Add-Line 'login' "run:$($p.Name)" $p.Value
        }
    }
}

$startupDirs = @(
    @{ Hive = 'HKCU'; Path = [Environment]::GetFolderPath('Startup') },
    @{ Hive = 'HKLM'; Path = [Environment]::GetFolderPath('CommonStartup') }
)
foreach ($dir in $startupDirs) {
    Get-ChildItem -Path $dir.Path -File | Where-Object {
        $_.Name -ne 'desktop.ini' -and -not (Test-StartupDisabled $dir.Hive 'StartupFolder' $_.Name)
    } | ForEach-Object { Add-Line 'login' "startup:$($_.Name)" $_.FullName }
}

# Microsoft's own tasks live under \Microsoft\ and change with every update.
Get-ScheduledTask | Where-Object {
    $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled'
} | ForEach-Object {
    $action = ($_.Actions | Select-Object -First 1).Execute
    Add-Line 'login' "task:$($_.TaskPath)$($_.TaskName)" $action
}

# Services shipped with Windows run from C:\Windows; everything else is third party.
Get-CimInstance Win32_Service | Where-Object {
    $_.StartMode -eq 'Auto' -and $_.PathName -and $_.PathName -notmatch '(?i)^"?C:\\Windows\\'
} | ForEach-Object { Add-Line 'login' "service:$($_.Name)" $_.PathName }

# --- listen: TCP ports reachable from other machines ---

$procNames = @{}
Get-Process | ForEach-Object { $procNames[$_.Id] = $_.ProcessName }
Get-NetTCPConnection -State Listen | Where-Object {
    $_.LocalAddress -notin @('127.0.0.1', '::1') -and $_.LocalAddress -notlike '127.*'
} | ForEach-Object {
    $name = $procNames[[int]$_.OwningProcess]
    if (-not $name) { $name = 'unknown' }
    # 49152+ is the dynamic range: RPC and friends pick a new one each boot.
    $port = if ($_.LocalPort -ge 49152) { 'dynamic' } else { "$($_.LocalPort)" }
    Add-Line 'listen' "${name}:$port" $_.LocalAddress
}

# --- setting: one line per setting, the value inside the key ---

function Add-Setting($name, $value) { Add-Line 'setting' "$name=$value" '' }

$mp = Get-MpComputerStatus
if ($mp) {
    Add-Setting 'defender-realtime' ($(if ($mp.RealTimeProtectionEnabled) { 'on' } else { 'off' }))
    Add-Setting 'defender-antivirus' ($(if ($mp.AntivirusEnabled) { 'on' } else { 'off' }))
} else {
    Add-Setting 'defender-realtime' 'unknown'
}

Get-NetFirewallProfile | ForEach-Object {
    Add-Setting "firewall-$($_.Name.ToLower())" ($(if ($_.Enabled) { 'on' } else { 'off' }))
}

$sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$lua = (Get-ItemProperty -Path $sys).EnableLUA
Add-Setting 'uac' ($(if ($lua -eq 1) { 'on' } elseif ($null -eq $lua) { 'unknown' } else { 'off' }))

$deny = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').fDenyTSConnections
Add-Setting 'remote-desktop' ($(if ($deny -eq 1) { 'off' } elseif ($null -eq $deny) { 'unknown' } else { 'on' }))

# BitLocker / device encryption status needs admin; without it this is unknown.
$vol = Get-BitLockerVolume -MountPoint $env:SystemDrive
if ($vol) {
    Add-Setting 'disk-encryption' ($(if ($vol.ProtectionStatus -eq 'On') { 'on' } else { 'off' }))
} else {
    Add-Setting 'disk-encryption' 'unknown'
}

$smb1 = (Get-SmbServerConfiguration).EnableSMB1Protocol
Add-Setting 'smb1' ($(if ($smb1 -eq $true) { 'on' } elseif ($smb1 -eq $false) { 'off' } else { 'unknown' }))

$lines.Keys | Sort-Object | ForEach-Object {
    [Console]::Out.WriteLine("$_`t$($lines[$_] -join ', ')")
}
