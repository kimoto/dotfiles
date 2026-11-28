#!/bin/bash

# Where did Claude get stopped or have to redo work, and how often?
#
# Counts the tool calls in Claude Code transcripts that did not go through:
# a permission refused, a hook that blocked the call, the user saying no, or
# a tool that failed. The same stumble seen many times is what is worth
# fixing in the rules, hooks or allow-list, so lines are grouped by a short
# signature and the most frequent come first.
#
# Reads either shape a transcript comes in, one JSON value per line: the local
# files under ~/.claude/projects (subagents' too), and the session events a
# cloud session's list_events returns (a page, or its data array, compacted
# to one line). A line that is not JSON, such as the last one of a session
# that died mid-write, is skipped; input with no JSON line at all fails.
# Signatures quote the start of each message with escape sequences, paths and
# secret-looking words taken out, but they can still name private repos or
# commands: the output goes to private places only.
#
# Usage: claude_stumbles.sh [--since YYYY-MM-DD] [--] [FILE...]
#   --since D  only calls on or after day D (UTC)
#   FILE       transcripts to read; default every *.jsonl under
#              $CLAUDE_CONFIG_DIR/projects (or ~/.claude/projects); - is stdin
# Output: <count>\t<kind>\t<signature>, most frequent first; kind is one of
# permission, hook, rejected, error.

set -euo pipefail

USAGE="usage: claude_stumbles.sh [--since YYYY-MM-DD] [--] [FILE...]"
since=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --since)
            since="${2:-}"
            if ! [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                echo "claude_stumbles: --since takes a day as YYYY-MM-DD" >&2
                exit 2
            fi
            shift 2
            ;;
        --) shift; break ;;
        # Only long options: project directories are named -home-…, so a
        # word with one dash is a file.
        --*) echo "$USAGE" >&2; exit 2 ;;
        *) break ;;
    esac
done

files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
    dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
    while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -name '*.jsonl' -type f 2>/dev/null)
    if [ "${#files[@]}" -eq 0 ]; then
        echo "claude_stumbles: no transcripts under $dir" >&2
        exit 1
    fi
fi

# One line at a time, so no transcript is held whole: jq turns each call into
# a short row naming its tool (T), each result that did not go through into a
# row (R), and each line it could parse into a P, so input that read as
# nothing (a page saved pretty-printed) is told apart from no stumbles. awk
# joins them by call id once all are read, counting a result read twice
# (overlapping pages, a resumed session) once. Each file ends in a newline, so
# a cut-off last line cannot swallow the next file's first.
for f in "${files[@]}"; do
    cat -- "$f" || echo "claude_stumbles: cannot read $f, left out" >&2
    echo
done | jq -rR --arg since "$since" '
    def events:
        if type == "array" then .[] | events
        elif (.ccr.data? // .data?) | type == "array" then (.ccr.data // .data)[] | events
        else . end;
    def body: .user.internal_anthropic_catchall // .assistant.internal_anthropic_catchall // .;
    def day: (.timestamp // .created_at // "") | strings | .[0:10];
    def text: if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end;
    # The output is read in a terminal, and the text came from anything a tool
    # printed: escape sequences and control bytes go before anything is kept.
    def clean: gsub("\u001b(\\[[0-?]*[ -/]*[@-~]|\\][^\u0007\u001b]*(\u0007|\u001b\\\\)?)?"; "")
        | gsub("[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]"; " ");
    # A word that may be a credential, or names a place, is not quoted: a known
    # token prefix, a long run of token characters with a digit or both cases
    # in it, the value after name=, anything else with = (base64 padding), the
    # word after one that introduces a credential, anything with a / in it.
    # A UUID, as an MCP server is renamed on reconnect, becomes <id> first.
    def mask:
        gsub("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}"; "<id>")
        | if test("(^|[^A-Za-z0-9])(gh[pousr]_|github_pat_|glpat-|sk-|xox[a-z]-|AKIA|AIza|hf_)")
            or ([scan("[A-Za-z0-9+_.=-]{20,}")] | any(test("[0-9]") or (test("[a-z]") and test("[A-Z]"))))
            then "<secret>"
        elif test("^[A-Za-z_][A-Za-z0-9_-]*=") then sub("=.*"; "=<secret>")
        elif test("=") then "<secret>"
        elif test("/") then "<path>"
        else . end;
    # The first few words name the check or the failure; what follows (a branch,
    # a path, a count) differs every time and would split one stumble in many,
    # so numbers become N.
    def first_words($n):
        clean | [splits("\\s+") | select(. != "")][0:$n] as $w
        | [range($w | length) as $i
            | if $i > 0 and ($w[$i - 1] | ascii_downcase | sub("[:=]$"; "")
                | IN("password", "passwd", "token", "secret", "bearer", "basic", "-p"))
              then "<secret>" else $w[$i] | mask end
            | gsub("[0-9]+"; "N")] | join(" ");
    # The first program a Bash call ran, by its file name, past a leading
    # `cd <dir> &&` or `;`, assignments and env/command: a failing command is
    # told apart by it, a blocked one by the hook that blocked it. In a chain
    # or a pipeline the one that failed may be a later one.
    def program: (.input.command? // "") | strings | clean | sub("^\\s*cd\\s+[^;&|]*(&&|;)\\s*"; "")
        | [splits("\\s+") | select(. != "" and (test("=") | not) and . != "env" and . != "command")][0] // ""
        | sub(".*/"; "") | mask;
    def decisions: try (.tool_result_meta | arrays
        | map(objects | select(.id | type == "string") | {(.id): (.permission_decision.decision? // "")})
        | add) catch null;

    # A line of an unexpected shape is skipped, not the whole run.
    fromjson? | select(type == "object" or type == "array") | "P",
    try (events | (day // "") as $day | body | (decisions // {}) as $decision
    | .message.content? | arrays | .[] | objects
    | if .type == "tool_use" and (.id | type == "string") then
        ["T", .id, (.name | if type == "string" then clean else "?" end), (if .name == "Bash" then program else "" end)]
      elif .type == "tool_result" and (.tool_use_id | type == "string")
          and ($since == "" or $day >= $since)
          and (.is_error == true or $decision[.tool_use_id] == "deny") then
        (.content | text | sub("^[\\s\u001b]+"; "")) as $t
        # The wordings Claude Code uses for a call it refused to run.
        | if ($t | test("^Permission (for this [a-z]+ was denied|to use .* (has been|was) denied)|haven.t granted it"))
            or ($decision[.tool_use_id] == "deny") then
            ["R", .tool_use_id, "permission",
              ($t | (capture("Reason: (?<r>.*)").r // capture("denied by (?<r>.*)").r // "")
                  | sub("\\.(\\s+[A-Z].*)?$"; "") | first_words(6))]
          elif ($t | test("^[A-Za-z]+(:[^ ]+)? hook error")) then
            ["R", .tool_use_id, "hook",
              ($t | capture("^(?<h>[A-Za-z]+(:[^ ]+)?) hook error").h | clean | mask) + ": "
              + ($t | sub("^[^\\n]*?hook error: (\\[[^\\]]*\\]: )?"; "") | first_words(6))]
          elif ($t | test("^(The user doesn.t want to proceed|User rejected)")) then
            ["R", .tool_use_id, "rejected", ""]
          else
            ["R", .tool_use_id, "error",
              (($t | capture("^Exit code (?<c>[0-9]+)") | "exit " + .c) // ($t | first_words(6)))]
          end
      else empty end
    # clean took every tab and newline out of the fields; @tsv would also
    # double each backslash in them.
    | map(tostring | clean) | join("\t")) catch empty
' | awk -F '\t' '
    $1 == "P" { parsed++; next }
    $1 == "T" { tool[$2] = $3; prog[$2] = $4; next }
    !($2 in seen) { seen[$2] = 1; id[++n] = $2; kind[n] = $3; sig[n] = $4 }
    END {
        if (!parsed) {
            print "claude_stumbles: no line read as JSON (one value per line: save a page with jq -c)" > "/dev/stderr"
            exit 1
        }
        for (i = 1; i <= n; i++) {
            t = (id[i] in tool) ? tool[id[i]] : "?"
            if (kind[i] == "error" && prog[id[i]] != "") t = t " " prog[id[i]]
            # A hook signature already names the event and the tool.
            if (kind[i] == "hook") printf "%s\t%s\n", kind[i], sig[i]
            else printf "%s\t%s%s\n", kind[i], t, (sig[i] == "" ? "" : ": " sig[i])
        }
    }
' | LC_ALL=C sort | uniq -c | LC_ALL=C sort -k1,1nr -k2 |
    awk '{ n = $1; sub(/^ *[0-9]+ /, ""); printf "%d\t%s\n", n, $0 }'
