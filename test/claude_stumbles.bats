#!/usr/bin/env bats

# claude_stumbles.sh groups the tool calls that did not go through. What
# matters is that each kind is told apart, that one stumble seen many times
# with different details counts as one line, and that the cloud event shape
# reads the same as a local transcript.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d)"
}

teardown() {
  cd "$BATS_TEST_DIRNAME"
  rm -rf "$WORK"
}

stumbles() {
  run "$REPO_ROOT/bin/claude_stumbles.sh" "$@"
}

# A tool call and its result, as two local transcript lines.
call() { # <id> <tool> <day> [command]
  jq -nc --arg id "$1" --arg tool "$2" --arg day "$3" --arg cmd "${4:-}" \
    '{type:"assistant", timestamp:($day+"T01:00:00Z"),
      message:{content:[{type:"tool_use", id:$id, name:$tool, input:{command:$cmd}}]}}'
}
result() { # <id> <day> <is_error> <text>
  jq -nc --arg id "$1" --arg day "$2" --argjson err "$3" --arg t "$4" \
    '{type:"user", timestamp:($day+"T01:00:01Z"),
      message:{content:[{type:"tool_result", tool_use_id:$id, is_error:$err, content:$t}]}}'
}

@test "each kind of stumble is counted, most frequent first" {
  {
    call a Bash 2026-11-28
    result a 2026-11-28 true 'PreToolUse:Bash hook error: [command hook 2]: This push publishes 1 commit(s) on branch-a'
    call b Bash 2026-11-28
    result b 2026-11-28 true 'PreToolUse:Bash hook error: [command hook 2]: This push publishes 3 commit(s) on branch-b'
    call c Bash 2026-11-28
    result c 2026-11-28 true \
      'Permission for this action was denied by the auto mode classifier. Reason: [Destructive or Unwanted Actions].'
    call d Edit 2026-11-28
    result d 2026-11-28 true "The user doesn't want to proceed with this tool use."
    call e Bash 2026-11-28
    result e 2026-11-28 true $'Exit code 2\n\e[31mnot ok 1\e[0m'
    call f Bash 2026-11-28
    result f 2026-11-28 false 'fine'
  } >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf '2\thook\tPreToolUse:Bash: This push publishes N commit(s) on')" ]
  [[ "$output" == *"$(printf '1\tpermission\tBash: [Destructive or Unwanted Actions]\n')"* ]]
  [[ "$output" == *"$(printf '1\trejected\tEdit')"* ]]
  [[ "$output" == *"$(printf '1\terror\tBash: exit 2')"* ]]
  [ "${#lines[@]}" -eq 4 ]
}

@test "a cloud events page reads like a local transcript, deny decisions included" {
  jq -nc '{ccr:{data:[
    {created_at:"2026-11-28T02:00:00Z",
      assistant:{internal_anthropic_catchall:{message:{content:[{type:"tool_use",id:"x",name:"Bash"}]}}}},
    {created_at:"2026-11-28T02:00:01Z", user:{internal_anthropic_catchall:{
      message:{content:[{type:"tool_result",tool_use_id:"x",is_error:true,content:[{type:"text",text:"no"}]}]},
      tool_result_meta:[{id:"x",permission_decision:{decision:"deny",reason_type:"rule"}}]}}}
  ]}}' >"$WORK/page.json"
  stumbles "$WORK/page.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\tpermission\tBash')" ]
}

@test "--since leaves out older days" {
  {
    call a Bash 2026-11-20
    result a 2026-11-20 true 'Exit code 1'
    call b Bash 2026-11-27
    result b 2026-11-27 true 'Exit code 1'
  } >"$WORK/t.jsonl"
  stumbles --since 2026-11-21 "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\terror\tBash: exit 1')" ]
}

@test "with no files it reads the projects directory, and says when it is empty" {
  export CLAUDE_CONFIG_DIR="$WORK/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
  stumbles
  [ "$status" -eq 1 ]
  [[ "$output" == *"no transcripts"* ]]
  { call a Bash 2026-11-28; result a 2026-11-28 true 'Exit code 1'; } >"$CLAUDE_CONFIG_DIR/projects/p/s.jsonl"
  stumbles
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\terror\tBash: exit 1')" ]
}

@test "a failing command is told apart by its program, a hook by what it says" {
  {
    call a Bash 2026-11-28 'cd /x && git push'
    result a 2026-11-28 true 'Exit code 1'
    call b Bash 2026-11-28 'bats test'
    result b 2026-11-28 true 'Exit code 1'
    call c mcp__x 2026-11-28
    result c 2026-11-28 true 'PreToolUse:mcp__x hook error: Before opening the PR for claude/branch-a in /repo'
    call d mcp__x 2026-11-28
    result d 2026-11-28 true 'PreToolUse:mcp__x hook error: Before opening the PR for claude/branch-b in /repo'
    call e Bash 2026-11-28 'rm -rf x'
    result e 2026-11-28 true 'Permission for this command was denied by a built-in safety check, so it did not run.'
  } >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf '1\terror\tBash git: exit 1')"* ]]
  [[ "$output" == *"$(printf '1\terror\tBash bats: exit 1')"* ]]
  [[ "$output" == *"$(printf '2\thook\tPreToolUse:mcp__x: Before opening the PR for <path>')"* ]]
  [[ "$output" == *"$(printf '1\tpermission\tBash: a built-in safety check, so it')"* ]]
}

@test "subagent transcripts, a broken line and a dash-named file are all read" {
  export CLAUDE_CONFIG_DIR="$WORK/claude"
  local sub="$CLAUDE_CONFIG_DIR/projects/-home-x/s1/subagents"
  mkdir -p "$sub"
  { call a Bash 2026-11-28; result a 2026-11-28 true 'Exit code 1'; printf '{"cut off'; } >"$sub/agent-1.jsonl"
  stumbles
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\terror\tBash: exit 1')" ]
  cd "$CLAUDE_CONFIG_DIR/projects"
  stumbles -home-x/s1/subagents/agent-1.jsonl
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\terror\tBash: exit 1')" ]
}

@test "other refusal wordings count as permission, a trailing stop does not split them" {
  {
    call a Bash 2026-11-28
    result a 2026-11-28 true 'Permission to use Bash with command rm -rf x has been denied.'
    call b Bash 2026-11-28
    result b 2026-11-28 true 'Permission for this action was denied. Reason: [X Y].'
    call c Bash 2026-11-28
    result c 2026-11-28 true 'Permission for this action was denied. Reason: [X Y]. If you need it, ask.'
  } >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf '2\tpermission\tBash: [X Y]')" ]
  [ "${lines[1]}" = "$(printf '1\tpermission\tBash')" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a cut-off file, an odd line and a result read twice do not change the count" {
  printf '{"cut off' >"$WORK/a.jsonl"
  {
    call a Bash 2026-11-28 'ls x'
    printf '{"timestamp":5,"tool_result_meta":[{"id":null}],"message":{"content":[{"type":"tool_result"}]}}\n'
    result a 2026-11-28 true 'Exit code 1'
  } >"$WORK/b.jsonl"
  stumbles "$WORK/a.jsonl" "$WORK/b.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\terror\tBash ls: exit 1')" ]
  stumbles "$WORK/b.jsonl" "$WORK/b.jsonl"
  [ "$output" = "$(printf '1\terror\tBash ls: exit 1')" ]
}

@test "bad arguments fail with usage" {
  stumbles --since yesterday
  [ "$status" -eq 2 ]
  stumbles --bogus
  [ "$status" -eq 2 ]
}

@test "a result that went through is not a stumble, whatever it quotes" {
  {
    call a Read 2026-11-28
    result a 2026-11-28 false "the docs say you haven't granted it yet"
    call b Bash 2026-11-28
    result b 2026-11-28 false 'PreToolUse:Bash hook error: quoted in a log'
    call c Bash 2026-11-28
    result c 2026-11-28 true 'Exit code 1'
  } >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\terror\tBash: exit 1')" ]
}

@test "a file that cannot be read is named, and the files after it still count" {
  { call a Bash 2026-11-28; result a 2026-11-28 true 'Exit code 1'; } >"$WORK/t.jsonl"
  stumbles "$WORK/missing.jsonl" "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot read $WORK/missing.jsonl"* ]]
  [[ "$output" == *"$(printf '1\terror\tBash: exit 1')"* ]]
}

@test "input with no line read as JSON fails instead of reading as no stumbles" {
  jq -n '{data:[]}' >"$WORK/pretty.json"
  stumbles "$WORK/pretty.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no line read as JSON"* ]]
}

@test "an odd tool_result_meta or a missing id leaves the other results on the line" {
  for meta in '{}' '["x"]' '[{"id":"a"}]'; do
    jq -nc --argjson meta "$meta" '{tool_result_meta:$meta, message:{content:[
      {type:"tool_result", is_error:true, content:"Exit code 1"},
      {type:"tool_result", tool_use_id:"a", is_error:true, content:"Exit code 1"}]}}' >"$WORK/t.jsonl"
    stumbles "$WORK/t.jsonl"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '1\terror\t?: exit 1')" ]
  done
}

@test "a reason is cut at a new sentence, not at an abbreviation" {
  { call a Bash 2026-11-28; result a 2026-11-28 true 'Permission for this action was denied. Reason: Uses e.g. rm here.'; } \
    >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$output" = "$(printf '1\tpermission\tBash: Uses e.g. rm here')" ]
}

@test "escape sequences and secret-looking words are not copied out" {
  # Built at run time, so no secret scanner reads a token in this file.
  local tok="gh""p_""$(printf 'a1%.0s' {1..18})"
  {
    call a Bash 2026-11-28
    result a 2026-11-28 true "$(printf 'X:\e]52;c;aGk=\a hook error: hi')"
    call b mcp__x 2026-11-28
    result b 2026-11-28 true "$(printf 'Error: token %s \ec rejected' "$tok")"
    call c Bash 2026-11-28 "$tok --x"
    result c 2026-11-28 true 'Exit code 1'
    call d mcp__x 2026-11-28
    result d 2026-11-28 true 'Error: key=abc rejected'
  } >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e'* && "$output" != *$'\a'* ]]
  [[ "$output" != *"$tok"* && "$output" != *abc* ]]
  [[ "$output" == *"$(printf 'hook\tX:: hi')"* ]]
  [[ "$output" == *"$(printf 'error\tmcp__x: Error: token <secret> c rejected')"* ]]
  [[ "$output" == *"$(printf 'error\tBash <secret>: exit 1')"* ]]
  [[ "$output" == *"$(printf 'error\tmcp__x: Error: key=<secret> rejected')"* ]]
}

@test "C1 and bidi controls, padded base64, long tokens and a word after password are not copied out" {
  {
    call a mcp__x 2026-11-28
    result a 2026-11-28 true "$(printf 'Error: \xc2\x9d0;t\xc2\x9c \xe2\x80\xae x')"
    call b mcp__x 2026-11-28
    result b 2026-11-28 true 'Auth: Basic dXNlcjpwYXNzd29yZA== no'
    call c mcp__x 2026-11-28
    result c 2026-11-28 true 'Key: wJalrXUtnFEMI+KzMDENG+bPxRfiCYEXAMPLEKEY bad'
    call d mcp__x 2026-11-28
    result d 2026-11-28 true 'login: password hunter2 wrong'
  } >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\xc2\x9d'* && "$output" != *$'\xe2\x80\xae'* ]]
  [[ "$output" == *"$(printf 'mcp__x: Auth: Basic <secret> no')"* ]]
  [[ "$output" == *"$(printf 'mcp__x: Key: <secret> bad')"* ]]
  [[ "$output" == *"$(printf 'mcp__x: login: password <secret> wrong')"* ]]
}

@test "a program run by path keeps its name, a renamed MCP server its tool" {
  local uuid=0f8fad5b-d9cb-469f-a165-70867728950e
  {
    call a Bash 2026-11-28 './bin/lint_a.sh'
    result a 2026-11-28 true 'Exit code 1'
    call b Bash 2026-11-28 './bin/run_b.sh'
    result b 2026-11-28 true 'Exit code 1'
    call c "mcp__${uuid}__create_pull_request" 2026-11-28
    result c 2026-11-28 true "PreToolUse:mcp__${uuid}__create_pull_request hook error: stop"
  } >"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf '1\terror\tBash lint_a.sh: exit 1')"* ]]
  [[ "$output" == *"$(printf '1\terror\tBash run_b.sh: exit 1')"* ]]
  [[ "$output" == *"$(printf '1\thook\tPreToolUse:mcp__<id>__create_pull_request: stop')"* ]]
}

@test "a pretty-printed page with scalars in it still fails as unread" {
  jq -n '{data:[{created_at:"2026-11-28", tags:["a", 1]}]}' >"$WORK/pretty.json"
  stumbles "$WORK/pretty.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no line read as JSON"* ]]
}

@test "a leading newline, a nameless tool and a backslash are read as they are" {
  jq -nc '{message:{content:[{type:"tool_use", id:"a", name:null}]}}' >"$WORK/t.jsonl"
  {
    result a 2026-11-28 true $'\nPermission to use Bash with command x has been denied.'
    call b Bash 2026-11-28
    result b 2026-11-28 true 'Error: C:\dir foo'
  } >>"$WORK/t.jsonl"
  stumbles "$WORK/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf '1\tpermission\t?')"* ]]
  [[ "$output" == *"$(printf '1\terror\tBash: Error: C:\\dir foo')"* ]]
  [ "${#lines[@]}" -eq 2 ]
}
