---
name: maw-context
description: |
  Author and maintain the MAW project-context overlay (`maw/project-context/README.md`) — the normative project knowledge that the pipeline injects into every agent. Use when the user says "add project context", "set up MAW for this project", "register a project invariant / rule / lesson / tool / skill for the pipeline", or "review MAW context proposals".
  Supports flag: --review to go straight to folding pending PCTX_PROPOSALS.md entries.
---

# MAW Project Context

You maintain the project-context overlay for the MAW pipeline. This is the **only** place project-specific knowledge lives — the base pipeline (`maw-execute-task`, `maw-tasks`, `agents/*.md`) stays 100% generic and never contains project text.

## What the overlay is

A single file: `maw/project-context/README.md`. The orchestrator's Step 0.7 reads it (if it exists) and appends it verbatim to the **end of every agent spawn prompt**, on every stage, under a header marking it NORMATIVE — it overrides generic guidance on conflict. Precedence is `task.md inline override > project context > base default`.

Consequences that drive every rule below:

- **It rides into every agent on every stage.** Tokens here are paid 8+ times per task. Keep it tight. Prose, not dumps. Point at canonical docs instead of pasting them; inline only the few lines reviewers actually need.
- **It is normative.** A wrong line here becomes law that beats the base for every future task, with no adversarial reviewer to catch it. Treat edits with the same care as editing a shared constant.
- **No machinery.** No manifest, no per-stage files, no include resolution, no token-budget engine. One file, written as prose by a human, kept short by discipline. If it grows unwieldy, that is a signal to cut, not to add structure.

## Step 0 — Detect state

Check whether `maw/project-context/README.md` exists.

- Absent → this is first-time setup; go to Step 1 (Scaffold).
- Present and the user is adding/changing knowledge → Step 2 (Intake).
- Present and the user asked to review proposals (or `--review`) → Step 3 (Review proposals).

## Step 1 — Scaffold

Create `maw/project-context/README.md` with a short skeleton the user fills in. Do not invent project facts — leave clearly-marked placeholders:

```markdown
# Project context (NORMATIVE for the MAW pipeline)

This file is injected verbatim into every pipeline agent. Keep it tight —
every line is paid on every stage. Point at canonical docs; inline only what
reviewers must see.

## Invariants
<!-- Hard rules that must never be violated. Point at the canonical doc, then
     list the 3-10 key rules verbatim so review agents see them without a file
     read. e.g. "See docs/architecture.md. Key: (1) ... (2) ..." -->

## Tooling
<!-- Project-specific build / test / runtime-QA commands, MCP servers, LSP
     operations agents should use. State which stage they matter for. -->

## Lessons
<!-- Curated, durable lessons (not raw notebook dumps). One line each, dated.
     Added here only via deliberate curation — see the maw-context skill. -->

## Project skills
<!-- Custom skills agents may invoke: name → when/which stage to call it. -->
```

Then run the Intake interview (Step 2) to fill the first real entries. If `maw/` is in `.gitignore` (local-only mode), remind the user that the overlay only reaches worktrees because the orchestrator copies it in — that path is already handled, no action needed from them.

## Step 2 — Intake interview

Ask what class of knowledge is being added, then write it into the right section of `README.md`:

- **Invariant / hard rule** → in `## Invariants`: a pointer to the canonical doc plus 3-10 key rules verbatim (so plan/code/QA reviewers see them without opening the file). Not the whole doc.
- **Accumulated lesson** → in `## Lessons`: one curated, dated line. Never paste a raw notebook entry. Compress to the rule that generalizes. Drop it if it does not generalize beyond one task.
- **Tooling** (build/test/runtime-QA command, MCP server, LSP operation) → in `## Tooling`: the command/tool and which stage(s) it applies to.
- **Custom project skill** → in `## Project skills`: skill name, when to invoke it, which stage.

After writing, re-read the whole file and apply Step 4 (Validate). If it has grown long, push back: propose cuts or tighter wording rather than accepting bloat.

## Step 3 — Review proposals (curated fold-in)

Pipeline agents never edit the overlay. When an agent hits a contradiction or a durable lesson it appends a dated entry to that task's `PCTX_PROPOSALS.md`. Folding those in is deliberate and happens here.

1. Scan all task folders (`maw/tasks/*/*/PCTX_PROPOSALS.md`) for proposal files.
2. Present each proposal to the user with its source task. For each: accept, edit, or reject.
3. For accepted ones, fold a tightened version into the correct `README.md` section (same discipline as Step 2 — curated, short, generalizing).
4. Mark folded proposals as resolved in their `PCTX_PROPOSALS.md` (append `> RESOLVED: folded into project-context on <date>`), do not delete the file — it stays with the task as history.
5. Run Step 4 (Validate).

Never auto-fold. A proposal from one pipeline run is unverified by design — the human (you, with the user) is the gate.

## Step 4 — Validate

Run after any write, or on request:

- `maw/project-context/README.md` exists and is non-empty.
- It is reasonably short. If it is large enough that injecting it into every agent on every stage is wasteful, warn explicitly and propose specific cuts — do not silently accept bloat.
- Any doc paths it points at actually exist in the repo (best-effort check). Broken pointer → warn.
- No raw notebook dumps or whole-doc pastes in `## Lessons` / `## Invariants` — those are pointer-plus-excerpt by convention.

Report what passed and what needs the user's attention. Do not edit base pipeline files — this skill only touches `maw/project-context/` and reads `PCTX_PROPOSALS.md`.

## Persistence

`maw/project-context/` follows the same two modes as the rest of MAW: git-tracked (committed, propagates to worktrees automatically) or local-only (gitignored; the orchestrator copies it into each worktree). You do not manage that — Step 1 of `maw-execute-task` handles the copy. If you create the overlay in git-tracked mode, commit it so worktrees and merges see it.
