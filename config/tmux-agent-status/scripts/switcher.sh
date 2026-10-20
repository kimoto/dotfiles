#!/bin/sh
# The candidate list for the fzf pane switcher (agent-status.tmux binds it),
# one pane per line as "<session:window.pane>  <window>  <label>".
#
# Ranked so the pane that needs you comes first: an agent waiting on you
# (@agent_state=waiting, set by state.sh), then finished (done), then
# everything else — each group most-recently-used first (@mru, stamped by
# .tmux.conf's hooks; 0 without them). The window-status ✳ only shows the
# current session; this list is what spans every session.
#
# The pane the switcher was opened from ($1) is left out, so the top entry is
# always somewhere to go. Label: pane title, falling back to the pane's cwd
# while the title is still the default hostname (no program has set one).
set -eu

cur="${1:-}"

tmux list-panes -a -f "#{!=:#{pane_id},$cur}" -F \
  "#{?#{==:#{@agent_state},waiting},2,#{?#{==:#{@agent_state},done},1,0}} #{?@mru,#{@mru},0} \
#S:#I.#P  #{?#{==:#{@agent_state},waiting},⏳ ,#{?#{==:#{@agent_state},done},✳ ,}}#W  \
#{?#{||:#{==:#{pane_title},#{host}},#{==:#{pane_title},#{host_short}}},#{b:pane_current_path},#{pane_title}}" |
  sort -k1,1rn -k2,2rn | cut -d' ' -f3-
