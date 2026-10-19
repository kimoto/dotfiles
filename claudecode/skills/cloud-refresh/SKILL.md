---
name: cloud-refresh
description: クラウドセッションの ~/.claude を dotfiles の最新 main に合わせ直す（fast-forward してリンクを張り直す）。★「設定を最新にして」「dotfiles pull して」「新しい skill が出てこない」と言われた時に使う。⚠️ クラウドセッション専用。手元の Mac では mklink.sh。
---

# クラウドセッションの設定を最新にする

起動時の hook と同じスクリプトを、セッションの途中でもう一度走らせる。

```sh
d=$(dirname "$(dirname "$(readlink -f ~/.claude/settings.json)")")
"$d/bin/refresh_cloud_session.sh"
```

⚠️ `settings.json` が `*/claudecode/settings-cloud.json` へのリンクでなければ、ここはクラウドセッションではない。
何もせずそう伝える。

## 伝えること

出力の `[refresh]` 行と `MISS` 行をそのまま根拠にして、次の3つを分けて言う。

- **いまのセッションで効くもの**: skill。新しく張ったものも、次の依頼から呼べる。
- **次のセッションから効くもの**: rules（`CLAUDE.md` を含む）、hook、`settings-cloud.json` の設定。
  ★Claude Code は起動時に一度だけ読む。「最新にした」とだけ言うと、いま効いたと読まれる。
- **最新にならなかったもの**: `pull skipped`（main 以外を checkout 中）か `MISS pull`
  （分岐・未コミット・通信失敗）なら、何が古いまま残ったか。⚠️ 勝手に reset や stash をしない。

★新しいセッションでも skill が足りないなら、環境のキャッシュが hook ごと古い。
環境設定の Setup script を変えると、次のセッションでそれが走り直してキャッシュも作り直される。
それを人に頼む（ここからは変えられない）。
