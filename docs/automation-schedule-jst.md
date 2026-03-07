# Automation設定（JST）

## 推奨スケジュール（MVP）

1. 平日 08:30
- Automation: `issue-refiner`
- 目的: 新規/滞留Issueをready判定可能な状態へ引き上げる

2. 4時間ごと（00:40, 04:40, 08:40, 12:40, 16:40, 20:40）
- Automation: `ready-worker`
- 目的: `agent:ready` のIssueを1件ずつ実装してPR作成

3. 4時間ごと（00:50, 04:50, 08:50, 12:50, 16:50, 20:50）
- Automation: `pr-gatekeeper`
- 目的: `agent:codex-pr`（Draft除外）を1件ずつ判定

## ずらし実行の理由

- `ready-worker` の10分後に `pr-gatekeeper` を動かすことで、
  PR作成直後にゲート判定を取りこぼしにくくする。

## 実行順（必須）

1. `issue-refiner`
2. `ready-worker`
3. `pr-gatekeeper`

## 停止・保留条件

- ロック競合時: 即停止
- lock ref を取得できない時: 即停止
- `issue-refiner`: `agent:refine`（追加回答待ち）で保留
- `pr-gatekeeper`: `agent:qa-failed` で保留

## 将来拡張（必要になったら）

1. `stale-lock-reaper`（1時間ごと）
- 24時間無更新の lock ref と見える化ラベルを解除

2. `metrics-reporter`（週1）
- ready化率、PRリードタイム、QA失敗率を可視化
