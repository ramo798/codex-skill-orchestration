# 運用Runbook（MVP 3スキル）

## 1. スキル一覧

1. `issue-refiner`
- 対象: `agent:codex` 付きOpen Issue（`agent:ready`は除外）
- 役割: 仕様化、質問、依存整理、ready判定
- 追加質問が必要な時のみ `agent:refine`

2. `ready-worker`
- 対象: `agent:codex` + `agent:ready` のOpen Issue
- 役割: 実装、`typecheck/biome/test`、通常PR作成
- 結果: Issueに `agent:pr-open`、PRに `agent:needs-review`

3. `pr-gatekeeper`
- 対象: `agent:codex-pr` のOpen PR（Draft除外）
- 役割: CI確認、リスク判定、QAラベル付与
- 結果: `agent:qa-passed` または `agent:qa-failed`

## 2. ガード（厳守）

- 1実行1Issue / 1実行1PR
- ロック競合検知時は即停止（リトライしない）
- `agent:in-progress` / `agent:gate-lock` は見える化用であり、排他の正本は Git ref lock とする
- Issue系スキルは `refs/heads/agent-lock/issues/<issue番号>` を共有し、PR系スキルは `refs/heads/agent-lock/prs/<PR番号>` を使う
- lock ref を取れない時は権限不足を含めて停止し、ラベルだけで続行しない
- ready以外は実装しない
- 高リスクPRは自動マージしない

## 3. ラベル仕様（agent接頭辞統一）

### Issue用

- `agent:codex`: 自動処理対象
- `agent:refine`: 要件の追加回答待ち
- `agent:blocked`: 依存待ち
- `agent:ready`: 実装可能
- `agent:in-progress`: 実行ロック中
- `agent:pr-open`: 対応PR作成済み
- `agent:failed`: 実行失敗

### PR用

- `agent:codex-pr`: Codex生成PR
- `agent:needs-review`: 人レビュー待ち
- `agent:gate-lock`: Gatekeeperロック中
- `agent:qa-passed`: QAゲート通過
- `agent:qa-failed`: QAゲート失敗
- `agent:human-gate`: 人判断必須（自動マージ禁止）

## 4. 状態遷移

1. 新規Issue作成
- 最低ラベル: `agent:codex`

2. Issue精錬
- 情報不足: `agent:refine`
- 依存待ち: `agent:blocked`
- 実装可: `agent:ready`

3. 実装
- 開始: lock ref 取得 + `agent:in-progress`
- PR作成後: Issue `agent:pr-open` / PR `agent:needs-review` + `agent:codex-pr`

4. PRゲート
- 失敗: `agent:qa-failed`
- 通過: `agent:qa-passed`

## 5. 失敗時の運用

1. `agent:failed`（Issue）
- 実装スキルが停止した時に付与
- コメントに停止理由と次アクションを1行で残す

2. `agent:qa-failed`（PR）
- CIチェック失敗、またはゲート条件未達
- CIチェックが0件（`no checks reported`）の場合は失敗扱いにしない
- コメントに不足条件（例: `required check failed`）を明記

## 6. 直近の反映事項

- Issueテンプレは `agent:codex` 単独付与に変更済み
- `ready-worker` は Draft PR ではなく通常PR作成へ変更済み
- QAラベルは `agent:qa-passed / agent:qa-failed` に統一済み
- 排他制御はラベル依存から Git ref lock 依存へ変更済み
