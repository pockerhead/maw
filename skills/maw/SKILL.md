---
name: maw
description: |
  Adversarial multi-agent development pipeline. Use when the user says "take the next task", "work through tasks", "run the pipeline", or wants to implement a task from the task board with full planning, review, implementation, and QA cycle.
  Supports flags: --worktree (force worktree mode), --no-worktree (force branch-only mode). These override the saved setting for the current run only.
  Supports positional arg: a task number or ID (e.g. `/maw 3`, `/maw TASK-003`) to run a specific task out of priority order instead of picking the highest-priority pending task.
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

## Task board structure

Tasks live in a directory tree where **the parent folder is the status**:

```
maw/tasks/
├── pending/          ← tasks waiting to be picked up
│   └── TASK-001/
│       └── task.md
├── in_progress/      ← currently being worked on
│   └── TASK-002/
│       ├── task.md
│       ├── PLAN_FINAL.md
│       └── ...artifacts...
├── done/             ← completed and merged
│   └── TASK-003/
│       ├── task.md
│       └── ...all artifacts...
└── blocked/          ← waiting on external input
    └── TASK-004/
        ├── task.md
        └── ...artifacts...
```

Each task folder contains `task.md` — the task definition:

```markdown
# TASK-001: Add rate limiting to /api/auth

Type: feature
Mode: full
Priority: high
Branch: feature/add-rate-limiting

## Description
Implement token bucket rate limiting on the authentication endpoint.
Limit: 5 requests per minute per IP. Return 429 with Retry-After header.

## Acceptance criteria
- [ ] 429 returned after 5 requests/min from same IP
- [ ] Retry-After header present
- [ ] Existing tests pass
- [ ] Unit tests for limiter logic
```

---

## Modes

The `Mode:` field in `task.md` controls which subset of the pipeline runs. Valid values:

| Mode | Pipeline | Stops after |
|---|---|---|
| `full` (default) | Clarifier → Planner → Plan Rev x2 → Implementer → Code Rev → Fixer → QA | QA_REPORT.md |
| `small-fix` | Implementer → Code Rev → Fixer → QA | QA_REPORT.md |
| `brainstorm` | Clarifier → Planner → Plan Rev x2 | PLAN_FINAL.md (no code written) |
| `deep-research` | Planner (web search emphasis) → Plan Rev x2 | PLAN_FINAL.md (research report, no code) |

**Backward compatibility:** if the `Mode:` field is missing from `task.md`, default to `full`.

Read `Mode:` right after picking the task (Step 0) and store it as `MODE`. Later steps are gated on this value — see Step 2 onwards.

---

## Orchestrator instructions

You are the orchestrator. Do not implement anything yourself. Your job is to spawn agents in sequence using the Task tool and pass artifacts between them via files.

### Step 0 — Pick a task

**If the user passed a task number or ID** (e.g. `/maw 3`, `/maw 003`, `/maw TASK-003`): normalize it to `TASK-NNN` (zero-pad to 3 digits) and look for the matching folder in `maw/tasks/pending/`. If not found there, also check `maw/tasks/blocked/` — running `/maw TASK-003` on a blocked task is a valid way to retry it, in which case move it from `blocked/` to `pending/` first. If the task exists in `in_progress/` or `done/`, refuse and report to the user. If the ID matches nothing, list available pending/blocked IDs and stop.

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

**Read the `Mode:` field** from the task's `task.md`. Store as `MODE`. If missing, default to `full`. Valid values: `full`, `small-fix`, `brainstorm`, `deep-research`. Any other value → stop and report to the user.

Also read the `Type:` field — useful for agent context but does not affect pipeline shape.

### Step 0.5 — Check worktree mode

**CLI override:** If the user invoked `/maw --worktree`, set `USE_WORKTREE=true` and skip the rest of this step. If `/maw --no-worktree`, set `USE_WORKTREE=false` and skip.

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

For `full` and `brainstorm`: spawn only if the task description is thin (no acceptance criteria, no technical context, ambiguous scope). Skip if the description is already detailed enough.

**Spawn prompt:**
```
You are a requirements analyst. Your only job is to determine if the following task has enough information to be implemented without guessing.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/task.md}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/

Rules:
- Read relevant source files to understand the existing codebase context.
- If the task is clear and complete: write {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md with the original task content unchanged.
- If anything is ambiguous or missing: ask the user ONE focused question (not a list). After the user answers, write TASK_FINAL.md with the enriched description.
- Do not plan. Do not suggest solutions. Only clarify scope.
```

If skipped, write `{WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md` with the original task content yourself.

### Step 3 — Planner agent

**Mode gate:** skip entirely if `MODE` is `small-fix`.

**Source file for this step:**
- `full` or `brainstorm`: use `TASK_FINAL.md` (written by Clarifier or copied from `task.md`).
- `deep-research`: use `task.md` directly (no TASK_FINAL.md exists in this mode).

**Mode-specific prompt prefix:**
- `deep-research`: prepend the following line to the spawn prompt before "You are a senior engineer...":
  > Mode: deep-research. Focus on researching best practices, existing solutions, and tradeoffs. Use WebSearch and WebFetch extensively. Output a research report, not an implementation plan. Cite sources with URLs. Compare at least 2–3 alternative approaches. Do not write file-level change steps — the goal is to inform a human decision, not to drive an implementer.
- `full` or `brainstorm`: use the spawn prompt as-is.

**Spawn prompt:**
```
You are a senior engineer writing an implementation plan.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md or task.md depending on mode}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/
Repo root: {REPO_ROOT}

Instructions:
- Open and read ALL files relevant to this task. Do not skim — open files fully.
- Understand the existing architecture before proposing anything.
- **Research phase (mandatory):** Before writing the plan, use WebSearch and WebFetch to look up best practices, common pitfalls, and proven architectural patterns relevant to the task. For example: if the task involves rate limiting — search for "token bucket vs leaky bucket best practices"; if it involves auth — search for current OWASP recommendations. Cite specific sources in the plan where relevant.
- Write a concrete implementation plan to {WORK_ROOT}/{TASK_DIR}/PLAN.md

PLAN.md must contain:
1. **Understanding** — what the existing code does today, relevant files and line ranges
2. **Approach** — chosen technical approach and why
3. **Steps** — ordered list of specific changes: file, what changes, why
4. **Risk areas** — what could go wrong
5. **Open questions** — anything that needs a decision before implementation

Be specific. "Add rate limiter middleware" is not a step. "Add `rateLimiter` middleware in `src/middleware/auth.ts` before the handler, using the token bucket from `src/lib/limiter.ts`" is a step.
```

**After Planner finishes:** read `{WORK_ROOT}/{TASK_DIR}/PLAN.md`. If section "Open questions" is non-empty — present each question to the user and wait for answers before proceeding. Append the answers to `TASK_FINAL.md` under a `### Resolved questions` section, then continue to Step 4.

### Step 4 — Plan reviewer 1

**Mode gate:** skip if `MODE` is `small-fix`.

**Spawn prompt:**
```
You are a senior engineer reviewing a plan written by an agent running on a weaker model. Your job is to find flaws and write a better plan.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md}
---

Plan to review:
---
{contents of {WORK_ROOT}/{TASK_DIR}/PLAN.md}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/
Repo root: {REPO_ROOT}

Instructions:
- Open the actual files mentioned in the plan. Verify every claim against real code.
- Do not trust the plan's description of existing code — go check yourself.
- **Research verification:** Use WebSearch and WebFetch to verify the technical approach from the plan. Check if the chosen patterns/libraries are still recommended, if there are known issues or better alternatives. Cross-reference the plan's approach with industry best practices.
- Identify: incorrect assumptions, missing steps, wrong file paths, architectural issues, skipped edge cases.
- Write {WORK_ROOT}/{TASK_DIR}/PLAN_V2.md — a corrected and improved plan.

PLAN_V2.md format:
1. **Review notes** — specific issues found in the original plan (with evidence from code)
2. **Updated understanding** — corrected description of existing code
3. **Revised approach** — updated technical approach if needed
4. **Revised steps** — full step list (not a diff — write the complete updated plan)
5. **Risk areas** — updated
```

### Step 5 — Plan reviewer 2 (final plan)

**Mode gate:** skip if `MODE` is `small-fix`.

**Spawn prompt:**
```
You are a principal engineer doing a final review of an implementation plan. The plan was written by an agent on a weaker model.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md}
---

Plan to review:
---
{contents of {WORK_ROOT}/{TASK_DIR}/PLAN_V2.md}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/
Repo root: {REPO_ROOT}

Instructions:
- Open the actual files. Verify the plan against real code — not the previous reviewer's description.
- **Final research check:** Use WebSearch and WebFetch for any remaining uncertainties — library version compatibility, edge cases documented in official docs, security advisories for dependencies involved. This is the last chance to catch a bad approach before implementation.
- Check for: anything PLAN_V2 still got wrong, steps that will break existing functionality, missing test coverage in the plan, deployment or migration concerns.
- Write {WORK_ROOT}/{TASK_DIR}/PLAN_FINAL.md — the definitive implementation plan.

PLAN_FINAL.md format:
1. **Summary** — one paragraph: what will be built and how
2. **Implementation steps** — ordered, specific, complete. Each step: file path, exact change, reason.
3. **Test plan** — what to test, how, expected outcomes
4. **Rollout notes** — migrations, env vars, feature flags, backward compat concerns
5. **Review notes** — what was changed from PLAN_V2 and why

This is the document the implementer will follow. It must be unambiguous.
```

### Step 6 — Implementer agent

**Mode gate:** skip entirely if `MODE` is `brainstorm` or `deep-research`. Those modes stop after PLAN_FINAL.md and never write code. Jump straight to Step 10 (Wrap up).

**Source files for this step:**
- `full`: task spec is `TASK_FINAL.md`, plan is `PLAN_FINAL.md`.
- `small-fix`: task spec is `task.md`, there is NO plan file. Replace `{contents of PLAN_FINAL.md}` in the prompt below with the literal text: `"No plan file — this is small-fix mode. task.md is the spec. Read it carefully, then make the minimal set of changes needed to satisfy the acceptance criteria. Open every file before editing. Do not expand scope beyond what task.md asks for."`

**Spawn prompt:**
```
You are an engineer implementing a task. You have a detailed plan to follow.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md or task.md depending on mode}
---

Implementation plan:
---
{contents of {WORK_ROOT}/{TASK_DIR}/PLAN_FINAL.md or the small-fix fallback text above}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/
You MUST work only inside this worktree. Do not modify files outside it.

Instructions:
- Follow PLAN_FINAL.md step by step.
- Open each file fully before editing it.
- After all changes: run the existing test suite. Fix any failures before proceeding.
- Write {WORK_ROOT}/{TASK_DIR}/IMPL_SUMMARY.md with:
  1. What was implemented (files changed, with line counts)
  2. What was not implemented and why (if anything deviated from the plan)
  3. Test results (command run + output summary)
  4. How to manually verify the feature
```

### Step 7 — Implementation reviewer (read-only)

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`.

**Source files:** in `small-fix` mode there is no `PLAN_FINAL.md` — replace the `{contents of PLAN_FINAL.md}` block with the literal text `"No plan — small-fix mode. The spec is task.md; verify the implementation against it directly."` and use `task.md` as the task source.

**Spawn prompt:**
```
You are a senior engineer reviewing code written by an agent on a weaker model. You are NOT allowed to make any code changes. Your only output is a review document.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md}
---

Final plan:
---
{contents of {WORK_ROOT}/{TASK_DIR}/PLAN_FINAL.md}
---

Implementation summary:
---
{contents of {WORK_ROOT}/{TASK_DIR}/IMPL_SUMMARY.md}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/

Instructions:
- Open every changed file fully. Read all the code.
- Check against PLAN_FINAL.md — did the implementation actually follow the plan?
- Look for: bugs, missed edge cases, security issues, performance problems, unclear code, missing error handling, insufficient tests.
- Do NOT edit any files. Do NOT fix anything.
- Write {WORK_ROOT}/{TASK_DIR}/IMPL_REVIEW.md with:
  1. **Verdict** — PASS / NEEDS_WORK / FAIL with one-line reason
  2. **Confirmed correct** — what the implementation got right (with file refs)
  3. **Issues** — each issue with: severity (critical/major/minor), file:line, description, suggested fix
  4. **Missing coverage** — test cases that should exist but don't
  5. **Nits** — minor style/clarity issues (optional section)
```

### Step 8 — Implementation fixer

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`.

**Source files:** in `small-fix` mode substitute `PLAN_FINAL.md` the same way as in Step 7, and use `task.md` as the task source.

**Spawn prompt:**
```
You are a senior engineer fixing code after a review. The review was written by an agent on a weaker model — verify each claim before acting on it.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md}
---

Final plan:
---
{contents of {WORK_ROOT}/{TASK_DIR}/PLAN_FINAL.md}
---

Review to act on:
---
{contents of {WORK_ROOT}/{TASK_DIR}/IMPL_REVIEW.md}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/
You MUST work only inside this worktree.

Instructions:
- For each issue in the review: open the referenced file and check whether the issue is real.
- Fix issues you agree with. Skip issues that are wrong or irrelevant — but document why you skipped them.
- After fixes: run the test suite again. Fix any new failures.
- Write {WORK_ROOT}/{TASK_DIR}/FIX_SUMMARY.md with:
  1. **Fixed** — each issue addressed (review item → what was done)
  2. **Skipped** — each issue not addressed and why
  3. **Test results** — command + output
```

### Step 9 — QA agent

**Mode gate:** skip if `MODE` is `brainstorm` or `deep-research`.

**Source files:** in `small-fix` mode substitute `PLAN_FINAL.md` the same way as in Step 7, and use `task.md` as the task source.

**Spawn prompt:**
```
You are a QA engineer. Your job is to build a test environment, exercise the implemented feature, and write a QA report. The implementation was done by an agent on a weaker model — approach it as if you expect to find bugs.

Task:
---
{contents of {WORK_ROOT}/{TASK_DIR}/TASK_FINAL.md}
---

Final plan:
---
{contents of {WORK_ROOT}/{TASK_DIR}/PLAN_FINAL.md}
---

Implementation summary:
---
{contents of {WORK_ROOT}/{TASK_DIR}/IMPL_SUMMARY.md}
---

Code review:
---
{contents of {WORK_ROOT}/{TASK_DIR}/IMPL_REVIEW.md}
---

Fix summary:
---
{contents of {WORK_ROOT}/{TASK_DIR}/FIX_SUMMARY.md}
---

Worktree path: {WORK_ROOT}/
Task dir: {WORK_ROOT}/{TASK_DIR}/
Repo root: {REPO_ROOT}

## Environment setup — follow this decision tree:

1. **Check for docker-compose**: if `docker-compose.yml` or `compose.yml` exists at repo root, use it.
   ```bash
   cd {REPO_ROOT} && docker-compose up -d
   # wait for health checks, then run against the live stack
   ```

2. **Check for Makefile/justfile with dev target**: if `make dev`, `just dev`, or `npm run dev` exists and starts a server, use it. Start it in background, wait up to 30 seconds for the port to open (`curl --retry 10 --retry-delay 3 --retry-connrefused http://localhost:{PORT}/health`). If not up after 30s — stop and fall through to option 3.

3. **Check for existing test infrastructure**: if there's a test runner (`pytest`, `go test`, `jest`, `cargo test`, etc.) configured, use it directly on the worktree.

4. **Build minimal environment yourself**:
   - Identify external dependencies from the changed code (databases, caches, external APIs).
   - For each dependency: check if a real instance is reachable locally, or spin up via docker (`docker run -d --name qa_{TASK_ID}_{SERVICE} ...`), or write a mock.
   - Prefer real instances over mocks. Use mocks only when a real instance would require credentials or is unreasonably complex.
   - Document what you spun up so it can be cleaned up.

## QA execution:

- Run all existing tests first. If they fail, note it and continue.
- Write and run additional tests targeting the acceptance criteria in the task.
- Test edge cases and failure paths, not just the happy path.
- For each acceptance criterion in the task: explicitly test it and record pass/fail.

## Output:

Write {WORK_ROOT}/{TASK_DIR}/QA_REPORT.md with:
1. **Environment** — what was used (docker-compose / direct / mocks), commands to reproduce
2. **Test results** — existing suite results + new tests written + results
3. **Acceptance criteria** — table: criterion | test performed | result (PASS/FAIL)
4. **Bugs found** — each bug: severity, reproduction steps, expected vs actual behavior
5. **Verdict** — SHIP / NEEDS_FIXES / REJECT with reasoning

## Cleanup:

After writing QA_REPORT.md, stop any services you started:
```bash
# if you used docker-compose:
cd {REPO_ROOT} && docker-compose down
# if you started individual containers, stop each by its exact name as listed in QA_REPORT:
# docker stop <name1> <name2> ... && docker rm <name1> <name2> ...
```
```

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

## Artifact map

All artifacts live inside the task folder alongside `task.md`. Which files appear depends on the mode:

**`full`** (all 7 agents):
```
task.md, TASK_FINAL.md, PLAN.md, PLAN_V2.md, PLAN_FINAL.md,
IMPL_SUMMARY.md, IMPL_REVIEW.md, FIX_SUMMARY.md, QA_REPORT.md
```

**`small-fix`** (Implementer → Code Rev → Fixer → QA):
```
task.md, IMPL_SUMMARY.md, IMPL_REVIEW.md, FIX_SUMMARY.md, QA_REPORT.md
```

**`brainstorm`** (Clarifier → Planner → Plan Rev x2):
```
task.md, TASK_FINAL.md, PLAN.md, PLAN_V2.md, PLAN_FINAL.md
```

**`deep-research`** (Planner → Plan Rev x2, no Clarifier):
```
task.md, PLAN.md, PLAN_V2.md, PLAN_FINAL.md
```

---

## Adversarial framing

Every review agent (Plan Rev 1, Plan Rev 2, Impl Rev, Impl Fixer, QA) receives the framing: **"the previous agent was on a weaker model"**. This is intentional. It triggers skepticism and forces the agent to verify claims against actual code rather than trusting what was written. The orchestrator (you) always uses this framing when spawning review agents — even if in reality all agents run on the same model.

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
