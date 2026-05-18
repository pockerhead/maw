---
name: maw-execute-task
description: |
  Adversarial multi-agent development pipeline. Use when the user says "take the next task", "work through tasks", "run the pipeline", or wants to implement a task from the task board with full planning, review, implementation, and QA cycle.
  Supports flags: --worktree (force worktree mode), --no-worktree (force branch-only mode). These override the saved setting for the current run only.
  Supports positional arg: a task number or ID (e.g. `/maw-execute-task 3`, `/maw-execute-task TASK-003`) to run a specific task out of priority order instead of picking the highest-priority pending task.
disable-model-invocation: true
---

# Adversarial Multi-Agent Development

## Settings

Pipeline settings are stored in `maw/settings.json`. The orchestrator checks this file at the start of every run.

```json
{
  "worktree_mode": "always" | "never" | "ask",
  "agent_model": "sonnet",
  "agent_model_overrides": { "planner": "opus", "code-reviewer": "opus" },
  "agent_effort": "medium",
  "agent_effort_overrides": { "code-reviewer": "high", "qa": "high" }
}
```

Agent names everywhere are the agent file stems: `clarifier`, `planner`, `plan-reviewer-1`, `plan-reviewer-2`, `implementer`, `code-reviewer`, `fixer`, `qa`.

- `worktree_mode`: `always` — always create a git worktree for the task (default if user picks this); `never` — work on a feature branch directly, no worktree; `ask` — ask the user each time before starting a task
- `agent_model`: model every spawned agent runs on by default. `sonnet` (default), `opus`, or `haiku`.
- `agent_model_overrides`: optional map of agent name → model for agents that should differ from `agent_model`. Omit the key (or the whole field) to use `agent_model`.
- `agent_effort`: default prompt-effort directive injected into every agent. `low`, `medium` (default), or `high`. `medium` injects nothing (lean default); `low` and `high` inject a short directive — see Step 0.6.
- `agent_effort_overrides`: optional map of agent name → effort for agents that should differ from `agent_effort`.

Both model and effort can also be overridden **per task** in `task.md` (see Step 0.6 precedence) — `task.md` always beats `settings.json`.

If `maw/settings.json` does not exist or `worktree_mode` is missing, the orchestrator **must ask the user** before proceeding (see Step 0.5). If `agent_model` or `agent_effort` is missing, the orchestrator **must ask the user** the model/effort question (see Step 0.6).

---

## Modes

The `Mode:` field in `task.md` controls which subset of the pipeline runs. Valid values:

| Mode | Pipeline | Stops after |
|---|---|---|
| `full` (default) | Clarifier -> Planner -> Plan Rev x2 -> Implementer -> Code Rev -> Fixer -> QA | QA_REPORT.md |
| `small-fix` | Implementer -> Code Rev -> Fixer -> QA | QA_REPORT.md |
| `brainstorm` | Clarifier -> Planner -> Plan Rev x2 | PLAN_FINAL.md (no code written) |
| `deep-research` | Planner (web search emphasis) -> Plan Rev x2 | PLAN_FINAL.md (research report, no code) |

**Backward compatibility:** if the `Mode:` field is missing from `task.md`, default to `full`.

Read `Mode:` right after picking the task (Step 0) and store it as `MODE`. Later steps are gated on this value.

---

## Orchestrator instructions

You are the orchestrator. Do not implement anything yourself. Your job is to spawn agents in sequence using the Task tool and pass artifacts between them via files.

**Agent prompts live in `agents/` directory** (relative to this skill). For each step, read the corresponding agent file, substitute variables (`{WORK_ROOT}`, `{TASK_DIR}`, `{REPO_ROOT}`, and file contents), then spawn the agent with the resulting prompt. Spawn it with the `model` parameter and effort directive resolved per Step 0.6.

### Step 0 — Pick a task

**If the user passed a task number or ID** (e.g. `/maw-execute-task 3`, `/maw-execute-task 003`, `/maw-execute-task TASK-003`): normalize it to `TASK-NNN` (zero-pad to 3 digits) and look for the matching folder in `maw/tasks/pending/`. If not found there, also check `maw/tasks/blocked/` — running `/maw-execute-task TASK-003` on a blocked task is a valid way to retry it, in which case move it from `blocked/` to `pending/` first. If the task exists in `in_progress/` or `done/`, refuse and report to the user. If the ID matches nothing, list available pending/blocked IDs and stop.

**Otherwise (no arg):** scan `maw/tasks/pending/` for task folders. Read each `task.md` to find priorities. Pick the highest-priority task (or the first one if priorities are equal).

Move the folder to `in_progress`:
```bash
TASK_ID="TASK-001"  # replace with actual ID
mkdir -p maw/tasks/in_progress
mv maw/tasks/pending/$TASK_ID maw/tasks/in_progress/$TASK_ID
```

**If `maw/` is NOT in `.gitignore`** (git-tracked mode):
```bash
git add maw/tasks/ && git commit -m "task: start $TASK_ID"
```

**If `maw/` IS in `.gitignore`** (local-only mode): skip the commit — files are not tracked.

If no pending tasks exist, report that to the user and stop.

**Read the `Mode:` field** from the task's `task.md`. Store as `MODE`. If missing, default to `full`. Valid values: `full`, `small-fix`, `brainstorm`, `deep-research`. Any other value -> stop and report to the user.

Also read the `Type:` field — useful for agent context but does not affect pipeline shape.

**Roadmap reconcile (before any work).** If `maw/ROADMAP.md` exists, open it and check it against the actual `## Dependencies` sections of the task.md files in `maw/tasks/pending/`. `task.md` is the source of truth; `ROADMAP.md` is a derived view. If they disagree, regenerate the affected part of `ROADMAP.md` from task.md before continuing — never edit a task.md to match the graph. Then drop the task you just moved to `in_progress/` out of the pending graph. In git-tracked mode, fold this into the existing `task: start $TASK_ID` commit (`git add maw/`). If `maw/ROADMAP.md` does not exist, skip — it is optional and maintained by `/maw-tasks`.

### Step 0.5 — Check worktree mode

**CLI override:** If the user invoked `/maw-execute-task --worktree`, set `USE_WORKTREE=true` and skip the rest of this step. If `/maw-execute-task --no-worktree`, set `USE_WORKTREE=false` and skip.

Read `maw/settings.json`. If the file does not exist or `worktree_mode` is missing:

1. Ask the user:
   ```
   How should the pipeline handle branching?
   1. Worktree (default) — create a git worktree for each task. Isolated from main, safe for parallel work.
   2. Branch only — checkout a feature branch directly, no worktree. Simpler, but blocks the main working tree.
   3. Ask each time — prompt before every task.
   ```
2. Save the answer to `maw/settings.json`:
   ```bash
   mkdir -p maw
   cat > maw/settings.json << 'EOF'
   {
     "worktree_mode": "always"
   }
   EOF
   ```
   (replace `"always"` with `"never"` or `"ask"` based on user's choice)

If `worktree_mode` is `"ask"`, ask the user now:
```
Use worktree for this task, or branch only?
```

Store the effective choice for this run in a variable `USE_WORKTREE` (true/false). All subsequent steps use this variable.

### Step 0.6 — Resolve per-agent model and effort

**First-run config.** Read `agent_model` and `agent_effort` from `maw/settings.json`. If either is missing (or the file did not exist), ask the user once:

```
1. Model for pipeline agents?
   a. Sonnet (default) — all 8 agents on sonnet.
   b. Customize — sonnet by default, pick a different model for specific agents.
2. Effort level for pipeline agents?
   a. Medium (default) — no extra directive.
   b. Customize — medium by default, raise/lower effort for specific agents.
```

For each "Customize", ask which agents and which value. Then write the result back into `maw/settings.json`, preserving `worktree_mode` (read the existing file first, merge — do not clobber other fields):

```bash
mkdir -p maw
cat > maw/settings.json << 'EOF'
{
  "worktree_mode": "always",
  "agent_model": "sonnet",
  "agent_model_overrides": { "planner": "opus" },
  "agent_effort": "medium",
  "agent_effort_overrides": { "code-reviewer": "high" }
}
EOF
```

(Override maps may be `{}` or omitted.) Asked only once — on later runs both fields are present and this prompt is skipped.

**Per-task overrides.** `task.md` may carry optional header lines:

```
Models: default=opus, code-reviewer=opus
Effort: default=high, implementer=low
```

Parse each line as comma-separated tokens: `default=<v>` (or a bare `<v>`) sets the task-wide value for that dimension; `<agent-name>=<v>` sets it for one agent. Missing line / missing token → no per-task value at that level. Invalid model or effort value → stop and report to the user.

**Resolution (per agent, for both model and effort). Highest match wins:**

1. `task.md` per-agent (`<name>=` in `Models:`/`Effort:`)
2. `task.md` task-wide (`default=` or bare value)
3. `settings.json` `*_overrides[<name>]`
4. `settings.json` `agent_model` / `agent_effort`
5. built-in default: model `sonnet`, effort `medium`

**Applying the resolved values at every agent spawn below:**

- **Model** → pass as the Task tool `model` parameter.
- **Effort** → prepend an effort directive to the agent's spawn prompt:
  - `medium` → prepend nothing.
  - `high` → `Effort: HIGH. Be exhaustive. Open files fully, verify every claim against actual code, probe edge cases and failure paths, do not shortcut or assume.`
  - `low` → `Effort: LOW. Optimize for speed. Smallest correct change, skip optional exploration and deep dives, do not gold-plate.`

This is the only thing that varies per agent — pipeline shape and the rest of each prompt are unaffected.

### Step 0.7 — Project context overlay (generic; no-op when absent)

Define `PCTX = {WORK_ROOT}/maw/project-context`. This is an optional, project-supplied overlay authored and maintained by the `/maw-context` skill. The base pipeline knows only the contract below — it never contains any project's actual content.

**At every agent spawn below** — every stage, every retry, every re-spawn — after the spawn prompt is built (with model/effort already resolved) and before calling the Task tool, assemble the project-context block from two optional sources:

1. **Shared (all agents):** `PCTX/README.md` — applies to every agent.
2. **Per-agent (this agent only):** `PCTX/agents/<stem>.md`, where `<stem>` is the agent file stem being spawned (`clarifier`, `planner`, `plan-reviewer-1`, `plan-reviewer-2`, `implementer`, `code-reviewer`, `fixer`, `qa`) — same stems as the model/effort overrides. Use it only when a stage genuinely needs context the others do not.

- If **neither** file exists → spawn the prompt unchanged. The pipeline behaves exactly as with no overlay; the base is byte-for-byte unaffected. This is the default for any generic project.
- If **either** exists → append this block verbatim to the **end** of the spawn prompt (include only the parts that exist; per-agent goes after shared so it can refine it):

  ```
  <!-- PROJECT_CONTEXT -->
  ## Project context (NORMATIVE — overrides the generic guidance above on any conflict)

  {contents of PCTX/README.md, verbatim — omit this line and heading if absent}

  ### For this stage (<stem>)
  {contents of PCTX/agents/<stem>.md, verbatim — omit this subsection if absent}

  ---
  If something in your step contradicts the project context above, or you hit a
  durable rule or lesson worth recording, DO NOT edit the project context.
  Append a dated entry to {TASK_DIR}/PCTX_PROPOSALS.md (create it if absent)
  stating what and why. Folding proposals into the real project context is a
  separate curated step — not yours.
  ```

  Substitute `{TASK_DIR}` and `<stem>` to real values. Everything is inlined as-is — no include resolution, no token-budget engine. The project author keeps these files tight because the shared one rides into every agent on every stage; that discipline is the `maw-context` skill's job, not the orchestrator's.

**Pointers, not dumps.** The overlay may *point* at canonical project docs / lessons / notebooks instead of pasting them (e.g. "See `docs/architecture.md`. Key rules: …"). When it does, the orchestrator follows the **Context propagation to subagents** discipline below: a subagent sees nothing the spawn prompt does not contain, so for a pointer the orchestrator must either inline the few relevant lines or instruct the agent to `Read` the path explicitly. The overlay declares the pointers; the orchestrator surgically inlines what the current task's risk area actually needs — never the whole referenced file.

**Precedence (generic; the same lattice applies to model/effort in Step 0.6):** an inline override in `task.md` beats the project context, which beats the base/agent default — `task.md > PCTX > base`. The injected header states this so the override is visible to the agent, not silent.

This is the only project-specific seam in the pipeline: conditional reads plus one append. Agent prompt files in `agents/` are never modified for project specifics.

### Step 1 — Create branch (and worktree if enabled)

Read the `Branch:` field from the task's `task.md` to get the branch name (e.g. `feature/add-rate-limiting`).

**If `USE_WORKTREE` is true (worktree mode):**

```bash
TASK_ID="TASK-001"           # replace with actual ID
BRANCH="feature/add-rate-limiting"  # from task.md Branch: field
WORKTREE_DIR=$(echo $BRANCH | tr '/' '-')  # feature-add-rate-limiting
WORK_ROOT=".worktrees/$WORKTREE_DIR"

git worktree remove --force $WORK_ROOT 2>/dev/null || true
git branch -D $BRANCH 2>/dev/null || true
git worktree add $WORK_ROOT -b $BRANCH
```

**If local-only mode** (`maw/` IS in `.gitignore`): `maw/` is gitignored, so the freshly-added worktree does **not** contain it. Copy the task folder and the project-context overlay (if present) into the worktree, or every agent — and the Step 0.7 overlay — will silently see nothing:

```bash
mkdir -p $WORK_ROOT/maw/tasks/in_progress
cp -r maw/tasks/in_progress/$TASK_ID $WORK_ROOT/maw/tasks/in_progress/
[ -d maw/project-context ] && cp -r maw/project-context $WORK_ROOT/maw/
[ -f maw/ROADMAP.md ] && cp maw/ROADMAP.md $WORK_ROOT/maw/
```

**If git-tracked mode** (`maw/` NOT in `.gitignore`): nothing to copy — both are already in the checkout.

All subsequent agents work exclusively inside `$WORK_ROOT/`. They must not touch the main branch.

The task folder is available at `$WORK_ROOT/maw/tasks/in_progress/$TASK_ID/` — this is where all artifacts are written. Create `metrics.md` there now (see the Metrics ledger section) before any agent is spawned.

Define shorthands for prompts:
- `TASK_DIR=maw/tasks/in_progress/$TASK_ID`
- `WORK_ROOT=.worktrees/$WORKTREE_DIR`

**If `USE_WORKTREE` is false (branch-only mode):**

```bash
TASK_ID="TASK-001"           # replace with actual ID
BRANCH="feature/add-rate-limiting"  # from task.md Branch: field

git checkout -b $BRANCH
```

All subsequent agents work in the repo root directory. They must not push to main.

The task folder is available at `maw/tasks/in_progress/$TASK_ID/` — this is where all artifacts are written. Create `metrics.md` there now (see the Metrics ledger section) before any agent is spawned.

Define shorthands for prompts:
- `TASK_DIR=maw/tasks/in_progress/$TASK_ID`
- `WORK_ROOT=.` (repo root)

---

**From this point forward, all paths in agent prompts use `{WORK_ROOT}` and `{TASK_DIR}`.** In worktree mode `WORK_ROOT` is `.worktrees/{WORKTREE_DIR}`, in branch-only mode it is `.` (the repo root).

### Step 2 — Clarifier agent (conditional)

**Mode gate:** skip this step entirely if `MODE` is `small-fix` or `deep-research`. In `small-fix`, `task.md` IS the spec and is used directly by the Implementer. In `deep-research`, the Planner works directly from `task.md` without a clarification pass.

For `full` and `brainstorm`: spawn only if the task description is thin (no acceptance criteria, no technical context, ambiguous scope). Skip if already detailed enough.

Read `agents/clarifier.md`. Substitute variables and task contents. Spawn the agent.

**After agent finishes:** read `{WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md`. If it contains a non-empty `## Open questions` section — present those questions to the user, wait for answers, then append them under `### Resolved questions` and remove the `## Open questions` section. (The clarifier is a subagent and cannot ask the user directly — relaying its questions is the orchestrator's job, same pattern as Step 3.)

If skipped, write `{WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md` with the original task content yourself.

### Step 3 — Planner agent

**Mode gate:** skip if `MODE` is `small-fix`.

**Source file:**
- `full` or `brainstorm`: `TASK_FINAL.md`
- `deep-research`: `task.md` directly

Read `agents/planner.md`. Substitute variables and task contents. For `deep-research` mode, prepend the deep-research prefix from the agent file. Spawn the agent.

**After agent finishes:** read `{WORK_ROOT}/{TASK_DIR}/PLAN.md`. If "Open questions" is non-empty — present to user, wait for answers, append to `TASK_FINAL.md` under `### Resolved questions`.

### Step 4 — Plan reviewer 1

**Mode gate:** skip if `MODE` is `small-fix`.

Read `agents/plan-reviewer-1.md`. Substitute variables and contents of `TASK_FINAL.md` + `PLAN.md`. Spawn the agent.

### Step 5 — Plan reviewer 2 (final plan)

**Mode gate:** skip if `MODE` is `small-fix`.

Read `agents/plan-reviewer-2.md`. Substitute variables and contents of `TASK_FINAL.md` + `PLAN_V2.md`. Spawn the agent.

### Step 6 — Implementer agent

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`. Jump to Step 10.

Read `agents/implementer.md`. For `small-fix` mode, follow the small-fix fallback instructions in the agent file. Substitute variables and spawn.

### Step 7 — Code reviewer (read-only)

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`.

Read `agents/code-reviewer.md`. For `small-fix` mode, follow the small-fix note in the agent file. Substitute variables and spawn.

### Step 8 — Implementation fixer

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`.

Read `agents/fixer.md`. For `small-fix` mode, follow the small-fix note in the agent file. Substitute variables and spawn.

### Step 9 — QA agent

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`.

Read `agents/qa.md`. For `small-fix` mode, follow the small-fix note in the agent file. Substitute variables and spawn.

### Step 10 — Wrap up

**First, regardless of mode or verdict:** append the `**TOTAL**` row to `{WORK_ROOT}/{TASK_DIR}/metrics.md` (see the Metrics ledger section) before the status-move commands below, so the totals land in the same commit as the final status move.

**Mode gate for plan-only modes:** if `MODE` is `brainstorm` or `deep-research`:

1. Verify `{WORK_ROOT}/{TASK_DIR}/PLAN_FINAL.md` exists. If not, something went wrong — report to the user and stop.
2. Move the task folder to `done/`:
   ```bash
   cd $WORK_ROOT
   mkdir -p maw/tasks/done
   mv maw/tasks/in_progress/$TASK_ID maw/tasks/done/$TASK_ID
   ```
3. **If git-tracked mode:**
   ```bash
   git add maw/tasks/ && git commit -m "task: finalize $TASK_ID ($MODE)"
   ```
4. Report to the user: mode, task ID, one-line summary of PLAN_FINAL.md, list of artifacts (`TASK_FINAL.md` if present, `PLAN.md`, `PLAN_V2.md`, `PLAN_FINAL.md`).
5. Do NOT offer to merge — nothing was implemented. No branch merge is applicable unless the user explicitly asks (e.g. to keep the plan artifacts on main).
6. Stop here.

**Otherwise (`full` or `small-fix`):**

1. Read `{WORK_ROOT}/{TASK_DIR}/QA_REPORT.md`. Get the verdict.

2. If verdict is **SHIP**:
   - Move the task folder to `done/` inside the worktree:
     ```bash
     cd $WORK_ROOT
     mkdir -p maw/tasks/done
     mv maw/tasks/in_progress/$TASK_ID maw/tasks/done/$TASK_ID
     ```
   - **If git-tracked mode** (maw/ not in .gitignore):
     ```bash
     git add maw/tasks/ && git commit -m "task: complete $TASK_ID"
     ```
   - Report to the user with verdict + one-line summary + artifact list.
   - Ask if they want to merge:
     - **Worktree mode:** `git checkout main && git merge --squash $BRANCH && git commit`, then cleanup: `git worktree remove --force $WORK_ROOT && git branch -D $BRANCH`
     - **Branch-only mode:** `git checkout main && git merge --squash $BRANCH && git commit && git branch -D $BRANCH`

3. If verdict is **NEEDS_FIXES** or **REJECT**:
   - Move the task folder to `blocked/` inside the worktree:
     ```bash
     cd $WORK_ROOT
     mkdir -p maw/tasks/blocked
     mv maw/tasks/in_progress/$TASK_ID maw/tasks/blocked/$TASK_ID
     ```
   - **If git-tracked mode** (maw/ not in .gitignore):
     ```bash
     git add maw/tasks/ && git commit -m "task: block $TASK_ID — QA issues"
     ```
   - List the blocking issues and ask the user how to proceed.

---

## Metrics ledger

Every task folder carries a `metrics.md` next to `task.md`: `{WORK_ROOT}/{TASK_DIR}/metrics.md`. It is a pure accounting artifact — it is **never** substituted into any agent prompt, so agents do not see it. It rides with the task folder through every status move and, in git-tracked mode, is committed by the existing `git add maw/tasks/` at each transition (no extra commit logic).

**Create it once**, right after the task folder is in place in `in_progress/` (Step 1), before the first spawn:

```markdown
# Metrics — TASK-NNN

| # | Step | Agent | Model | Effort | Outcome | Tool uses | Tokens | Duration |
|---|------|-------|-------|--------|---------|-----------|--------|----------|
```

**After every agent spawn returns** — every agent, every step, including clarifier, plan reviewers, QA, and any retry or re-spawn — read the `<usage>` trailer of the Task result. It looks like:

```
<usage>total_tokens: 42889
tool_uses: 16
duration_ms: 91043</usage>
```

Append one row: incrementing `#`, the step number, the agent name (suffix `(retry)` / `(re-spawn N)` if it is not the first spawn of that agent), the resolved model and effort, a short outcome (verdict like `PASS`/`NEEDS_WORK`/`SHIP`, or `ok` / `no-output`), then `tool_uses`, `total_tokens`, and `duration_ms` rendered as `Xm Ys`. One spawn = one row; nothing is overwritten. If a result has no `<usage>` trailer, write `n/a` in those three columns rather than guessing.

**At wrap-up (Step 10), before the final status move**, append a `**TOTAL**` row: sum of `Tokens`, sum of `Tool uses`, sum of `Duration`, and put the spawned-agent count in the Agent column (e.g. `9 spawns / 8 agents`). This row is the per-task total across all agents spawned within the task.

## Adversarial framing

Every review agent (Plan Rev 1, Plan Rev 2, Code Rev, Fixer, QA) receives the framing: **"the previous agent was on a weaker model"**. This is intentional. It triggers skepticism and forces the agent to verify claims against actual code rather than trusting what was written. The orchestrator (you) always uses this framing when spawning review agents — even if in reality all agents run on the same model.

The framing comes with an implicit constraint: **change only what you can verify is wrong**. Rewriting correct code "to be safe" introduces new bugs. If uncertain — document the concern in the review artifact and let the next agent decide.

---

## Context propagation to subagents

**Invariant (verified against Claude Code docs + GitHub Issue #27661, Feb 2026):** a Task-spawned subagent does **not** inherit the parent session. It does not auto-load project `CLAUDE.md`, global `~/.claude/CLAUDE.md`, `@`-imported files, hooks, or permission rules. It starts in a fresh context window with only its own agent-template system prompt plus **the spawn prompt string you pass it**. Whatever you do not put in that string, the subagent cannot see — there is no transitive reach through `@`-imports in the project's `CLAUDE.md`.

This is why the Step 0.7 overlay exists at all, and why it must be inlined rather than referenced. It also imposes discipline whenever the project overlay *points* at a doc/lesson/notebook instead of pasting it:

1. **Make normative docs reachable explicitly.** Do not write "follow project conventions" — the agent has no auto-loaded conventions. Either inline the relevant rules, or give an explicit instruction to `Read <path> fully before acting`. For tight-budget review stages (plan reviewers, code reviewer, fixer, QA), inline-quote the 3–10 most relevant rules instead of "Read fully".
2. **Inline relevant lessons surgically.** If the overlay points at a lessons file / project notebook and a specific entry applies to *this task's risk area*, inline those 1–3 sentences under a "Lessons from prior work" heading in the spawn prompt. Never paste the whole notebook — that drowns signal and burns budget. Relevance is your judgement as orchestrator (you have the full picture); this is curation, not enforcement.
3. **Quote concrete `file:line` references** instead of "look at the existing patterns".

**Anti-patterns:** "follow CLAUDE.md" (not auto-loaded); "you know the codebase" (fresh context); trusting `@`-imports to reach the subagent (they don't); dumping an entire notebook into every spawn (overload).

**Future-mode alternatives (not used by default, noted for consumers).** Per-subagent `memory:` frontmatter (Claude Code v2.1.33+) gives a named subagent its own persistent MEMORY.md — a per-stage silo, not shared. Fork mode (`CLAUDE_CODE_FORK_SUBAGENT=1`, experimental) makes a subagent inherit the full parent conversation including `CLAUDE.md` — at the cost of context isolation. MAW stays on the inline-context-in-spawn-prompt pattern until one of these matures or Issue #27661 ships native propagation. Project-specific paths and excerpts always live in the `PCTX` overlay, never in this base file.

---

## Rules for the orchestrator

- Never implement anything yourself. You only spawn agents and move files/folders.
- Each agent is a fresh Task call with no conversation history — all context must be in the spawn prompt.
- Every Task spawn passes a `model` parameter and (if not `medium`) an effort directive, both resolved via the Step 0.6 precedence (task.md beats settings.json). Never spawn without resolving them.
- After every Task spawn returns, append a row to `metrics.md` from the result's `<usage>` trailer (see the Metrics ledger section). No spawn is exempt — clarifier, reviewers, QA, retries, re-spawns all get a row.
- Before every Task spawn, apply the Step 0.7 project-context overlay (no-op if `PCTX/README.md` and `PCTX/agents/<stem>.md` are both absent). Never edit files in `agents/` for project specifics — the overlay is the only seam. Never let a pipeline agent write into `PCTX/`; agents only append proposals to the task-local `PCTX_PROPOSALS.md`.
- `maw/ROADMAP.md` (if present) is a derived view of the task.md `## Dependencies` sections — never authoritative. On any disagreement, task.md wins and the graph is regenerated, never the reverse. It is optional; absence is not an error.
- If a Task call fails or produces no output file, retry once with an explicit instruction to write the output file before finishing.
- Never merge to main without user confirmation.
- If any agent produces a FAIL verdict: pause, report to user, wait for instructions before continuing.
- Status changes are folder moves (`mv maw/tasks/pending/X maw/tasks/in_progress/X`), not edits to a file.
- In git-tracked mode (maw/ not in .gitignore): always commit status transitions so they propagate correctly through worktrees and merges.
- In local-only mode (maw/ in .gitignore): skip all maw/tasks/ commits — only commit code changes.
