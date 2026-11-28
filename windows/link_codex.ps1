# Run from Windows PowerShell; native Windows links can target a WSL UNC checkout.
# Existing files and links belonging to another setup are never replaced; our own
# links from an older checkout are.
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$UserDirectory = $env:USERPROFILE,
    [string]$CodexDirectory = $env:CODEX_HOME,
    [switch]$SkipLinks
)

$ErrorActionPreference = 'Stop'

# A plain absolute file-system path. mklink and .NET resolve a relative path
# against the process directory, not PowerShell's, and know no PSDrive; and
# Windows PowerShell 5.1's Resolve-Path leaves '..' in a UNC path.
function Get-AbsolutePath([string]$Path) {
    [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
}

# Windows PowerShell 5.1 reports a link to \\server\share as UNC\server\share,
# and a relative target is relative to the link's own directory.
function Get-LinkTarget($Item) {
    $target = [string]@($Item.Target)[0] -replace '^UNC\\', '\\'
    if ($target -and -not [System.IO.Path]::IsPathRooted($target)) {
        $target = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $Item.FullName) $target))
    }
    $target
}

# Ours is a symlink into claudecode/<kind>/ of any checkout, as
# bin/prune_claude_links.sh decides it; for rules, the directory itself.
# Anything else belongs to another tool.
function Test-OurLink($Item, [string]$Kind) {
    $pattern = if ($Kind -eq 'rules') { '\\claudecode\\rules$' } else { "\\claudecode\\$Kind\\[^\\]+$" }
    $Item.LinkType -eq 'SymbolicLink' -and (Get-LinkTarget $Item) -match $pattern
}

# Deletes the link and never what it points at, whichever kind of link it is.
function Remove-Link([string]$Path) {
    if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) {
        [System.IO.Directory]::Delete($Path, $false)
    } else {
        [System.IO.File]::Delete($Path)
    }
}

# mklink rather than New-Item: Windows PowerShell 5.1's New-Item asks for
# elevation even with Developer Mode on, and mklink does not. The caller says
# which kind, since a target in a stopped WSL distribution cannot be asked.
function New-Link([string]$Destination, [string]$Source, [bool]$Directory) {
    $directoryFlag = if ($Directory) { '/D ' } else { '' }
    # Under 'Stop', 5.1 ends the script on mklink's own error message, before
    # the hint below can be shown.
    $ErrorActionPreference = 'Continue'
    # cmd.exe warns when started in a UNC directory, as it is when this script
    # runs from the WSL checkout.
    Push-Location -LiteralPath ([System.IO.Path]::GetTempPath())
    try {
        $output = cmd.exe /d /c "mklink $directoryFlag`"$Destination`" `"$Source`"" 2>&1
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create ${Destination}: $output " +
            'Turn on Developer Mode, or rerun this script from an administrator PowerShell.'
    }
}

if (-not $UserDirectory) {
    throw 'UserDirectory is required when USERPROFILE is unset.'
}
if (-not $CodexDirectory) {
    $CodexDirectory = Join-Path $UserDirectory '.codex'
}
$repoDirectory = Get-AbsolutePath (Join-Path $PSScriptRoot '..')
$UserDirectory = Get-AbsolutePath $UserDirectory
$CodexDirectory = Get-AbsolutePath $CodexDirectory
# cmd.exe expands %NAME% even inside quotes, so mklink would get another path.
foreach ($path in @($repoDirectory, $UserDirectory, $CodexDirectory)) {
    if ($path.Contains('%')) {
        throw "A path with '%' cannot be passed to mklink: $path"
    }
}
$configSource = Join-Path $repoDirectory 'codex/config.toml'
$configPath = Join-Path $CodexDirectory 'config.toml'
if (-not (Test-Path -LiteralPath $configSource -PathType Leaf)) {
    throw "Missing source: $configSource"
}

$links = if ($SkipLinks) { @() } else { @(
    @{
        Source = Join-Path $repoDirectory 'codex/AGENTS.md'
        Destination = Join-Path $CodexDirectory 'AGENTS.md'
        Kind = $null
    },
    @{
        Source = Join-Path $repoDirectory 'claudecode/rules'
        Destination = Join-Path $UserDirectory '.claude/rules/dotfiles'
        Kind = 'rules'
    }
) }

# Preflight every destination before creating anything, including dangling links.
$pending = @()
foreach ($link in $links) {
    if (-not (Test-Path -LiteralPath $link.Source)) {
        throw "Missing source: $($link.Source)"
    }
    $link.Replace = $false
    $existing = Get-Item -LiteralPath $link.Destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        if ($existing.LinkType -eq 'SymbolicLink' -and (Get-LinkTarget $existing) -eq $link.Source) {
            Write-Output "Already linked: $($link.Destination)"
            continue
        }
        $replaceable = $null -ne $link.Kind -and (Test-OurLink $existing $link.Kind)
        if (-not $replaceable) {
            throw "Preserving existing destination: $($link.Destination). Merge or relocate it manually."
        }
        $link.Replace = $true
    }
    $pending += $link
}

# Skills and agents are linked one by one, as bin/mklink.sh does: those
# directories also hold what other tools install, so an entry under one of our
# names stays unless it is our own link, from this or an older checkout.
if (-not $SkipLinks) {
    $itemSources = @(Get-ChildItem -LiteralPath (Join-Path $repoDirectory 'claudecode/skills') -Directory) +
        @(Get-ChildItem -LiteralPath (Join-Path $repoDirectory 'claudecode/agents') -File -Filter '*.md')
    foreach ($source in $itemSources) {
        $kind = if ($source.PSIsContainer) { 'skills' } else { 'agents' }
        $destination = Join-Path $UserDirectory ".claude/$kind/$($source.Name)"
        $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing -and $existing.LinkType -eq 'SymbolicLink' -and
            (Get-LinkTarget $existing) -eq $source.FullName) {
            Write-Output "Already linked: $destination"
            continue
        }
        if ($null -ne $existing -and -not (Test-OurLink $existing $kind)) {
            Write-Warning "$destination is not ours; left alone"
            continue
        }
        $pending += @{
            Source = $source.FullName; Destination = $destination; Kind = $kind; Replace = ($null -ne $existing)
        }
    }
}

# Only the top-level defaults from the checked-in file are owned here. Tables
# belong to Codex Desktop, plugins, MCP servers, and per-project trust state.
$defaults = [ordered]@{}
foreach ($line in Get-Content -LiteralPath $configSource) {
    if ($line -match '^\s*\[') {
        break
    }
    if ($line -match '^\s*([A-Za-z0-9_-]+)\s*=') {
        $defaults[$Matches[1]] = $line
    }
}
if ($defaults.Count -eq 0) {
    throw "No top-level defaults found in $configSource"
}

$configItem = Get-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
if ($null -ne $configItem -and ($configItem.PSIsContainer -or $null -ne $configItem.LinkType)) {
    throw "Preserving non-regular Codex config: $configPath"
}
$existingLines = if ($null -eq $configItem) { @() } else { @(Get-Content -LiteralPath $configPath) }
$tableIndex = $existingLines.Count
for ($index = 0; $index -lt $existingLines.Count; $index++) {
    if ($existingLines[$index] -match '^\s*\[') {
        $tableIndex = $index
        break
    }
}

$topLevel = [System.Collections.Generic.List[string]]::new()
$updated = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
for ($index = 0; $index -lt $tableIndex; $index++) {
    $line = $existingLines[$index]
    if ($line -match '^\s*([A-Za-z0-9_-]+)\s*=' -and $defaults.Contains($Matches[1])) {
        if ($updated.Add($Matches[1])) {
            $topLevel.Add($defaults[$Matches[1]])
        }
        continue
    }
    $topLevel.Add($line)
}
foreach ($key in $defaults.Keys) {
    if ($updated.Add($key)) {
        $topLevel.Add($defaults[$key])
    }
}
if ($tableIndex -lt $existingLines.Count -and
    $topLevel.Count -gt 0 -and
    -not [string]::IsNullOrWhiteSpace($topLevel[$topLevel.Count - 1])) {
    $topLevel.Add('')
}

$outputLines = @($topLevel)
if ($tableIndex -lt $existingLines.Count) {
    $outputLines += $existingLines[$tableIndex..($existingLines.Count - 1)]
}
$newConfig = ($outputLines -join [Environment]::NewLine) + [Environment]::NewLine
$oldConfig = if ($null -eq $configItem) { $null } else { [System.IO.File]::ReadAllText($configPath) }
if ($oldConfig -eq $newConfig) {
    Write-Output "Already configured: $configPath"
} elseif ($PSCmdlet.ShouldProcess($configPath, "Merge defaults from $configSource")) {
    New-Item -ItemType Directory -Path $CodexDirectory -Force | Out-Null
    $temporaryPath = Join-Path $CodexDirectory (".config.toml.{0}.tmp" -f $PID)
    try {
        $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($temporaryPath, $newConfig, $utf8WithoutBom)
        Move-Item -LiteralPath $temporaryPath -Destination $configPath -Force
    } finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
    Write-Output "Configured: $configPath"
}


# Replacing a link deletes the old one first, so find out before touching any
# link whether this shell may make them at all.
if ($pending.Count -gt 0 -and -not $WhatIfPreference) {
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-link-probe-{0}" -f [guid]::NewGuid())
    New-Link $probe $configSource $false
    Remove-Link $probe
}

foreach ($link in $pending) {
    if ($PSCmdlet.ShouldProcess($link.Destination, "Create symbolic link to $($link.Source)")) {
        $parentDirectory = Split-Path -Parent $link.Destination
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
        $isDirectory = Test-Path -LiteralPath $link.Source -PathType Container
        if (-not $link.Replace) {
            New-Link $link.Destination $link.Source $isDirectory
        } else {
            $old = Get-Item -LiteralPath $link.Destination -Force
            $oldTarget = Get-LinkTarget $old
            $oldIsDirectory = $old.PSIsContainer
            Remove-Link $link.Destination
            try {
                New-Link $link.Destination $link.Source $isDirectory
            } catch {
                $failure = $_.Exception.Message
                try {
                    if ($oldTarget.Contains('%')) {
                        throw "'%' in the old target"
                    }
                    New-Link $link.Destination $oldTarget $oldIsDirectory
                } catch {
                    throw "$failure The old link to $oldTarget could not be restored either."
                }
                throw
            }
        }
        Get-Item -LiteralPath $link.Destination | Select-Object FullName, LinkType, Target
    }
}

# A skill or agent removed from the repo leaves its link pointing at nothing,
# as bin/prune_claude_links.sh handles on macOS and Linux.
if (-not $SkipLinks) {
    foreach ($kind in @('skills', 'agents')) {
        $directory = Join-Path $UserDirectory ".claude/$kind"
        if (-not (Test-Path -LiteralPath $directory)) {
            continue
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force -Attributes ReparsePoint)) {
            # Ownership first: another tool's link may point at a share that
            # takes a network timeout to answer.
            if (-not (Test-OurLink $item $kind)) {
                continue
            }
            # Only when the checkout itself answers: a WSL distribution that
            # is not running would make every link into it look broken.
            $target = Get-LinkTarget $item
            if ((Test-Path -LiteralPath (Split-Path -Parent $target)) -and -not (Test-Path -LiteralPath $target)) {
                if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove broken link')) {
                    Remove-Link $item.FullName
                    Write-Output "Removed broken link: $($item.FullName)"
                }
            }
        }
    }
}

$overridePath = Join-Path $CodexDirectory 'AGENTS.override.md'
if ((Test-Path -LiteralPath $overridePath) -and
    -not [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $overridePath -Raw))) {
    Write-Warning "$overridePath takes precedence over AGENTS.md."
}
