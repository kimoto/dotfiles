#!/bin/bash

# Weekly cron wrapper: post the 404 digest of personal_website as a GitHub
# issue. Runs on the VPS (vps-sakura); the real work lives in
# ~/bin/report-404s.sh, whose source of truth is the personal_website repo
# (scripts/vps/report-404s.sh — sync via scp, do not edit the VPS copy).
#
# Wiring (manual, on the VPS crontab):
#   0 9 * * 1 run-parts --regex '\.sh$' "$HOME/dotfiles/cron/weekly"
# run-parts skips filenames containing dots by default, so --regex is
# required to pick up *.sh (kept as .sh so bin/lint_shell.sh covers it).
#
# Requires on the VPS:
#   ~/bin/report-404s.sh                       (deployed from personal_website)
#   ~/.secrets/github-404-report.token         (fine-grained PAT, issues RW)
set -euo pipefail

LOG_DIR="${HOME}/.local/state/404-report"
mkdir -p "$LOG_DIR"

{
    echo "=== start $(date '+%Y-%m-%dT%H:%M:%S%z')"
    "${HOME}/bin/report-404s.sh" --post
    echo "=== done $(date '+%Y-%m-%dT%H:%M:%S%z')"
} >> "${LOG_DIR}/cron.log" 2>&1
