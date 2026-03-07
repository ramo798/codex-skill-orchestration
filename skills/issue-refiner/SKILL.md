---
name: issue-refiner
description: GitHub Issueを実装前のready状態に整えるスキル。曖昧なIssueを仕様化し、依存関係とリスクを整理してラベルを更新したい時に使う。入口は `agent:codex` のみで、追加回答が必要な時だけ `agent:refine` を付与し、ready時には外す。1実行1Issueを厳守する。
---

# Issue Refiner

GitHub Issueを実装可能な状態へ精錬する。`gh` コマンドで操作し、1回の実行で1Issueだけ扱う。

## 固定ガード

- `gh` 以外の手段でIssueを書き換えない。
- 対象は `agent:codex` が付いたOpen Issueに限定する。
- `agent:ready` が付いたIssueは対象外とする。
- `agent:refine` が付いたIssueは、前回質問以降にユーザーの新規回答がある場合のみ再処理する。
- 1実行で処理するIssueは必ず1件に固定する。候補が複数あっても先頭1件以外には触れない。
- `agent:in-progress` は見える化専用であり、排他の根拠にしない。排他の正本は `refs/heads/agent-lock/issues/<issue番号>` の Git ref とする。
- `issue-refiner` と `ready-worker` は同じIssue lock refを共有し、同一Issueを同時に触れないようにする。
- lock ref を作れない場合、または取得後の再確認で競合を検知した場合は即停止する。ラベルだけで続行してはならない。
- lock ref 取得後も、Issueへ書き込む直前ごとに lock ref と他者更新の有無を再確認する。再試行しない。
- 未解決質問が1件でもある場合は `agent:ready` を絶対に付けない。

## ラベル規約

- `agent:codex`: 自動処理対象
- `agent:refine`: 追加回答待ち（ユーザー返答が必要）
- `agent:blocked`: 依存待ち
- `agent:ready`: 実装可能
- `agent:in-progress`: ロック中

## ワークフロー

1. 実行ユーザーを特定する。

```bash
ME="$(gh api user --jq .login)"
OWNER_REPO="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
BASE_SHA="$(gh api "repos/$OWNER_REPO/git/ref/heads/$DEFAULT_BRANCH" --jq .object.sha)"
```

2. 候補Issueを取得し、`agent:ready` / `agent:in-progress` が付いていないものを、更新時刻が古い順で先頭1件だけ選ぶ。

```bash
ISSUE_NUMBER="$(gh issue list \
  --state open \
  --label agent:codex \
  --limit 50 \
  --json number,updatedAt,labels \
  --jq 'map(select((.labels | map(.name) | index("agent:ready")) | not)) | map(select((.labels | map(.name) | index("agent:in-progress")) | not)) | sort_by(.updatedAt) | .[0].number // empty')"
```

3. `ISSUE_NUMBER` が空なら何もしないで終了する。
4. 候補一覧は参考情報として扱い、対象Issueを再取得してロック前チェックを行う。`agent:in-progress` または他assignee検知時は即停止する。
5. Issue共通 lock ref を組み立てる。

```bash
LOCK_REF="refs/heads/agent-lock/issues/$ISSUE_NUMBER"
LOCK_API_PATH="${LOCK_REF#refs/}"
LOCKED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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

8. 直後に再取得してロック状態を再確認する。最低でも次をすべて満たさない限り停止する。
- `gh api "repos/$OWNER_REPO/git/ref/$LOCK_API_PATH"` が成功する
- `agent:in-progress` が付いている
- assignee に `ME` 以外がいない
- `LOCKED_AT` 以降に他者の新規コメントが無い
9. Issue本文とコメントから以下を整理し、コメントで仕様ブロックを提示する。
- Acceptance Criteria（Given/When/Thenで3〜7件）
- Out of Scope
- Test Plan（正常系/異常系/境界）
- Risk / Rollback
- `depends on` / `blocks` の明示
10. `gh issue comment` または `gh issue edit` を打つ直前ごとに、手順8の再確認を必ずやり直す。1つでも崩れていたら追記せず停止する。
11. `agent:refine` が既に付いていて、前回質問以降にユーザー回答が無い場合は追記せず停止する。
12. 追加質問が必要なら最大3件だけ投げ、`agent:refine` を付与して停止する。
13. 依存が未解決なら `agent:blocked` を付与し、`agent:ready` を付けない。
14. ready条件を満たす時のみ `agent:ready` を付与し、`agent:refine` `agent:blocked` を外す。
15. 終了時にロックを解除する。見える化ラベルの解除に失敗しても lock ref の削除は必ず試みる。

```bash
gh issue edit "$ISSUE_NUMBER" --remove-label agent:in-progress --remove-assignee "$ME"
gh api -X DELETE "repos/$OWNER_REPO/git/refs/$LOCK_API_PATH"
```

## ready判定

次をすべて満たす時だけ ready と判定する。

- 合意済みAcceptance Criteriaがある
- 未解決質問が0件
- 依存Issueがすべてclose済み
- テスト観点が明記されている

## 失敗時の扱い

- ロック競合: 即停止し、作業を進めない。
- lock ref 作成失敗: 競合または権限不足として停止し、ラベルだけで続行しない。
- APIエラー: 可能ならロック解除を試みて停止する。
- 判断不能: 推測で進めず `agent:refine` を付けて停止する。
