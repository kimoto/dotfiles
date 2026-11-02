---
name: review-branch
description: いま居る repo の commit（か、これから開く PR の題・本文）を、書き手の考えを渡さずにレビュアーの agent へ並べて回し、返った指摘を直すところまでやる。★「レビューして」「push 前に見て」「この branch 見て」と言われた時と、push を止められてレビューを求められた時に使う。⚠️ レビュアーは報告だけ、直すのは呼んだ側。
---

# branch のレビュー

★**レビュアーに渡すのは「repo のパス」「範囲」「目的」だけ。**書き手の推論を渡すと、それを確かめる係になってしまう。
⚠️ public repo では、security の指摘を commit・PR の文面に書かない。

## 範囲

どこまで・誰に見せるかは呼んだ側が決める。迷ったら広く見る。

- 言われた範囲があればそれ。無ければ、まだ誰も見ていない commit（push を止めた hook が示す）。base は先に fetch しておく。
- ★**既定は、最終的な差分を通しで（`<base>...HEAD`）見る。**重複や security の穴は、足した分だけを見ても分からない。誰が見るかは下の節で決める。
- 前回の指摘を直しただけの小さな commit なら、その分を下の 1 と、その指摘を出した係だけで見てよい。**前回の指摘と、それぞれを直した commit は渡す。却下した理由は渡さない。**
- revert だけなら回さない。docs だけでも 1 は回す。
- 表より狭くしたときは、そう判断した理由を一言返す。

## 全体のレビュー: 正しさが選んだ係を、呼んだ側が起動する

★**いつも回すのは 1 の正しさ（Opus）だけ。ほかの係は、正しさが範囲の差分を見て下の表から選ぶ。**書き手の context で選ぶと、書き手が関係ないと思った所が見られずに残る。ほかの係が要る差分は限られ、関係ない係も見るものが無いのに1人3〜4万トークンかかる。

| 係 | 回すとき |
|---|---|
| 1 正しさ | いつも |
| 2 Codex か checklist | 込み入ったロジック・並行処理・境界値を触ったとき。正しさは `review-correctness-checklist` と書き、Codex が有効な機械では呼んだ側が下の 2 の Codex に置き換える |
| 3 rules | commit メッセージ・コメント・文章を触り、差分の外の文章が古くなりうるとき |
| 4 portability | shell（`.sh`・`.bash`・`.zsh`・`bin/` の拡張子なし・shebang のあるファイル）、Makefile、`.github/workflows/` のコードの行を変えたとき（コメントだけは除く） |
| `review-security` | 走るもの・許すもの・見張るものを触ったとき: hook と hook を登録・設置するスクリプト、`settings*.json`・`.claude/`・`.mcp.json`・Codex の設定、`.github/`、agent の定義と指示（rules・skills・`CLAUDE.md`・`AGENTS.md`）、git の設定と hook、秘密の検査の設定、shell の rc、依存の固定（renovate・mise・lock）。中身に権限・認証・秘密・外への通信が出てくるときも。迷ったら回す |
| `review-tests` | 挙動を変え、それを確かめるテストが要るとき |
| `review-speed` | 人や処理が待つ所（hook・ループ・起動時の処理）を触ったとき |
| `review-refactor` | 新しい関数や繰り返しを足したとき |

起動は2回に分ける。

1. `review-correctness` を `run_in_background: false` で起動する。渡すのは repo のパス・範囲・目的。
2. 正しさの `回す係:` に並んだ係を、1つのメッセージで `run_in_background: false` で起動する（Codex だけは Bash のバックグラウンド）。⚠️ 正しさが返るまで待つので、ほかの係の待ちはそのあとに足される。正しさを待たずに起動すると、選ぶ人がいなくなる。呼んだ側が足すのはよいが減らさない。⚠️ 正しさが `回す係:` の行を返さない・表の係名で答えない・`全員` と答えたときは、表の全員を回す。

subagent には Agent tool が無いので、全員を回す subagent を1つ挟むことはできない。全員の報告がそろうまで指摘に手を付けない。そろったら重複を除き、どの係が出したかを付けて読む。選ばれた係と外れた係を、正しさの理由つきで返す。

1. **正しさ**: `review-correctness` agent。
2. **Codex**: `run_in_background` で `node <~/.claude/plugins/cache/openai-codex/codex/ の最新版>/scripts/codex-companion.mjs review --base <base>`。Bash の前面の上限（既定2分）を超えうるため。有効な環境（`~/.claude/settings.json` の `enabledPlugins["codex@openai-codex"]` が true、cloud 以外）だけ。違うモデルは違うものを見落とす。無い環境では、代わりに `review-correctness-checklist` agent。
3. `review-rules` agent — commit メッセージと差分のコメント、差分のせいで古くなった差分の外の文章。
4. `review-portability` agent — CI・bash 3.2・コンテナなど、別の環境での違い。
5. `review-refactor`・`review-tests`・`review-security`・`review-speed` の各 agent。
   ⚠️ `~/.claude/agents/<名前>.md` が無いマシン（pull したがリンクし直していない）では、代わりに subagent に `~/.claude/skills/<対応する sweep>/SKILL.md` の**差分モード**をやらせ、括弧の model を指定する（各 agent の frontmatter と同じ）。対応: refactor → refactor-sweep（sonnet）、tests → test-sweep（sonnet）、security → security-audit（opus）、speed → bottleneck-sweep（sonnet）。
   sweep の無い correctness・correctness-checklist・rules・portability は、subagent に dotfiles の `claudecode/agents/<名前>.md`（`~/.claude/skills/review-branch` のリンク先から3つ上が dotfiles）を読ませてそのとおりにやらせ、model はその frontmatter に合わせる。レビューする repo の中を探さない。

## 終わったら

1. 指摘を直して commit する。直さないものは、なぜかを返事に書く。直しても指摘が続いて終わらないなら、それ以上は回さず本人に聞く。
2. レビューを求めてきた側（push を止めた hook など）が完了の印を頼んでいたら、そのとおりにする。
3. push や PR 作成を止められていたなら、もう一度やる。

## PR の題と本文

PR を開く前は `review-rules` agent に、repo のパス・branch・使う予定の題と本文だけを渡す。1人だけなので、そのまま返事を待つ。直してから PR を作る。
