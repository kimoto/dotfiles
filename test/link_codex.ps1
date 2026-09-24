$ErrorActionPreference = 'Stop'

$repoDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
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

    Write-Output 'ok link_codex'
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
