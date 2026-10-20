---
name: cloud-refresh
description: クラウドセッションの ~/.claude を dotfiles の最新 main に合わせ直す（fast-forward してリンクを張り直す）。★「設定を最新にして」「dotfiles pull して」「新しい skill が出てこない」と言われた時に使う。⚠️ クラウドセッション専用。手元の Mac では mklink.sh。
---

# クラウドセッションの設定を最新にする

起動時の hook と同じスクリプトを、セッションの途中でもう一度走らせ、
変わった rules を読み直す。

```sh
d=$(dirname "$(dirname "$(readlink -f ~/.claude/settings.json)")")
"$d/bin/refresh_cloud_session.sh"
```

⚠️ `settings.json` が `*/claudecode/settings-cloud.json` へのリンクでなければ、ここはクラウドセッションではない。
何もせずそう伝える。

## 変わった rules をこのセッションに入れる

rules は起動時に一度読まれたきりなので、張り直しただけではこのセッションは古い版のまま動く。
出力の `rule changed:` 行のファイルは全部 Read して、以降の作業に適用する。
起動時に読んだ版と食い違う箇所は、新しい方に従う。
`rule removed:` 行のファイルは、起動時の版がまだ文脈に残っていても従わない。

★行が出るのは、このセッションが始まった commit から動いた分だけ。
起動時の hook が持ってきた分も含むので、もう読んだ版を読み直すことがあるが、それでよい。

## 伝えること

出力の `[refresh]` 行と `MISS` 行をそのまま根拠にして、次の3つを分けて言う。

- **いまのセッションで効くもの**: skill（新しく張ったものも、次の依頼から呼べる）と、
  上で Read した rules。どの rules を読み直したかを名前で言う。
- **自動で入るもの**: `settings changed:` 行の `settings-cloud.json`。
  Claude Code はファイルの変更を見て読み直すので、hook・permissions・env・outputStyle は
  このセッションにも入る。⚠️ 例外は起動時だけ読む key（`model` など）と、もう走った
  SessionStart hook。その2つが変わっていれば、このセッションには入らないと言う。
- **最新にならなかったもの**: `pull skipped`（main 以外を checkout 中）か `MISS pull`
  （分岐・未コミット・通信失敗）なら、何が古いまま残ったか。⚠️ 勝手に reset や stash をしない。

★`rule removed:` が出たら、新しいスレッドで続けるよう勧める。
消えた rule は起動時の版が文脈に残ったままで、従わないと決めても消せない。
`rule changed:` だけなら読み直しで足りるので勧めない。毎回勧めると、本当に要る時に読まれない。

★新しいセッションでも skill が足りないなら、環境のキャッシュが hook ごと古い。
環境設定の Setup script を変えると、次のセッションでそれが走り直してキャッシュも作り直される。
それを人に頼む（ここからは変えられない）。
