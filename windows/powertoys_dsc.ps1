# What PowerToys should be set to (powertoys-settings.json) and how far the
# machine is from it, dot-sourced by the script that applies it and the check
# that reads it back. PowerToys.DSC.exe is PowerToys' own settings tool.

function Find-PowerToysDsc {
    # Per-user is what winget installs by default; Program Files is the machine-scope install.
    @((Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.DSC.exe'),
        (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.DSC.exe')) |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

# Each module's wanted settings, as the JSON argument PowerToys.DSC.exe takes.
function Get-PowerToysWanted {
    $wanted = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'powertoys-settings.json') | ConvertFrom-Json
    foreach ($module in $wanted.psobject.Properties) {
        $json = $module.Value | ConvertTo-Json -Depth 10 -Compress
        # Windows PowerShell 5.1 drops the quotes inside an argument it hands a
        # native program unless they are escaped; PowerShell 7 passes them as is.
        if ($PSVersionTable.PSVersion.Major -lt 7) { $json = $json -replace '"', '\"' }
        [pscustomobject]@{ Module = $module.Name; Json = $json }
    }
}

# The modules whose settings differ from powertoys-settings.json.
function Get-PowerToysDrift([string]$Dsc) {
    foreach ($entry in Get-PowerToysWanted) {
        $state = & $Dsc test --resource 'settings' --module $entry.Module --input $entry.Json | Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or -not $state -or -not ($state | ConvertFrom-Json)._inDesiredState) { $entry.Module }
    }
}

# "Run at startup" is this scheduled task, which PowerToys registers when it
# starts with the setting on; the setting alone starts nothing.
function Test-PowerToysAutostart {
    [bool](Get-ScheduledTask -TaskPath '\PowerToys\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like 'Autorun for *' -and $_.State -ne 'Disabled' })
}
