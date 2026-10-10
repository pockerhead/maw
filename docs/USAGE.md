# Usage

## Choosing a mode

The mode table with costs is in the [README](../README.md#modes).

When you create a task, MAW analyzes the description and suggests a mode:

```
> /maw-tasks "fix 404 on the profile page"

This looks like a focused bug fix with clear scope.
Suggested mode: small-fix (Implementer → Code Review → Fixer → QA)

[full] [small-fix] [brainstorm] [deep-research]
```

You confirm or override. The mode is saved in `task.md`:

```markdown
# TASK-001: Fix 404 on the profile page

Type: bugfix
Mode: small-fix
Priority: high
Branch: bugfix/fix-profile-404
```

`Type` is the semantic category (feature, bugfix, refactor, chore). `Mode` is which agents run. You can set mode explicitly with `/maw-tasks --mode deep-research` or change it in task.md before running `/maw-execute-task`.

## Commands

Create tasks:
```
/maw-tasks                                          # interactive intake
/maw-tasks "description here"                       # one-shot, mode is suggested
/maw-tasks --mode small-fix "fix 404 on profile"    # explicit mode, skips suggestion
/maw-tasks --mode deep-research "rate limiting options"
```

Flags:
- `--mode <full|small-fix|brainstorm|deep-research>` — set the MAW mode directly and skip the suggestion step. Without this flag, the skill analyzes the description and proposes a mode you can confirm or override.

Run the pipeline:
```
/maw-execute-task                 # pick the highest-priority pending task
/maw-execute-task 3               # run TASK-003 specifically (jump the queue)
/maw-execute-task TASK-003        # same, explicit form
/maw-execute-task --worktree      # force worktree mode for this run
/maw-execute-task --no-worktree   # force branch-only mode for this run
/maw-execute-task 3 --worktree    # combine: run TASK-003 in a worktree
```

Flags:
- `--worktree` — isolate the task in a git worktree (overrides saved setting for this run)
- `--no-worktree` — work on a feature branch directly, no worktree (overrides saved setting for this run)

Positional arg (task number or `TASK-NNN`): skip priority selection and run a specific task. Useful for urgent work that needs to jump the queue, or retrying a blocked task. The task must exist in `pending/` or `blocked/`.

Update MAW itself:
```
/maw-update                       # or just say "update MAW"
```

It reruns the installer with the surfaces and options already installed (so `maw-reason` and `maw-selfreview` stay), asks first if installed MAW files have uncommitted local edits, and reports the upstream commit and what changed. `maw/` is never touched. Restart the harness afterwards.

## What gets produced

Every run leaves a full audit trail in the task folder. Artifacts depend on mode:

**full mode:**
```
maw/tasks/done/TASK-001/
├── task.md           ← original task
├── TASK_FINAL.md     ← clarified requirements
├── PREMISE_CHALLENGE.md ← isolated premise audit (holds / suspect, primary-source cited)
├── PLAN.md           ← initial plan
├── PLAN_V2.md        ← reviewed plan
├── PLAN_FINAL.md     ← final plan after two review passes
├── IMPL_SUMMARY.md   ← what was implemented
├── IMPL_REVIEW.md    ← code review findings
├── FIX_SUMMARY.md    ← what was fixed after review
├── QA_REPORT.md      ← test results
├── transcripts/      ← ignored, lossless harness-written spawn logs
├── scratch/          ← persistent scripts, probes, measurements, and text evidence
├── log.jsonl         ← append-only decisions/dead ends (pointers, not facts)
└── metrics.md        ← per-agent tokens / tool uses / duration + task total
```

`metrics.md` is written by the orchestrator (not by agents — they never see it). One row per agent attempt, including retries, continuations, and re-spawns, with provider/model/effort columns; usage comes with the native completion notification or from the external CLI's JSON output. Wrap-up appends per-provider `SUBTOTAL` rows plus a `TOTAL` row (spawn count, tool uses, duration — token counts are never summed across providers). Present in every mode.

**small-fix:** task.md + IMPL_SUMMARY.md + IMPL_REVIEW.md + FIX_SUMMARY.md + QA_REPORT.md + transcripts/ + scratch/ + log.jsonl + metrics.md

**brainstorm:** task.md + TASK_FINAL.md + PREMISE_CHALLENGE.md + PLAN.md + PLAN_V2.md + PLAN_FINAL.md + transcripts/ + scratch/ + log.jsonl + metrics.md

**deep-research:** task.md + TASK_FINAL.md (orchestrator-written copy of task.md) + PREMISE_CHALLENGE.md + PLAN.md (research report) + PLAN_V2.md + PLAN_FINAL.md + transcripts/ + scratch/ + log.jsonl + metrics.md

Transcripts are complete harness/provider captures and are never pasted into prompts; later stages receive paths and search selectively. Their `.gitignore` keeps payloads out of ordinary commits because prompts, PCTX, excerpts, and secrets may appear there. This does not protect against local disclosure, backups, or `git add -f`. Retention is unlimited in v1, so `done/` grows. Scratch persists with the task as executable coverage evidence; fixer and QA inspect it but must verify independently. `log.jsonl` accepts only `decision` and `dead_end`; entries point to evidence and are never trusted without checking refs. Premise challenge and both plan reviewers receive scratch plus append-only log access, but no transcript path and no log read. All three are absent when `shared_memory` is `false` in `maw/settings.json` (see [CONFIGURATION.md](CONFIGURATION.md)).

Plus `PCTX_PROPOSALS.md` in any task where an agent proposed a project-context change (see [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)).

Plus `OPEN_DECISIONS.md` in any task where the orchestrator hit a judgement call that blocked nothing — a scope edge, an adjacent defect, a defensible choice between two options. Rather than stopping to ask and leaving the pipeline parked, it takes the defensible option and records the call, the alternative, and what would flip it. The whole file is surfaced at wrap-up, which is where you overrule it. Present in every mode; absent when the run had no such calls.

## Roadmap graph

`maw/ROADMAP.md` is an auto-maintained dependency view of the pending task board, derived from the `## Dependencies` section of each `task.md` (`task.md` is the source of truth — the graph is never authoritative). `/maw-tasks` regenerates it on every task create/edit; `/maw-execute-task` reconciles it against the task files before starting and drops the started task out of the pending graph. It is a short tree of hard blockers plus a list of soft orderings and unblocks — structure only, no narrative. Optional: absence is not an error, and projects that never declare dependencies never get one.

## Cost

MAW trades tokens for reliability. Token consumption depends on mode; the per-mode table is in the [README](../README.md#modes).

Each agent consumes 40–70k tokens on a medium-sized codebase. Implementer and Code Review can exceed 100k on complex tasks. At Opus pricing, multiply accordingly.

Every spawn also carries a fixed shared-memory path/access block (larger for the six full-access roles). Its real token impact is measured from per-run metrics rather than estimated here.

On long tasks most of the cost is prompt-cache reads: a stage costs about its calls times its context, and a wait longer than the cache lifetime rewrites the whole context. Three things matter most. Set `"subagentPromptCacheTtl": "1h"` in `~/.claude/settings.json`. Let the orchestrator slice a long plan into fresh implementers. Leave the full and slow test suites to QA. The orchestrator's Cost discipline section has the measured numbers.

Codex-provider stages are billed per your Codex auth mode (ChatGPT plan quota or API-key tokens) — the table above prices Claude tokens only; `metrics.md` keeps per-provider subtotals and never sums tokens across providers.

The tradeoff: if the cost of shipping a bug exceeds the cost of running the pipeline, use MAW. Modes let you pick the right level of rigor per task instead of paying for the full pipeline every time.

Back to the [README](../README.md).
