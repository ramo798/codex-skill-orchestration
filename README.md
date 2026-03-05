# codex-skill-orchestration

Codex Skills + Automations の運用を管理するためのリポジトリです。

## 目的

- 自動開発フロー（Issue精錬 -> 実装 -> PRゲート）を再現可能な形で管理する
- スキル定義・ラベル設計・Automation時刻を1か所に集約する
- 変更履歴をGitで追跡する

## いまの最小構成（MVP）

- `issue-refiner`
- `ready-worker`
- `pr-gatekeeper`

## ディレクトリ構成

- `skills/`: スキル定義の正本（`SKILL.md`, `agents/openai.yaml`）
- `docs/`: 運用設計、ラベル設計、Automation時刻
- `scripts/`: `~/.codex/skills` への同期用スクリプト

## このリポでスキル管理できる？

可能です。運用は次の2段階にします。

1. このリポジトリ内 `skills/` を編集してGit管理する
2. `scripts/sync-skills-to-codex.sh` で `~/.codex/skills` へ反映する

> Codexが実際に読むのは `~/.codex/skills` 側なので、編集後の同期は必須です。

## 使い方

```bash
# 1) このリポのスキルを ~/.codex/skills に反映
./scripts/sync-skills-to-codex.sh

# 2) 反映されたファイル確認
find ~/.codex/skills -maxdepth 2 -type f | rg 'issue-refiner|ready-worker|pr-gatekeeper'
```

## 運用ドキュメント

- `docs/operations-runbook.md`
- `docs/automation-schedule-jst.md`
