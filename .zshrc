#===============================================================
#    ________      _______. __    __  .______        ______
#   |       /     /       ||  |  |  | |   _  \      /      |
#   `---/  /     |   (----`|  |__|  | |  |_)  |    |  ,----'
#      /  /       \   \    |   __   | |      /     |  |
#  __ /  /----.----)   |   |  |  |  | |  |\  \----.|  `----.
# (__)________|_______/    |__|  |__| | _| `._____| \______|
#
# Author: kimoto
#
# Load order matters in a few places (kept intentionally):
#   - compinit runs before `sheldon source` so plugin compdefs (e.g. carapace)
#     can register against an initialized completion system.
#   - LS_COLORS is exported before the completion list-colors zstyle reads it.
#   - CI strict mode (err_exit) is enabled after plugins load, so a missing
#     optional plugin doesn't abort the interactive load test.
#===============================================================

#=====================
# base shell setup
#=====================
unlimit
limit -s
umask 022
bindkey -e

OMITTED_DIR="%(3~,%-1~/.../%1~,%~)"
# Fallback prompt; starship (loaded via sheldon) overrides this once active.
PROMPT="%n@${HOST} %{$fg[blue]%}${OMITTED_DIR}%{$reset_color%}[%!]%{%(?..$fg[red])%}%#%{$reset_color%} "

#=====================
# completion system
#=====================
# Initialized before plugins so plugin-provided compdefs register correctly.
# Rebuild the dump only when missing or older than a day; otherwise trust the
# cache (-C) to keep startup fast.
autoload -Uz compinit
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
# Rebuild the dump when it's missing or out of date, otherwise load it with
# `compinit -C` to skip the security/rebuild scan. "Out of date" = some fpath
# directory is newer than the dump, i.e. a completion file was added or removed
# (which bumps the directory's mtime). This only stats the fpath directories,
# not every completion file, so it stays cheap. Bare-qualifier globs need no
# extendedglob; the `e` qualifier runs the -nt test per directory, and the
# array assignment forces the filename generation that [[ ]] would suppress.
_zcompdump_stale=( ${^fpath}(N/e['[[ $REPLY -nt $_zcompdump ]]']) )
if [[ ! -e "$_zcompdump" || $#_zcompdump_stale -gt 0 ]]; then
  compinit -d "$_zcompdump"
else
  compinit -C -d "$_zcompdump"
fi
unset _zcompdump _zcompdump_stale

#=====================
# paths
#=====================
typeset -U path # 重複したパスをPATHに登録しない
typeset -U manpath
typeset -xT SUDO_PATH sudo_path
path=(
  $HOME{,/.local,/.cargo,/.docker}/bin(N-/)
  {/opt/homebrew,/home/linuxbrew/.linuxbrew}/bin(N-/)
  $path
)
manpath=(
  {$HOME/.local,/opt/local,/usr/local,/usr}/share/man(N-/)
  $manpath
)
sudo_path=(
  {,/usr/pkg,/usr/local,/usr}/sbin(N-/)
  $sudo_path
)

#=====================
# package managers / plugins
#=====================
if builtin command -v brew >/dev/null; then
  eval "$(brew shellenv)"
fi

if builtin command -v sheldon >/dev/null; then
  eval "$(sheldon source)"
fi

# CI strict mode: fail on actual command errors during .zshrc load.
# Enabled after plugins so an absent optional plugin doesn't abort the load.
if [[ -n "$CI" ]]; then
  setopt err_exit
  setopt err_return
fi

#=====================
# setopts
#=====================
setopt autocd # cd不要
setopt autopushd # cdの履歴に残す
setopt nocorrectall # correctallの無効化
setopt histignoredups # 重複を記録しない
setopt histignorealldups # 古い方を削除
setopt pushdignoredups # 重複を記録しない
setopt interactivecomments # コメントを有効化
setopt share_history # historyを共有
setopt incappendhistory # incrementalに追加
setopt multios # 複数のリダイレクトやパイプに対応
setopt extended_history # ヒストリに時刻を追加
setopt noclobber # リダイレクトで上書き禁止
setopt listpacked # 詰めて表示
setopt nopromptcr # 改行コードで終わらない出力をケア、しない
setopt complete_in_word # 語の途中でも補完
setopt always_last_prompt # カーソル位置は保持したままファイル名一覧を順次その場で表示
setopt magic_equal_subst # --prefix=~/local の~も展開できるように
setopt ignore_eof # Ctrl-Dを無視
setopt auto_param_slash # 末尾/を自動的に付加
setopt mark_dirs # ディレクトリは末尾に/追加
setopt list_types #
setopt auto_menu # 補完キー連打
setopt auto_param_keys # カッコの対応などを自動的に補完
setopt print_eight_bit
setopt globdots # dotも補完

#=====================
# history & shell vars
#=====================
HISTFILE=~/.zsh_history
HISTSIZE=9999999
SAVEHIST=9999999
MAILCHECK=0
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
watch=notme # watch and notify, other login user
zle_highlight+=(paste:none)

#=====================
# env
#=====================
export PAGER="less --RAW-CONTROL-CHARS --quit-if-one-screen --mouse -X"
export BAT_PAGER="less --RAW-CONTROL-CHARS --quit-if-one-screen -X"
export LESS='-M -i -f -Q'
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export EDITOR=nvim
export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"
export LANG=ja_JP.UTF-8
export CLICOLOR=1
export XDG_CONFIG_HOME="$HOME/.config"
# LS_COLORS is exported during `sheldon source` via _evalcache — see the
# vivid-ls-colors inline plugin in config/sheldon/plugins.toml.
export GPG_TTY=$(tty)
# carapace: fall back to zsh's native completions for commands it has no spec for
export CARAPACE_BRIDGES='zsh,bash'

#=====================
# completion zstyles
#=====================
zstyle ':completion:*:default' menu select=1
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # 大文字/小文字を無視
zstyle ':completion:*' completer _complete _match _approximate # 曖昧な入力でも補完キーにより自動でマッチさせる
zstyle ':completion:*' squeeze-slashes true # 引数の最後の補完時は、スラッシュを除去
zstyle ':completion:*:cd:*' ignore-parents parent pwd # ../ってやったときは現在の居るディレクトリが補完候補にならないように
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zcompcache
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

#=====================
# aliases
#=====================
alias ls='eza --hyperlink --icons auto'
alias ll='ls --long --all --git-repos-no-status --time-style=relative --sort=modified'
alias tree='ll -T'
alias mv='nocorrect mv'
alias cp='nocorrect cp -v' # verbose
alias mkdir='nocorrect mkdir'
alias vi='nvim'
alias reload="exec zsh"
[[ $- == *i* ]] && alias cd="z"
alias cat='bat'
alias less='bat --pager=less'
alias curl='curlie' # for pretty-print
alias top='btop'
alias ping='gping'
alias dig='doggo'
alias grep='grep --color=auto'
# egrep/fgrep are obsolescent (grep >=3.8 warns): keep the muscle memory but
# route through the grep alias above, so they get color and skip the warning.
alias egrep='grep -E'
alias fgrep='grep -F'
alias navi='navi --print --prevent-interpolation'
alias mysqlsh='mysqlsh --quiet-start=2 --no-name-cache'
alias gist='gh gist create --web'

#=====================
# keybindings
#=====================
bindkey "^\\" undo

#=====================
# utility functions
#=====================
temp(){
  cd "$(mktemp -d $HOME/tmp/$(date +'%Y%m%d').$1${1:+.}\`XXXXXX)"
}

# lazygit: chase into the directory it was left in (newdir file), if any.
lg() {
  export LAZYGIT_NEW_DIR_FILE=~/.lazygit/newdir
  lazygit "$@"
  if [ -f $LAZYGIT_NEW_DIR_FILE ]; then
    cd "$(cat $LAZYGIT_NEW_DIR_FILE)"
    rm -f $LAZYGIT_NEW_DIR_FILE > /dev/null
  fi
}

# ghq + fzf: jump to a cloned repo.
g() {
  local dir=$(ghq list | fzf --preview "bat --style=plain --color=always $(ghq root)/{}/README.*" --query="$*")
  [ -n "$dir" ] && cd "$(ghq root)/$dir" || return
}

# git branch switch via fzf.
b() {
  local branch=$(git branch -l --format='%(refname:short)' --sort=-authordate | fzf --preview '' --query="$*")
  test -z "$branch" || git switch "$branch"
}

B() {
  gh branch
}

c() {
  kubectx
}

# ls if no arg / directory arg, otherwise bat the file.
l() {
  if [[ "$#" == 0 ]]; then
    ll
  else
    if [[ -d "$1" ]]; then
      ll $@
    else
      bat $@
    fi
  fi
}

# test: switch starship main / sub prompt
starship_conf_main="$XDG_CONFIG_HOME/starship.toml"
starship_conf_sub="$XDG_CONFIG_HOME/starship_sub.toml"
px() {
  if [ "$STARSHIP_CONFIG" = "$starship_conf_main" ]; then
    export STARSHIP_CONFIG="$starship_conf_sub"
  elif [ "$STARSHIP_CONFIG" = "" ]; then
    export STARSHIP_CONFIG="$starship_conf_sub"
  else
    export STARSHIP_CONFIG="$starship_conf_main"
  fi
}

#=====================
# zle widgets
#=====================
# navi snippet picker -> insert into the command line.
search_snippet_and_replace_lbuffer() {
  LBUFFER+=$(navi)
  zle redisplay
}
zle -N search_snippet_and_replace_lbuffer
bindkey '^X^N' search_snippet_and_replace_lbuffer

# ripgrep -> fzf -> nvim live grep [QUERY]
RELOAD='reload:rg --column --color=always --smart-case {q} || :'
OPENER='if [[ $FZF_SELECT_COUNT -eq 0 ]]; then
          nvim {1} +{2}     # No selection. Open the current line in Vim.
        else
          nvim +cw -q {+f}  # Build quickfix list for the selected items.
        fi'

livegrep () (
  fzf --disabled --ansi --multi \
      --bind "start:$RELOAD" --bind "change:$RELOAD" \
      --bind "enter:become:$OPENER" \
      --delimiter : \
      --preview 'bat --style=plain --color=always --highlight-line {2} {1}' \
      --preview-window '~4,+{2}+4/3,<80(up)' \
      --query "$*"
)
zle -N livegrep
bindkey '^G' livegrep

#=====================
# fzf
#=====================
export FZF_DEFAULT_COMMAND='rg --files --hidden --color=auto --follow --glob "!**/.git/*"'
export FZF_DEFAULT_OPTS=" \
  --height 20% --layout=reverse \
  --margin=0 --padding=0 --info=inline \
  --tiebreak=index --filepath-word \
  --exit-0 \
  --bind='ctrl-w:backward-kill-word,ctrl-k:kill-line' \
  --bind='ctrl-x:jump' \
  --bind='up:preview-page-up' \
  --bind='down:preview-page-down' \
  --bind=\"ctrl-o:execute:$OPENER\" \
  --bind='ctrl-z:ignore' \
  --bind='ctrl-]:replace-query' \
  --bind='?:toggle-preview' \
  --bind='alt-a:select-all,alt-d:deselect-all' \
"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="$FZF_DEFAULT_OPTS --preview 'bat --color=always {1}'"
export FZF_COMPLETION_OPTS="--border --info=inline"
# Use fd (https://github.com/sharkdp/fd) for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fd --hidden --follow --exclude ".git" . "$1"
}
# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude ".git" . "$1"
}

# This speeds up pasting w/ autosuggest
# https://github.com/zsh-users/zsh-autosuggestions/issues/238
pasteinit() {
  OLD_SELF_INSERT=${${(s.:.)widgets[self-insert]}[2,3]}
  zle -N self-insert url-quote-magic # I wonder if you'd need `.url-quote-magic`?
}
pastefinish() {
  zle -N self-insert $OLD_SELF_INSERT
}
zstyle :bracketed-paste-magic paste-init pasteinit
zstyle :bracketed-paste-magic paste-finish pastefinish

#=====================
# hooks
#=====================
autoload -Uz add-zsh-hook

# List the directory after every cd.
chpwd() {
  [[ -o interactive ]] || return
  ll
}

# Keep the tmux window name in sync with the current directory.
update_tmux_window () {
  [[ -n "$TMUX" ]] || return
  tmux rename-window "$(basename "$PWD")"
}
add-zsh-hook chpwd update_tmux_window
add-zsh-hook precmd update_tmux_window

# Emit OSC 133;A so tmux can track prompt positions (next-prompt/previous-prompt in copy mode).
# Prepend to PROMPT (after Starship sets it) so the mark lands at the exact moment zsh draws
# the prompt, avoiding cursor-position races with Starship's own terminal sequences.
_tmux_prompt_mark() {
  [[ -n "$TMUX" ]] || return
  PROMPT=$'%{\e]133;A\a%}'"$PROMPT"
}
add-zsh-hook precmd _tmux_prompt_mark

# Ship a dotfiles PR: push → create PR → auto-merge → wait for MERGED → switch to main.
# Stays on the branch until the PR actually merges, so symlinked dotfiles never revert mid-flight.
dotfiles-ship() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD) || return 1
  git push -u origin HEAD || return 1
  gh pr create --fill || return 1
  gh pr merge --auto --merge || return 1
  echo "Waiting for CI..."
  gh pr checks --watch
  echo "Waiting for merge..."
  until [[ $(gh pr view --json state -q '.state') == "MERGED" ]]; do
    sleep 3
  done
  git switch main
  git pull
  git branch -d "$branch"
}

#=====================
# load other settings
#=====================
source-if-exist() {
  file_path="$1"
  if [[ -f "$file_path" ]]; then
    source "$file_path"
    return $?
  fi
  return 0
}

# host-based config
source-if-exist "$XDG_CONFIG_HOME/hosts/${${HOST%%.*}:l}.zshrc"

# local config
source-if-exist "$HOME/.zshrc.local"

#=====================
# dotfiles sync reminder
#=====================
# Remind at startup when the dotfiles repo needs syncing between machines
# (uncommitted / unpushed / behind upstream) so updates aren't forgotten when
# hopping between home and office. Skipped in CI via DOTFILES_NO_SYNC_CHECK.
if [[ -z "${DOTFILES_NO_SYNC_CHECK:-}" ]]; then
  _dotfiles_dir="${${(%):-%x}:A:h}"
  [[ -x "$_dotfiles_dir/bin/dotfiles_sync_check.sh" ]] && "$_dotfiles_dir/bin/dotfiles_sync_check.sh"
  unset _dotfiles_dir
fi

#=====================
# Brewfile drift reminder
#=====================
# Remind at startup when a Brewfile bundle has packages that aren't installed
# yet (after adding a formula, or on a freshly bootstrapped machine). Notify
# only: prints the cached result and refreshes it in a background job (at most
# once per 24h), so startup never blocks on brew; see bin/brew_bundle_check.sh.
# Skipped in CI via DOTFILES_NO_BREW_CHECK.
if [[ -z "${DOTFILES_NO_BREW_CHECK:-}" ]]; then
  _dotfiles_dir="${${(%):-%x}:A:h}"
  [[ -x "$_dotfiles_dir/bin/brew_bundle_check.sh" ]] && "$_dotfiles_dir/bin/brew_bundle_check.sh"
  unset _dotfiles_dir
fi
