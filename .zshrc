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
umask 007
bindkey -e

autoload -U zmv
autoload -U zargs
zmodload -i zsh/files

# compinit
fpath=($HOME/.zsh $fpath)
autoload -U compinit
compinit -u

# colors
autoload -U colors
colors

zstyle ':completion:*' special-dirs true
zstyle ':completion:*:default' menu select=1
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'
zstyle ':completion:*' group-name ''

zstyle ':completion:*' use-cache on               # 補完のキャッシュを有効にする
zstyle ':completion:*' cache-path ~/tmp/zsh_cache # 補完のキャッシュパス

# 曖昧な入力でも補完キーにより自動でマッチさせる
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 1 numeric

zstyle ':completion:*:functions' ignored-patterns '_*' # 持っていないコマンドの補完を無効化
zstyle ':completion:*' squeeze-slashes true # 引数の最後の補完時は、スラッシュを除去
# zstyle ':completion:*:cd:*' ignore-parents parent pwd # ../ってやったときは現在の居るディレクトリが補完候補にならないように

# TODO = .. nyuuryoku de parent directory he
#autoload -Uz add-zsh-hook
#autoload -Uz vcs_info
#zstyle ':vcs_info:*' enable git svn hg bzr
#zstyle ':vcs_info:*' formats '(%s)-[%b]'
#zstyle ':vcs_info:*' actionformats '(%s)-[%b|%a]'
#zstyle ':vcs_info:(svn|bzr):*' branchformat '%b:r%r'
#zstyle ':vcs_info:bzr:*' use-simple true
#
## この check-for-changes が今回の設定するところ
#zstyle ':vcs_info:git:*' check-for-changes false
#zstyle ':vcs_info:git:*' stagedstr "+"    # 適当な文字列に変更する
#zstyle ':vcs_info:git:*' unstagedstr "-"  # 適当の文字列に変更する
#zstyle ':vcs_info:git:*' formats '(%s)-[%b] %c%u'
#zstyle ':vcs_info:git:*' actionformats '(%s)-[%b|%a] %c%u'
#
#function _update_vcs_info_msg() {
#    psvar=()
#    LANG=en_US.UTF-8 vcs_info
#    [[ -n "$vcs_info_msg_0_" ]] && psvar[1]="$vcs_info_msg_0_"
#}
#add-zsh-hook precmd _update_vcs_info_msg
#RPROMPT="%1(v|%F{green}%1v%f|)"

# setopt
setopt autocd
setopt nocorrectall
setopt histignoredups
setopt pushdignoredups
setopt interactivecomments
setopt multios
setopt incappendhistory
setopt autopushd
setopt extendedhistory
setopt extendedglob
setopt noclobber
setopt printeightbit
setopt listpacked
setopt listrowsfirst
setopt cdablevars
unsetopt promptcr
setopt pushd_ignore_dups
setopt extended_glob
setopt extended_history
setopt complete_in_word
setopt menu_complete
setopt multios
setopt auto_menu
#set -u
#set -o errexit

# terminal
stty erase '^H'
stty stop undef

# alias
if [ `uname` = "Linux" ]; then
  alias ls='ls --color=auto'
fi

alias mv='nocorrect mv'
alias cp='nocorrect cp'
alias gem='nocorrect gem'
alias mkdir='nocorrect mkdir'
alias ll='ls -rlth'
alias vi='vim'
alias zmv='noglob zmv'
alias mmv='zmv -W'
alias zcp='zmv -C'
alias zln='zmv -L'
alias memo='vi -c ":HatenaEdit"'
alias 2ch='emacs -f navi2ch'
alias s='screen -xRRU -S working_space'
alias t='tmux -2 -u'
alias d='emacs -f dired'
alias changelog='emacs -f add-change-log-entry-other-window'
alias mew='emacs -f mew'
alias svn='nocorrect svn'
alias e='emacsclient -t -a emacs' 
alias cp='cp -v' # verbose
alias q='exit'
bindkey -s ':q' "^A^Kexit\n" # :qとすばやく入力するとexitされる

# var
HISTFILE=~/.zsh_history
HISTSIZE=9999999
SAVEHIST=9999999
MAILCHECK=0

if [ "$TERM" = "emacs" ]; then
  PROMPT="%n %~[%!]%# "
else
  OMITTED_DIR="%(3~,%-1~/.../%1~,%~)"
  PROMPT="%n %{$fg[blue]%}${OMITTED_DIR}%{$reset_color%}[%!]%{%(?..$fg[red])%}%#%{$reset_color%} "
fi

WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
watch=notme # watch and notify, other login user

# env
export PAGER="less --RAW-CONTROL-CHARS"
export EDITOR=vim
export LESS="-girMXfFQ"
#export LESSOPEN="|lesspipe.sh %s"
export LANG=ja_JP.UTF-8
export CLICOLOR=1
export SVN_EDITOR=vim
export PATH="$HOME/utils:$HOME/bin:$HOME/local/bin:$HOME/usr/local/bin:/opt/local/bin:/usr/local/bin:$PATH"
export MANPATH="$HOME/local/share/man:/opt/local/share/man:$MANPATH"
export LD_LIBRARY_PATH="$HOME/local/lib"
export C_INCLUDE_PATH="$HOME/local/include"
export KEYTIMEOUT=20
export __CF_USER_TEXT_ENCODING='0x1F6:0x08000100:14' # use utf8 with pbcopy/pbpaste 
export GREP_OPTIONS='--color=auto'
export GISTY_DIR="$HOME/dev/gists"

# ~/.ssh/known_hostsからホスト名を補完します
function print_known_hosts (){ 
if [ -f $HOME/.ssh/known_hosts ]; then
  cat $HOME/.ssh/known_hosts | tr ',' ' ' | cut -d' ' -f1 
fi  
}
_cache_hosts=($( print_known_hosts ))

# insert-files
autoload insert-files
zle -N insert-files
bindkey '^X^F' insert-files

# binding SourceEngine like key config
function reloadconfig {
  source ~/.zshrc
}
zle -N reloadconfig
bindkey '^[[15~' reloadconfig

# ls-colors
LS_COLORS="fi=37:di=36:ex=32:ln=34:bd=33:cd=33:pi=35:so=35"
LS_COLORS="$LS_COLORS:*.gz=31:*.Z=31:*.lzh=31:*.zip=31:*.bz2=31"
LS_COLORS="$LS_COLORS:*.tar=31:*.tgz=31"
LS_COLORS="$LS_COLORS:*.gif=33:*.jpg=33:*.jpeg=33:*.tif=33:*.ps=33"
LS_COLORS="$LS_COLORS:*.xpm=33:*.xbm=33:*.xwd=33:*.xcf=33"
LS_COLORS="$LS_COLORS:*.avi=33:*.mov=33:*.mpeg=33:*.mpg=33"
LS_COLORS="$LS_COLORS:*.mid=33:*.MID=33:*.rcp=33:*.RCP=33:*.mp3=33"
LS_COLORS="$LS_COLORS:*.mod=33:*.MOD=33:*.au=33:*.aiff=33:*.wav=33"
LS_COLORS="$LS_COLORS:*.htm=35:*.html=35:*.java=35:*.class=32"
LS_COLORS="$LS_COLORS:*.c=35:*.h=35:*.C=35:*.c++=35"
LS_COLORS="$LS_COLORS:*.tex=35:*~=0"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
export LS_COLORS

# history-search
#autoload history-search-end
#zle -N history-beginning-search-backward-end history-search-end
#zle -N history-beginning-search-forward-end history-search-end
#bindkey "^P" history-beginning-search-backward-end
#bindkey "^N" history-beginning-search-forward-end

bindkey "^R" history-incremental-pattern-search-backward

# bindkey -s
bindkey -s "vv" '!vi\n'
#bindkey -s "rr" '!ruby\n'

bindkey "^\\" undo

# replace-string
autoload -U replace-string
zle -N replace-string
bindkey "^[r" replace-string

# narrow-to-region
autoload -U narrow-to-region-invisible
zle -N narrow-to-region-invisible
bindkey "\C-xn" narrow-to-region-invisible

# predict on
autoload predict-on
zle -N predict-on
zle -N predict-off
bindkey '^X^Z' predict-on
bindkey '^Z' predict-off
zstyle ':predict' verbose true

# url-quote-magic
autoload -U url-quote-magic
zle -N self-insert url-quote-magic

# refe
#refe(){
#  $HOME/utils/refe_utf8.sh $@
#}

# for debug
#rr() {
#  local f
#  f=(~/.zsh/*(.))
#  unfunction $f:t 2> /dev/null
#  autoload -U $f:t
#}

## test
#expand-to-home-or-insert () {
#  if [ "$LBUFFER" = "" -o "$LBUFFER[-1]" = " " ]; then
#    LBUFFER+="~/"
#  else
#    zle self-insert
#  fi
#}
#zle -N expand-to-home-or-insert
#bindkey "\\"  expand-to-home-or-insert

# 先頭の^だけ上のディレクトリに移動
function change-directory-up() {
if [ "$LBUFFER" = "" ]; then
  cd ..
  zle reset-prompt
else
  zle self-insert
fi
}
zle -N change-directory-up; bindkey '\^' change-directory-up


# 先頭の-だけ直前のディレクトリに移動
function change-directory-prev() {
unsetopt pushdtohome
if [ "$LBUFFER" = "" ]; then
  cd -
  zle reset-prompt
else
  zle self-insert
fi
}
#zle -N change-directory-prev; bindkey '\-' change-directory-prev
zle -N change-directory-prev; bindkey '^O' change-directory-prev

function execute-last-command-line() {
if [ "$LBUFFER" = "" ]; then
  LBUFFER="builtin r $EDITOR"
  zle accept-line
else
  zle self-insert
fi
}
zle -N execute-last-command-line; bindkey '\@' execute-last-command-line

# screen dabbrev
HARDCOPYFILE=$HOME/tmp/screen-hardcopy
touch $HARDCOPYFILE

dabbrev-complete () {
  local reply lines=80 # 80行分
  screen -X eval "hardcopy -h $HARDCOPYFILE"
  reply=($(sed '/^$/d' $HARDCOPYFILE | sed '$ d' | tail -$lines))
  compadd - "${reply[@]%[*/=@|]}"
}

#zle -C dabbrev-complete menu-complete dabbrev-complete
#bindkey '^o' dabbrev-complete
#bindkey '^o^_' reverse-menu-complete

# test alias
alias reload="exec zsh"

# for screen
preexec () {
  screen-statusline-update $@
}

screen-statusline-update () {
  if [ "$TERM" = "screen" ]; then
    1="$1 " # deprecated.
    echo -ne "\ek${${(s: :)1}[0]}:$HOST\e\\"
  fi
}
screen-statusline-initialize () {
  screen-statusline-update "zsh"
}

hgrep(){
  fc -l -E 1 | fuzzygrep $@
}

h(){
  hgrep "$@" | tail
}

logger(){
  exec script ~/var/log/`~/utils/timestamp`.log
}

alias-if-exist(){
  which "$1" >/dev/null && alias $2
}

view-cheat-sheet(){
  set +u
  if [ "$1" = "" ]; then
    less /tmp/cheat-sheet
  else
    less +/$1 /tmp/cheat-sheet
  fi
}

cheat-sheet(){
  set +u
  if [ "$1" = "" ]; then
    ;
  else
    cp "$1" /tmp/cheat-sheet
  fi

  view-cheat-sheet
}

is-text-file(){
  (file -L -s "$@" | cut -d':' -f2- | grep text) >/dev/null 
}

inspect-file(){
  set +u
  if [ "$1" = "" ]; then
    ll
  else
    is-text-file "$1" && (pygmentize -g "$1" | less -R) || (less -R "$1")
  fi
}
alias l=inspect-file

# chpwd
function chpwd(){
l
}

iname() {
  find . -type d -name .svn -prune -o \( -iname "*$1*" -print \)
}
alias inaem=iname

g(){
  set -f
  find . -type d '(' -name .svn -o -name CVS ')' -prune -o -print0 | xargs -0 fgrep -i "$1"
}

# load local config
h=${${HOST%%.*}:l}
if [ -f "$HOME/config/hosts/$h.zshrc" ]; then
  source "$HOME/config/hosts/$h.zshrc"
fi

if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi

## set environment utils
if [ -e "$HOME/utils/env.sh" ]; then
  . "$HOME/utils/env.sh"
fi

screen-statusline-initialize
