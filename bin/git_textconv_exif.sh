#!/bin/sh
# textconv for git's exif diff driver (.gitconfig, routed by
# config/git/attributes): prints an image's metadata and a checksum line.
#
# The checksum is there because two images that differ only in their pixels
# have identical metadata, and without it `git diff` would show no change.
# Without exiftool (it is only in Brewfile.extra) the checksum line alone is
# printed: a textconv that fails makes git abort the whole diff, not just this
# file.
#
# --System:all drops the filesystem tags (file name, dates, permissions), which
# differ between the temp files git hands over and would show up as changes.

f=$1
if command -v exiftool >/dev/null 2>&1; then
  exiftool -S --System:all --ExifToolVersion "$f" || exit
else
  echo "(exiftool not installed: metadata not shown)"
fi
printf 'Checksum: %s\n' "$(cksum <"$f")"
