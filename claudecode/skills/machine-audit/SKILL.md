---
name: machine-audit
description: この PC（Mac／Windows）の自動起動・外に開いているポート・セキュリティ設定を集め、「残すと決めたもの」の一覧に無いものだけを名指しして、止めるか残すかを本人に yes/no で聞く。★「PC 点検して」「不要な常駐ない?」「セキュリティ設定大丈夫?」と言われた時、OS アップグレードの後、月1の収集が新顔を見つけた時に使う。⚠️ 見つけたことは非公開の場所にだけ書く・本人の yes なしに止めない／消さない。
---

# マシンの監査（新顔だけを名指しする）

★**集めるのは機械、決めるのは本人。**スクリプトが毎回同じ形で状態を出し、`machine_audit_diff.sh` が
「残すと決めたもの」（allow）に無いものだけを返す。この skill はその新顔を調べて、止めるか残すかの
**2択にして渡す**。⚠️ 全件を並べ直さない。前回までに決めたことは allow が覚えている。

★★ **見つけたことは非公開の場所にだけ書く。**スナップショットと allow は、呼ぶ側が指定する
非公開ディレクトリ（`$MACHINE_AUDIT_DIR`）に置く。公開 repo に開いているポート・常駐・設定の穴を書かない。
⚠️ `$MACHINE_AUDIT_DIR` が無ければ推測で置かない。聞く。

## 1. 集める

ホスト名を `HOST` とする（Windows は `hostname.exe`、Mac は `scutil --get LocalHostName`）。

- Mac: `bin/machine_audit_collect_macos.sh >| "$MACHINE_AUDIT_DIR/$HOST.snapshot.tsv"`
- Windows（WSL から）: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w windows/machine_audit_collect.ps1)" | tr -d '\r' >| …`

⚠️ 終了コードと行数を見る。0行・`unknown` だらけは「問題なし」ではなく**集め損ね**。
`unknown` は権限が要る項目（Mac の Login Items など）——本人のターミナルで叩く1行を出す。

## 2. 比べる

`bin/machine_audit_diff.sh "$MACHINE_AUDIT_DIR/$HOST.snapshot.tsv" "$MACHINE_AUDIT_DIR/$HOST.allow.tsv"`

- `new` — 決めていないもの。3へ
- `gone` — 残すと決めたが、もう無いもの。allow から消す候補（消えて困るのは設定だけ。
  `setting` の `gone` は**値が変わった**ということなので、`new` 側と組で見る）
- allow が無い（初回）なら、全部が `new` になる。⚠️ 初回は件数が多いので、**明らかに OS 由来のもの**
  （Windows の `svchost`・`System`・`lsass`、Mac の `com.apple.*` など）はまとめて1問にする

## 3. 調べて2択にする

新顔1件ずつ、**何者か・誰が入れたか・止めると何が困るか**を調べる。
⚠️ Web 検索に入れてよいのはソフト名・サービス名・ポート番号だけ。ホスト名・ユーザー名・SID・IP は入れない。

`AskUserQuestion` で、1問に最大4件（各件「止める／残す」）。★**推奨を先に置き、理由は1行**。
残すものには allow に書く理由をそのまま選択肢の説明に書く。

## 4. 反映する

- **止める**: 自動起動を切るのが既定（アンインストールは本人が言ったときだけ）。
  戻し方を必ず1行添える（Mac `launchctl enable gui/<uid>/<label>`、Windows `Enable-ScheduledTask` など）。
  管理者権限が要るものは本人のターミナルで叩く1行にして渡す。⚠️ AI から sudo／昇格しない
- **残す**: `$HOST.allow.tsv` に `kind<TAB>key<TAB>理由` を1行。理由の無い行は diff が拒否する。
  版や ID を含む名前は末尾 `*` で前方一致にする（`service:GoogleUpdaterService*`）
- 止めたものは、もう一度 1 を走らせて**消えたことを見る**（設定を書き戻して読んだだけでは確かめたことにならない）

## 5. 残す

スナップショットと allow を非公開の場所に commit する。報告は
**止めたもの（戻し方つき）／残したもの／本人の手に残ったもの**の3つだけ。
