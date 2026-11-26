# Find-GitBash, dot-sourced by the scripts that run what Claude Code on Windows
# runs: its hook commands go to Git Bash.

# Git Bash, not the bash first on PATH: that one is WSL's System32\bash.exe.
# git --exec-path is <Git>/mingw64/libexec/git-core, whichever of git's own
# directories put git on PATH.
function Find-GitBash {
    if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path -LiteralPath $env:CLAUDE_CODE_GIT_BASH_PATH)) {
        return $env:CLAUDE_CODE_GIT_BASH_PATH
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git not found; install Git for Windows first.'
    }
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (git --exec-path)))
    $bash = Join-Path $root 'bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
        throw "Git Bash not found at $bash; set CLAUDE_CODE_GIT_BASH_PATH."
    }
    $bash
}
