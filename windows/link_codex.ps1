# Run from Windows PowerShell; native Windows links can target a WSL UNC checkout.
# Existing files and links belonging to another setup are never replaced.
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$UserDirectory = $env:USERPROFILE,
    [string]$CodexDirectory = $env:CODEX_HOME,
    [switch]$SkipLinks
)

$ErrorActionPreference = 'Stop'
$repoDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
if (-not $UserDirectory) {
    throw 'UserDirectory is required when USERPROFILE is unset.'
}
if (-not $CodexDirectory) {
    $CodexDirectory = Join-Path $UserDirectory '.codex'
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
    },
    @{
        Source = Join-Path $repoDirectory 'claudecode/rules'
        Destination = Join-Path $UserDirectory '.claude/rules/dotfiles'
    }
) }

# Preflight every destination before creating anything, including dangling links.
$pending = @()
foreach ($link in $links) {
    if (-not (Test-Path -LiteralPath $link.Source)) {
        throw "Missing source: $($link.Source)"
    }
    $existing = Get-Item -LiteralPath $link.Destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $link.Source) {
            Write-Output "Already linked: $($link.Destination)"
            continue
        }
        throw "Preserving existing destination: $($link.Destination). Merge or relocate it manually."
    }
    $pending += $link
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


foreach ($link in $pending) {
    if ($PSCmdlet.ShouldProcess($link.Destination, "Create symbolic link to $($link.Source)")) {
        $parentDirectory = Split-Path -Parent $link.Destination
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
        try {
            New-Item -ItemType SymbolicLink -Path $link.Destination -Target $link.Source | Out-Null
        } catch {
            throw "Could not create $($link.Destination): $($_.Exception.Message) " +
                'If Windows requires elevation, rerun this script from an administrator PowerShell.'
        }
        Get-Item -LiteralPath $link.Destination | Select-Object FullName, LinkType, Target
    }
}

$overridePath = Join-Path $CodexDirectory 'AGENTS.override.md'
if ((Test-Path -LiteralPath $overridePath) -and
    -not [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $overridePath -Raw))) {
    Write-Warning "$overridePath takes precedence over AGENTS.md."
}
