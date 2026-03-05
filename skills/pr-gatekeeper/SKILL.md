---
name: pr-gatekeeper
description: Bot作成PRを1件だけ品質ゲートに通し、条件一致時のみマージするスキル。`agent:codex-pr` ラベル付きOpen PRを対象にし、競合ロック時は即停止する。複数PRを同時処理せず、1実行1PRを厳守する。
---

# PR Gatekeeper

自動生成PRの品質とリスクを判定し、安全なものだけ次段へ進める。

## 固定ガード

- 対象は `agent:codex-pr` ラベル付きOpen PRだけ。
- Draft PRは対象外とする（Ready for review 後に判定する）。
- 1実行1PRを厳守する。候補が複数でも先頭1件だけ扱う。
- ロックラベル `agent:gate-lock` があるPRは競合とみなし即停止する。
- `agent:human-gate` があるPRは自動マージしない。
- 高リスク変更は自動マージしない。

## 高リスク判定

次に1つでも該当したら高リスクとみなす。

- 認証・認可関連（`auth`, `session`, `permission` を含むパス）
- 課金・決済関連（`billing`, `payment` を含むパス）
- DBスキーマ変更（`schema.ts`, `drizzle/*.sql`）
- 変更量が大きい（追加+削除が 500 行超）

## 判定ラベル

- `agent:qa-passed`: QAゲート通過
- `agent:qa-failed`: QAゲート失敗

## ワークフロー

1. 対象PRを1件だけ選ぶ（Draftは除外）。

```bash
PR_NUMBER="$(gh pr list \
  --state open \
  --label agent:codex-pr \
  --limit 50 \
  --json number,updatedAt,isDraft \
  --jq 'map(select(.isDraft == false)) | sort_by(.updatedAt) | .[0].number // empty')"
```

2. PRが無ければ終了する（対象が全てDraftの場合も含む）。
3. `agent:gate-lock` が付いていたら競合として即停止する。
4. ロックを付ける。

```bash
gh pr edit "$PR_NUMBER" --add-label agent:gate-lock
```

5. CI結果を確認する。失敗があれば `agent:qa-failed` を付けて停止する。

```bash
gh pr checks "$PR_NUMBER"
```

6. 差分リスクを確認する。

```bash
gh pr view "$PR_NUMBER" --json additions,deletions,files,labels
```

7. 高リスクまたは `agent:human-gate` がある場合は、レビュー依頼コメントを付けて停止する。
8. 低リスクでCI成功なら `agent:qa-passed` を付ける。
9. 自動マージ条件を満たす場合のみマージする。
- 必須レビュー要件を満たす
- CI成功
- 高リスクに非該当
- `agent:human-gate` が無い

```bash
gh pr merge "$PR_NUMBER" --squash --auto
```

10. 終了時にロックラベルを外す。

```bash
gh pr edit "$PR_NUMBER" --remove-label agent:gate-lock
```

## 停止条件

- ロック競合
- CI失敗
- 高リスク変更
- 人レビュー必須フラグ

停止時は理由をPRコメントに残し、次アクションを1行で示す。
