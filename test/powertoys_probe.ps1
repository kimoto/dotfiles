$ErrorActionPreference = 'Continue'
$dsc = "$env:LOCALAPPDATA\PowerToys\PowerToys.DSC.exe"
function Show-App([string]$Label) {
    $s = (& $dsc get --resource 'settings' --module App | ConvertFrom-Json).settings
    "$Label startup=$($s.startup) AdvancedPaste=$($s.enabled.AdvancedPaste) Peek=$($s.enabled.Peek)" +
        " CmdPal=$($s.enabled.CmdPal) FancyZones=$($s.enabled.FancyZones)" +
        " count=$(@($s.enabled.psobject.Properties).Count)"
}
function Show-Procs {
    Get-Process | Where-Object { $_.Name -match 'PowerToys|CmdPal|CommandPalette' } |
        ForEach-Object { "  $($_.Name) $($_.Id)" }
}
function Show-Tasks([string]$Label) {
    "$Label tasks:"
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { "$($_.TaskPath)$($_.TaskName)" -match 'PowerToys' } |
        ForEach-Object { "  $($_.TaskPath)$($_.TaskName) $($_.State) $($_.Actions.Execute) $($_.Actions.Arguments)" }
}
"== processes"
Show-Procs
Show-App 'before'
Show-Tasks 'before'
"== set App partial"
$in = '{"settings":{"startup":true,"enabled":{"AdvancedPaste":true}}}' -replace '"', '\"'
(& $dsc set --resource 'settings' --module App --input $in | Select-Object -Last 1); "exit $LASTEXITCODE"
Show-App 'after set'
Show-Tasks 'after set'
(& $dsc test --resource 'settings' --module App --input $in | Select-Object -Last 1); "exit $LASTEXITCODE"
"== start PowerToys, wait, read again"
$exe = "$env:LOCALAPPDATA\PowerToys\PowerToys.exe"
if (-not (Get-Process PowerToys -ErrorAction SilentlyContinue)) { Start-Process $exe; "started $exe" }
Start-Sleep -Seconds 20
Show-Procs
Show-App 'after run'
Show-Tasks 'after run'
"== set again while running"
(& $dsc set --resource 'settings' --module App --input $in | Select-Object -Last 1); "exit $LASTEXITCODE"
Start-Sleep -Seconds 5
Show-App 'after set while running'
Show-Tasks 'after set while running'
"== cmdpal settings"
$cmdpal = "$env:LOCALAPPDATA\Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState\settings.json"
$text = Get-Content -Raw $cmdpal -ErrorAction SilentlyContinue
"length $($text.Length)"
if ($text) { $text.Substring(0, [Math]::Min(2500, $text.Length)) }
"== HKCU Run"
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
(Get-ItemProperty $run -ErrorAction SilentlyContinue).psobject.Properties |
    Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "  $($_.Name)=$($_.Value)" }
exit 0
