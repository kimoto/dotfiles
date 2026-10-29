#!/usr/bin/env bats

# Tests for hammerspoon/markdown.js, the popup's Markdown renderer. What must
# hold: text from the model never becomes a tag, and a list's plain text keeps
# its bullets. Run through macOS's own JavaScript (osascript), so they skip on
# Linux, where CI runs bats.

setup() {
  command -v osascript >/dev/null || skip "needs osascript (macOS)"
  RENDERER="$BATS_TEST_DIRNAME/../hammerspoon/markdown.js"
}

render() {
  osascript -l JavaScript -e '
    ObjC.import("Foundation");
    function run(argv) {
      eval($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js);
      return renderMarkdown(argv[1]);
    }' "$RENDERER" "$1"
}

@test "model text with tags in it stays text" {
  run render '<img src=x onerror="post(1)"> & **<b>x</b>**'
  [ "$status" -eq 0 ]
  [ "$output" = '<p>&lt;img src=x onerror=&quot;post(1)&quot;&gt; &amp; <strong>&lt;b&gt;x&lt;/b&gt;</strong></p>' ]
}

@test "a gist, then bullets with a bold phrase" {
  run render $'要点です。\n\n- **金曜**までに返事\n- 費用は `3万円`'
  local mark='<span class="mark">・</span>'
  [ "$output" = "<p>要点です。</p><ul><li>$mark<strong>金曜</strong>までに返事</li><li>${mark}費用は <code>3万円</code></li></ul>" ]
}

@test "numbered items keep their numbers, lines in a paragraph keep their breaks" {
  run render $'1. 一つ目\n2. 二つ目\n次の行\nその次'
  local list='<ol><li><span class="mark">1. </span>一つ目</li><li><span class="mark">2. </span>二つ目</li></ol>'
  [ "$output" = "$list<p>次の行<br>その次</p>" ]
}

@test "a code block is shown as it is" {
  run render $'```\n**not bold** <x>\n```'
  [ "$output" = '<pre><code>**not bold** &lt;x&gt;</code></pre>' ]
}
