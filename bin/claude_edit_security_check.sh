#!/bin/bash
# shellcheck disable=SC2016 # the rule patterns below match a literal $
# Claude Code PreToolUse hook for Edit/Write/MultiEdit (registered by
# bin/install_claude_security_hooks.sh, and by claudecode/settings-cloud.json in
# a cloud session): the first time an edit introduces a known-dangerous pattern
# into a file, stop it once and tell the model why. Retrying the same edit
# passes, so the model decides; this is a reminder, not a wall.
#
# Registered globally, not per repo: the repos that need it most are the ones
# with no linter of their own. Where a linter exists (shellcheck, zizmor) it
# still runs at commit; this only moves the notice to the moment of writing.
#
# ★An edit is flagged only when it adds a match: the new text holds more
#  matching lines than the text it replaces (Edit/MultiEdit) or the file it
#  overwrites (Write). Touching code that already had the pattern stays quiet.
# ⚠️ Each (session, file, rule) speaks once. A reminder that repeats on every
#    edit is one the model learns to retry past without reading.
# ⚠️ A list of what must not pass is never complete; that is acceptable here
#    only because nothing relies on this hook to stop anything.
# ⚠️ Fails open: any path it does not understand exits 0.
set -uo pipefail

STATE_DIR="${CLAUDE_EDIT_SECURITY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-edit-security}"

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null) || exit 0
session_id=$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null)
tool=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)
path=$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null)
case "$session_id" in
  ''|*[!A-Za-z0-9_-]*) exit 0 ;;
esac
[ -n "$path" ] || exit 0

case "$tool" in
  Write)
    new=$(jq -r '.tool_input.content // empty' <<<"$payload")
    old=""
    [ -r "$path" ] && old=$(cat "$path" 2>/dev/null)
    ;;
  Edit)
    new=$(jq -r '.tool_input.new_string // empty' <<<"$payload")
    old=$(jq -r '.tool_input.old_string // empty' <<<"$payload")
    ;;
  MultiEdit)
    new=$(jq -r '[.tool_input.edits[]?.new_string // empty] | join("\n")' <<<"$payload")
    old=$(jq -r '[.tool_input.edits[]?.old_string // empty] | join("\n")' <<<"$payload")
    ;;
  *) exit 0 ;;
esac
[ -n "$new" ] || exit 0

# rule <id> <file-path ERE, empty = any file> <what to do instead> <ERE>...
# The EREs are alternatives; any one matching is a hit.
# Each pattern is one a reviewer would ask about in any repo, whatever the
# language; anything a project's own linter would be the better judge of stays
# out, since that linter knows the context and this does not.
# A non-whitespace separator: read would merge runs of a whitespace IFS and
# drop an empty path field.
SEP=$'\x1f'
RULES=()
rule() {
  local id=$1 path_re=$2 msg=$3 re
  shift 3
  re=$(IFS='|'; printf '%s' "$*")
  RULES+=("$id$SEP$path_re$SEP$re$SEP$msg")
}

rule actions-injection '\.github/(workflows/[^/]*|actions/.*/action)\.ya?ml$' \
  'An expression expanded in run: can carry attacker text into a shell. Pass it via env: and quote it.' \
  '\$\{\{[^}]*(github\.event\.|github\.head_ref|inputs\.)'
rule pipe-to-shell '' \
  'Piping a download into a shell runs whatever the server sends. Save it, check a pinned hash, then run.' \
  '(curl|wget)[^|;]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)'
rule tls-off '' \
  'This turns off certificate or host-key checks, so anyone on the path can pose as the server.' \
  'curl[^|;]*[[:space:]](-k|--insecure)([[:space:]]|$)' \
  'verify[[:space:]]*=[[:space:]]*False' \
  'NODE_TLS_REJECT_UNAUTHORIZED' \
  'StrictHostKeyChecking[[:space:]=]+no' \
  'InsecureSkipVerify:[[:space:]]*true' \
  'rejectUnauthorized:[[:space:]]*false'
rule rm-unguarded '' \
  'An empty variable makes this rm -r /. Write ${VAR:?}/ so an unset variable stops the script.' \
  'rm[[:space:]]+-[A-Za-z]*[rR][A-Za-z]*[[:space:]][^;&|]*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?/'
rule chmod-world '' \
  '777 lets every user on the machine rewrite this. Grant the narrowest mode that works.' \
  'chmod[[:space:]]+(-R[[:space:]]+)?0?777([[:space:]]|$)'
rule secret-literal '' \
  'This looks like a real credential. Read it at runtime from the env, a 0600 file, or the keychain.' \
  '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
  'AKIA[0-9A-Z]{16}' \
  'gh[pousr]_[A-Za-z0-9]{36}' \
  'github_pat_[A-Za-z0-9_]{22,}' \
  'sk-ant-[A-Za-z0-9_-]{20,}' \
  'xox[abprs]-[A-Za-z0-9-]{10,}'
rule dom-xss '\.(jsx?|tsx?|mjs|cjs|vue|svelte|html?)$' \
  'A string inserted as HTML runs any markup in it. Use textContent, or sanitize it first.' \
  '\.(inner|outer)HTML[[:space:]]*\+?=' \
  'dangerouslySetInnerHTML' \
  'document\.write\(' \
  'insertAdjacentHTML\('
rule js-eval '\.(jsx?|tsx?|mjs|cjs|vue|svelte)$' \
  'Evaluating a string as code runs whatever reaches it. Parse data with JSON.parse instead.' \
  '(^|[^.A-Za-z0-9_$])eval\(' \
  'new Function\('
rule js-exec '\.(jsx?|tsx?|mjs|cjs)$' \
  'child_process exec runs its argument through a shell. Use execFile or spawn with an array.' \
  '(^|[^.A-Za-z0-9_$])exec(Sync)?\('
rule py-shell '\.py$' \
  'A shell command line built from data is injectable. Pass an argument list without shell=True.' \
  'shell[[:space:]]*=[[:space:]]*True' \
  'os\.(system|popen)\('
rule py-eval '\.py$' \
  'Evaluating a string as code runs whatever reaches it. Use ast.literal_eval or json for data.' \
  '(^|[^.A-Za-z0-9_])(eval|exec)\('
rule py-deserialize '\.py$' \
  'pickle, marshal and yaml.load run code from untrusted input. Use json or yaml.safe_load.' \
  'pickle\.loads?\(' \
  'marshal\.loads?\(' \
  'yaml\.(unsafe_)?load\('

count() { grep -cE -- "$2" <<<"$1" 2>/dev/null || true; }

hits=()
for rule in "${RULES[@]}"; do
  IFS=$SEP read -r id path_re re msg <<<"$rule"
  if [ -n "$path_re" ] && ! grep -qE -- "$path_re" <<<"$path"; then
    continue
  fi
  n_new=$(count "$new" "$re")
  [ "${n_new:-0}" -gt 0 ] || continue
  n_old=$(count "$old" "$re")
  [ "$n_new" -gt "${n_old:-0}" ] || continue
  hits+=("$id|$msg")
done
[ "${#hits[@]}" -gt 0 ] || exit 0

mkdir -p "$STATE_DIR/$session_id" 2>/dev/null || exit 0
# Sessions end without notice, so old state is swept here.
find "$STATE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null || true
key=$(printf '%s' "$path" | cksum | cut -d' ' -f1)

fresh=()
for hit in "${hits[@]}"; do
  id=${hit%%|*}
  mark="$STATE_DIR/$session_id/$key.$id"
  [ -e "$mark" ] && continue
  : >"$mark" 2>/dev/null || exit 0
  fresh+=("- $id: ${hit#*|}")
done
[ "${#fresh[@]}" -gt 0 ] || exit 0

{
  printf 'Security reminder for %s (shown once per file and rule):\n' "$path"
  printf '%s\n' "${fresh[@]}"
  printf 'If the pattern is intended and safe here, retry the same edit and it will pass. '
  printf 'Otherwise rewrite it. Mention the choice to the user either way.\n'
} >&2
exit 2
