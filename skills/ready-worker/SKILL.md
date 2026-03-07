---
name: ready-worker
description: agent:ready なGitHub Issueを1件だけ実装してPRを作るスキル。agent:codex と agent:ready の両ラベルIssueを対象にし、ロック競合時は即停止する。複数Issueを同時処理せず、1実行1Issueを厳守する。
---

# Ready Worker

ready化済みIssueを安全に実装し、PR作成まで進める。`gh` とローカルgit操作を使う。

## 固定ガード

- 対象は `agent:codex` かつ `agent:ready` のOpen Issueのみ。
- 1実行1Issueを厳守する。候補が複数あっても先頭1件以外は絶対に触らない。
- `agent:in-progress` は見える化専用であり、排他の正本にしない。排他の正本は `refs/heads/agent-lock/issues/<issue番号>` の Git ref とする。
- `issue-refiner` と `ready-worker` は同じIssue lock refを共有し、同一Issueを同時に触れないようにする。
- lock ref を作れない場合、または取得後に競合が見えた場合は即停止する。ラベルだけで続行しない。
- 実装範囲は対象IssueのAcceptance Criteriaに一致する範囲だけ。
- `ready` でないIssueは触らない。
- PRは通常PRで作成する（`--draft` は使わない）。

## ラベル規約

- `agent:codex`: 自動処理対象
- `agent:ready`: 実装可能
- `agent:in-progress`: ロック中
- `agent:pr-open`: Issueに対応するPR作成済み
- `agent:needs-review`: PRレビュー待ち（PR側ラベル）
- `agent:failed`: 実装失敗

## ワークフロー

1. 実行ユーザーを取得する。

```bash
ME="$(gh api user --jq .login)"
OWNER_REPO="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
BASE_SHA="$(gh api "repos/$OWNER_REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha)"
```

2. 対象Issueを1件だけ選ぶ。

```bash
ISSUE_NUMBER="$(gh issue list \
  --state open \
  --label agent:codex \
  --label agent:ready \
  --limit 50 \
  --json number,updatedAt \
  --jq 'sort_by(.updatedAt) | .[0].number // empty')"
```

3. Issueが無ければ終了する。
4. 候補一覧は参考情報として扱い、対象Issueを再取得してロック前チェックを行う。`agent:in-progress` または他assignee検知時は即停止する。
5. Issue共通 lock ref を組み立てる。

```bash
LOCK_REF="refs/heads/agent-lock/issues/$ISSUE_NUMBER"
LOCK_API_PATH="${LOCK_REF#refs/}"
```

6. まず lock ref を原子的に作成してロックを取る。`Reference already exists` は競合として扱い即停止する。

```bash
gh api -X POST "repos/$OWNER_REPO/git/refs" \
  -f ref="$LOCK_REF" \
  -f sha="$BASE_SHA"
```

7. lock ref を取れた時だけ、見える化のために `agent:in-progress` と assignee を付ける。ここが失敗した場合は lock ref を削除して停止する。

```bash
gh issue edit "$ISSUE_NUMBER" --add-label agent:in-progress --add-assignee "$ME"
```

8. 再取得でロック状態を検証する。最低でも次を満たさない限り停止する。
- `gh api "repos/$OWNER_REPO/git/ref/$LOCK_API_PATH"` が成功する
- `agent:in-progress` が付いている
- assignee に `ME` 以外がいない
9. Issueタイトルからブランチを作る。

```bash
TITLE="$(gh issue view "$ISSUE_NUMBER" --json title --jq .title)"
SLUG="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g;s/^-//;s/-$//' | cut -c1-40)"
BRANCH="codex/issue-${ISSUE_NUMBER}-${SLUG}"
git checkout -b "$BRANCH"
```

10. 実装し、必須チェックを実行する。

```bash
npm run typecheck
npm run biome
npm run test
```

11. 変更をコミットし、通常PRを作る。
- PR本文は日本語で詳細に記載する。
- `何を変えたか` `なぜ必要か` `テスト結果` `未対応事項` を明記する。

```bash
git add -A
git commit -m "feat: implement #${ISSUE_NUMBER}"
git push -u origin "$BRANCH"
gh pr create --fill --base main --head "$BRANCH"
```

12. Issueにコメントやラベル更新を行う直前には、手順8のロック再確認を必ずやり直す。
13. IssueにPRリンクをコメントし、Issueには `agent:pr-open` を付与する。PRには `agent:needs-review` を付与する。
14. 成否にかかわらず最後にロック解除を試みる。見える化ラベルの解除に失敗しても lock ref の削除は必ず試みる。

```bash
gh issue edit "$ISSUE_NUMBER" --remove-label agent:in-progress --remove-assignee "$ME"
gh api -X DELETE "repos/$OWNER_REPO/git/refs/$LOCK_API_PATH"
```

## 停止条件

- ロック競合を検知した時
- テスト失敗時
- 仕様が不足して実装判断ができない時
- CIや権限不足でPR作成ができない時

停止時は理由をIssueコメントに残し、`agent:failed` または適切な補助ラベルを付ける。
