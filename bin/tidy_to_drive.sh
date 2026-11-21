#!/bin/bash

# Tidies settled documents and photos off the Desktop: what is worth keeping
# goes to its named folder in Google Drive, what is not goes to the Trash, and
# what the classifier cannot call stays put and is reported. A kept file is
# deleted locally only after a fresh download of the uploaded copy hashes the
# same; rclone's exit code and Drive's stored checksum both describe what Drive
# believes it received, and the point is to prove the bytes come back.
#
# The judgement lives in bin/tidy_classify.sh; this script only acts on its
# answer and checks the answer's shape, so a document that talks the
# classifier into something odd can at worst misfile a copy or trash a file
# the Trash can give back.
#
# hammerspoon/tidy.lua runs it. Hammerspoon, not launchd: the Desktop is
# behind macOS privacy control, and a launchd job could only reach it by giving
# /bin/bash Full Disk Access. Run from Hammerspoon, the script inherits the
# Desktop permission granted to that one app.
#
# One-time setup: brew install rclone webp, then make a remote whose root is
# the folder holding both destinations (its id is in the folder's Drive URL):
#   rclone config create gdrive-docs drive scope=drive root_folder_id=<id>
#
# Settings (environment, all optional):
#   TIDY_SOURCE_DIRS    colon-separated folders, top level only (default ~/Desktop)
#   DRIVE_DEST          rclone path of the filing folder (default gdrive-docs:14.Paperwork/)
#   SHOT_DEST           rclone path screenshots go under, as <year>/<year-month>/
#                       (default gdrive-docs:15.Screenshots/)
#   MIN_AGE_MINUTES     how long a file sits first (default 4320 = 3 days), so a
#                       file put there to attach somewhere stays put.
#   TIDY_CLASSIFIER     command given one file, see tidy_classify.sh
#   TIDY_STATE_DIR      where "already asked about" is remembered
#   TIDY_DRY_RUN=1      classify and list, change nothing.
# Exit status: 0 all done, 1 something failed and was kept, 3 some files need
# the owner's call (listed in the log as "unsure").

set -euo pipefail
# One stream, so an rclone error lands next to the "kept" line it explains.
exec 2>&1

TIDY_SOURCE_DIRS="${TIDY_SOURCE_DIRS:-$HOME/Desktop}"
DRIVE_DEST="${DRIVE_DEST:-gdrive-docs:14.Paperwork/}"
SHOT_DEST="${SHOT_DEST:-gdrive-docs:15.Screenshots/}"
# A bare folder name would glue onto the next path part.
case "$DRIVE_DEST" in *: | */) ;; *) DRIVE_DEST="$DRIVE_DEST/" ;; esac
case "$SHOT_DEST" in *: | */) ;; *) SHOT_DEST="$SHOT_DEST/" ;; esac
TIDY_CLASSIFIER="${TIDY_CLASSIFIER:-$(cd "$(dirname "$0")" && pwd)/tidy_classify.sh}"
TIDY_STATE_DIR="${TIDY_STATE_DIR:-$HOME/.local/state/tidy_to_drive}"
MIN_AGE_MINUTES="${MIN_AGE_MINUTES:-4320}"
DRY_RUN="${TIDY_DRY_RUN:-0}"

# Allow-list, each for a reason: pdf for statements and certificates, the image
# types for phone photos, scans and screenshots. Everything else (folders,
# aliases, installers, half-finished downloads) stays where it is.
ALLOWED_EXTENSIONS="pdf heic jpg jpeg png"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

# Prints the hash, or nothing when the tool failed; callers treat empty as
# "cannot verify", never as a match.
sha256_of() {
    local out
    if command -v sha256sum >/dev/null 2>&1; then
        out=$(sha256sum <"$1") || return 0
    else
        out=$(shasum -a 256 <"$1") || return 0
    fi
    out="${out%% *}"
    case "$out" in
        *[!0-9a-f]* | "") return 0 ;;
    esac
    [ "${#out}" -eq 64 ] && printf '%s' "$out"
    return 0
}

is_allowed() {
    local name="$1" ext
    case "$name" in *.*) ;; *) return 1 ;; esac
    ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')
    case " $ALLOWED_EXTENSIONS " in
        *" $ext "*) return 0 ;;
    esac
    return 1
}

case "$MIN_AGE_MINUTES" in
    "" | *[!0-9]*)
        log "MIN_AGE_MINUTES must be a whole number of minutes, got '$MIN_AGE_MINUTES'"
        exit 1
        ;;
esac
if [ "$DRY_RUN" != 1 ]; then
    for tool in rclone cwebp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log "$tool not found (brew install rclone webp); nothing moved."
            exit 1
        fi
    done
fi

# One run at a time: an hourly slot can land while a slow upload still runs.
# A lock older than STALE_LOCK_MINUTES belongs to a run that was killed (a
# shutdown mid-upload); no real run takes that long, so it is cleared.
STALE_LOCK_MINUTES=360
lock="${TMPDIR:-/tmp}/tidy_to_drive.lock"
if ! mkdir "$lock" 2>/dev/null; then
    if [ -n "$(find "$lock" -maxdepth 0 -mmin "+$STALE_LOCK_MINUTES" 2>/dev/null)" ]; then
        log "clearing a lock left by a run that died"
        rm -rf "$lock"
    fi
    if ! mkdir "$lock" 2>/dev/null; then
        log "another run is still going; skipping."
        exit 0
    fi
fi
work=$(mktemp -d) || {
    rmdir "$lock"
    exit 1
}
trap 'rm -rf "$lock" "$work"' EXIT

# A file that fails the same way every hour would be retried, and its owner
# notified, every hour; after MAX_TRIES it waits like an unsure one.
MAX_TRIES=3
moved=0
trashed=0
kept=0
unsure=0
mkdir -p "$TIDY_STATE_DIR"
asked="$TIDY_STATE_DIR/asked"
tries="$TIDY_STATE_DIR/tries"
touch "$asked" "$tries"

keep() {
    log "$1, kept: $2"
    kept=$((kept + 1))
}

# The shapes paperwork-archive names things in: <year>/<year-month>_<procedure>
# and <kind>_<year>[-mm[-dd]]_<who>.<ext>, lower-case English, so nothing the
# classifier says can climb out of the filing folder.
valid_folder() {
    [[ "$1" =~ ^[0-9]{4}/[0-9]{4}-[0-9]{2}_[a-z0-9]+(-[a-z0-9]+)*$ ]]
}
valid_name() {
    [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*_[0-9]{4}(-[0-9]{2}){0,2}_[a-z0-9]+(-[a-z0-9]+)*\.(pdf|heic|jpg|jpeg|png)$ ]]
}

to_trash() {
    if command -v trash >/dev/null 2>&1; then
        trash "$1"
    else
        osascript -e 'on run argv' \
            -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' \
            -e 'end run' "$1" >/dev/null
    fi
}

# file_away ORIGINAL NAME ORIGINAL_HASH UPLOAD UPLOAD_HASH REMOTE
# Uploads UPLOAD (the original, or a converted copy of it) to REMOTE and
# deletes ORIGINAL once REMOTE downloads back as UPLOAD's bytes.
file_away() {
    local file="$1" name="$2" local_hash="$3" upload="$4" upload_hash="$5" remote="$6" back taken=0
    local listed
    if ! listed=$(rclone lsf "$remote" </dev/null); then
        keep "cannot check Drive" "$name"
        return 0
    fi
    [ -n "$listed" ] && taken=1
    # --ignore-existing: a different file already under that name is never
    # overwritten; its bytes then fail the compare below and this one is kept.
    if ! rclone copyto --ignore-existing "$upload" "$remote" </dev/null; then
        keep "upload failed" "$name"
        return 0
    fi
    back="$work/back"
    rm -f "$back"
    if ! rclone copyto "$remote" "$back" </dev/null; then
        keep "download-back failed" "$name"
        return 0
    fi
    local back_hash
    back_hash=$(sha256_of "$back")
    if [ -z "$upload_hash" ] || [ -z "$back_hash" ]; then
        keep "cannot hash the Drive copy" "$name"
        return 0
    fi
    if [ "$back_hash" != "$upload_hash" ] && [ "$taken" = 0 ]; then
        keep "Drive copy differs" "$name"
        return 0
    fi
    if [ "$back_hash" != "$upload_hash" ]; then
        # Another file already holds that name; asking again next hour would
        # get the same name, so it waits for the owner like an unsure one.
        printf '%s %s\n' "$local_hash" "$name" >>"$asked"
        log "unsure (Drive already has a different $remote): $name"
        unsure=$((unsure + 1))
        return 0
    fi
    rm -f -- "$file"
    log "filed: $name -> $remote"
    moved=$((moved + 1))
}

# A screenshot is kept as a memory, not trashed: a PNG becomes lossless WebP
# (smaller for text and flat colour, every pixel the same), other types go up
# as they are. The month folder is the month it was taken (mtime).
file_shot() {
    local file="$1" name="$2" local_hash="$3" ext upload upload_name month
    ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')
    # perl, because BSD and GNU stat and date spell "mtime as a date" apart.
    if ! month=$(perl -MPOSIX -e 'print strftime("%Y/%Y-%m", localtime((stat shift)[9]))' "$file") ||
        [ -z "$month" ]; then
        keep "cannot read the date" "$name"
        return 0
    fi
    upload="$file"
    upload_name="$name"
    if [ "$ext" = png ]; then
        upload="$work/shot.webp"
        rm -f "$upload"
        if ! cwebp -quiet -lossless -mt "$file" -o "$upload" </dev/null; then
            keep "WebP conversion failed" "$name"
            return 0
        fi
        upload_name="${name%.*}.webp"
    fi
    file_away "$file" "$name" "$local_hash" "$upload" "$(sha256_of "$upload")" "$SHOT_DEST$month/$upload_name"
}

count_try() {
    local hash n
    hash=$(sha256_of "$1")
    [ -n "$hash" ] || return 0
    echo "$hash" >>"$tries"
    n=$(grep -c "^$hash\$" "$tries" || true)
    if [ "$n" -ge "$MAX_TRIES" ]; then
        printf '%s %s\n' "$hash" "$(basename "$1")" >>"$asked"
        log "unsure (failed $n times, not retrying): $(basename "$1")"
        unsure=$((unsure + 1))
    fi
}

tidy_one() {
    local file="$1" name local_hash verdict folder newname
    name=$(basename "$file")
    case "$name" in .*) return 0 ;; esac
    is_allowed "$name" || return 0

    local_hash=$(sha256_of "$file")
    if [ -z "$local_hash" ]; then
        keep "cannot hash" "$name"
        return 0
    fi
    if grep -q "^$local_hash " "$asked"; then
        return 0
    fi
    if ! verdict=$("$TIDY_CLASSIFIER" "$file" </dev/null); then
        keep "classifier failed" "$name"
        return 0
    fi
    IFS=$'\t' read -r verdict folder newname <<<"$verdict"
    case "$verdict" in
        keep)
            if ! valid_folder "$folder" || ! valid_name "$newname" ||
                [ "${newname##*.}" != "$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')" ]; then
                log "unsure (classifier gave a bad name): $name"
                verdict=unsure
                folder=""
                newname=""
            fi
            ;;
        junk | shot) ;;
        *) verdict=unsure ;;
    esac
    if [ "$DRY_RUN" = 1 ]; then
        log "would $verdict: $name${folder:+ -> $folder/$newname}"
        return 0
    fi
    case "$verdict" in
        keep) file_away "$file" "$name" "$local_hash" "$file" "$local_hash" "$DRIVE_DEST$folder/$newname" ;;
        shot) file_shot "$file" "$name" "$local_hash" ;;
        junk)
            if to_trash "$file"; then
                log "trashed: $name"
                trashed=$((trashed + 1))
            else
                keep "could not move to Trash" "$name"
            fi
            ;;
        unsure)
            # Asked once: the file stays, and the next runs leave it alone
            # until its bytes change.
            printf '%s %s\n' "$local_hash" "$name" >>"$asked"
            log "unsure: $name"
            unsure=$((unsure + 1))
            ;;
    esac
}

IFS=: read -r -a sources <<<"$TIDY_SOURCE_DIRS"
for dir in "${sources[@]}"; do
    if [ ! -d "$dir" ]; then
        log "no folder $dir; check TIDY_SOURCE_DIRS"
        kept=$((kept + 1))
        continue
    fi
    list="$work/list"
    # -cmin, not -mmin: browsers and AirDrop can stamp mtime with the file's
    # original date, so an old statement saved a minute ago would look settled.
    # The listing goes to a file first so that a find that cannot read the
    # folder (privacy control said no) fails the run instead of finding nothing.
    if ! find "$dir" -mindepth 1 -maxdepth 1 -type f -cmin "+$MIN_AGE_MINUTES" -print0 >|"$list"; then
        log "cannot list $dir (is the folder permission granted to Hammerspoon?)"
        kept=$((kept + 1))
        continue
    fi
    while IFS= read -r -d '' file; do
        # Keeps a long run's lock from looking abandoned to the next one.
        touch "$lock"
        kept_before=$kept
        tidy_one "$file"
        [ "$kept" -eq "$kept_before" ] || count_try "$file"
    done <"$list"
done

log "done: $moved filed, $trashed trashed, $unsure unsure, $kept kept"
[ "$kept" -eq 0 ] || exit 1
[ "$unsure" -eq 0 ] || exit 3
