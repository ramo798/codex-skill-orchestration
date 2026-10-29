#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/skills"
DST_DIR="${HOME}/.codex/skills"

SKILLS=(
  "issue-refiner"
  "ready-worker"
  "pr-gatekeeper"
)

mkdir -p "$DST_DIR"

for skill in "${SKILLS[@]}"; do
  if [[ ! -d "$SRC_DIR/$skill" ]]; then
    echo "[WARN] missing skill: $SRC_DIR/$skill" >&2
    continue
  fi

  mkdir -p "$DST_DIR/$skill"
  # Trailing slashes copy the directory *contents*; --delete then mirrors the
  # source exactly, removing files under the destination that no longer exist here.
  rsync -a --delete "$SRC_DIR/$skill/" "$DST_DIR/$skill/"
  echo "[OK] synced: $skill"
done

echo "Done: skills synced to $DST_DIR"
