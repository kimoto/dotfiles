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
- ★**既定は、最終的な差分を通しで（`<base>..HEAD`）全員で見る。**重複や security の穴は、足した分だけを見ても分からない。
- 前回の指摘を直しただけの小さな commit なら、その分を下の 1 と 2 だけで見てよい。**前回の指摘と、それぞれを直した commit は渡す。却下した理由は渡さない。**
- revert だけなら回さない。docs だけなら `review-rules` だけ回す（差分の外で古くなった文章を見るため）。
- 全員より狭くしたときは、そう判断した理由を一言返す。

## 全体のレビュー: まとめ役が全員を `run_in_background` で並べて回す

まとめ役の subagent を1つだけ起動し、下の全員を回させる。まとめ役は全員が終わるのを待ち、重複を除いた1つの報告で返す。指摘ごとに、どの係が出したかを付ける。呼んだ側に届くのは、その報告1つだけになる。

1. **正しさ**: `review-correctness` agent。
2. **Codex**: `node <~/.claude/plugins/cache/openai-codex/codex/ の最新版>/scripts/codex-companion.mjs review --base <base>`。有効な環境（`~/.claude/settings.json` の `enabledPlugins["codex@openai-codex"]` が true、cloud 以外）だけ。違うモデルは違うものを見落とす。無い環境では、代わりに `review-correctness-checklist` agent。
3. `review-rules` agent — commit メッセージと差分のコメント、差分のせいで古くなった差分の外の文章。
4. `review-portability` agent — CI・bash 3.2・コンテナなど、別の環境での違い。
5. `review-refactor`・`review-tests`・`review-security`・`review-speed` の各 agent。
   ⚠️ `~/.claude/agents/<名前>.md` が無いマシン（pull したがリンクし直していない）では、代わりに subagent に `~/.claude/skills/<対応する sweep>/SKILL.md` の**差分モード**をやらせ、括弧の model を指定する（各 agent の frontmatter と同じ）。対応: refactor → refactor-sweep（sonnet）、tests → test-sweep（sonnet）、security → security-audit（opus）、speed → bottleneck-sweep（sonnet）。
   sweep の無い correctness・correctness-checklist・rules・portability は、subagent に dotfiles の `claudecode/agents/<名前>.md`（`~/.claude/skills/review-branch` のリンク先から2つ上）を読ませてそのとおりにやらせ、model はその frontmatter に合わせる。レビューする repo の中を探さない。

## 終わったら

1. 指摘を直して commit する。直さないものは、なぜかを返事に書く。直しても指摘が続いて終わらないなら、それ以上は回さず本人に聞く。
2. レビューを求めてきた側（push を止めた hook など）が完了の印を頼んでいたら、そのとおりにする。
3. push や PR 作成を止められていたなら、もう一度やる。

## PR の題と本文

PR を開く前は `review-rules` agent に、repo のパス・branch・使う予定の題と本文だけを渡す。短いので foreground でよい。直してから PR を作る。
