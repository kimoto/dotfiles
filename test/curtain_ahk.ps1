# Runs the Windows curtain under a real AutoHotkey v2: its rules against the
# same cases as the Mac's (curtain_logic_test.ahk), and mac-keys.ahk with the
# curtain included through /validate, so a syntax error fails here rather than
# as a dialog at login. Installs AutoHotkey with Chocolatey where it is missing.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath

function Find-AutoHotkey {
    @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

$ahk = Find-AutoHotkey
if (-not $ahk) {
    choco install autohotkey --yes --no-progress | Out-Null
    $ahk = Find-AutoHotkey
}
if (-not $ahk) { throw 'AutoHotkey v2 is not installed and Chocolatey did not install it.' }

# AutoHotkey is a GUI program: its output comes back only through files, and a
# script stuck on a dialog must not hold the job until its timeout.
function Invoke-Ahk([string[]]$arguments) {
    $out = New-TemporaryFile
    $err = New-TemporaryFile
    $p = Start-Process -FilePath $ahk -ArgumentList $arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput $out -RedirectStandardError $err
    # Without the handle taken while it runs, ExitCode reads back as $null.
    $null = $p.Handle
    if (-not $p.WaitForExit(60000)) {
        $p.Kill()
        throw "AutoHotkey did not finish: $($arguments -join ' ')"
    }
    $text = (Get-Content -Raw -Encoding UTF8 $out) + (Get-Content -Raw -Encoding UTF8 $err)
    Remove-Item $out, $err
    if ($null -eq $p.ExitCode) { throw "No exit code from AutoHotkey: $($arguments -join ' ')" }
    [pscustomobject]@{ Code = $p.ExitCode; Text = $text }
}

$failed = $false
$test = Invoke-Ahk @('/ErrorStdOut', "`"$(Join-Path $repo 'test\curtain_logic_test.ahk')`"")
Write-Output $test.Text
if ($test.Code -ne 0) { $failed = $true; Write-Output "curtain_logic_test.ahk exited $($test.Code)" }

foreach ($script in @('windows\autohotkey\mac-keys.ahk', 'windows\autohotkey\curtain.ahk',
        'windows\autohotkey\launch-mac-keys.ahk')) {
    $check = Invoke-Ahk @('/ErrorStdOut', '/Validate', "`"$(Join-Path $repo $script)`"")
    if ($check.Code -ne 0) { $failed = $true; Write-Output "$script does not load:`n$($check.Text)" }
}
if ($failed) { exit 1 }
