---
name: dotfiles-recommender
description: Dotfiles改善提案、Brewfile.*と.zshrcを中心にリポ全体を点検し、より良いアプリ/仕組み/設定値の提案や見直し点を提示する必要があるときに使う。BrewfileやZsh設定のレビュー、改善案作成、提案リスト整理、リスク区分、適用手順提示が必要な依頼で使用する。
---

# Dotfiles Recommender

## Overview

Dotfilesリポジトリをレビューし、Brewfile.*と.zshrcを起点に改善点や提案を整理して提示する。変更は依頼があるまで行わず、提案の根拠と影響範囲を明確にする。

## Workflow

### 0) Preflight

- 作業前に `git status -sb` を確認し、既存の変更や未追跡が多い場合は**別worktree**で作業を分離する。
- ブランチ名は `fix/yyyymm` / `vk/<slug>` / `chore/<slug>` のいずれかにする。迷う場合はユーザーに確認する。

### 1) Scope and inputs

- 対象ファイルを列挙する: `Brewfile.*`、ルートの`.zshrc`、`config/`配下、`bin/`配下。
- 目的OSを確認する（macOS / Linux / 両方）。不明なら確認質問を出す。
- 最新情報が必要なアプリ提案はWeb検索が必要になる旨を伝え、許可を取る。許可がない場合は一般的な改善案に留める。

### 2) Review focus

- **Brewfile.*:**
  - 重複、用途の重なり、OS別の住み分け漏れを確認する。
  - `tap`/`brew`/`cask`の分類や依存関係の整理余地を探す。
  - コメントから意図が読み取れるかを確認し、必要なら補足提案を出す。
- **.zshrc:**
  - 起動時間に影響する設定（`compinit`、`autoload`、プラグイン読み込み順）を点検する。
  - `PATH`順序、エイリアス衝突、条件分岐のOS差分を確認する。
  - 変更の影響が大きい提案は「任意/要相談」に分ける。
- **Repo全体:**
  - `config/`で管理しているアプリ設定の抜けや重複を確認する。
  - `bin/`のスクリプト品質や古い記述の改善余地を探す。
  - READMEやAGENTS.mdの運用ルールと整合しているかを確認する。

### 3) Output format

- 提案は次の3区分で整理する: **Quick wins**, **Optional upgrades**, **Risky changes**。
- 各提案に以下を明記する:
  - 対象ファイル
  - 提案内容（具体的な変更案）
  - 根拠（なぜ良いか）
  - 影響範囲（壊れる可能性や注意点）
  - 適用手順（コマンドや差分例）
- 変更実装を求められたら、最小限の変更に留め、必要ならテスト/チェック（例: `shellcheck bin/*.sh`）を案内する。

### 4) Apply and PR

- 変更提案が採用されたら `dotfiles-pr-flow` を**呼び出して**PR作成フローに移譲する。
- PR手順の詳細はこのスキルで繰り返さず、`dotfiles-pr-flow` に従う。
- PR本文のSummaryに「Created via dotfiles-recommender skill」を1行追加する（AI disclosureは末尾）。
- 作業後は作成したworktreeの削除と `git worktree prune` を行う。

## Guidance

- 具体的な提案が難しい場合は、質問を返して前提を固める。
- ベストプラクティスの押し付けではなく、現状の意図を尊重した代替案として提示する。
- 不確実な提案には「仮説」や「要検証」を明記する。
