# AGENTS.md

このリポジトリは、Codex Skills と Automations の運用を管理するためのリポジトリです。

## 目的

- スキル定義（`SKILL.md`, `agents/openai.yaml`）をGitで一元管理する
- 自動開発フロー（Issue精錬 -> 実装 -> PRゲート）の運用ルールを文書化する
- Automationの実行時刻と運用手順を再現可能な形で保持する

## 管理対象

- `skills/`: 各スキルの正本
- `docs/`: Runbook、ラベル設計、Automation時刻などの運用ドキュメント
- `scripts/`: `~/.codex/skills` への同期スクリプト

## 基本運用ルール

1. スキル変更は必ずこのリポジトリの `skills/` で行う  
2. 変更後は `scripts/sync-skills-to-codex.sh` で `~/.codex/skills` へ同期する  
3. ラベル仕様・実行順・停止条件を変える場合は `docs/` も同時に更新する  
4. 仕様が曖昧なまま自動化しない（ガード条件を先に明文化する）

## スキル変更時の必須ルール

- `skills/` 配下を変更した場合、作業完了前に必ず `./scripts/sync-skills-to-codex.sh` を実行する
- 同期後は反映確認コマンドで対象スキルが `~/.codex/skills` に存在することを確認する
- 同期未実施の状態でPRをマージしない

## PR Gatekeeper のCI判定ルール

- `gh pr checks` 実行時にチェックが1件も存在しない場合（例: `no checks reported`）は、CI成功として扱って処理を継続する
- チェックが存在して失敗している場合のみ `agent:qa-failed` を付与する

## 同期手順

```bash
./scripts/sync-skills-to-codex.sh
```

必要に応じて反映を確認する。

```bash
find ~/.codex/skills -maxdepth 2 -type f | rg 'issue-refiner|ready-worker|pr-gatekeeper'
```

## PR作成ルール

- PR本文は日本語で、詳細に記載する
- 最低限、次の項目を含める
  - 背景 / 目的
  - 変更内容
  - 影響範囲
  - テスト結果
  - 未対応事項（あれば）

## ドキュメント記述ルール

- ドキュメントは通常の日本語で記載する
- 略語を使う場合は初出で意味を明記する
- 運用判断に関わる箇所は、条件と例外を明確に書く

## 参照ドキュメント

- `README.md`
- `docs/operations-runbook.md`
- `docs/automation-schedule-jst.md`
