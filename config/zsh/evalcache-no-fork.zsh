# Overrides mroth/evalcache's _evalcache (sourced right after the plugin via
# its sheldon post hook). Upstream builds the cache filename by piping the
# command string through md5/md5sum — a fork per call, ~3ms on Linux and ~10ms
# on macOS, paid on every startup even when all caches hit. Derive the name
# from the sanitized command string instead: no fork, still unique per command
# line, and still matches the init-*.sh pattern _evalcache_clear expects.
# Filenames differ from upstream's, so switching regenerates each cache once.
_evalcache () {
  local cacheDir="${ZSH_EVALCACHE_DIR:-$HOME/.zsh-evalcache}"
  local cacheFile="$cacheDir/init-${${(j:-:)@}//[^A-Za-z0-9_.-]/-}.sh"
  if [[ "$ZSH_EVALCACHE_DISABLE" == "true" ]]; then
    eval "$("$@")"
  elif [[ -s "$cacheFile" ]]; then
    source "$cacheFile"
  elif builtin type "$1" >/dev/null 2>&1; then
    echo "evalcache: $1 initialization not cached, caching output of: $*" >&2
    mkdir -p "$cacheDir"
    "$@" >| "$cacheFile"
    zcompile "$cacheFile" # like upstream (mroth/evalcache#13): parse once, source the wordcode after
    source "$cacheFile"
  else
    echo "evalcache: ERROR: $1 is not installed or in PATH" >&2
    return 1
  fi
}
