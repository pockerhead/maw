# Install

```bash
curl -fsSL https://raw.githubusercontent.com/pockerhead/maw/main/install.sh | sh
```

With no flags the installer detects which harnesses are present (`claude`, `codex`) and installs a surface for each. Explicit targets: `sh install.sh --claude`, `--codex`, or `--all`; add `--with-reason` for the experimental deliberation surface and `--with-hooks` for its gate. On Windows run it through Git Bash (`sh install.sh`); a native `install.ps1` twin is planned but not shipped yet.

Both surfaces include `maw-execute-task/scripts/runner.sh` for external CLI stages. It shows live provider event types and tool-call activity while saving the complete JSONL stream; native Claude subagents continue through the Task tool. From PowerShell, launch shell scripts through Git's `bin/sh.exe -lc` so its Unix utilities are on PATH.

When upgrading an existing installation, rerun the installer to deliver the runner as well as the updated prompts, then restart the harness. Copying only the new SKILL.md leaves external-stage preflight unable to find its helper.

- **Claude Code surface**: `.claude/skills/{maw-execute-task,maw-tasks,maw-context}/` (+ raw agent bodies) and 45 named subagents in `.claude/agents/`; `--with-reason` adds the `maw-reason` skill, 6 role bodies, and 30 more subagents.
- **Codex CLI surface**: `.agents/skills/{maw-execute-task,maw-tasks,maw-context}/` (+ raw agent bodies) — repository-scoped skills, committable, so teammates on the other harness get a working install from git without re-running the installer. `maw-reason` is Claude-only in v1.

For Claude Code, add to your project's `CLAUDE.md`:

```markdown
# Skills
@.claude/skills/maw-execute-task/SKILL.md
@.claude/skills/maw-tasks/SKILL.md
@.claude/skills/maw-context/SKILL.md
```

**Restart the harness after installing (or reinstalling).** Claude Code discovers the named subagents in `.claude/agents/` at session start; Codex discovers repository skills at startup — neither picks them up mid-session. Start a fresh session before invoking `/maw-execute-task`, or spawns will fail to resolve.

**Invocation per harness:** in Claude Code, type the slash commands (`/maw-tasks`, `/maw-execute-task`). In Codex there are no custom slash commands — ask in words ("create a task with the maw-tasks skill", "run maw-execute-task for task 3") and the repository skill is picked up. **Codex hosting on Windows** additionally requires launching the orchestrator with the sandbox disabled (nested provider CLIs cannot reach your credentials from inside the codex sandbox, and `.git` is write-protected there); — see the Hosting section of the orchestrator skill. Note that a Codex host always loads your own `~/.codex/AGENTS.md` (an interactive session has no way to suppress it) — that is accepted: the orchestrator treats its skill contract as outranking ambient instructions, and pipeline agents never inherit them.

Back to the [README](../README.md).
