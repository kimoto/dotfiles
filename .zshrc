#===============================================================
#    ________      _______. __    __  .______        ______
#   |       /     /       ||  |  |  | |   _  \      /      |
#   `---/  /     |   (----`|  |__|  | |  |_)  |    |  ,----'
#      /  /       \   \    |   __   | |      /     |  |
#  __ /  /----.----)   |   |  |  |  | |  |\  \----.|  `----.
# (__)________|_______/    |__|  |__| | _| `._____| \______|
#
# Author: kimoto
#===============================================================

#=====================
# base settings
#=====================
unlimit
limit -s
umask 022
bindkey -e
autoload -Uz compinit
compinit
OMITTED_DIR="%(3~,%-1~/.../%1~,%~)"
PROMPT="%n@${HOST} %{$fg[blue]%}${OMITTED_DIR}%{$reset_color%}[%!]%{%(?..$fg[red])%}%#%{$reset_color%} "

# paths
typeset -U path # 重複したパスをPATHに登録しない
typeset -U manpath
typeset -xT SUDO_PATH sudo_path
path+=(
  $HOME{,/.local,/.cargo,/.docker}/bin(N-/)
  {/opt/homebrew,/home/linuxbrew/.linuxbrew}/bin(N-/)
)
manpath+=(
  {$HOME/.local,/opt/local,/usr/local,/usr}/share/man(N-/)
)
sudo_path+=(
  {,/usr/pkg,/usr/local,/usr}/sbin(N-/)
)

# setup base commands
if builtin command -v brew >/dev/null; then
  eval "$(brew shellenv)"
fi

if builtin command -v sheldon >/dev/null; then
  eval "$(sheldon source)"
fi

# setopts
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

# aliases
alias ls='eza --hyperlink --icons auto'
alias ll='ls --long --all --git-repos-no-status --time-style=relative --sort=modified'
alias tree='ll -T'
alias mv='nocorrect mv'
alias cp='nocorrect cp -v' # verbose
alias mkdir='nocorrect mkdir'
alias vi='nvim'
alias reload="exec zsh"
alias cd="z"
alias cat='bat'
alias less='bat --pager=less'
alias curl='curlie' # for pretty-print
alias ag='rg'
alias grep='grep --color=auto'

# vars
HISTFILE=~/.zsh_history
HISTSIZE=9999999
SAVEHIST=9999999
MAILCHECK=0
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
watch=notme # watch and notify, other login user
zle_highlight+=(paste:none)

# env
export PAGER="less --RAW-CONTROL-CHARS --quit-if-one-screen --mouse -X"
export BAT_PAGER="$PAGER"
export LESS='-M -i -M -f -Q'
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export EDITOR=nvim
export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"
export LANG=ja_JP.UTF-8
export CLICOLOR=1
export XDG_CONFIG_HOME="$HOME/.config"
export LS_COLORS=$(vivid generate solarized-dark)
export TERM=xterm-256color
export GPG_TTY=$(tty)

# zstyles
zstyle ':completion:*:default' menu select=1
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # 大文字/小文字を無視
zstyle ':completion:*' completer _complete _match _approximate # 曖昧な入力でも補完キーにより自動でマッチさせる
zstyle ':completion:*' squeeze-slashes true # 引数の最後の補完時は、スラッシュを除去
zstyle ':completion:*:cd:*' ignore-parents parent pwd # ../ってやったときは現在の居るディレクトリが補完候補にならないように
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# bindkeys
bindkey "^\\" undo

# utility functions
temp(){
  cd "$(mktemp -d $HOME/tmp/$(date +'%Y%m%d').$1${1:+.}\`XXXXXX)"
}

# yazi
y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# yazi
lg() {
  export LAZYGIT_NEW_DIR_FILE=~/.lazygit/newdir
  lazygit "$@"
  if [ -f $LAZYGIT_NEW_DIR_FILE ]; then
    cd "$(cat $LAZYGIT_NEW_DIR_FILE)"
    rm -f $LAZYGIT_NEW_DIR_FILE > /dev/null
  fi
}

chpwd() {
  ll
}

g() {
  local dir=$(ghq list | fzf --preview "bat --style=plain --color=always $(ghq root)/{}/README.*" --query="$*")
  [ -n "$dir" ] && cd "$(ghq root)/$dir" || return
}

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

#=====================
# extras
#=====================

# replace --help for colorize
alias -g -- -h='-h 2>&1 | bat --language=help --style=plain'
alias -g -- --help='--help 2>&1 | bat --language=help --style=plain'

# ripgrep->fzf->vim [QUERY]
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

# setup fzf
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

#============
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
#============

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
# load other settings
#=====================
source-if-exist() {
  $file_path=$1
  if [ -f "$file_path" ]; then
    source $file_path
  fi
}

# host-based config
h=${${HOST%%.*}:l}
source-if-exist "$XDG_CONFIG_HOME/hosts/$h.zshrc"

# local config
source-if-exist "$HOME/.zshrc.local"
