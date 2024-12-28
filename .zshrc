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
setopt multios # 複数のリダイレクトやパイプに対応
setopt extended_history # ヒストリに時刻を追加
setopt noclobber # リダイレクトで上書き禁止
setopt listpacked # 詰めて表示
#setopt listrowsfirst # 最初の項目をまず選択
#setopt cdablevars # 同じ名前の変なディレクトリに移動しちゃうやつ
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
alias ll='eza -l --git --git-repos-no-status --time-style=relative --sort=modified --icons'
alias ls='eza --git --icons'
alias tree='eza -T -l --git --git-repos-no-status --time-style=relative --sort=modified --icons'
alias mv='nocorrect mv'
alias cp='nocorrect cp -v' # verbose
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
zle_highlight+=(paste:none)

# install homebrew
if builtin command -v brew >/dev/null; then
  eval "$(brew shellenv)"
fi

if builtin command -v sheldon >/dev/null; then
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

# load local config
h=${${HOST%%.*}:l}
if [ -f "$HOME/config/hosts/$h.zshrc" ]; then
  source "$HOME/config/hosts/$h.zshrc"
fi

if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
