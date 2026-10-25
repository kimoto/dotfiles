---
name: prune-sweep
description: いま居る repo で、使われていないもの・重複しているものを根拠つきで探し、正味削除の PR を1本と、持ち主に聞く issue を1件まで出す。★「減らして」「使ってないの消して」と言われた時と、routine から使う。⚠️ 勘で消さない・使われ方が repo の外でしか分からないものは issue で聞く・マージしない。
---

# 減らす

手で呼んでも routine から呼んでも同じ手順。どの repo かは呼ぶ側が決める。
1回の成果は「正味削除の PR 最大1本」と「持ち主に判断を聞く issue 最大1件」。

## 0. 準備

- 対象 repo の既定ブランチの最新で作業する（`git fetch origin <base> && git checkout -B <base> origin/<base>`）。
  `CLAUDE.md`（または `AGENTS.md`）を全部読む
- ★**repo ごとの決まりは `CLAUDE.md` の `## Scouts` 節にある。**そこに書かれたもの（検査コマンド・触らない場所・保留中・残すと決めたもの・PR と issue の言語・open PR の上限）はこの skill より優先する
- ⚠️ `## Scouts` 節が無い repo では推測で進めない。何もせず「Scouts 節が無い」と報告して終わる
- ★**手を入れる前に、既定ブランチのまま `## Scouts` 節の検査を回す。**落ちたら:
  - 環境のせい（root で動いている・道具が無い）なら、落ちたものを控える。変更後に同じものだけ落ちていればよい
  - 環境のせいでなければ（日付・外の版の変化）、直さずに「既定ブランチが赤（何が）」と報告して終わる
- GitHub 操作は GitHub MCP（`gh` は無いことがある）。search_* は使わず、list_pull_requests / list_issues をラベルで絞る
- repo の visibility を確かめる。公開 repo なら、PR・issue・コミットに private repo の名前・中身、ホスト名、どのマシンで使っているかを書かない

## 1. 無人で呼ばれたときの間隔（backoff）

呼ぶ側（routine）が間隔を決めているときは、最初の3項目を飛ばし、open PR の確認からにする。

- ラベル `routine:prune-sweep` の PR と issue（open/closed とも）の一番新しい created_at から今日（JST）までの日数 d。一件も無ければ routine を作った日を起点にする
- d が 0 か 2 の累乗（1・2・4・8・16…）のときだけ走る。出力が出れば翌日から間隔が戻り、出ない間は倍々に空く。それ以外は「休み（d 日出力なし）」の1行で終わる
- 照会に失敗したら休まずに走り、その旨を報告に書く
- open な `routine:prune-sweep` PR があれば新しい PR は作らない（issue は可）
- `## Scouts` 節（とそこが指す文書）に open PR の上限があれば、そこに書かれた数え方で従う

## 2. 候補の探し方

- ★**検出は道具に任せ、判定を自分でする。**`## Scouts` 節に検出の道具（Python は vulture、JS/TS は knip、Go は deadcode など）があれば先に回す。道具の出力は候補であって根拠ではない。動的な呼び出し（文字列で import・getattr・外から呼ばれる入口）を `rg` で確かめてから消す
- どこからも呼ばれないスクリプト・関数・モジュール・設定（名前を `rg` で repo 全体に。CI・hook・他スクリプト・docs・`.claude/` まで）
- 依存の宣言にあるのに、どこからも import されないもの
- 同じことを2か所でしている設定、もう無い機能・OS・版向けの分岐、使われないオプション
- ⚠️★**使われているかが repo の外でしか分からないもの**（人の手が叩くコマンド、実機で動いている timer やサービス、外から叩かれる URL）は PR にしない。issue にして、持ち主に何を確かめてほしいかを書く
- closed かつ未マージの `routine:prune-sweep` PR で出した候補、`## Scouts` 節の保留中・残すと決めたものは出さない

## 3. PR の条件

- 正味削除（削除行 > 追加行）。使われていない根拠（`rg` の結果など）を本文に書ける1テーマだけ
- ブランチ `refactor/<short-desc>`。Conventional Commits
- コミット identity は `## Scouts` 節に書かれたもの（`-c user.name=… -c user.email=…` で渡す）。無ければ git の設定のまま
- push 前に `## Scouts` 節の検査コマンドを手で回す。消したものが docs や一覧に載っていれば同じ PR で直す
- PR テンプレートがあれば埋める。ラベル `routine` と `routine:prune-sweep`（付ける前に `"$(readlink -f ~/.claude/skills/prune-sweep)/../../../bin/routine_labels.sh" routine:prune-sweep` で色を揃えて無ければ作る。`gh` が無ければ飛ばす）、assignee は `## Scouts` 節に書かれた人（無ければ付けない）。subscribe_pr_activity して CI を緑にする。**マージしない**

## 報告

1行目だけで分かる形にする（`<repo>` は repo 名）:

```
🌿 prune-sweep <repo>: PR <URL>（−N行）
🌿 prune-sweep <repo>: issue <URL>
🌿 prune-sweep <repo>: 候補なし（見た範囲）
⚠️ prune-sweep <repo>: 確認できなかった（理由）
```

⚠️「何も無かった」と「確認できなかった」を混ぜない。
