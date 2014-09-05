#= bashrc
#= $Id$

umask 022
ulimit -c 0

if [[ "$PS1" ]]; then
	# terminal 
	workdir="\[\e[34m\]\w\[\e[m\]"
	PS0="\u $workdir\\$ "
	PS1="\u@\H $workdir\\$ "
	unset workdir

	shopt -s cdspell
	shopt -s cmdhist
	shopt -s histappend
	shopt -s no_empty_cmd_completion
	# shopt -s implicitcd 

	# alias
	alias ..='cd ..'
	alias ls='ls --color=auto'
	alias ll='ls -lh'
	alias vi='vim'
	alias s='screen -xRR'
	alias h='history 25'
	alias total='sort | uniq -c | sort -nr' 
	alias ipaddr="egrep -o '[0-9]+(\.[0-9]+){3}'"
  alias irb='pry'

	set -o emacs
  #set -o errexit
  #set -u

	complete -d cd
	complete -u su finger 
	complete -c man

  # shell var
	TMOUT=$((60 * 60))	# 1 hour
	BLOCKSIZE=K
	IGNOREEOF=3
	HISTSIZE=50000
	HISTFILESIZE=50000
	HISTTIMEFORMAT="%y/%m/%d %H:%M:%S  "
	# HISTIGNORE=ls:h

  # env
	export PAGER=less
	export EDITOR=vim
	export VISUAL=vim
	export CVSEDITOR=vim
	export SVN_EDITOR=vim
	export LANG=ja_JP.UTF-8
	export LESS="-gieRmX"
	export LESSCHARSET=latin1	# output binary
	export PATH=$HOME/bin:$HOME/local/bin:$PATH
	export GREP_OPTIONS="--binary-files=without-match --color=auto"

  # history grep 
  function hgrep {
  	history | egrep -i "$*" | tail;
  }
  
  # command grep
  function cmdgrep {
  	echo $PATH | tr '\n:' '\0' | sort -uz | xargs -0 ls 2>/dev/null | egrep -i "$*"
  }
  
  # change prompt (short prompt <-> long prompt)
  function px {
  	local tmp=$PS0; PS0=$PS1; PS1=$tmp;
  }

  if [ -e "$HOME/.bashrc.local" ]; then
    source "$HOME/.bashrc.local"
  fi
fi

[[ -s "$HOME/perl5/perlbrew/etc/bashrc" ]] && source "$HOME/perl5/perlbrew/etc/bashrc"
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" 
[[ -s "$HOME/.phpbrew/bashrc" ]] && source "$HOME/.phpbrew/bashrc"

