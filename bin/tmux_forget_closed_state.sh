#!/bin/bash
# Point tmux-resurrect's "last" save at an empty one, so tmux-continuum's
# restore on the next server start brings nothing back. .tmux.conf runs this
# when the last shell exits; see the hook there for when.
#
# The paths come from resurrect's own helpers, so @resurrect-dir and its
# ~/.tmux/resurrect vs XDG fallback stay resurrect's call. They read options
# from the server, which is still up while this runs.
set -eo pipefail

# shellcheck source=/dev/null
. "${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins/}tmux-resurrect/scripts/helpers.sh"

save="$(resurrect_file_path)"
mkdir -p "$(resurrect_dir)"
: >"$save"
ln -fs "$(basename "$save")" "$(last_resurrect_file)"
