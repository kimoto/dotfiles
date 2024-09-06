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
unlimit
limit -s
umask 022
bindkey -e

# compinit
autoload -Uz compinit
compinit

#zstyle ':completion:*' special-dirs true
zstyle ':completion:*:default' menu select=1
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # 大文字/小文字を無視
#zstyle ':completion:*' verbose yes
#zstyle ':completion:*:descriptions' format '%B%d%b'
#zstyle ':completion:*:messages' format '%d'
#zstyle ':completion:*:warnings' format 'No matches for: %d'
#zstyle ':completion:*' group-name ''
#zstyle ':completion:*' use-cache on               # 補完のキャッシュを有効にする
#zstyle ':completion:*' cache-path ~/tmp/zsh_cache # 補完のキャッシュパス
zstyle ':completion:*' completer _complete _match _approximate # 曖昧な入力でも補完キーにより自動でマッチさせる
#zstyle ':completion:*:match:*' original only
#zstyle ':completion:*:approximate:*' max-errors 1 numeric
#zstyle ':completion:*:functions' ignored-patterns '_*' # 持っていないコマンドの補完を無効化
zstyle ':completion:*' squeeze-slashes true # 引数の最後の補完時は、スラッシュを除去
zstyle ':completion:*:cd:*' ignore-parents parent pwd # ../ってやったときは現在の居るディレクトリが補完候補にならないように
#zstyle ':completion:*:sudo:*' command-path ${(s.:.)PATH} # sudo時も$PATH内のコマンドを補完する

# setopt
setopt autocd # cd不要
setopt autopushd # cdの履歴に残す
setopt nocorrectall # correctallの無効化
setopt histignoredups # 重複を記録しない
setopt histignorealldups # 古い方を削除
setopt pushdignoredups # 重複を記録しない
setopt interactivecomments # コメントを有効化
setopt share_history # historyを共有
setopt incappendhistory # incrementalに追加
#setopt multios
#setopt extendedhistory
#setopt extendedglob
#setopt noclobber
#setopt printeightbit
#setopt listpacked
#setopt listrowsfirst
#setopt cdablevars
#unsetopt promptcr
#setopt extended_glob
#setopt complete_in_word
#setopt menu_complete
#setopt auto_menu
#setopt magic_equal_subst # --prefix=~/local の~も展開できるように
#setopt ignore_eof # Ctrl-Dを無視

# aliases
alias ll='eza -l --git --git-repos-no-status --time-style=relative --sort=modified --icons'
alias ls='eza --git --icons'
alias tree='eza -T -l --git --git-repos-no-status --time-style=relative --sort=modified --icons'
alias mv='nocorrect mv'
alias cp='cnocorrect cp -v' # verbose
alias mkdir='nocorrect mkdir'
alias vi='nvim'
alias reload="exec zsh"
alias cd="z"
alias cat='bat'

function temp(){ cd `mktemp -d $HOME/tmp/\`date +'%Y%m%d'.$1${1:+.}\`XXXXXX` }

# var
HISTFILE=~/.zsh_history
HISTSIZE=9999999
SAVEHIST=9999999
MAILCHECK=0

OMITTED_DIR="%(3~,%-1~/.../%1~,%~)"
PROMPT="%n@${HOST} %{$fg[blue]%}${OMITTED_DIR}%{$reset_color%}[%!]%{%(?..$fg[red])%}%#%{$reset_color%} "

WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
watch=notme # watch and notify, other login user

# env
export GOPATH="$HOME/go"
export PAGER="less --RAW-CONTROL-CHARS"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export VISUAL=nvim
export EDITOR=nvim
export GIT_EDITOR=nvim
export LESS="-girMXfFQ"
export LANG=ja_JP.UTF-8
export CLICOLOR=1

typeset -U path # 重複したパスをPATHに登録しない
typeset -U manpath
typeset -xT SUDO_PATH sudo_path
path=(
  $HOME/bin
  $HOME/usr/local/bin
  $HOME/local/bin
  $HOME/.local/bin
  $HOME/.cargo/bin
  $HOME/.docker/bin
  $HOME/utils
  $HOME/go/bin
  /usr/local/bin
  /usr/local/sbin
  /opt/local/bin
  /opt/homebrew/bin
  /usr/bin
  /usr/sbin
  /bin
)
manpath+=(
  $HOME/local/share/man
  /opt/local/share/man
  /usr/local/share/man
  /usr/share/man
)
sudo_path=({,/usr/pkg,/usr/local,/usr}/sbin(N-/))

# install homebrew
if [ -d "/opt/homebrew/bin" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  eval "$(sheldon source)"
fi

LS_COLORS=$(vivid generate solarized-dark)
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
export LS_COLORS

bindkey "^\\" undo

# chpwd
function chpwd(){
  ll
}

g() {
  local dir
  dir=$(ghq list | fzf --height=20% --layout=reverse --info=inline --margin=0 --padding=0 --no-multi --exit-0 --query="$*")
  [ -n "$dir" ] && cd "$(ghq root)/$dir" || return
}

# temporary disabled
#b() {
#  local branch
#  branch=$(git branch -l | fzf --height=20% --layout=reverse --info=inline --margin=0 --padding=0 --no-multi --exit-0 --query="$*" | awk '{print $1}')
#  test -z "$branch" || git checkout "$branch"
#}

#B() {
#  local branch
#  branch=$(git branch -a -l | fzf --height=20% --layout=reverse --info=inline --margin=0 --padding=0 --no-multi --exit-0 --query="$*" | awk '{print $1}')
#  test -z "$branch" || git checkout "$branch"
#}

export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!**/.git/*"'
export FZF_DEFAULT_OPTS="
    --height 20% --reverse
    --margin=0 --info=inline
    --tiebreak=index --filepath-word
    --color fg:-1,bg:-1,hl:33,fg+:250,bg+:235,hl+:33
    --color info:37,prompt:37,pointer:230,marker:230,spinner:37
    --bind='ctrl-w:backward-kill-word,ctrl-x:jump,down:preview-page-down'
    --bind='ctrl-z:ignore,ctrl-]:replace-query,up:preview-page-up'
    --bind='ctrl-a:toggle-all,?:toggle-preview'
"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="$FZF_DEFAULT_OPTS"
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

# load local config
h=${${HOST%%.*}:l}
if [ -f "$HOME/config/hosts/$h.zshrc" ]; then
  source "$HOME/config/hosts/$h.zshrc"
fi

if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
