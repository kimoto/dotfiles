#!/bin/sh
# prefix + f (.tmux.conf): the candidate list for the fzf pane switcher, one
# pane per line as "<session:window.pane>  <window>  <label>".
#
# Ranked so the pane that needs you comes first: Claude Code waiting on you
# (@claude_state=waiting, set by bin/claude_tmux_indicator.sh), then finished
# (done), then everything else — each group most-recently-used first (@mru,
# stamped by .tmux.conf's hooks). The window-status ✳ only shows the current
# session; this list is what spans every session.
#
# The pane the switcher was opened from ($1) is left out, so the top entry is
# always somewhere to go. Label: pane title, falling back to the pane's cwd
# while the title is still the default hostname (no program has set one).
set -eu

cur="${1:-}"

tmux list-panes -a -f "#{!=:#{pane_id},$cur}" -F \
  "#{?#{==:#{@claude_state},waiting},2,#{?#{==:#{@claude_state},done},1,0}} #{?@mru,#{@mru},0} \
#S:#I.#P  #{?#{==:#{@claude_state},waiting},⏳ ,#{?#{==:#{@claude_state},done},✳ ,}}#W  \
#{?#{||:#{==:#{pane_title},#{host}},#{==:#{pane_title},#{host_short}}},#{b:pane_current_path},#{pane_title}}" |
  sort -k1,1rn -k2,2rn | cut -d' ' -f3-
