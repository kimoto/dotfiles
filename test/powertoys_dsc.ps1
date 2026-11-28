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
    $hotkey = (Get-Content -Raw -LiteralPath (Join-Path $repoDirectory 'windows/powertoys-settings.json') |
        ConvertFrom-Json).commandPaletteHotkey
    if (Test-CommandPaletteHotkey $palette $hotkey) {
        throw 'Test-CommandPaletteHotkey took the default hotkey for the wanted one.'
    }
    if (Test-CommandPaletteHotkey (Join-Path $sandbox 'missing.json') $hotkey) {
        throw 'Test-CommandPaletteHotkey passed a settings file that does not exist.'
    }
    Set-CommandPaletteHotkey $palette $hotkey
    if (-not (Test-CommandPaletteHotkey $palette $hotkey)) {
        throw 'Set-CommandPaletteHotkey did not leave the wanted hotkey.'
    }
    $after = [System.IO.File]::ReadAllText($palette)
    $rest = $before.Substring($before.IndexOf('  "DockFocusHotkey"'))
    if (-not $after.EndsWith($rest)) {
        throw "Set-CommandPaletteHotkey changed more than the top-level hotkey: $after"
    }

    # A file with no hotkey to replace is put back as it was, not half-written.
    $bare = Join-Path $sandbox 'bare.json'
    [System.IO.File]::WriteAllText($bare, '{ "Language": "" }')
    $refused = $false
    try { Set-CommandPaletteHotkey $bare $hotkey } catch { $refused = $true }
    if (-not $refused -or [System.IO.File]::ReadAllText($bare) -ne '{ "Language": "" }') {
        throw 'Set-CommandPaletteHotkey did not refuse, or changed, a file with no hotkey.'
    }
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'ok powertoys_dsc'
