#!/bin/sh
mkdir -p .claude/skills/maw-execute-task/agents .claude/skills/maw-tasks

REPO="https://raw.githubusercontent.com/pockerhead/maw/main"

curl -fsSL "$REPO/skills/maw-execute-task/SKILL.md" -o .claude/skills/maw-execute-task/SKILL.md
curl -fsSL "$REPO/skills/maw-tasks/SKILL.md" -o .claude/skills/maw-tasks/SKILL.md

for agent in clarifier planner plan-reviewer-1 plan-reviewer-2 implementer code-reviewer fixer qa; do
  curl -fsSL "$REPO/skills/maw-execute-task/agents/$agent.md" -o ".claude/skills/maw-execute-task/agents/$agent.md"
done

echo "Installed:"
echo "  .claude/skills/maw-execute-task/SKILL.md       (multi-agent pipeline)"
echo "  .claude/skills/maw-execute-task/agents/*.md     (8 agent prompts)"
echo "  .claude/skills/maw-tasks/SKILL.md               (task creator)"
