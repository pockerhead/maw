#!/bin/sh
mkdir -p .claude/skills/maw-execute-task .claude/skills/maw-tasks .claude/skills/maw-context .claude/agents

REPO="https://raw.githubusercontent.com/pockerhead/maw/main"

curl -fsSL "$REPO/skills/maw-execute-task/SKILL.md" -o .claude/skills/maw-execute-task/SKILL.md
curl -fsSL "$REPO/skills/maw-tasks/SKILL.md" -o .claude/skills/maw-tasks/SKILL.md
curl -fsSL "$REPO/skills/maw-context/SKILL.md" -o .claude/skills/maw-context/SKILL.md

# Generate one named subagent per (agent, effort) pair into .claude/agents/.
# Files are flat (no subdirectory) and prefixed maw- so Claude Code's top-level
# agent discovery finds them without relying on recursive subdirectory scanning.
# Real effort lives in the subagent frontmatter (Claude Code applies it for real,
# not as a prose directive). The orchestrator selects the variant by name at spawn
# time: maw-<stem>-<effort>. Bodies are static role prompts; the orchestrator
# injects all dynamic context (paths, artifacts, PCTX overlay) in the spawn prompt.
EFFORTS="low medium high xhigh max"
AGENTS="clarifier premise-challenge planner plan-reviewer-1 plan-reviewer-2 implementer code-reviewer fixer qa"

for agent in $AGENTS; do
  body=$(curl -fsSL "$REPO/skills/maw-execute-task/agents/$agent.md") || {
    echo "failed to fetch body for $agent" >&2
    exit 1
  }
  for eff in $EFFORTS; do
    out=".claude/agents/maw-$agent-$eff.md"
    {
      printf -- '---\n'
      printf 'name: maw-%s-%s\n' "$agent" "$eff"
      printf 'description: Private to the MAW pipeline (effort=%s). Invoked only by the maw-execute-task orchestrator via subagent_type. Do not invoke directly.\n' "$eff"
      printf 'effort: %s\n' "$eff"
      printf -- '---\n\n'
      printf '%s\n' "$body"
    } > "$out"
  done
done

agent_count=$(printf '%s\n' $AGENTS | wc -l | tr -d ' ')
effort_count=$(printf '%s\n' $EFFORTS | wc -l | tr -d ' ')
total=$((agent_count * effort_count))

echo "Installed:"
echo "  .claude/skills/maw-execute-task/SKILL.md       (multi-agent pipeline orchestrator)"
echo "  .claude/skills/maw-tasks/SKILL.md               (task creator)"
echo "  .claude/skills/maw-context/SKILL.md             (project-context overlay author)"
echo "  .claude/agents/maw-*.md                          ($total subagents: $agent_count agents x $effort_count effort levels)"
echo ""
echo "Note: xhigh and max effort require an Opus model. Sonnet/Haiku variants at"
echo "those levels will error at spawn — the orchestrator clamps for this."
