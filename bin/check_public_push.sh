#!/bin/bash

# Stop in front of the one git operation that has no undo: a push to a PUBLIC
# repository. A force-push moves the ref back, but the objects stay fetchable by
# SHA - measured: a commit already off master still answered 200 from the API
# and its blob still fetched - so the only control that works is the moment
# before the push. A private remote
# is left alone; the cost of being asked is only paid where publishing happens.
#
# Called by the `git` wrapper function in .zshrc with the command's whole argv,
# so the wrapper only has to pick WHEN to ask - every decision about WHAT counts
# as a publishing push is here, where it can be tested.
#
# Usage:
#   check_public_push.sh <the full argv of a git command>   # e.g. -C /r push origin main
# Exit:
#   0  not a push, remote is not GitHub, or the remote is private -> proceed
#   1  the remote is public (or its visibility could not be read) and no yes
# Intentional bypass: PUBLIC_PUSH_OK=1 git push ...

set -euo pipefail

# --- is this invocation a push at all? -------------------------------------
# Global options may sit in front of the subcommand, and these carry a separate
# value that must not be mistaken for it (`git -C /some/repo push`).
sub=""
while [ $# -gt 0 ]; do
    case "$1" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix)
            shift
            if [ $# -gt 0 ]; then shift; fi
            ;;
        -*) shift ;;
        *)  sub="$1"; shift; break ;;
    esac
done

if [ "$sub" != "push" ] || [ -n "${PUBLIC_PUSH_OK:-}" ]; then
    exit 0
fi

# --- which remote is this push aimed at? -----------------------------------
remote=""
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)     shift; remote="${1:-}"; break ;;
        --repo=*)   remote="${1#--repo=}"; break ;;
        -o|--push-option|--receive-pack|--exec)
            shift
            if [ $# -gt 0 ]; then shift; fi
            ;;
        -*) shift ;;
        *)  remote="$1"; break ;;
    esac
done

if [ -z "$remote" ]; then
    branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    remote=$(git config --get "branch.${branch}.remote" 2>/dev/null || true)
    [ -n "$remote" ] || remote=$(git config --get remote.pushDefault 2>/dev/null || true)
    [ -n "$remote" ] || remote="origin"
fi

# A push target may be a URL rather than a configured remote name.
url=$(git remote get-url --push "$remote" 2>/dev/null || echo "$remote")

# --- GitHub only ------------------------------------------------------------
# Anywhere else, visibility is not a question this can answer, and a guard that
# fires where it cannot judge is a guard that gets switched off.
case "$url" in
    *github.com[:/]*) ;;
    *) exit 0 ;;
esac

slug="${url#*github.com}"
slug="${slug#:}"
slug="${slug#/}"
slug="${slug%.git}"
owner="${slug%%/*}"
name="${slug#*/}"
name="${name%%/*}"
if [ -z "$owner" ] || [ -z "$name" ] || [ "$owner" = "$slug" ]; then
    exit 0
fi

# One API call, ~0.6s, and only on a push: the push itself is a network round
# trip, so this sits inside a wait that was already accepted. The timeout is
# there because a gh that never returns would take the terminal with it.
visibility="unknown"
if command -v gh >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
        visibility=$(timeout 5 gh api "repos/$owner/$name" \
            --jq 'if .private then "private" else "public" end' 2>/dev/null) || visibility="unknown"
    else
        visibility=$(gh api "repos/$owner/$name" \
            --jq 'if .private then "private" else "public" end' 2>/dev/null) || visibility="unknown"
    fi
fi
[ -n "$visibility" ] || visibility="unknown"

if [ "$visibility" = "private" ]; then
    exit 0
fi

if [ "$visibility" = "public" ]; then
    headline="PUBLIC: $owner/$name - this push is visible to anyone."
else
    headline="UNKNOWN visibility: $owner/$name - gh could not answer, so treat it as public."
fi

# A terminal can answer; anything else (an agent, a script, CI) is told what the
# target is and stops, so the decision reaches a person instead of a default.
if [ -t 0 ]; then
    printf '%s\n' "$headline" >&2
    printf 'push anyway? [y/N] ' >&2
    read -r -t 30 answer || answer=""
    case "$answer" in
        [yY]|[yY][eE][sS]) exit 0 ;;
    esac
    echo "stopped." >&2
    exit 1
fi

printf '%s\n' "$headline" >&2
echo "Stopped: this cannot be taken back - a force-push removes the ref, the objects stay" >&2
echo "fetchable by SHA. Ask the person whose repository it is." >&2
exit 1
