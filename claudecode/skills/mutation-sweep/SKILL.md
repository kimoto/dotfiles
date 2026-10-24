---
name: mutation-sweep
description: いま居る repo で、スクリプトの失敗の出口（exit 1）をわざと壊してもテストが落ちない所を探し、一番効く1か所にテストを足す PR を1本出す。★「テストの穴を探して」「mutation test して」と言われた時に使う。手で呼ぶ用で routine にはしない。⚠️ テストを skip・弱めない・1回1か所・マージしない。
---

# テストの穴を埋める

1回の成果は「失敗の出口を1か所見張るテストを足す PR 最大1本」。

## 0. 準備

- 対象 repo の既定ブランチの最新で作業する（`git fetch origin <base> && git checkout -B <base> origin/<base>`）。
  `CLAUDE.md`（または `AGENTS.md`）を全部読む
- 壊して試す道具: `## Scouts` 節に書かれていればそれ、無ければ `bin/mutation_sweep.sh`。どちらも無ければ何もせず「道具が無い」と報告して終わる
- repo の visibility を確かめる。公開 repo なら、PR とコミットに private repo の名前・中身、ホスト名、どのマシンで使っているかを書かない

## 1. 回す

- `./bin/mutation_sweep.sh` を引数なしで回す（dotfiles で約6分）。範囲を絞るならスクリプトを引数に並べる
- ⚠️ 作業ツリーのファイルを書き換えながら走る。同じ checkout で別の作業をしない。終わったら `git status` で何も残っていないことを確かめる
- 先に、既定ブランチのまま全テストが green か見る。落ちているテストがあると、それに頼るものは全部 killed に見える

## 2. 1か所選ぶ

`survived` の行から、落ちたことに誰も気づかないと困る順に選ぶ:

1. 検査そのものの失敗（lint・check・golden 比較が「違う」と言う出口）。ここが黙ると、壊れた変更が素通りする
2. 安全の出口（秘密の検出、push・commit の前の止め、保護の確認）
3. bootstrap や install の「ここまで来なかった」を知らせる出口
4. それ以外の入力エラー

後回しにするもの: 道具が無い・OS が違う・`mktemp` 失敗のような、環境が壊れているときだけ通る出口。テストにする手間に見合わない。

- 同じ出口を見張る open PR、closed かつ未マージの `mutation-sweep` PR で出した出口は選ばない

## 3. テストを足す

- その出口を通る入力を作り、終了コードと、出るはずのメッセージを確かめるテストを書く。repo のテストの書き方（bats の fixture、`BATS_TEST_TMPDIR` など）に合わせる
- ★**赤を見る。**その1か所を `exit 0` にしたまま新しいテストを回して落ちることを確かめ、元に戻して green を確かめる
- スクリプトを触るのは、テストから入れない所に入口を作るときだけ（例: 比較先のファイルを環境変数で差し替える）。既定の挙動は変えない。変えたならヘッダーのコメントに足す
- ⚠️ 既存のテストを skip・弱めない。テストが遅くなるなら、何秒増えたかを PR に書く

## 4. PR

- ブランチ `test/<short-desc>`。Conventional Commits の `test(scope): …`（スクリプトに入口を足しても、目的がテストなら `test`）
- コミット identity は `command git -c user.name=kimoto -c user.email=9657+kimoto@users.noreply.github.com commit`
- push 前に `## Scouts` 節の検査、無ければ repo の lint とテストを手で回す
- PR テンプレートがあれば埋める。Verification に「壊して赤、戻して緑」を書く。assignee kimoto。subscribe_pr_activity して CI を緑にする。CI でそのテストが skip されずに走ったことをログで確かめる。**マージしない**

## 報告

1行目だけで分かる形にする（`<repo>` は repo 名）:

```
🧪 mutation-sweep <repo>: PR <URL>（どの出口・生き残り N 件中）
🧪 mutation-sweep <repo>: 生き残りなし（見た範囲）
⚠️ mutation-sweep <repo>: 確認できなかった（理由）
```

2行目以降に、選ばなかった生き残りのうち次に効きそうなものを3つまで。
