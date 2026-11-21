#!/bin/bash

# Says what bin/tidy_to_drive.sh should do with one file, by having Claude read
# it. Prints one line, tab-separated:
#   keep  <year>/<year-month>_<procedure>  <kind>_<year>_<who>.<ext>
#   junk
#   unsure
# Anything else is read as unsure by the caller.
#
# Haiku, because the call is a sort into three bins plus a name, a few files a
# day; the bigger models would spend the weekly allowance on it. Read is the
# only tool it has, with no MCP servers: the file's text is untrusted, and
# the answer is only ever parsed, never run.
#
# Rules go first and settle what they can without a model: a screenshot is
# junk (the Trash gives back the rare one that mattered). Where a file was
# downloaded from is only passed on as a hint; it cannot name the file.
#
# HEIC is converted to JPEG first: the model reads JPEG and PNG, not HEIC.

set -euo pipefail

file="$1"
model="${TIDY_CLASSIFY_MODEL:-haiku}"

name=$(basename "$file")
case "$name" in
    Screenshot* | "Screen Shot"* | スクリーンショット* | CleanShot*)
        echo junk
        exit 0
        ;;
esac
where_from=""
# mdls is macOS Spotlight metadata; elsewhere the rules above are all there is.
if command -v mdls >/dev/null 2>&1; then
    if [ "$(mdls -raw -name kMDItemIsScreenCapture "$file" 2>/dev/null)" = 1 ]; then
        echo junk
        exit 0
    fi
    where_from=$(mdls -raw -name kMDItemWhereFroms "$file" 2>/dev/null | tr -d '\n"()' | sed 's/  */ /g') || true
    case "$where_from" in "(null)" | null) where_from="" ;; esac
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
read_path="$file"
case "$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')" in
    heic)
        read_path="$work/page.jpg"
        sips -s format jpeg "$file" --out "$read_path" >/dev/null
        ;;
esac
original_ext=$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')
today=$(date +%Y-%m)

prompt=$(
    cat <<EOF
Read the file at $read_path and decide what to do with it. Answer with exactly one line and nothing else.
${where_from:+It was downloaded from: $where_from}

keep — a record worth filing: something issued by a government office, school, employer, insurer, bank,
hospital or landlord, or a contract, certificate, statement, tax form or receipt for a procedure.
junk — anything done with: screenshots of apps or chats, manuals, flyers, tickets for past events, memes,
product photos.
unsure — anything else, or when you cannot read it.

For keep, the line is: keep<TAB><folder><TAB><name>
- folder: <year>/<year-month>_<procedure>, where year-month is the month of the procedure the document belongs
  to (use $today if unclear) and procedure is short lower-case English with hyphens, e.g.
  2026/2026-11_health-insurance-dependents
- name: <kind>_<year>_<who>.$original_ext, lower-case English with hyphens; kind like withholding, juminhyo,
  receipt, contract; year is the year the document covers (or its issue date as yyyy-mm-dd); who is the given
  name in lower-case romaji, or family if it is for the household.
Never use Japanese era years; convert them to the Western year.

For junk or unsure, the line is just the word.
EOF
)

answer=$(claude -p "$prompt" \
    --model "$model" \
    --tools Read \
    --allowedTools Read \
    --strict-mcp-config \
    --max-turns 3 \
    --output-format text </dev/null)
# The last line only: a model that thinks aloud first still ends on its answer.
answer=$(printf '%s\n' "$answer" | sed '/^[[:space:]]*$/d' | tail -n 1)
answer="${answer//<TAB>/$'\t'}"
printf '%s\n' "$answer"
