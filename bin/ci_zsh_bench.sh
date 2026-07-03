#!/bin/bash
# Benchmark interactive zsh startup with zsh-bench (romkatv/zsh-bench) and keep
# the numbers around instead of letting them scroll away in the job log:
#   - appended to $GITHUB_STEP_SUMMARY as a table (the run's Summary page)
#   - written to $RUNNER_TEMP/zsh-bench.txt for the workflow's artifact upload
# Measures the login shell of the current user, i.e. the dotfiles that
# bin/mkworld.sh symlinked into $HOME during the CI prepare phase. Record-only:
# it never fails the build over a slow number.

set -euo pipefail

# Same startup toggles as ci_zsh_loading_test.sh: keep the sync/brew reminders
# (network + noise) out of the measured startup.
export DOTFILES_NO_SYNC_CHECK=1
export DOTFILES_NO_BREW_CHECK=1
export TERM="xterm-256color"

# zsh-bench needs zsh >= 5.8 on PATH to run itself; in CI that's the brew zsh
# from Brewfile.basic - the same binary the loading test exercises.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Pinned like GitHub Actions `uses:`: a full commit SHA, not a branch.
ZSH_BENCH_REPO="https://github.com/romkatv/zsh-bench"
ZSH_BENCH_REV="28b1b1bc888159f0a2cf50f9d29381758341aba1"

bench_dir="$(mktemp -d)"
trap 'rm -rf "$bench_dir"' EXIT
git init --quiet "$bench_dir"
git -C "$bench_dir" fetch --quiet --depth 1 "$ZSH_BENCH_REPO" "$ZSH_BENCH_REV"
git -C "$bench_dir" checkout --quiet FETCH_HEAD

out_file="${RUNNER_TEMP:-$(mktemp -d)}/zsh-bench.txt"
"$bench_dir/zsh-bench" --iters "${ZSH_BENCH_ITERS:-16}" | tee "$out_file"

# The key=value lines are the machine-readable half of the output; render them
# as a table on the run's Summary page so results are visible without digging
# through logs.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## zsh-bench (login shell startup)"
    echo ""
    echo "| metric | value |"
    echo "| --- | --- |"
    grep -E '^[a-z_]+=' "$out_file" | sed -E 's/^([a-z_]+)=(.*)$/| \1 | \2 |/'
  } >>"$GITHUB_STEP_SUMMARY"
fi
