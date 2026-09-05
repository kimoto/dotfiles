#!/bin/bash
set -e
PROJECTS=/srv/kymt.me/projects
TARGET="${1:-}"
usage(){ echo "Usage: $0 [list | all | <app_name>]"; exit 1; }
list_apps(){ for d in "$PROJECTS"/*/; do [ -d "${d}tmp" ] || continue; basename "$d"; done; }
case "$TARGET" in
  list) list_apps ;;
  all)  for app in $(list_apps); do touch "$PROJECTS/$app/tmp/restart.txt" && echo "OK: $app"; done ;;
  "")   usage ;;
  *)
    if [ -d "$PROJECTS/$TARGET/tmp" ]; then touch "$PROJECTS/$TARGET/tmp/restart.txt" && echo "OK: $TARGET"
    else echo "ERROR: $PROJECTS/$TARGET/tmp not found" >&2; exit 1; fi ;;
esac
