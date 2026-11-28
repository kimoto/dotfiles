#!/bin/sh
# fzf preview for a file path (Ctrl-T in .zshrc): images are drawn with chafa,
# everything else goes through bat as before.
#
# Images are picked by extension, not by `file`: the preview reruns on every
# cursor move, and an extension test costs nothing.
#
# --format symbols because the preview pane may sit inside tmux, which does not
# pass kitty or sixel graphics through; Unicode blocks draw everywhere.
#
# Without chafa (it is only in Brewfile.extra) images fall back to bat, which
# only says the file is binary.

f=$1
case $f in
  *.[pP][nN][gG] | *.[jJ][pP][gG] | *.[jJ][pP][eE][gG] | *.[gG][iI][fF] | \
    *.[wW][eE][bB][pP] | *.[bB][mM][pP] | *.[tT][iI][fF] | *.[tT][iI][fF][fF] | \
    *.[aA][vV][iI][fF] | *.[jJ][xX][lL])
    if command -v chafa >/dev/null 2>&1; then
      exec chafa --format symbols --animate off \
        --size "${FZF_PREVIEW_COLUMNS:-80}x${FZF_PREVIEW_LINES:-24}" "$f"
    fi
    ;;
esac
exec bat --color=always "$f"
