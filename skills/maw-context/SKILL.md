---
name: maw-context
description: |
  Author and maintain the MAW project-context overlay (`maw/project-context/`) — the project knowledge the pipeline injects into agents. Use when the user says "add project context", "set up MAW for this project", "register a project invariant / rule / lesson / tool / skill / domain for the pipeline", or "review MAW context proposals".
  Supports flags: --review to go straight to folding pending PCTX_PROPOSALS.md entries; --migrate to add law/procedure/lesson tags to an untagged overlay without changing anything else.
---

# MAW Project Context

You maintain the project-context overlay for the MAW pipeline. This is the **only** place project-specific knowledge lives — the base pipeline (`maw-execute-task`, `maw-tasks`, `agents/*.md`) stays 100% generic and never contains project text.

## What the overlay is

Three tiers, each gated on a different axis. Conflating them is the mistake to avoid.

Shared-memory paths, access rules, the `log.jsonl` schema, post-spawn lifecycle, and continuity rules belong only to the base `maw-execute-task` skill. Never duplicate or override them in project context.

1. **`maw/project-context/README.md` — CONSTANT, every agent, every stage.** The orchestrator injects it into every spawn with the `{PCTX}` placeholder substituted to the real path (so it is *near*-verbatim, not pure-verbatim). It holds only what is true regardless of subsystem or stage: a short orientation, universal invariants, and a **domain catalog**. It is paid on every spawn, so it is bounded by deliberate discipline, not "free".
2. **`maw/project-context/domains/<name>.md` — gated by DOMAIN.** A subsystem's normative invariants + risk lessons + pointers to bulky docs. Injected NORMATIVE into every running stage (including planner and plan reviewers — planning correctness needs them) when the task is in that domain. It reaches an agent two ways: pre-injected because `task.md` declared the domain, or self-loaded because the agent hit an observable trigger in the catalog (the recall safety net).
3. **`maw/project-context/agents/<stem>.md` — gated by STAGE.** Stage tooling / project skills / checklists for one agent only. `<stem>` ∈ `clarifier|premise-challenge|planner|plan-reviewer-1|plan-reviewer-2|implementer|code-reviewer|fixer|qa`. Build/test/runtime-QA commands and stage skills go here, not in README — clarifier and planners must not carry tooling they never use. If the same tooling genuinely applies to several stages, repeat it tersely in each; do not hoist it to README.

   Special case `agents/premise-challenge.md`: this agent is deliberately isolated from the task's premise lineage — it must see only the task and the real system. Its per-agent overlay may declare **only** where this project's primary sources / executable repro harness live (e.g. "the failing-test command is `make repro`", "runtime truth is observed via <tool>"). It must contain **no** premise narrative, no assumed root cause, no "how we usually do X" — that would re-inject the lineage the isolation exists to break. If you have nothing but narrative to add here, add nothing. The same access boundary protects `agents/plan-reviewer-1.md` and `agents/plan-reviewer-2.md`: none of these three overlays may instruct its role to read `log.jsonl`, transcripts, or reconstruct an omitted path.

Honest cost: the constant README grows with the number of domains (one catalog line each). At ~M domains it is roughly a few hundred tokens paid 8+ times per task. That is bounded and acceptable, not "tiny" — keep catalog entries to one line and prune dead domains.

Two rules that drive everything:

- **README is normative and global; a wrong line is law.** It beats the base for every future task with no adversarial reviewer to catch it (pipeline review agents verify *code satisfies the law*, they do not audit whether the law is correct — that gate is here, Step 3). Edit it like a shared constant. Growing unwieldy → move content into a domain module, do not bloat the constant.
- **Reduced, human-authored machinery — not zero.** The catalog is a minimal hand-written manifest; pre-inject is human-declared selective injection. This is deliberate and implementable in a prompt because a human authors it. There is no resolution engine and no includes, and one mechanical gate: the overflow check (`pctx-sleep.sh check`, limits from `maw/settings.json`).

## Step 0 — Detect state

Check whether `maw/project-context/README.md` exists.

- Absent → first-time setup; go to Step 1 (Scaffold).
- Present, user is adding/changing knowledge → Step 2 (Intake).
- Present, user asked to review proposals (or `--review`) → Step 3 (Review proposals).
- Present, user asked to migrate tags (or `--migrate`) → Step 3c (Migrate tags).

## Step 1 — Scaffold

Create `maw/project-context/README.md` with this skeleton. Do not invent project facts — leave marked placeholders. Create `domains/` and `agents/` lazily (Step 2), never empty.

The body of this file is injected verbatim into every agent's spawn prompt, so it must read as content **for** the agent — never as a note to yourself about where things go (that discipline lives in this skill and in Step 4 validation, not in the file). The orchestrator already wraps it under a `## Project context (NORMATIVE — a constraint you must satisfy)` heading, so do not repeat a title or a "this is injected everywhere" line. Start at `## Orientation`:

```markdown
## Orientation
<!-- 2-4 lines: what this project is, the stack, the one architectural law
     nobody may break. A fresh-context agent is blind without this. -->

## Universal invariants
<!-- Rules true for ANY change regardless of subsystem (e.g. no secrets in
     code, public API is a contract, errors are typed not panics). 3-7 lines.
     If a rule only matters when you touch subsystem X → it is NOT here, it
     goes in domains/X.md. -->

## Domain catalog
<!-- One line per domain. The trigger MUST be zero-knowledge-observable:
     file/path globs, literal symbol / import / command tokens. NEVER a
     concept name ("the auth layer") — a fresh agent with no project
     knowledge must decide from the trigger alone. Module path uses the
     {PCTX} placeholder; the orchestrator substitutes the real path. -->
- trigger: <observable signal, e.g. files under `src/billing/**` or any `Decimal` use>  → {PCTX}/domains/money.md
- trigger: <observable signal, e.g. any file under `src/auth/**` or a call to `verify_token`> → {PCTX}/domains/auth.md

HARD RULE: before you plan or write any part whose work matches a trigger
above — even if this task was not framed as being in that domain — you MUST
read the mapped module from disk first and treat it as normative. Do not
proceed on that part without it.
```

Domain module skeleton (`domains/<name>.md`, created in Step 2 when the user has one):

```markdown
# Domain: <name>
# NORMATIVE when active — a constraint to satisfy, not a claim for you to audit.

## Invariants
<!-- Subsystem hard rules, verbatim. The few lines reviewers must see. -->

## Procedures
<!-- How to do something in this subsystem: ordered steps, a command, a checklist. -->

## Risk lessons
<!-- Curated, dated, one line each. Folded here via Step 3 or 3b, not raw dumps. -->

## Pointers
<!-- Bulky canonical docs to read from disk (not paste): path → what it contains. -->
```

### Tags

The single definition used by Steps 2, 3, 3b and 3c:

- `[law]`: a rule that must always hold (must / never / always).
- `[procedure]`: how to do something: ordered steps, a command, a checklist.
- `[lesson class=<slug>]`: a lesson that came from a defect. The slug is a kebab-case name of the defect class (`[a-z0-9-]+`). Reuse an existing slug when the class matches.

Tags go only on top-level `- ` lines (column 0) under `## Invariants`, `## Procedures` or `## Risk lessons` of `domains/*.md`, written as `- [law] `, `- [procedure] ` or `- [lesson class=<slug>] `. Never in README or `agents/*.md`, never on sub-bullets or continuation lines. Untagged legacy lines are valid and count as `[lesson class=untagged]` until a migration tags them. Every new line written by Step 2, Step 3 or Step 3b carries a tag.

### Archive

`maw/project-context/archive/<domain>.md` holds lessons taken out of the injected overlay, one per line:

`- [lesson class=<slug>] <text> | archived: YYYY-MM-DD | reason: <why> | holder: <path>[#symbol]`

The holder is code (a test, a check, a lint) that now enforces the class. The archive is never injected and never listed in the catalog; stages can find it with grep. `class=untagged` never appears in it.

Per-agent file (`agents/<stem>.md`): only created in Step 2 when a single stage has tooling/skills the others must not carry.

If `maw/` is in `.gitignore` (local-only mode), tell the user the overlay still reaches worktrees because the orchestrator copies it in — already handled, no action from them.

## Step 2 — Intake interview

Ask what class of knowledge is being added, then route it:

- **Universal invariant** (any change, any subsystem) → `README.md` `## Universal invariants`. Keep it 3-7 lines total; if it is subsystem-specific it is not universal.
- **Domain invariant or risk lesson** (matters only in subsystem X) → `domains/X.md` (`## Invariants` / `## Risk lessons`). Create the module if absent **and** add/confirm its `## Domain catalog` line in `README.md` with a zero-knowledge-observable trigger (path glob / literal token — never a concept). The trigger is the recall safety net; a concept-only trigger is a defect.
- **Bulky doc / lesson file / notebook to reference, not inline** → the `## Pointers` section of the relevant `domains/X.md` (path + what it contains). Never pasted; agents read it from disk when in that domain.
- **Tooling** (build/test/runtime-QA command, MCP server, LSP op) → `agents/<stem>.md` for the stage(s) that run it (implementer/fixer/qa/code-reviewer). Not README.
- **Custom project skill** → `agents/<stem>.md` for the stage that invokes it: skill name + when to call it.

After writing, apply Step 4 (Validate). If `README.md` grew, push back: move content into a domain module, do not accept constant bloat.

## Step 3 — Review proposals (curated fold-in)

Pipeline agents never edit the overlay. When an agent hits a contradiction or a durable lesson it appends a dated entry to that task's `PCTX_PROPOSALS.md`. Folding happens here (human-gated) or in Step 3b (automatic, when `pctx_fold` is `auto`).

1. Scan all task folders (`maw/tasks/*/*/PCTX_PROPOSALS.md`) for proposal files.
2. Present each to the user with its source task: accept, edit, or reject.
3. For accepted ones, fold a tightened version into the **correct tier** — universal → README; subsystem → the matching `domains/X.md` (create + catalog line if it is a new domain); stage tooling → `agents/<stem>.md`. Same discipline as Step 2: curated, short, generalizing. Write each folded line with its tag (Tags).
4. Append `> RESOLVED: folded into <target> on <date>` to the proposal in `PCTX_PROPOSALS.md`. Do not delete it — it stays with the task as history.
5. Run Step 4 (Validate).

When `--review` runs and the script `../maw-execute-task/scripts/pctx-sleep.sh` (the installed sibling, relative to this SKILL.md) exists, also run `check`, `untagged`, `refs` and `restore --dry-run` on the overlay and show their output to the human. When it is missing, do the same checks by hand.

## Step 3b — Automatic fold and sleep pass

Run by the `maw-execute-task` orchestrator at wrap-up (its Step 10 "PCTX wrap-up" carries the exact commands), never by a pipeline agent and never by this skill on its own.

- **When it may write without a human:** `pctx_fold` is `"auto"` in `maw/settings.json`, and the finishing task is moving to `done/`.
- **Input:** only the finishing task's `PCTX_PROPOSALS.md`. Proposals from other tasks wait for `--review`.
- **Script:** `pctx-sleep.sh`, subcommands `check`, `untagged`, `refs`, `holder`, `restore`, `validate`, `migrate-check`, `state`. Exit 0 ok, 1 negative result, 10 overflow, 2 usage error. An absent overlay directory is a no-op.

Order:

1. Snapshot S0. Count `U` with `untagged` on the overlay before any write.
2. `restore`: bring back archived lessons whose class this task's `IMPL_REVIEW.md` or `QA_REPORT.md` names as `class=<slug>` (reason `miss`), or whose holder no longer exists (reason `holder-missing`).
3. Fold the current proposals into `domains/*.md` / `agents/*.md`, with tags.
4. `validate` plus the Step 4 checks. On failure, revert to S0. The proposals stay unmarked and the pass ends.
5. Mark each folded proposal `> RESOLVED: auto-folded into <target> on <date>`. Commit the fold (git-tracked).
6. `check`. Exit 0 ends the pass. Exit 10: snapshot S1, then:
   - **Migration pass (U > 0):** tag every untagged line (Tags). Delete, merge, move, archive and clean nothing. Then run `migrate-check S1 <overlay>` and `validate`.
   - **Consolidation pass (U = 0):** merge two or more lessons that share a class into one `[law]` or `[procedure]` line. Archive a lesson only after `holder` passes for a named holder, recording `archived`, `reason` and `holder`. Never re-archive a line that carries `| restored: ... reason=miss holder=<h>` with that same holder `<h>`; the miss showed that holder does not enforce the class. For each `refs` hit outside README, remove only that backticked token and append `(ref removed <date>)` to the line, keeping the line. Then run `validate` and the Step 4 checks.
7. On failure, revert to S1; the fold stays. On success, commit the pass and save it as a patch (orchestrator Step 10).
8. Write `.sleep-state` (`state`) and the report line.

Safeguards:

- S1: README.md is never auto-written. A README-targeted proposal stays pending for `--review`, because a wrong README line is unaudited law.
- S2: Every auto change is revertible on its own. Git-tracked mode makes two commits, `pctx: fold (<TASK_ID>)` and `pctx: migrate tags (<TASK_ID>)` or `pctx: sleep pass (<TASK_ID>)`. The second is also saved as `<task folder>/pctx-pass.patch`, which survives a squash merge (`git apply -R` undoes it). Local-only mode takes a full snapshot first into `<task folder>/pctx-before/`.
- S3: No archive without a verified holder. Cleaning removes only tokens confirmed missing and never removes a line.
- S4: A failed `validate`, Step 4 check or `migrate-check` reverts that stage, and the report says `reverted`.
- S5: The pass runs only on `done/`. A `blocked/` task gets report-only output.
- S6: A new domain (catalog line) is never created automatically, because that needs a README write (S1). A proposal for an unknown domain stays pending.
- S7: The first pass on an overlay with untagged lines only adds tags, and `migrate-check` enforces this. Merging and archiving start on the next pass.

## Step 3c — Migrate tags (`--migrate`, human-gated)

1. Git-tracked mode: if `git status --porcelain -- maw/project-context` is not empty, stop and ask the human to commit or stash first. Both modes: copy the overlay into a temp snapshot (`mktemp -d`).
2. Tag every untagged line per Tags. Change nothing else.
3. When the script exists, run `sh pctx-sleep.sh migrate-check <snapshot> maw/project-context` and `sh pctx-sleep.sh validate maw/project-context .`. When it is missing, compare by hand. On failure, restore the snapshot and report it.
4. Show the diff: `git diff -- maw/project-context` (git-tracked) or `diff -ru <snapshot> maw/project-context` (local-only).
5. The human accepts: commit `pctx: migrate tags (manual)` (git-tracked), then delete the snapshot. The human rejects: restore the snapshot.
6. Run Step 4.

## Step 4 — Validate

Run after any write, or on request:

- `README.md` exists, non-empty, and has only `## Orientation`, `## Universal invariants`, `## Domain catalog` — no tooling, no per-stage content, no pasted bulky docs.
- Every `## Domain catalog` line: trigger is zero-knowledge-observable (path/glob/literal token, not a concept), is one line, and its `{PCTX}/domains/<name>.md` target file actually exists. Dangling catalog entry or concept-only trigger → flag (an agent told to read a missing file, or unable to recognize the trigger from zero knowledge, is a hole).
- Every domain module referenced by the catalog has a catalog entry, and vice versa (no orphans either direction).
- No raw notebook dumps or whole-doc pastes anywhere — bulky sources are `## Pointers` references, not pasted.
- No overlay duplicates a shared-memory path, schema, access matrix, lifecycle, or continuity rule from the base pipeline.
- `agents/premise-challenge.md`, `agents/plan-reviewer-1.md`, and `agents/plan-reviewer-2.md` grant no transcript or `log.jsonl` read access. Flag a protected-role access grant or shared-memory duplication for human correction; never silently treat it as higher-priority law.
- `archive/` files are not in the catalog; run `pctx-sleep.sh validate` when the script is present.
- README is reasonably short for being injected every spawn; if it is heavy, warn and propose cuts / moving content into domain modules.

Report what passed and what needs the user. Do not edit base pipeline files — this skill only touches `maw/project-context/` (including `archive/`) and reads `PCTX_PROPOSALS.md`.

## Persistence

`maw/project-context/` follows MAW's two modes: git-tracked (committed, propagates to worktrees automatically) or local-only (gitignored; the orchestrator copies the whole directory — `domains/`, `agents/`, README — into each worktree). You do not manage that; Step 1 of `maw-execute-task` handles the copy. In git-tracked mode, commit the overlay so worktrees and merges see it.
