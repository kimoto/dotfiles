#!/bin/sh
TARGET="$1"

if [ "$TARGET" = "" ]; then
  echo "usage: $0 TARGET_DIR"
  exit 1
fi

for file in `ls $TARGET`
do
  sh "$TARGET/$file"
done;
