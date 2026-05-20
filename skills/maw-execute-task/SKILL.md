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

Agent names everywhere are the agent file stems: `clarifier`, `premise-challenge`, `planner`, `plan-reviewer-1`, `plan-reviewer-2`, `implementer`, `code-reviewer`, `fixer`, `qa`.

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
| `full` (default) | Clarifier -> Premise Challenge -> Planner -> Plan Rev x2 -> Implementer -> Code Rev -> Fixer -> QA | QA_REPORT.md |
| `small-fix` | Implementer -> Code Rev -> Fixer -> QA | QA_REPORT.md |
| `brainstorm` | Clarifier -> Premise Challenge -> Planner -> Plan Rev x2 | PLAN_FINAL.md (no code written) |
| `deep-research` | Premise Challenge -> Planner (web search emphasis) -> Plan Rev x2 | PLAN_FINAL.md (research report, no code) |

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

Also read the `Type:` field — useful for agent context but does not affect pipeline shape. Read the optional `Domains:` line if present (comma-separated domain names) and store it as `DOMAINS` — Step 0.7 uses it to pre-inject project-context domain modules. Missing line → no pre-injected domains (the Step 0.7 catalog still covers self-load).

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
   a. Sonnet (default) — all 9 agents on sonnet.
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

Define `PCTX = {WORK_ROOT}/maw/project-context`. Optional, project-supplied, authored by the `/maw-context` skill. The base pipeline knows only the contract below — it never contains project content. Three tiers:

- **`PCTX/README.md` — constant**, into every agent every stage.
- **`PCTX/domains/<name>.md` — domain-gated**, normative, into every running stage when the task is in that domain.
- **`PCTX/agents/<stem>.md` — stage-gated**, into that one agent only.

If `PCTX/` does not exist → spawn every prompt unchanged; the base is byte-for-byte unaffected. This is the default for any generic project. Otherwise, **at every agent spawn** — every stage, every retry, every re-spawn — after the prompt is built (model/effort resolved) and before calling Task, append this block to the **end** of the spawn prompt, including only the parts that exist:

```
<!-- PROJECT_CONTEXT -->
## Project context (NORMATIVE — a constraint you must satisfy)
This overrides the generic guidance above on any conflict. It is project law,
human-curated. Do not audit whether the law is correct — verify your work
SATISFIES it. (Disagreement goes to PCTX_PROPOSALS.md, below, never silent.)

{PCTX/README.md — with the {PCTX} placeholder replaced by the real path}

{For each active domain: contents of PCTX/domains/<name>.md, under a
"### Domain: <name>" heading — omit if no domain is active}

### For this stage (<stem>)
{PCTX/agents/<stem>.md — omit this subsection if that file is absent}

---
If something in your step contradicts the project context above, or you hit a
durable rule or lesson worth recording, DO NOT edit the project context.
Append a dated entry to {TASK_DIR}/PCTX_PROPOSALS.md (create it if absent)
stating what and why. Folding proposals into the real project context is a
separate curated step — not yours.
```

Substitute `{TASK_DIR}`, `<stem>`, and every `{PCTX}` to real values. Because the catalog inside `README.md` contains `{PCTX}/domains/...` paths an agent may self-Read, the orchestrator **must** substitute `{PCTX}` when injecting README — it is near-verbatim, not pure-verbatim. (`{PCTX}` resolves to the worktree-correct path in both persistence modes; the whole `PCTX/` dir is copied into the worktree in local-only mode, Step 1.)

**Which domains are active.** A domain module is injected when either holds:

1. **Pre-injected** — `task.md` has a `Domains:` line (written by `/maw-tasks`, confirmed by the user — see that skill). Each listed `<name>` whose `PCTX/domains/<name>.md` exists is active for this whole run. This is the reliable path: a recorded human decision, not an execute-time guess.
2. **Self-loaded** — the `## Domain catalog` in `README.md` (always injected, since README is constant) lists `trigger → {PCTX}/domains/<name>.md` with observable triggers and a HARD RULE telling the agent to Read the mapped module before working any part that matches a trigger. This is the recall safety net for a task that wanders into a domain `task.md` did not declare. The agent self-loads; you do not predict it.

You are not asked to guess domains from prose. Pre-inject only what `task.md Domains:` declares; the catalog covers the rest.

**Precedence (generic; same lattice as model/effort in Step 0.6):** `task.md` inline override > project context > base/agent default. The injected header states this so it is visible, not silent.

This is the only project-specific seam: conditional reads plus one append plus `{PCTX}` substitution. Files in `agents/` are never modified for project specifics.

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

### Step 2.5 — Premise challenge (isolated; conditional)

**Mode gate:** skip if `MODE` is `small-fix` (scope is contained, no planning stage — the premise risk is low and is covered later by the repro discipline). Runs in `full`, `brainstorm`, `deep-research`. Runs **before** the planner on purpose: a rotten premise must be caught before any planning is spent on it.

Why this exists: every later stage verifies the *solution within the premise* and inherits the premise's lineage (task.md → TASK_FINAL → plan → reviews). Nothing else attacks the premise itself. This is the one isolated check that does, and the only thing that historically catches a wrong premise is a concrete counter-example from outside the lineage.

Read `agents/premise-challenge.md`. Substitute variables. **Pass it only** the premise source (`TASK_FINAL.md` if it exists, else `task.md`) and the working/repo paths — **never** your own root-cause writeup, a summary, the plan, or any reviewer note. The agent investigates primary sources (code at `file:line`, an executable result it runs, the raw failing artifact) itself; isolation from the lineage is the whole point. Spawn the agent. Do **not** apply the "previous agent was on a weaker model" framing here — this agent has its own evidence-bound framing; that adversarial framing is for solution reviewers only.

**After agent finishes:** read `{WORK_ROOT}/{TASK_DIR}/PREMISE_CHALLENGE.md`.

- Verdict `PREMISE HOLDS` → proceed to Step 3.
- Verdict `PREMISE SUSPECT` → **treat exactly like a FAIL verdict** (see Rules): pause, surface `PREMISE_CHALLENGE.md` to the user verbatim, wait for instructions. Do not spawn the planner. The premise, not the plan, is what is in question — the user decides whether to amend `task.md`/`TASK_FINAL.md` and re-run, or override.

### Step 3 — Planner agent

**Mode gate:** skip if `MODE` is `small-fix`.

**Source file:**
- `full` or `brainstorm`: `TASK_FINAL.md`
- `deep-research`: `task.md` directly

Read `agents/planner.md`. Substitute variables and task contents. For `deep-research` mode, prepend the deep-research prefix from the agent file. Spawn the agent.

**After agent finishes:** read `{WORK_ROOT}/{TASK_DIR}/PLAN.md`. If "Open questions" is non-empty — present to user, wait for answers, append to `TASK_FINAL.md` under `### Resolved questions`.

### Step 4 — Plan reviewer 1

**Mode gate:** skip if `MODE` is `small-fix`.

Read `agents/plan-reviewer-1.md`. Substitute variables only — `TASK_FINAL.md` and `PLAN.md` are read from disk by the agent itself (mandatory Read block in the prompt), not inlined here. Spawn the agent.

### Step 5 — Plan reviewer 2 (final plan)

**Mode gate:** skip if `MODE` is `small-fix`.

Read `agents/plan-reviewer-2.md`. Substitute variables only — `TASK_FINAL.md` and `PLAN_V2.md` are read from disk by the agent itself (mandatory Read block in the prompt), not inlined here. Spawn the agent.

### Step 6 — Implementer agent

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`. Jump to Step 10.

Read `agents/implementer.md`. For `small-fix` mode, follow the small-fix fallback instructions in the agent file. Substitute variables and spawn.

**After agent finishes:** read `{WORK_ROOT}/{TASK_DIR}/IMPL_SUMMARY.md`. If it contains `Verdict: PLAN_BLOCKED` — **treat exactly like a FAIL verdict**: pause, surface `IMPL_SUMMARY.md` to the user verbatim, wait for instructions. Do **not** spawn the code-reviewer. The plan, not the code, is what is in question — the user decides whether to amend `PLAN_FINAL.md`, restart planning, or override. This is the implementer's pre-flight escape hatch for catching a broken-presupposition plan before wrong code materializes.

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

**Also regardless of mode or verdict:** if `maw/ROADMAP.md` exists, regenerate it after the status move from the remaining `maw/tasks/pending/` task.md `## Dependencies` sections (same generation rule as `/maw-tasks` Step 5). This task has now left `in_progress/`, so its pending dependents must be re-derived — a `blocked by` whose blocker is now in `done/` is satisfied and that edge drops; one whose blocker went to `blocked/` stays, annotated. This is the symmetric counterpart to the Step 0 reconcile (Step 0 handles `pending→in_progress`, this handles `in_progress→done|blocked`). In git-tracked mode include it in the same status-move commit (`git add maw/`). If `maw/ROADMAP.md` does not exist, skip.

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
4. Report to the user: mode, task ID, one-line summary of PLAN_FINAL.md, list of artifacts (`TASK_FINAL.md` if present, `PREMISE_CHALLENGE.md` unless small-fix, `PLAN.md`, `PLAN_V2.md`, `PLAN_FINAL.md`).
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

Append one row: incrementing `#`, the step number, the agent name (suffix `(retry)` / `(re-spawn N)` if it is not the first spawn of that agent), the resolved model and effort, a short outcome (verdict like `PASS`/`NEEDS_WORK`/`SHIP`/`PREMISE HOLDS`/`PREMISE SUSPECT`/`PLAN_BLOCKED`, or `ok` / `no-output`), then `tool_uses`, `total_tokens`, and `duration_ms` rendered as `Xm Ys`. One spawn = one row; nothing is overwritten. If a result has no `<usage>` trailer, write `n/a` in those three columns rather than guessing.

**At wrap-up (Step 10), before the final status move**, append a `**TOTAL**` row: sum of `Tokens`, sum of `Tool uses`, sum of `Duration`, and put the spawned-agent count in the Agent column (e.g. `10 spawns / 9 agents`). This row is the per-task total across all agents spawned within the task.

## Adversarial framing

Every review agent (Plan Rev 1, Plan Rev 2, Code Rev, Fixer, QA) receives the framing: **"the previous agent was on a weaker model"**. This is intentional. It triggers skepticism and forces the agent to verify claims against actual code rather than trusting what was written. The orchestrator (you) always uses this framing when spawning review agents — even if in reality all agents run on the same model.

The framing comes with an implicit constraint: **change only what you can verify is wrong**. Rewriting correct code "to be safe" introduces new bugs. If uncertain — document the concern in the review artifact and let the next agent decide.

This framing reduces, but cannot eliminate, a deeper defect: every solution reviewer verifies the solution *within the premise the orchestrator framed* and inherits that premise's lineage; same-lineage reviewers raise false-consensus confidence, not accuracy, and a model cannot repair a wrong premise from inside the context that contains it (arXiv 2506.01332, 2310.01798; the fix is independent evidence, not a fiercer arguer — arXiv 2506.13609). Step 2.5's premise-challenge is the structural mitigation: an isolated agent fed only the task and the real system, never the lineage. It does **not** receive the "previous agent was weaker" framing — that points at prior *work*, not at the *frame*. The defect is reduced, not removed; the human remains the last line on the residue.

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
- Before every Task spawn, apply the Step 0.7 project-context overlay (no-op if `PCTX/` is absent), substituting `{PCTX}` to the real path. Pre-inject domain modules per `task.md Domains:`; never guess domains from prose — the constant catalog is the self-load net. Never edit files in `agents/` for project specifics — the overlay is the only seam. Never let a pipeline agent write into `PCTX/`; agents only append proposals to the task-local `PCTX_PROPOSALS.md`.
- `maw/ROADMAP.md` (if present) is a derived view of the task.md `## Dependencies` sections — never authoritative. On any disagreement, task.md wins and the graph is regenerated, never the reverse. It is optional; absence is not an error.
- If a Task call fails or produces no output file, retry once with an explicit instruction to write the output file before finishing.
- Never merge to main without user confirmation.
- If any agent produces a FAIL verdict — or `premise-challenge` returns `PREMISE SUSPECT`, or `implementer` returns `PLAN_BLOCKED` — pause, report to user (surface the artifact verbatim), wait for instructions before continuing.
- **Primary source over proxy (premise audit).** For any task that is a retry, a relaunch, or marked premise-suspect, hand `premise-challenge` the primary artifact (the raw failing test / log / repro / code), never your own writeup or a summary of it. A `PREMISE_CHALLENGE` verdict that cites only a derived artifact (a summary, a prior mandate, a log line used as a proxy for a fact) is invalid — it must cite a primary source: code at `file:line`, an executable result, or a direct observation of the real system. A repro or observation predicate is a deliverable to be produced, not a conclusion to be asserted. What counts as the primary source / repro harness for a given project is supplied by that project's `PCTX` overlay, not hardcoded here.
- Status changes are folder moves (`mv maw/tasks/pending/X maw/tasks/in_progress/X`), not edits to a file.
- In git-tracked mode (maw/ not in .gitignore): always commit status transitions so they propagate correctly through worktrees and merges.
- In local-only mode (maw/ in .gitignore): skip all maw/tasks/ commits — only commit code changes.
