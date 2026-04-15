#!/bin/sh
mkdir -p .claude/skills/maw .claude/skills/tasks

REPO="https://raw.githubusercontent.com/pockerhead/maw/main"

curl -fsSL "$REPO/skills/maw/SKILL.md" -o .claude/skills/maw/SKILL.md
curl -fsSL "$REPO/skills/tasks/SKILL.md" -o .claude/skills/tasks/SKILL.md

echo "Installed:"
echo "  .claude/skills/maw/SKILL.md    (multi-agent pipeline)"
echo "  .claude/skills/tasks/SKILL.md  (task creator)"
