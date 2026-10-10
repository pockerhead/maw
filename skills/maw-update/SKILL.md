---
name: maw-update
description: |
  Update the MAW installation in this project to the latest published version. Use when the user says "update MAW", "upgrade MAW", "reinstall MAW", "обнови maw", or asks for the newest pipeline prompts.
  Reruns the official installer with the same surfaces and options that are installed now, so nothing optional is dropped. Never touches `maw/` (tasks, settings, project context).
---

# MAW Update

You update the MAW files in the current project by rerunning the installer from the README. The installer replaces every installed MAW file and leaves `maw/` alone. Work from the project root (`git rev-parse --show-toplevel`, or the current directory outside git). On Windows, run the shell commands through Git Bash.

## Step 1 — Detect what is installed

The installer only installs what its flags ask for, and it **deletes** `maw-reason` when `--with-reason` is absent. So the flags must reproduce the current install:

| present in the project | flag |
|---|---|
| `.claude/skills/maw-execute-task/SKILL.md` | `--claude` |
| `.agents/skills/maw-execute-task/SKILL.md` | `--codex` |
| `.claude/skills/maw-reason/SKILL.md` | `--with-reason` |
| `.claude/hooks/maw-reason-gate.sh` | `--with-hooks` |
| `.claude/skills/maw-selfreview/SKILL.md` | `--with-selfreview` |

If neither surface is present, MAW is not installed here. Say so and stop; installing is the user's call (the README has the command).

If the user asks to add or drop a surface or option during the update, change the flags accordingly and say what changes.

## Step 2 — Protect local edits

The installer overwrites installed files without asking. In a git repository, run `git status --porcelain -- .claude/skills/maw-* .claude/agents/maw-* .claude/hooks/maw-* .agents/skills/maw-*`. If any of those paths has uncommitted changes, list them and ask the user before going on: they may be deliberate local edits that the update would erase.

If those paths are not tracked by git, copy the installed `maw-*` skill directories to a temporary directory first, so you can show a diff in Step 4.

## Step 3 — Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/pockerhead/maw/main/install.sh | sh -s -- <flags from Step 1>
```

Record the upstream commit for the report: `git ls-remote https://github.com/pockerhead/maw.git HEAD`. GitHub's raw CDN can lag a fresh push by a few minutes. If the user expects a commit that the installed files do not contain yet, wait and rerun rather than editing files by hand.

If the installer exits nonzero, show its last lines and stop. A failed fetch leaves the previous install in place, because the installer downloads everything before it copies.

## Step 4 — Report

- The upstream commit and the flags you used.
- What changed: `git diff --stat` over the installed paths, or a diff against the Step 2 copy. Name the changed skills and agent bodies in one line each. Do not paste whole files.
- **Restart needed.** Claude Code discovers skills and named subagents at session start, and Codex discovers repository skills at startup. Tell the user to restart before the next pipeline run, and do not start one in this session.

Do not commit the updated files unless the user asks. In a project that commits `.claude/` or `.agents/`, offer one commit: `chore: update MAW to <short-hash>`.
