# The two judgements windows/powertoys_dsc.ps1 makes, against a stand-in tool
# and stand-in scheduled tasks: the real PowerToys only ever shows the check
# a machine that is already right.
$ErrorActionPreference = 'Stop'

$repoDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
. (Join-Path $repoDirectory 'windows/powertoys_dsc.ps1')
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-powertoys-dsc-{0}" -f [guid]::NewGuid())

try {
    New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

    # Answers by module name: argument 5 of `test --resource settings --module <name>`.
    $tool = Join-Path $sandbox 'dsc.cmd'
    Set-Content -LiteralPath $tool -Encoding Ascii -Value @(
        '@echo off'
        'if "%5"=="Matches" (echo {"_inDesiredState":true}& echo []& exit /b 0)'
        'if "%5"=="Differs" (echo {"_inDesiredState":false}& echo ["settings"]& exit /b 0)'
        'if "%5"=="Fails" (echo {"_inDesiredState":true}& exit /b 1)'
        'if "%5"=="Silent" exit /b 0'
        'echo not json'
        'exit /b 0'
    )
    $wanted = Join-Path $sandbox 'wanted.json'
    $modules = 'Matches', 'Differs', 'Fails', 'Silent', 'Garbled'
    $entries = $modules | ForEach-Object { "`"$_`": { `"settings`": { `"startup`": true } }" }
    Set-Content -LiteralPath $wanted -Value ('{"modules":{' + ($entries -join ',') + '}}')

    $drift = @(Get-PowerToysDrift $tool $wanted)
    $expected = 'Differs', 'Fails', 'Silent', 'Garbled'
    if (($drift -join ',') -ne ($expected -join ',')) {
        throw "Drift is '$($drift -join ',')', not '$($expected -join ',')'."
    }

    function New-Task([string]$Name, [string]$State) { [pscustomobject]@{ TaskName = $Name; State = $State } }
    $cases = @(
        @{ Tasks = @(); Expected = $false; Why = 'no task' }
        @{ Tasks = @(New-Task 'Autorun for someone' 'Disabled'); Expected = $false; Why = 'a disabled task' }
        @{ Tasks = @(New-Task 'Update' 'Ready'); Expected = $false; Why = 'another task' }
        @{ Tasks = @(New-Task 'Autorun for someone' 'Ready'); Expected = $true; Why = 'the startup task' }
    )
    foreach ($case in $cases) {
        $script:tasks = $case.Tasks
        function Get-ScheduledTask { $script:tasks }
        if ((Test-PowerToysAutostart) -ne $case.Expected) {
            throw "Test-PowerToysAutostart did not answer $($case.Expected) for $($case.Why)."
        }
    }

    # Command Palette's file as it writes it: the hotkey first, then other
    # objects with the same shape, one of them under the same name deeper in.
    $palette = Join-Path $sandbox 'palette.json'
    $other = '{ "win": true, "ctrl": false, "alt": true, "shift": false, "code": 74, "key": "" }'
    $before = @(
        '{'
        '  "Hotkey": {'
        '    "win": true,'
        '    "ctrl": false,'
        '    "alt": true,'
        '    "shift": false,'
        '    "code": 32,'
        '    "key": ""'
        '  },'
        "  `"DockFocusHotkey`": $other,"
        '  "Language": "",'
        "  `"ProviderSettings`": { `"one`": { `"Hotkey`": $other, `"PinnedCommandIds`": [] } }"
        '}'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($palette, $before)
    $hotkey = Get-CommandPaletteWantedHotkey
    if (Test-CommandPaletteHotkey $palette $hotkey) {
        throw 'Test-CommandPaletteHotkey took the default hotkey for the wanted one.'
    }
    if (Test-CommandPaletteHotkey (Join-Path $sandbox 'missing.json') $hotkey) {
        throw 'Test-CommandPaletteHotkey passed a settings file that does not exist.'
    }
    $half = Join-Path $sandbox 'half.json'
    [System.IO.File]::WriteAllText($half, '{ "Hotkey": { "win": true,')
    if ($null -ne (Get-CommandPaletteHotkey $half)) {
        throw 'Get-CommandPaletteHotkey read a hotkey out of a half-written file.'
    }
    Set-CommandPaletteHotkey $palette $hotkey
    if (-not (Test-CommandPaletteHotkey $palette $hotkey)) {
        throw 'Set-CommandPaletteHotkey did not leave the wanted hotkey.'
    }
    # Everything after the top-level hotkey is Command Palette's and stays as it was.
    $after = [System.IO.File]::ReadAllText($palette)
    $rest = $before.Substring($before.IndexOf('  "DockFocusHotkey"'))
    if (-not $after.EndsWith($rest)) {
        throw "Set-CommandPaletteHotkey changed more than the top-level hotkey: $after"
    }

    # One part off is a different key, whichever part it is.
    $nearly = Join-Path $sandbox 'nearly.json'
    foreach ($part in '"shift":false', '"code":32') {
        $changed = $part.Replace('false', 'true').Replace('32', '74')
        if (-not $after.Contains($part)) { throw "The written hotkey has no $part to change: $after" }
        [System.IO.File]::WriteAllText($nearly, $after.Replace($part, $changed))
        if (Test-CommandPaletteHotkey $nearly $hotkey) {
            throw "Test-CommandPaletteHotkey passed a hotkey with $changed."
        }
    }

    # A file whose top-level hotkey cannot be found is put back as it was, not
    # half-written: with no hotkey at all, and with one only deeper in.
    $odd = Join-Path $sandbox 'odd.json'
    foreach ($text in '{ "Language": "" }', "{ `"ProviderSettings`": { `"one`": { `"Hotkey`": $other } } }") {
        [System.IO.File]::WriteAllText($odd, $text)
        $refused = $false
        try { Set-CommandPaletteHotkey $odd $hotkey } catch { $refused = $true }
        if (-not $refused -or [System.IO.File]::ReadAllText($odd) -ne $text) {
            throw "Set-CommandPaletteHotkey did not refuse, or changed, a file with no top-level hotkey: $text"
        }
    }
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'ok powertoys_dsc'
