$ErrorActionPreference = 'Stop'

$repoDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scriptPath = Join-Path $repoDirectory 'windows/link_codex.ps1'
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-link-codex-{0}" -f [guid]::NewGuid())
$userDirectory = Join-Path $sandbox 'home'
$codexDirectory = Join-Path $userDirectory '.codex'
$configPath = Join-Path $codexDirectory 'config.toml'

try {
    New-Item -ItemType Directory -Path $codexDirectory -Force | Out-Null
    @'
model = "old-model"
model_reasoning_effort = "high"
notify = ["keep-me"]

[desktop]
followUpQueueMode = "steer"

[projects.'keep-me']
trust_level = "trusted"
'@ | Set-Content -LiteralPath $configPath

    & $scriptPath -UserDirectory $userDirectory -CodexDirectory $codexDirectory -SkipLinks

    $actual = Get-Content -LiteralPath $configPath -Raw
    if ($actual -notmatch '(?m)^model = "gpt-5\.6-sol"\r?$') {
        throw 'model default was not merged.'
    }
    if ($actual -notmatch '(?m)^model_reasoning_effort = "medium"\r?$') {
        throw 'reasoning default was not merged.'
    }
    foreach ($preserved in @('notify = ["keep-me"]', '[desktop]', '[projects.''keep-me'']')) {
        if (-not $actual.Contains($preserved)) {
            throw "Existing config was not preserved: $preserved"
        }
    }

    & $scriptPath -UserDirectory $userDirectory -CodexDirectory $codexDirectory -SkipLinks
    $secondRun = Get-Content -LiteralPath $configPath -Raw
    if ($secondRun -ne $actual) {
        throw 'A second run changed an already configured file.'
    }

    if (Test-Path -LiteralPath (Join-Path $userDirectory '.claude')) {
        throw '-SkipLinks still linked something under .claude.'
    }

    Write-Output 'ok link_codex'

    # Links need symlink rights: the CI runner is an administrator, a
    # workstation needs Developer Mode.
    function New-TestLink([string]$Destination, [string]$Source, [switch]$Directory) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        $flag = if ($Directory) { '/D ' } else { '' }
        Push-Location -LiteralPath $sandbox
        cmd.exe /d /c "mklink $flag`"$Destination`" `"$Source`"" | Out-Null
        $made = $LASTEXITCODE -eq 0
        Pop-Location
        if (-not $made) {
            throw 'This test needs symlink rights: Developer Mode, or an administrator shell.'
        }
    }
    function Assert-Link([string]$Destination, [string]$Source) {
        $item = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        # Windows PowerShell 5.1 reports a UNC target as UNC\server\share.
        $target = [string]@($item.Target)[0] -replace '^UNC\\', '\\'
        if ($null -eq $item -or $item.LinkType -ne 'SymbolicLink' -or $target -ne $Source) {
            throw "Not linked to ${Source}: $Destination"
        }
    }

    # Arrange: what an older checkout and other tools left behind.
    $claudeDirectory = Join-Path $userDirectory '.claude'
    $skillSources = @(Get-ChildItem -LiteralPath (Join-Path $repoDirectory 'claudecode/skills') -Directory)
    $agentSources = @(Get-ChildItem -LiteralPath (Join-Path $repoDirectory 'claudecode/agents') -File -Filter '*.md')
    $oldCheckout = Join-Path $sandbox 'old/claudecode'
    $theirSkill = Join-Path $claudeDirectory "skills/$($skillSources[0].Name)"
    New-Item -ItemType Directory -Path $theirSkill -Force | Out-Null
    'not ours' | Set-Content -LiteralPath (Join-Path $theirSkill 'SKILL.md')
    $theirAgentTarget = Join-Path $sandbox 'their-agent.md'
    'not ours' | Set-Content -LiteralPath $theirAgentTarget
    $theirAgent = Join-Path $claudeDirectory "agents/$($agentSources[0].Name)"
    New-TestLink $theirAgent $theirAgentTarget
    # Replacing an old link must leave what it pointed at untouched.
    $oldSkill = Join-Path $oldCheckout "skills/$($skillSources[1].Name)"
    New-Item -ItemType Directory -Path $oldSkill -Force | Out-Null
    'old checkout' | Set-Content -LiteralPath (Join-Path $oldSkill 'SKILL.md')
    New-TestLink (Join-Path $claudeDirectory "skills/$($skillSources[1].Name)") $oldSkill -Directory
    $oldAgent = Join-Path $oldCheckout "agents/$($agentSources[1].Name)"
    New-Item -ItemType Directory -Path (Split-Path -Parent $oldAgent) -Force | Out-Null
    'old checkout' | Set-Content -LiteralPath $oldAgent
    New-TestLink (Join-Path $claudeDirectory "agents/$($agentSources[1].Name)") $oldAgent
    $oldRules = Join-Path $oldCheckout 'rules'
    New-Item -ItemType Directory -Path $oldRules -Force | Out-Null
    New-TestLink (Join-Path $claudeDirectory 'rules/dotfiles') $oldRules -Directory
    $goneSkill = Join-Path $claudeDirectory 'skills/removed-from-repo'
    New-TestLink $goneSkill (Join-Path $oldCheckout 'skills/removed-from-repo') -Directory
    # A checkout that cannot be reached, as a stopped WSL distribution.
    $unreachableSkill = Join-Path $claudeDirectory 'skills/in-a-stopped-distro'
    New-TestLink $unreachableSkill (Join-Path $sandbox 'unreachable/claudecode/skills/in-a-stopped-distro') -Directory
    $goneAgent = Join-Path $claudeDirectory 'agents/removed-from-repo.md'
    New-TestLink $goneAgent (Join-Path $oldCheckout 'agents/removed-from-repo.md')
    # Another tool's link that is broken too: not ours to tidy.
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'their-tool/skills') -Force | Out-Null
    $theirBrokenSkill = Join-Path $claudeDirectory 'skills/their-broken'
    New-TestLink $theirBrokenSkill (Join-Path $sandbox 'their-tool/skills/gone') -Directory

    # -WhatIf changes nothing.
    & $scriptPath -UserDirectory $userDirectory -CodexDirectory $codexDirectory -WhatIf 3>$null 6>$null | Out-Null
    Assert-Link (Join-Path $claudeDirectory "skills/$($skillSources[1].Name)") $oldSkill
    if ($null -eq (Get-Item -LiteralPath $goneSkill -Force -ErrorAction SilentlyContinue)) {
        throw "-WhatIf removed a link: $goneSkill"
    }

    # Act.
    & $scriptPath -UserDirectory $userDirectory -CodexDirectory $codexDirectory 3>$null | Out-Null

    # Assert.
    Assert-Link (Join-Path $codexDirectory 'AGENTS.md') (Join-Path $repoDirectory 'codex/AGENTS.md')
    Assert-Link (Join-Path $claudeDirectory 'rules/dotfiles') (Join-Path $repoDirectory 'claudecode/rules')
    foreach ($skill in $skillSources | Select-Object -Skip 1) {
        Assert-Link (Join-Path $claudeDirectory "skills/$($skill.Name)") $skill.FullName
    }
    foreach ($agent in $agentSources | Select-Object -Skip 1) {
        Assert-Link (Join-Path $claudeDirectory "agents/$($agent.Name)") $agent.FullName
    }
    if ((Get-Item -LiteralPath $theirSkill -Force).LinkType -or
        (Get-Content -LiteralPath (Join-Path $theirSkill 'SKILL.md')) -ne 'not ours') {
        throw "A skill directory that is not ours was replaced: $theirSkill"
    }
    Assert-Link $theirAgent $theirAgentTarget
    if ((Get-Content -LiteralPath (Join-Path $oldSkill 'SKILL.md')) -ne 'old checkout' -or
        (Get-Content -LiteralPath $oldAgent) -ne 'old checkout') {
        throw 'Replacing an old link changed what it pointed at.'
    }
    if ($null -ne (Get-Item -LiteralPath $goneSkill -Force -ErrorAction SilentlyContinue)) {
        throw "A link to a removed skill was kept: $goneSkill"
    }
    if ($null -eq (Get-Item -LiteralPath $unreachableSkill -Force -ErrorAction SilentlyContinue)) {
        throw "A link into an unreachable checkout was removed: $unreachableSkill"
    }
    if ($null -ne (Get-Item -LiteralPath $goneAgent -Force -ErrorAction SilentlyContinue)) {
        throw "A link to a removed agent was kept: $goneAgent"
    }
    if ($null -eq (Get-Item -LiteralPath $theirBrokenSkill -Force -ErrorAction SilentlyContinue)) {
        throw "Another tool's broken link was removed: $theirBrokenSkill"
    }

    $rerun = & $scriptPath -UserDirectory $userDirectory -CodexDirectory $codexDirectory 3>$null | Out-String
    if ($rerun -notmatch "Already linked: .*$([regex]::Escape($skillSources[1].Name))") {
        throw 'A second run did not recognise the links it made.'
    }

    # Rules another tool put in our place stop the run before anything changes.
    $otherHome = Join-Path $sandbox 'other-home'
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'their-rules') -Force | Out-Null
    New-TestLink (Join-Path $otherHome '.claude/rules/dotfiles') (Join-Path $sandbox 'their-rules') -Directory
    $stopped = $false
    try {
        & $scriptPath -UserDirectory $otherHome -CodexDirectory (Join-Path $otherHome '.codex') 3>$null | Out-Null
    } catch {
        $stopped = $_.Exception.Message -like 'Preserving existing destination:*'
    }
    if (-not $stopped) {
        throw 'Rules that are not ours did not stop the run.'
    }
    Assert-Link (Join-Path $otherHome '.claude/rules/dotfiles') (Join-Path $sandbox 'their-rules')

    Write-Output 'ok link_codex links'
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
