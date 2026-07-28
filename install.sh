#!/bin/sh
# MAW installer. Targets:
#   --claude       install the Claude Code surface (.claude/)
#   --codex        install the Codex CLI surface (.agents/)
#   --all          both
#   (no target)    detect installed harnesses and install for all detected;
#                  if none detected, fall back to the Claude layout (legacy behavior).
# Options:
#   --with-reason  also install the experimental maw-reason deliberation surface
#                  (Claude only; opt-in because no live chain has run yet)
#   --with-hooks   also install and wire the maw-reason enforcement gate
#                  (implies --with-reason)
set -e

REPO="https://raw.githubusercontent.com/pockerhead/maw/main"
SKILLS="maw-execute-task maw-tasks maw-context"
AGENTS="clarifier premise-challenge planner plan-reviewer-1 plan-reviewer-2 implementer code-reviewer fixer qa"
# maw-reason is Claude-only in v1: its chain leans on `claude -p` external
# spawns whose flags and isolation are verified on that host.
REASON_SKILL="maw-reason"
REASON_AGENTS="coordinator premise-check generator compressor attacker synthesizer"
EFFORTS="low medium high xhigh max"

INSTALL_CLAUDE=0
INSTALL_CODEX=0
WITH_HOOKS=0
WITH_REASON=0
TARGET_GIVEN=0
for arg in "$@"; do
  case "$arg" in
    --claude)      INSTALL_CLAUDE=1; TARGET_GIVEN=1 ;;
    --codex)       INSTALL_CODEX=1;  TARGET_GIVEN=1 ;;
    --all)         INSTALL_CLAUDE=1; INSTALL_CODEX=1; TARGET_GIVEN=1 ;;
    --with-reason) WITH_REASON=1 ;;
    --with-hooks)  WITH_HOOKS=1; WITH_REASON=1 ;;
    *) echo "Unknown flag: $arg (use --claude | --codex | --all [--with-reason] [--with-hooks])" >&2; exit 1 ;;
  esac
done
if [ $TARGET_GIVEN -eq 0 ]; then
  command -v claude >/dev/null 2>&1 && INSTALL_CLAUDE=1
  command -v codex  >/dev/null 2>&1 && INSTALL_CODEX=1
  if [ $INSTALL_CLAUDE -eq 0 ] && [ $INSTALL_CODEX -eq 0 ]; then
    echo "No harness binary detected; defaulting to the Claude Code layout."
    INSTALL_CLAUDE=1
  fi
fi
if [ $WITH_REASON -eq 1 ] && [ $INSTALL_CLAUDE -eq 0 ]; then
  echo "--with-reason/--with-hooks apply to the Claude Code surface only; ignoring." >&2
  WITH_REASON=0
  WITH_HOOKS=0
fi

# Download everything first (atomic-ish: no partial surface on a failed fetch).
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for s in $SKILLS; do
  curl -fsSL "$REPO/skills/$s/SKILL.md" -o "$TMP/$s.SKILL.md"
done
for a in $AGENTS; do
  curl -fsSL "$REPO/skills/maw-execute-task/agents/$a.md" -o "$TMP/agent-$a.md"
done
if [ $WITH_REASON -eq 1 ]; then
  curl -fsSL "$REPO/skills/$REASON_SKILL/SKILL.md" -o "$TMP/$REASON_SKILL.SKILL.md"
  for a in $REASON_AGENTS; do
    curl -fsSL "$REPO/skills/$REASON_SKILL/agents/$a.md" -o "$TMP/reason-agent-$a.md"
  done
  [ $WITH_HOOKS -eq 1 ] && curl -fsSL "$REPO/hooks/maw-reason-gate.sh" -o "$TMP/maw-reason-gate.sh"
fi

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
  # Reason-chain roles: same variant mechanism, different owner skill.
  if [ $WITH_REASON -eq 1 ]; then
    for agent in $REASON_AGENTS; do
      for eff in $EFFORTS; do
        out="$TMP/claude-agents/maw-$agent-$eff.md"
        {
          printf -- '---\n'
          printf 'name: maw-%s-%s\n' "$agent" "$eff"
          printf 'description: Private to the MAW reason chain (effort=%s). Invoked only by the maw-reason skill and its coordinator. Do not invoke directly.\n' "$eff"
          printf 'effort: %s\n' "$eff"
          printf -- '---\n\n'
          cat "$TMP/reason-agent-$agent.md"
        } > "$out"
      done
    done
  fi
  install_surface ".claude/skills"
  rm -rf ".claude/skills/$REASON_SKILL"   # removed when reason is not requested
  if [ $WITH_REASON -eq 1 ]; then
    mkdir -p ".claude/skills/$REASON_SKILL/agents"
    cp "$TMP/$REASON_SKILL.SKILL.md" ".claude/skills/$REASON_SKILL/SKILL.md"
    for a in $REASON_AGENTS; do
      cp "$TMP/reason-agent-$a.md" ".claude/skills/$REASON_SKILL/agents/$a.md"
    done
  fi
  mkdir -p .claude/agents
  rm -f .claude/agents/maw-*.md   # drop stale variants from removed/renamed stems
  cp "$TMP/claude-agents/"*.md .claude/agents/
  if [ $WITH_HOOKS -eq 1 ]; then
    mkdir -p .claude/hooks
    cp "$TMP/maw-reason-gate.sh" .claude/hooks/maw-reason-gate.sh
    chmod +x .claude/hooks/maw-reason-gate.sh
    # Wire it in for real. A copied-but-unwired hook enforces nothing, and the
    # option is named for enforcement.
    HOOK_CMD='${CLAUDE_PROJECT_DIR}/.claude/hooks/maw-reason-gate.sh'
    HOOK_WIRED=0
    SETTINGS=.claude/settings.json

    # No settings file yet: write it whole. No parser needed, no risk of
    # clobbering anything, and this is the common case on a fresh install.
    if [ ! -e "$SETTINGS" ]; then
      cat > "$SETTINGS" <<EOF
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$HOOK_CMD" } ] }
    ]
  }
}
EOF
      HOOK_WIRED=1
    elif grep -q 'maw-reason-gate\.sh' "$SETTINGS" 2>/dev/null; then
      HOOK_WIRED=1          # already wired by an earlier run; leave it alone
    elif command -v jq >/dev/null 2>&1; then
      if jq --arg cmd "$HOOK_CMD" '
            .hooks //= {} | .hooks.Stop //= [] |
            .hooks.Stop += [{"hooks":[{"type":"command","command":$cmd}]}]
          ' "$SETTINGS" > "$TMP/settings.json" 2>/dev/null; then
        cp "$TMP/settings.json" "$SETTINGS"
        HOOK_WIRED=1
      fi
    else
      # jq absent and a settings file exists: try Python, which ships with far
      # more machines than jq does. Never hand-edit the JSON with sed.
      for PY in python3 python; do
        command -v "$PY" >/dev/null 2>&1 || continue
        if "$PY" - "$SETTINGS" "$HOOK_CMD" <<'PYEOF' 2>/dev/null
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
hooks = cfg.setdefault("hooks", {})
stop = hooks.setdefault("Stop", [])
if not any(h.get("command") == cmd for entry in stop for h in entry.get("hooks", [])):
    stop.append({"hooks": [{"type": "command", "command": cmd}]})
with open(path, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
PYEOF
        then HOOK_WIRED=1; break; fi
      done
    fi
  fi
fi

if [ $INSTALL_CODEX -eq 1 ]; then
  install_surface ".agents/skills"
fi

agent_count=$(printf '%s\n' $AGENTS | wc -l | tr -d ' ')
reason_count=$(printf '%s\n' $REASON_AGENTS | wc -l | tr -d ' ')
effort_count=$(printf '%s\n' $EFFORTS | wc -l | tr -d ' ')
stem_total=$agent_count
[ $WITH_REASON -eq 1 ] && stem_total=$((agent_count + reason_count))
total=$((stem_total * effort_count))

echo "Installed:"
if [ $INSTALL_CLAUDE -eq 1 ]; then
  echo "  .claude/skills/{maw-execute-task,maw-tasks,maw-context}/SKILL.md"
  echo "  .claude/skills/maw-execute-task/agents/*.md     ($agent_count raw agent bodies)"
  if [ $WITH_REASON -eq 1 ]; then
    echo "  .claude/skills/maw-reason/{SKILL.md,agents/*.md} ($reason_count raw role bodies, experimental)"
  fi
  echo "  .claude/agents/maw-*.md                         ($total subagents: $stem_total stems x $effort_count effort levels)"
  if [ $WITH_HOOKS -eq 1 ]; then
    if [ "${HOOK_WIRED:-0}" -eq 1 ]; then
      echo "  .claude/hooks/maw-reason-gate.sh                (Stop hook, wired into .claude/settings.json)"
    else
      echo "  .claude/hooks/maw-reason-gate.sh                (Stop hook - NOT wired, see below)"
    fi
  fi
fi
if [ $INSTALL_CODEX -eq 1 ]; then
  echo "  .agents/skills/{maw-execute-task,maw-tasks,maw-context}/SKILL.md"
  echo "  .agents/skills/maw-execute-task/agents/*.md     ($agent_count raw agent bodies)"
  echo "  (maw-reason is Claude-only in v1 and was not installed here)"
fi
if [ $WITH_REASON -eq 1 ]; then
  echo ""
  echo "maw-reason is EXPERIMENTAL: no live chain has been run end to end yet."
  echo "See the maw-reason rows in docs/ACCEPTANCE.md for what is still unverified."
fi
if [ $WITH_HOOKS -eq 1 ] && [ "${HOOK_WIRED:-0}" -eq 0 ]; then
  echo ""
  echo "Could not wire the gate automatically (jq not found, or settings.json is"
  echo "not valid JSON). It enforces NOTHING until you add to .claude/settings.json:"
  echo '  { "hooks": { "Stop": [ { "hooks": [ { "type": "command",'
  echo '      "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/maw-reason-gate.sh" } ] } ] } }'
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
