#!/bin/sh

layout="$1"

aerospace list-windows --workspace focused --format '%{window-id}' | xargs -n1 aerospace layout "$layout" --window-id
