#!/bin/sh
mkdir -p .claude/skills/maw-execute-task/agents .claude/skills/maw-tasks .claude/skills/maw-context

REPO="https://raw.githubusercontent.com/pockerhead/maw/main"

curl -fsSL "$REPO/skills/maw-execute-task/SKILL.md" -o .claude/skills/maw-execute-task/SKILL.md
curl -fsSL "$REPO/skills/maw-tasks/SKILL.md" -o .claude/skills/maw-tasks/SKILL.md
curl -fsSL "$REPO/skills/maw-context/SKILL.md" -o .claude/skills/maw-context/SKILL.md

for agent in clarifier premise-challenge planner plan-reviewer-1 plan-reviewer-2 implementer code-reviewer fixer qa; do
  curl -fsSL "$REPO/skills/maw-execute-task/agents/$agent.md" -o ".claude/skills/maw-execute-task/agents/$agent.md"
done

echo "Installed:"
echo "  .claude/skills/maw-execute-task/SKILL.md       (multi-agent pipeline)"
echo "  .claude/skills/maw-execute-task/agents/*.md     (9 agent prompts)"
echo "  .claude/skills/maw-tasks/SKILL.md               (task creator)"
echo "  .claude/skills/maw-context/SKILL.md             (project-context overlay author)"
