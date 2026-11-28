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
    Set-Content -LiteralPath $wanted -Value ('{' + ($entries -join ',') + '}')

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
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'ok powertoys_dsc'
