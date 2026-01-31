---
name: dotfiles-pr-flow
description: DotfilesリポジトリのPR作成フローを、ローカル変更の整理からShellCheck・コミット・push・gh pr createまで、AGENTS.mdのルールに従って実行する必要があるときに使う。dotfiles向けのPR手順や必須ルールを正確に踏む依頼で使用する。
---

# Dotfiles PR Flow

## Overview

dotfilesリポジトリ固有のPR手順に従い、ブランチ作成、変更、チェック、コミット、push、PR作成までを順に行う。

## Workflow

### 1) Confirm scope and repo rules

- リポジトリ直下の `AGENTS.md` を読み、PR/ShellCheck/コミット規約を適用する。
- 明確な理由がない限り、1 PR = 1 commit とする。

### 2) Create a branch if missing

- ブランチが無ければ作成する。
- 命名は `fix/yyyymm` / `vk/<slug>` / `chore/<slug>` を使う。迷う場合はユーザーに確認する。
- 既存の作業ツリーが汚れていて分離が必要なら、別worktreeで作業する。

### 3) Make changes

- 依頼されたファイルのみを編集する。
- 変更は最小限に留め、タスクに集中させる。

### 4) Run required checks

- `bin/` 配下のシェルを変更した場合は必ず実行する:
  - `shellcheck bin/*.sh`
- 明示依頼がない限り、チェックは最小限にする。

### 5) Commit (rules apply)

- コミットメッセージは英語にする。
- 署名がハングする場合は次を実行する:
  - `export GPG_TTY=$(tty)`
  - pinentry設定を確認（macOS: pinentry-mac + gpg-agent.conf）。
- 例:
  - `git add <user-specified files>`
  - `git commit -m "<English summary>"`

### 6) Push

- `git push -u origin <branch>` を実行する。

### 7) Create PR

- コミット後、PR作成は必ずユーザー確認を取る。
- 確認後に `gh pr create` を実行する。
- PR本文の末尾にAI開示文を入れる（デフォルト）:
  - `AI disclosure: Drafted with Codex.`
- 変更がスキル由来の場合はSummaryに1行入れる（例: `Created via dotfiles-recommender skill`）。
- 改行崩れ回避のため `--body-file` を優先する。

PR本文例（AI開示は末尾）:

```
## Summary
- ...

## Testing
- ...

AI disclosure: Drafted with Codex.
```

PR本文の更新は次で行う:
- `gh pr edit --body-file <file>`

## Notes

- コミットメッセージにもAI開示を要求された場合は、末尾に1行追加する。
- フローは必ず「変更 →（必要ならShellCheck）→ commit → push → PR」の順で進める。
