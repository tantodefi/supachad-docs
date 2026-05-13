#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026
# SPDX-License-Identifier: Apache-2.0
#
# sync-from-nemoclaw.sh — Pulls selected source files from the parent
# tantodefi/NemoClaw repo (chad-dev branch) into the docs/ tree, with
# an explicit allowlist of what's safe to publish.
#
# Run when source has moved meaningfully — chad-readme.md, the
# operations docs, the design notes. Does NOT replace hand-authored
# pages (intro.md, architecture.md, changelog.md) — those stay
# operator-authored to keep the public voice consistent.
#
# Usage:
#   ./scripts/sync-from-nemoclaw.sh [--ref <branch-or-sha>] [--source <path>]
#
# Defaults: ref=chad-dev, source=$NEMO_SOURCE or ../source

set -euo pipefail

ref="chad-dev"
source_path="${NEMO_SOURCE:-$(cd "$(dirname "$0")/../.." && pwd)/source}"
work=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)    ref="$2"; shift 2 ;;
    --source) source_path="$2"; shift 2 ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# If no local source dir, fall back to a fresh clone of the public repo
if [ ! -d "$source_path" ]; then
  work="$(mktemp -d -t nemoclaw-sync-XXXXXX)"
  trap 'rm -rf "$work"' EXIT
  echo "==> cloning tantodefi/NemoClaw#${ref} → $work"
  git clone --depth 1 --branch "$ref" \
    https://github.com/tantodefi/NemoClaw.git "$work"
  source_path="$work"
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
docs="${repo_root}/docs"

# Allowlist: source-relative path → docs-relative target
# Hand-authored docs (intro.md, architecture.md, etc.) are NOT in this
# list; they live entirely under operator authorship.
declare -a syncs=(
  "chad-readme.md:_source/chad-readme.md"
  "docs/design/spawn-as-github-run.md:_source/spawn-design.md"
  "docs/operations/chad-devflow.md:_source/devflow.md"
  "docs/operations/chad-autonomy.md:_source/autonomy-internal.md"
  "docs/operations/chad-workflows.md:_source/workflows.md"
  "docs/operations/gbrain.md:_source/gbrain-ops.md"
  ".github/skills/chad-orchestrator/SKILL.md:_source/orchestrator-skill.md"
)

mkdir -p "${docs}/_source"
copied=0; missing=0
for entry in "${syncs[@]}"; do
  src_rel="${entry%%:*}"
  dst_rel="${entry#*:}"
  src="${source_path}/${src_rel}"
  dst="${docs}/${dst_rel}"
  if [ ! -f "$src" ]; then
    echo "  missing: $src_rel"
    missing=$((missing + 1))
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  copied=$((copied + 1))
  echo "  synced: $src_rel → ${dst_rel}"
done

# Header injected at the top of each synced doc so readers know the
# canonical home and how stale the copy might be
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for entry in "${syncs[@]}"; do
  dst_rel="${entry#*:}"
  dst="${docs}/${dst_rel}"
  [ -f "$dst" ] || continue
  src_rel="${entry%%:*}"
  tmp="$(mktemp)"
  {
    echo "<!-- AUTO-SYNCED FROM tantodefi/NemoClaw — DO NOT EDIT HERE -->"
    echo "<!-- source: ${src_rel} · ref: ${ref} · synced: ${ts} -->"
    echo
    cat "$dst"
  } > "$tmp"
  mv "$tmp" "$dst"
done

echo "==> ${copied} synced, ${missing} missing"
echo "==> hand-authored pages (intro/architecture/memory/orchestrator/substrates/autonomy/operations/changelog/reproducing) are NOT touched by sync"
