---
name: speed-watch
description: dotfiles の「人が待つもの」（zsh・nvim・tmux の起動、hook、pre-commit、bats）の速さを測って issue #392 に記録し、悪化していれば原因を直す PR を、そうでなければ遅いものを速くする PR を1本出す。★「速さ測って」「遅くなってない?」と言われた時と、週次 routine から使う。⚠️ 数字以外を公開の issue に書かない・マージしない。
---

# dotfiles の速さを見張る

仕事は3つ: **(A) 測って記録する、(B) 悪化していれば原因を直す、(C) 遅いものを1つ速くする。**

★**手で呼んでも routine から呼んでも同じ手順。**(C) をいつやるか（間隔）は呼ぶ側が決める。手で呼ばれたら (C) もやる。

## 0. 準備

- dotfiles の `main` の最新で作業する（測るのは main。ブランチの上だと SessionStart の hook がネットワークを叩いて数字が揺れる）。`AGENTS.md`（= `CLAUDE.md`）と `claudecode/rules/`（特に latency.md・hooks.md・experiments.md・tooling.md）を読む
- `./bin/setup_cloud_session.sh` で検査の道具を入れる。zsh・tmux・nvim が入らなければ、その項目は `n/a` のまま（速かったことにしない）
- GitHub 操作は GitHub MCP か `gh api`（REST）。`search_*` は使わない

## (A) 測る（毎回）

- `./bin/speed_report.sh` を回す。出てきた1行を、そのまま issue #392「Speed watch log」にコメントで足す
- ★毎回ちがう一行コマンドで測らない。足りない項目があれば `bin/speed_report.sh` を直す（bats 付き、テストは一度わざと壊して落ちるのを見る）
- ⚠️ コメントには数字以外を書かない。ホスト名・CPU 名・private repo・どのマシンで使っているかは書かない（dotfiles は公開 repo）

クラウドのコンテナで測るときの落とし穴:

- mise の shim は PATH の**最後**に置く（`PATH=$PATH:~/.local/share/mise/shims`）。先頭だと、bats の一時 HOME で gitleaks の shim が落ちて bats が `fail` になる
- HOME を変えると mise の shim が壊れる（config の trust）。nvim・sheldon・starship は `mise use -g aqua:...` で入れる
- tmux 3.4 の `kill-server` はサーバーが消える前に戻る。socket 名を使い回さず、1回ごとに変える
- `/dev/null` を引数に取る `ln -sf` に余計な引数を渡さない（/dev/null を壊したことがある）

## (B) 悪化を見る（毎回）

- #392 の直近4回の中央値と比べ、1.25 倍を超え、測り直しても同じなら悪化
- 全項目がそろって動いたなら入れ物（コンテナ）側の変化。報告に書くだけで PR は出さない
- 1項目だけなら、前回のコメントの commit から今の main までを二分探索して原因の commit を特定し、直す PR を出す（間隔に関係なくすぐ）

## (C) 速くする（呼ぶ側が決めた間隔で）

- 予算は latency.md（人が待つものは 1 秒未満、pre-commit 1 秒未満、pre-push 10 秒未満）。予算から一番はみ出している項目を1つ選び、速くする PR を1本
- PR 本文に前後の数字（中央値・回数）を書く。1回で大差がつけば、追加の比較は要らない（experiments.md）
- open な `routine:speed-watch` PR があれば新しく作らない。closed かつ未マージの PR で出した案は二度と出さない
- 出さないと決まっているもの: tpm プラグインの中身を `.tmux.conf` に取り込むこと（#225・#402）

## PR の約束

- 新しいブランチ `perf/<short-desc>`（スクリプトを足すなら `feat/`）。Conventional Commits、英語
- push する前に `./bin/run_tests.sh`、`bin/lint_*.sh`、触った領域の e2e を回す
- `.github/PULL_REQUEST_TEMPLATE.md` を埋める。ラベル `routine` と `routine:speed-watch`、assignee kimoto。`subscribe_pr_activity` して CI を green にする
- **マージしない**

## 報告（1行目だけで分かる形）

「⏱ speed-watch: 記録のみ（悪化なし）」「⏱ speed-watch: <項目> が悪化 → PR <URL>」「⏱ speed-watch: 改善 PR <URL>（<項目> <前>→<後>ms）」「⚠️ speed-watch: 測れなかった（理由）」のどれか。2行目に #392 のコメントの URL。
