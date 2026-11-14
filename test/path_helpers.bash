# Shared by bats suites that run a script with a PATH holding only the tools
# it needs before it looks for the one under test, so a copy of that tool on
# the machine running the suite cannot answer instead.

# only_on_path DIR TOOL...: make DIR hold links to just these tools.
only_on_path() {
  local dir=$1 tool
  shift
  mkdir -p "$dir"
  for tool in "$@"; do
    ln -s "$(command -v "$tool")" "$dir/$tool"
  done
}
