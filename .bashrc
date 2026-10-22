umask 022
ulimit -c 0

# Interactive shells only.
if [[ "$PS1" ]]; then
  workdir="\[\e[34m\]\w\[\e[m\]"
  PS0="\u $workdir\\$ "
  PS1="\u@\H $workdir\\$ "
  unset workdir

  shopt -s cdspell
  shopt -s cmdhist
  shopt -s histappend
  shopt -s no_empty_cmd_completion

  # alias
  alias ..='cd ..'
  alias ls='ls --color=auto'
  alias ll='ls -lh'
  alias vi='vim'
  alias s='screen -xRR'
  alias h='history 25'
  alias total='sort | uniq -c | sort -nr'
  alias ipaddr="grep -Eo '[0-9]+(\.[0-9]+){3}'"
  alias irb='pry'

  set -o emacs

  complete -d cd
  complete -u su finger
  complete -c man

  # shell var
  TMOUT=$((60 * 60)) # an idle shell exits after an hour
  BLOCKSIZE=K
  IGNOREEOF=3
  HISTSIZE=50000
  HISTFILESIZE=50000
  HISTTIMEFORMAT="%y/%m/%d %H:%M:%S  "

  # env
  export PAGER=less
  export EDITOR=vim
  export VISUAL=vim
  export LANG=ja_JP.UTF-8
  export LESS="-gieRmX"
  export PATH=$HOME/bin:$HOME/local/bin:$PATH
  alias grep='grep --binary-files=without-match --color=auto'
  # egrep/fgrep are obsolescent (grep >=3.8 warns): keep the muscle memory but
  # route through the grep alias above, so they get color and skip the warning.
  alias egrep='grep -E'
  alias fgrep='grep -F'

  # The last ten history lines matching a pattern.
  function hgrep {
    history | grep -Ei "$*" | tail;
  }

  # Commands on $PATH whose name matches a pattern.
  function cmdgrep {
    echo $PATH | tr '\n:' '\0' | sort -uz | xargs -0 ls 2>/dev/null | grep -Ei "$*"
  }

  # Swap between the short and the long prompt.
  function px {
    local tmp=$PS0; PS0=$PS1; PS1=$tmp;
  }

  if [[ -e "$HOME/.bashrc.local" ]]; then
    source "$HOME/.bashrc.local"
  fi
fi
