# Minimal replacement for zsh-abbr: expands a fixed set of static
# word -> command abbreviations on space/enter. zsh-abbr wraps every
# operation - including plain startup loading, not just `abbr add`/`abbr
# erase` - in a cross-shell file lock (job-queue) that protects its shared,
# editable abbreviations store from concurrent-write races. That guarantee
# isn't needed here: these entries are static, hand-edited, one shell at a
# time. Measured at ~44ms/startup, almost all of it job-queue forks
# (uuidgen, ls, tail, rm); this is a handful of zsh builtins.
typeset -gA ABBR_MAP=(
  ag    'rg'
  aic   'aicommits'
  aica  'aicommits -a'
  aicap 'aicommits -a && git push'
  ci    'git commit -a -v'
  co    'git checkout'
  di    'git diff'
  ga    'git add'
  gau   'git add -u'
  gr    'git grep'
  l     "git log --graph --color=always \
--pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'"
  lo    'git log -p'
  mysql 'mysqlsh'
  pu    'git pull'
  st    'git status'
)

_abbr_expand() {
  local word=${LBUFFER##*[[:space:]]}
  [[ -n $word && -n ${ABBR_MAP[$word]} ]] && LBUFFER[-${#word},-1]=${ABBR_MAP[$word]}
}

_abbr_expand_space() {
  _abbr_expand
  zle self-insert
}
zle -N _abbr_expand_space
bindkey ' ' _abbr_expand_space

_abbr_expand_accept() {
  _abbr_expand
  zle accept-line
}
zle -N _abbr_expand_accept
bindkey '^M' _abbr_expand_accept
