# Registers the workstation's Claude Code hooks for this Windows user, with the
# same bin/install_claude_*.sh that mkworld.sh runs on macOS and Linux, run
# through Git Bash: the shell Claude Code itself runs hook commands in.
# Run from Windows PowerShell, from the checkout that stays (see setup.ps1).
[CmdletBinding()]
param(
    [string]$BinDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'bin')
)

$ErrorActionPreference = 'Stop'

# The tmux hooks are left out: there is no tmux on the Windows side.
$installers = @(
    'install_claude_idle_hooks.sh',
    'install_claude_context_hooks.sh',
    'install_claude_secret_scan_hook.sh',
    'install_claude_review_gate.sh',
    'install_claude_pr_hooks.sh'
)

. (Join-Path $PSScriptRoot 'git_bash.ps1')

# winget put jq on PATH after this process started; read PATH again as a new
# terminal would have it.
$env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
    [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    # Each installer would only warn and skip, leaving no hook and no error.
    throw 'jq not found; winget import of windows/winget-packages.json installs it.'
}

$bash = Find-GitBash
# Git Bash reads forward slashes; \\wsl.localhost\... becomes //wsl.localhost/...
$bin = (Resolve-Path -LiteralPath $BinDirectory).ProviderPath -replace '\\', '/'

# The registered commands point at the checkout's bin/: ~/bin on Windows is not
# ours (bin/claude_settings_lib.sh). HOME is where Claude Code on Windows reads
# its settings.
$saved = @{ CLAUDE_HOOK_BIN = $env:CLAUDE_HOOK_BIN; HOME = $env:HOME }
$env:CLAUDE_HOOK_BIN = $bin
$env:HOME = $env:USERPROFILE
try {
    foreach ($installer in $installers) {
        # Each installer reports on stderr, which 5.1 under 'Stop' would turn
        # into a terminating error.
        $ErrorActionPreference = 'Continue'
        & $bash "$bin/$installer"
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0) {
            throw "$installer failed with exit code $LASTEXITCODE."
        }
    }
} finally {
    # setup.ps1 runs the later steps in this same process.
    foreach ($name in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
}
