$ErrorActionPreference = 'Continue'
$dsc = @("$env:LOCALAPPDATA\PowerToys\PowerToys.DSC.exe", "$env:ProgramFiles\PowerToys\PowerToys.DSC.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
"dsc: $dsc"
winget list --id Microsoft.PowerToys --exact --disable-interactivity
& $dsc modules --resource 'settings'
foreach ($m in 'App', 'Peek', 'AdvancedPaste', 'CmdPal') {
    "== $m"
    & $dsc get --resource 'settings' --module $m
    "exit $LASTEXITCODE"
}
"== set via argument"
$key = @{ win = $true; ctrl = $false; alt = $false; shift = $true; code = 80; key = 'P' }
$in = @{ settings = @{ properties = @{ ActivationShortcut = $key }; name = 'Peek'; version = '1.0' } } |
    ConvertTo-Json -Depth 10 -Compress
$in
& $dsc set --resource 'settings' --module Peek --input $in; "exit $LASTEXITCODE"
& $dsc test --resource 'settings' --module Peek --input $in; "exit $LASTEXITCODE"
"== set via escaped argument"
$esc = $in -replace '"', '\"'
& $dsc set --resource 'settings' --module Peek --input $esc; "exit $LASTEXITCODE"
& $dsc test --resource 'settings' --module Peek --input $esc; "exit $LASTEXITCODE"
"== set via stdin"
$in | & $dsc set --resource 'settings' --module Peek; "exit $LASTEXITCODE"
& $dsc --help
& $dsc set --help
"== files"
$root = "$env:LOCALAPPDATA\Microsoft\PowerToys"
Get-ChildItem -Recurse $root -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
Get-Content "$root\settings.json" -ErrorAction SilentlyContinue
Get-Content "$root\Peek\settings.json" -ErrorAction SilentlyContinue
"== cmdpal"
Get-AppxPackage *CommandPalette* | Format-List Name, Version, PackageFamilyName, InstallLocation
Get-ChildItem -Recurse "$env:LOCALAPPDATA\Packages\Microsoft.CommandPalette*" -ErrorAction SilentlyContinue |
    Select-Object -First 40 | ForEach-Object { $_.FullName }
"== autostart"
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List
schtasks /query /fo csv 2>$null | Select-String -SimpleMatch PowerToys
exit 0
