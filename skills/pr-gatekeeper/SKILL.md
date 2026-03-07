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
- `agent:gate-lock` は見える化専用であり、排他の正本にしない。排他の正本は `refs/heads/agent-lock/prs/<PR番号>` の Git ref とする。
- lock ref を作れない場合、または取得後に競合が見えた場合は即停止する。ラベルだけで続行しない。
- `agent:human-gate` があるPRは自動マージしない。
- 高リスク変更は自動マージしない。
- CIチェックが0件の場合は成功扱いで継続する（`no checks reported` は失敗扱いにしない）。

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

1. 実行対象のrepo情報を取得する。

```bash
OWNER_REPO="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
BASE_SHA="$(gh api "repos/$OWNER_REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha)"
```

2. 対象PRを1件だけ選ぶ（Draftは除外）。

```bash
PR_NUMBER="$(gh pr list \
  --state open \
  --label agent:codex-pr \
  --limit 50 \
  --json number,updatedAt,isDraft \
  --jq 'map(select(.isDraft == false)) | sort_by(.updatedAt) | .[0].number // empty')"
```

3. PRが無ければ終了する（対象が全てDraftの場合も含む）。
4. 候補一覧は参考情報として扱い、対象PRを再取得して `agent:gate-lock` の有無を確認する。既に付いていたら競合として即停止する。
5. PR共通 lock ref を組み立てる。

```bash
LOCK_REF="refs/heads/agent-lock/prs/$PR_NUMBER"
LOCK_API_PATH="${LOCK_REF#refs/}"
```

6. まず lock ref を原子的に作成してロックを取る。`Reference already exists` は競合として扱い即停止する。

```bash
gh api -X POST "repos/$OWNER_REPO/git/refs" \
  -f ref="$LOCK_REF" \
  -f sha="$BASE_SHA"
```

7. lock ref を取れた時だけ、見える化のために `agent:gate-lock` を付ける。ここが失敗した場合は lock ref を削除して停止する。

```bash
gh pr edit "$PR_NUMBER" --add-label agent:gate-lock
```

8. 再取得でロック状態を検証する。最低でも次を満たさない限り停止する。
- `gh api "repos/$OWNER_REPO/git/ref/$LOCK_API_PATH"` が成功する
- `agent:gate-lock` が付いている
9. CI結果を確認する。
- 失敗チェックがある場合は `agent:qa-failed` を付けて停止する。
- チェックが0件（`no checks reported`）の場合は成功扱いで継続する。

```bash
gh pr checks "$PR_NUMBER"
```

10. PRへコメントまたはラベル更新を行う直前には、手順8のロック再確認を必ずやり直す。
11. 差分リスクを確認する。

```bash
gh pr view "$PR_NUMBER" --json additions,deletions,files,labels
```

12. 高リスクまたは `agent:human-gate` がある場合は、レビュー依頼コメントを付けて停止する。
13. 低リスクでCI成功なら `agent:qa-passed` を付ける。
14. 自動マージ条件を満たす場合のみマージする。
- 必須レビュー要件を満たす
- CI成功
- 高リスクに非該当
- `agent:human-gate` が無い

```bash
gh pr merge "$PR_NUMBER" --squash --auto
```

15. 終了時にロックラベルを外す。ラベル解除に失敗しても lock ref の削除は必ず試みる。

```bash
gh pr edit "$PR_NUMBER" --remove-label agent:gate-lock
gh api -X DELETE "repos/$OWNER_REPO/git/refs/$LOCK_API_PATH"
```

## 停止条件

- ロック競合
- CI失敗
- 高リスク変更
- 人レビュー必須フラグ

停止時は理由をPRコメントに残し、次アクションを1行で示す。
