#!/bin/bash
# Benchmark interactive zsh startup in CI and keep the numbers around instead
# of letting them scroll away in the job log:
#   - appended to $GITHUB_STEP_SUMMARY as a table (the run's Summary page)
#   - written to $RUNNER_TEMP/zsh-startup-bench.txt for the artifact upload
#
# The metric is deliberately simple: wall-clock time of `zsh -lic exit` (parse
# the config, run compinit/sheldon/evalcache, become ready for a command),
# repeated N times, reported as min/mean/max. An earlier version drove
# romkatv/zsh-bench here, but its zle-level protocol deadlocks against this
# config (`setopt ignore_eof` blocks its stdin-EOF exit on a completion-list
# prompt, and its instrumented typing never completed against the custom
# space/enter widgets) - see PR #107. A plain timing loop cannot hang and is
# what a startup-time budget check would threshold anyway. Measures the
# dotfiles that bin/mkworld.sh symlinked into $HOME during the CI prepare
# phase. Record-only: it never fails the build over a slow number.

set -euo pipefail

die() {
  echo "CI error: $*" >&2
  exit 1
}

# Same startup toggles as ci_zsh_loading_test.sh: keep the sync/brew reminders
# (network + noise) out of the measured startup.
export DOTFILES_NO_SYNC_CHECK=1
export DOTFILES_NO_BREW_CHECK=1
export TERM="xterm-256color"

# In CI the shell under test is the brew zsh from Brewfile.basic - the same
# binary the loading test exercises.
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
command -v zsh >/dev/null || die "zsh not found"

# One timed startup. CI= (empty) for the same reason ci_zsh_loading_test.sh
# runs every probe with it: CI=true switches .zshrc into strict mode
# (err_exit), which is not how an interactive shell runs for real. The
# per-run timeout turns any regression into a hang into a fast, attributable
# step failure instead of a job stuck until the runner's 6h limit.
run_once() {
  local t0 t1
  t0=$(date +%s%N)
  timeout 60 env CI= zsh -lic exit </dev/null >/dev/null 2>&1 \
    || die "interactive zsh startup failed or timed out (rc=$?)"
  t1=$(date +%s%N)
  echo $(((t1 - t0) / 1000000))
}

iters="${ZSH_BENCH_ITERS:-10}"
run_once >/dev/null # warm-up: compdump/eval caches, page cache

samples=()
for _ in $(seq "$iters"); do
  samples+=("$(run_once)")
done

out_file="${RUNNER_TEMP:-$(mktemp -d)}/zsh-startup-bench.txt"
{
  echo "zsh_version=$(zsh --version | awk '{print $2}')"
  echo "iters=$iters"
  printf '%s\n' "${samples[@]}" | sort -n | awk '
    { v[NR] = $1; sum += $1 }
    END {
      printf "startup_min_ms=%d\n", v[1]
      printf "startup_mean_ms=%d\n", sum / NR
      printf "startup_max_ms=%d\n", v[NR]
    }'
  echo "samples_ms=$(
    IFS=,
    echo "${samples[*]}"
  )"
} | tee "$out_file"

# The key=value lines are the machine-readable output; render them as a table
# on the run's Summary page so results are visible without digging through
# logs.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## zsh startup bench (zsh -lic exit)"
    echo ""
    echo "| metric | value |"
    echo "| --- | --- |"
    grep -E '^[a-z_]+=' "$out_file" | sed -E 's/^([a-z_]+)=(.*)$/| \1 | \2 |/'
  } >>"$GITHUB_STEP_SUMMARY"
fi
