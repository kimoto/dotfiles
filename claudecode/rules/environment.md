# 環境メモ

## curl は curlie にエイリアスされている

`.zshrc` で `alias curl='curlie'`（pretty-print 用）。Claude Code の Bash ツールもこのエイリアスを踏む。curlie は httpie 風に引数を解釈するため、素の curl と挙動が変わる:

- フラグの値（`--connect-to` の引数など）をデータ項目と誤解釈して **GET が POST になる**ことがある
- `-sI` などの出力が空になることがある

**本物の curl が必要なときは `command curl ...` か `/usr/bin/curl ...` を使うこと。**
