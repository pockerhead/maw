#!/bin/sh
# MAW installer. Targets:
#   --claude   install the Claude Code surface (.claude/)
#   --codex    install the Codex CLI surface (.agents/)
#   --all      both
#   (no flag)  detect installed harnesses and install for all detected;
#              if none detected, fall back to the Claude layout (legacy behavior).
set -e

REPO="https://raw.githubusercontent.com/pockerhead/maw/main"
SKILLS="maw-execute-task maw-tasks maw-context"
AGENTS="clarifier premise-challenge planner plan-reviewer-1 plan-reviewer-2 implementer code-reviewer fixer qa"
EFFORTS="low medium high xhigh max"

INSTALL_CLAUDE=0
INSTALL_CODEX=0
case "$1" in
  --claude) INSTALL_CLAUDE=1 ;;
  --codex)  INSTALL_CODEX=1 ;;
  --all)    INSTALL_CLAUDE=1; INSTALL_CODEX=1 ;;
  "")
    command -v claude >/dev/null 2>&1 && INSTALL_CLAUDE=1
    command -v codex  >/dev/null 2>&1 && INSTALL_CODEX=1
    if [ $INSTALL_CLAUDE -eq 0 ] && [ $INSTALL_CODEX -eq 0 ]; then
      echo "No harness binary detected; defaulting to the Claude Code layout."
      INSTALL_CLAUDE=1
    fi
    ;;
  *) echo "Unknown flag: $1 (use --claude | --codex | --all)" >&2; exit 1 ;;
esac

# Download everything first (atomic-ish: no partial surface on a failed fetch).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for s in $SKILLS; do
  curl -fsSL "$REPO/skills/$s/SKILL.md" -o "$TMP/$s.SKILL.md"
done
for a in $AGENTS; do
  curl -fsSL "$REPO/skills/maw-execute-task/agents/$a.md" -o "$TMP/agent-$a.md"
done

install_surface() {
  # $1 = surface root for skills (.claude/skills or .agents/skills)
  root="$1"
  mkdir -p "$root/maw-execute-task/agents" "$root/maw-tasks" "$root/maw-context"
  for s in $SKILLS; do
    cp "$TMP/$s.SKILL.md" "$root/$s/SKILL.md"
  done
  # Raw agent bodies ship with the orchestrator skill: the external runner
  # (cross-provider spawns, Codex hosting) reads them relative to SKILL.md.
  for a in $AGENTS; do
    cp "$TMP/agent-$a.md" "$root/maw-execute-task/agents/$a.md"
  done
}

if [ $INSTALL_CLAUDE -eq 1 ]; then
  # Claude-native path additionally needs named subagent variants: real effort
  # lives in the frontmatter (Claude Code applies it for real, not as prose).
  # The orchestrator selects the variant by name at spawn: maw-<stem>-<effort>.
  # Generate everything in the staging dir first, install with one copy pass —
  # a failure mid-generation leaves the target directories untouched.
  mkdir -p "$TMP/claude-agents"
  for agent in $AGENTS; do
    for eff in $EFFORTS; do
      out="$TMP/claude-agents/maw-$agent-$eff.md"
      {
        printf -- '---\n'
        printf 'name: maw-%s-%s\n' "$agent" "$eff"
        printf 'description: Private to the MAW pipeline (effort=%s). Invoked only by the maw-execute-task orchestrator via subagent_type. Do not invoke directly.\n' "$eff"
        printf 'effort: %s\n' "$eff"
        printf -- '---\n\n'
        cat "$TMP/agent-$agent.md"
      } > "$out"
    done
  done
  install_surface ".claude/skills"
  mkdir -p .claude/agents
  rm -f .claude/agents/maw-*.md   # drop stale variants from removed/renamed stems
  cp "$TMP/claude-agents/"*.md .claude/agents/
fi

if [ $INSTALL_CODEX -eq 1 ]; then
  install_surface ".agents/skills"
fi

agent_count=$(printf '%s\n' $AGENTS | wc -l | tr -d ' ')
effort_count=$(printf '%s\n' $EFFORTS | wc -l | tr -d ' ')
total=$((agent_count * effort_count))

echo "Installed:"
if [ $INSTALL_CLAUDE -eq 1 ]; then
  echo "  .claude/skills/{maw-execute-task,maw-tasks,maw-context}/SKILL.md"
  echo "  .claude/skills/maw-execute-task/agents/*.md     ($agent_count raw agent bodies)"
  echo "  .claude/agents/maw-*.md                         ($total subagents: $agent_count agents x $effort_count effort levels)"
fi
if [ $INSTALL_CODEX -eq 1 ]; then
  echo "  .agents/skills/{maw-execute-task,maw-tasks,maw-context}/SKILL.md"
  echo "  .agents/skills/maw-execute-task/agents/*.md     ($agent_count raw agent bodies)"
fi
echo ""
echo "Note: model/effort validity is clamped per provider by the orchestrator's"
echo "capability catalog (e.g. claude haiku caps at high; codex gpt-5.5 caps at"
echo "xhigh). Invalid pairs stop with a report - nothing silently downgrades."
if [ $INSTALL_CLAUDE -eq 1 ]; then
  echo ""
  echo "Restart Claude Code (fresh session) so the named subagents are discovered."
fi
if [ $INSTALL_CODEX -eq 1 ]; then
  echo "Restart Codex so the repository skills are discovered."
fi
