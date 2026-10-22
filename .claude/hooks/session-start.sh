#!/bin/bash
# Runs at every Claude Code session start. Claude Code already loads
# CLAUDE.md (which imports AGENTS.md) on its own, so this only adds the live state from
# SCRATCHPAD.md: the part of the project that changes between sessions.

if [ ! -f "AGENTS.md" ]; then
  echo "=== AGENTS.md not found. Fill it in to get started (see README.md) ==="
  exit 0
fi

if [ -f "SCRATCHPAD.md" ]; then
  echo "=== CURRENT STATE (from SCRATCHPAD.md) ==="
  awk 'tolower($0) ~ /^## current state/ {on=1} on && /^---/ {exit} on {print}' SCRATCHPAD.md
  echo "=== END CURRENT STATE ==="
fi
