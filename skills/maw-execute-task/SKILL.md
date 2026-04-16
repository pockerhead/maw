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
  "worktree_mode": "always" | "never" | "ask"
}
```

- `always` — always create a git worktree for the task (default if user picks this)
- `never` — work on a feature branch directly, no worktree
- `ask` — ask the user each time before starting a task

If `maw/settings.json` does not exist or `worktree_mode` is missing, the orchestrator **must ask the user** before proceeding (see Step 0.5).

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

**Agent prompts live in `agents/` directory** (relative to this skill). For each step, read the corresponding agent file, substitute variables (`{WORK_ROOT}`, `{TASK_DIR}`, `{REPO_ROOT}`, and file contents), then spawn the agent with the resulting prompt.

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

All subsequent agents work exclusively inside `$WORK_ROOT/`. They must not touch the main branch.

The task folder is available at `$WORK_ROOT/maw/tasks/in_progress/$TASK_ID/` — this is where all artifacts are written.

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

The task folder is available at `maw/tasks/in_progress/$TASK_ID/` — this is where all artifacts are written.

Define shorthands for prompts:
- `TASK_DIR=maw/tasks/in_progress/$TASK_ID`
- `WORK_ROOT=.` (repo root)

---

**From this point forward, all paths in agent prompts use `{WORK_ROOT}` and `{TASK_DIR}`.** In worktree mode `WORK_ROOT` is `.worktrees/{WORKTREE_DIR}`, in branch-only mode it is `.` (the repo root).

### Step 2 — Clarifier agent (conditional)

**Mode gate:** skip this step entirely if `MODE` is `small-fix` or `deep-research`. In `small-fix`, `task.md` IS the spec and is used directly by the Implementer. In `deep-research`, the Planner works directly from `task.md` without a clarification pass.

For `full` and `brainstorm`: spawn only if the task description is thin (no acceptance criteria, no technical context, ambiguous scope). Skip if already detailed enough.

Read `agents/clarifier.md`. Substitute variables and task contents. Spawn the agent.

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

## Adversarial framing

Every review agent (Plan Rev 1, Plan Rev 2, Code Rev, Fixer, QA) receives the framing: **"the previous agent was on a weaker model"**. This is intentional. It triggers skepticism and forces the agent to verify claims against actual code rather than trusting what was written. The orchestrator (you) always uses this framing when spawning review agents — even if in reality all agents run on the same model.

The framing comes with an implicit constraint: **change only what you can verify is wrong**. Rewriting correct code "to be safe" introduces new bugs. If uncertain — document the concern in the review artifact and let the next agent decide.

---

## Rules for the orchestrator

- Never implement anything yourself. You only spawn agents and move files/folders.
- Each agent is a fresh Task call with no conversation history — all context must be in the spawn prompt.
- If a Task call fails or produces no output file, retry once with an explicit instruction to write the output file before finishing.
- Never merge to main without user confirmation.
- If any agent produces a FAIL verdict: pause, report to user, wait for instructions before continuing.
- Status changes are folder moves (`mv maw/tasks/pending/X maw/tasks/in_progress/X`), not edits to a file.
- In git-tracked mode (maw/ not in .gitignore): always commit status transitions so they propagate correctly through worktrees and merges.
- In local-only mode (maw/ in .gitignore): skip all maw/tasks/ commits — only commit code changes.
