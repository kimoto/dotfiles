#!/bin/bash
# shell_cmd_plain <tool> <command>: a shell tool's command rewritten so the
# hooks' bash-shaped patterns read it as git and gh would run. This file is
# *sourced*, not executed, by the review gate, the secret scan, the privacy
# check and the PR reminder, so all four see the same command.
#
# Either shell: git.exe and gh.exe, or a path to them, are git and gh.
# PowerShell only: names ignore case, a backtick escapes the next character
# (g`it is git; one before a line break continues the line), the call
# operator runs a quoted name or path (& "git"), and Set-Location, sl,
# Push-Location and pushd at the start of a command move as cd does.
# Bracket classes, not sed's I flag: BSD sed has no I.
# Not read: a command run through another one (cmd /c, Start-Process, iex).
# The hooks are help for an agent's own judgement, not a wall.
# A hook's quick exit tests the payload without backticks and under
# nocasematch, so it does not skip a spelling this function reads.
shell_cmd_plain() {
  local c=${2//$'\r'/}
  local git='[Gg][Ii][Tt]' gh='[Gg][Hh]' exe='\.[Ee][Xx][Ee]'
  if [ "$1" = PowerShell ]; then
    local nl='
'
    # The gate reads a line break as "; ".
    c=${c//\`$nl/ } c=${c//\`; / } c=${c//\`/}
    local loc='[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]' push='[Pp][Uu][Ss][Hh]'
    local cd_words="[Ss][Ee][Tt]-$loc|[Ss][Ll]|$push-$loc|${push}[Dd]|[Cc][Dd]|[Cc][Hh][Dd][Ii][Rr]"
    # Two expressions, not one with a backreference to the quote: POSIX ERE
    # has none in a pattern.
    c=$(sed -E \
      -e "s/&[[:space:]]*\"([^\"]*[\\\\/])?($git|$gh)($exe)?\"/\\& \\2/g" \
      -e "s/&[[:space:]]*'([^']*[\\\\/])?($git|$gh)($exe)?'/\\& \\2/g" \
      -e "s/(^|[;&|({])([[:space:]]*)($cd_words)[[:space:]]+(-[A-Za-z]+(:|[[:space:]]+))?/\\1\\2cd /g" \
      -e "s/(^|[;&|({[:space:]])$git([[:space:]]|\$)/\\1git\\2/g" \
      -e "s/(^|[;&|({[:space:]])$gh([[:space:]]|\$)/\\1gh\\2/g" \
      <<<"$c")
  fi
  sed -E \
    -e "s/(^|[;&|({[:space:]])([^[:space:];&|(){}\"']*[\\\\/])?($git)$exe([[:space:]]|\$)/\\1git\\4/g" \
    -e "s/(^|[;&|({[:space:]])([^[:space:];&|(){}\"']*[\\\\/])?($gh)$exe([[:space:]]|\$)/\\1gh\\4/g" \
    <<<"$c"
}

