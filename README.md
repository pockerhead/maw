# MAW — Multi-Agent Workflow for Claude Code

**Prompt rules tell an LLM what to do. MAW adds a verification layer for when it doesn't listen.**

A sequential adversarial pipeline where each agent reviews the previous agent's work against actual code, not descriptions. Each agent operates under the assumption the previous one was weaker and made mistakes.

Prompt guidelines like Karpathy's (30k+ stars) are useful conventions — MAW is complementary: it catches what slips through despite the rules.

**Empirical result (single user, two projects, ~30k LOC):** zero bugs shipped over two weeks. Anecdotal, not a benchmark — your mileage will vary depending on codebase and task complexity.

## The problem

You can paste the best coding guidelines into your system prompt. The LLM will read them, agree they're important, and then drift from them under complex context. An agent that writes code and reviews its own output has the same blind spots in both passes.

Compare:

| Approach | How it works | Failure mode |
|---|---|---|
| Prompt rules (Karpathy-style) | Tell the agent "be careful" | Agent drifts from rules under complex context |
| Self-review | Agent checks its own work | Same blind spots that caused the error review the error |
| **MAW** | Independent agents verify against code | Reviewer has no shared context with implementer — different blind spots |

## Architecture

![MAW pipeline architecture](assets/maw_pipeline_architecture.svg)

Key design decisions:
- **No shared context** — agents communicate only through files (task.md, PLAN.md, diffs). No chat history carries over. This is a common pattern in adversarial pipelines, but MAW enforces it across every stage including planning.
- **Adversarial by default** — each agent's prompt includes the assumption that the previous agent was unreliable. Not hostile, but skeptical.
- **Premise challenge** — before planning, an isolated agent fed only the task and the real system (never the orchestrator's framing, the plan, or any summary) tests whether the *premise itself* is wrong, and halts to the human if it is. Every other stage verifies the solution within the premise and inherits its lineage; this is the one structural check that attacks the frame. It reduces — does not eliminate — the "pipeline faithfully executes a wrong premise" failure; the human remains the last line.
- **All state in git** — artifacts live in the task folder on a feature branch. Everything is inspectable and recoverable.

## Modes

Not every task needs the whole pipeline. MAW has four modes that control which part runs:

| Mode | Pipeline | When to use | ~Tokens |
|---|---|---|---|
| `full` | Clarifier → Premise Challenge → Planner → Plan Review x2 → Implementer → Code Review → Fixer → QA | Features, migrations, auth/payments | 280–560k |
| `small-fix` | Implementer → Code Review → Fixer → QA | Bug fixes, small changes with clear scope | 120–200k |
| `brainstorm` | Clarifier → Premise Challenge → Planner → Plan Review x2 | Explore approaches before committing to implementation | 100–180k |
| `deep-research` | Premise Challenge → Planner (web search) → Plan Review x2 | Research best practices, compare solutions, audit approaches | 80–150k |

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

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/pockerhead/maw/main/install.sh | sh
```

Add to your project's `CLAUDE.md`:

```markdown
## Skills
@.claude/skills/maw-execute-task/SKILL.md
@.claude/skills/maw-tasks/SKILL.md
@.claude/skills/maw-context/SKILL.md
```

**Restart Claude Code after installing (or reinstalling).** The pipeline agents are named subagents in `.claude/agents/`, and Claude Code discovers them at session start — they will not be picked up mid-session. After running `install.sh`, start a fresh session (or reload the window) before invoking `/maw-execute-task`, or the orchestrator's `subagent_type` spawns will fail to resolve.

## Usage

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
└── metrics.md        ← per-agent tokens / tool uses / duration + task total
```

`metrics.md` is written by the orchestrator (not by agents — they never see it). One row per agent spawn, including retries and re-spawns, parsed from each Task result's usage trailer, with a `TOTAL` row summing the whole task. Present in every mode.

**small-fix:** task.md + IMPL_SUMMARY.md + IMPL_REVIEW.md + FIX_SUMMARY.md + QA_REPORT.md + metrics.md

**brainstorm:** task.md + TASK_FINAL.md + PREMISE_CHALLENGE.md + PLAN.md + PLAN_V2.md + PLAN_FINAL.md + metrics.md

**deep-research:** task.md + PREMISE_CHALLENGE.md + PLAN.md (research report) + PLAN_V2.md + PLAN_FINAL.md + metrics.md

Plus `PCTX_PROPOSALS.md` in any task where an agent proposed a project-context change (see below).

## Project context overlay

The base pipeline is 100% generic — it contains no knowledge of your project. Project-specific knowledge lives in `maw/project-context/`, authored with `/maw-context`.

```
/maw-context            # scaffold, or add an invariant / domain / lesson / tool
/maw-context --review   # fold pending agent proposals into the overlay
```

If `maw/project-context/` does not exist, the pipeline behaves byte-for-byte as with no overlay — this is the default and requires nothing. If it exists, three tiers are injected, each gated on a different axis:

- `README.md` — **constant**, into every agent every stage. Only what is true regardless of subsystem or stage: a short orientation, universal invariants, and a **domain catalog** (observable `trigger → domains/<name>.md` lines plus a hard rule to self-load a module on a matching trigger). Bounded by domain count, not free — kept disciplined.
- `domains/<name>.md` — **domain-gated**, normative. Injected into every running stage (planner and reviewers included — planning correctness needs it) when the task is in that domain. It gets there two ways: pre-injected because `task.md` declared `Domains:` (a recorded decision `/maw-tasks` proposes and the user confirms), or self-loaded when an agent hits an observable catalog trigger a task did not predict (the recall safety net). Subsystem invariants, risk lessons, and pointers to bulky docs live here.
- `agents/<stem>.md` — **stage-gated**, into one agent only. Build/test/runtime-QA tooling and stage skills — clarifier and planners do not carry tooling they never use.

A subagent inherits nothing — not `CLAUDE.md`, not `@`-imports, not notebooks (a verified Claude Code invariant the pipeline is built around), so everything needed must be injected or self-`Read`. Project context is normative as **law to satisfy, not a claim to audit** — review agents verify the code satisfies it; whether the law itself is right is human-gated via `/maw-context --review`. Agents never edit the overlay: they append dated entries to that task's `PCTX_PROPOSALS.md`, folded in deliberately.

This is reduced, human-authored machinery — a hand-written catalog and human-declared `Domains:`, no resolution engine, no token-budget gate, no includes. The base change is the orchestrator plus the `maw-context`/`maw-tasks` skills; the overlay seam never modifies the agent prompts.

## Roadmap graph

`maw/ROADMAP.md` is an auto-maintained dependency view of the pending task board, derived from the `## Dependencies` section of each `task.md` (`task.md` is the source of truth — the graph is never authoritative). `/maw-tasks` regenerates it on every task create/edit; `/maw-execute-task` reconciles it against the task files before starting and drops the started task out of the pending graph. It is a short tree of hard blockers plus a list of soft orderings and unblocks — structure only, no narrative. Optional: absence is not an error, and projects that never declare dependencies never get one.

## How it compares

The adversarial multi-agent space is growing. Several tools take different slices of the problem:

| | MAW | Claude Forge | adversarial-dev | Forge AI | adversarial-review (ng) |
|---|---|---|---|---|---|
| Approach | Sequential adversarial | GAN-style loops | GAN 3-agent harness | Competing architects + judge | Dual-agent consensus |
| Scope | Task → QA (full cycle) | Feature + audit + docs | Planning → building → eval | Planning + execution | Code review only |
| Modes | 4 (full, small-fix, brainstorm, deep-research) | brainstorm + audit | — | --fast flag | Cost-gating by diff score |
| Task management | Built-in (pending/done/blocked) | No | No | No | No |
| Provider | Claude Code | Claude Code | Claude SDK + Codex SDK | Claude/Codex/Cursor/API | Claude Code |
| Install | One curl | cp -r | git clone + pip | pip install | /plugin marketplace |

MAW's specific niche: full lifecycle with built-in task tracking and mode-based cost control. If you need only code review, ng/adversarial-review is more focused. If you need provider-agnostic planning, Forge AI is better suited.

## Cost and when to use

MAW trades tokens for reliability. Token consumption depends on mode:

| Mode | Tokens | Cost (Sonnet) |
|---|---|---|
| full | 280–560k | $1–4 |
| small-fix | 120–200k | $0.5–1.5 |
| brainstorm | 100–180k | $0.4–1.2 |
| deep-research | 80–150k | $0.3–1 |

Each agent consumes 40–70k tokens on a medium-sized codebase. Implementer and Code Review can exceed 100k on complex tasks. At Opus pricing, multiply accordingly.

The tradeoff: if the cost of shipping a bug exceeds the cost of running the pipeline, use MAW. Modes let you pick the right level of rigor per task instead of paying for the full pipeline every time.

## Settings

First run asks two things, both saved to `maw/settings.json`.

**Branching** (`worktree_mode`):

| Value | Behavior |
|---|---|
| `always` | Git worktree per task (default) |
| `never` | Feature branch only |
| `ask` | Prompt each time |

**Agent model and effort.** Every spawned agent runs on `sonnet` at `medium` effort by default. On first run MAW asks whether to keep the defaults or customize per agent. Effort is a **real Claude Code effort level** baked into each generated subagent variant (`maw-<stem>-<effort>` in `.claude/agents/`) — not a prose directive; the orchestrator selects the variant by name at spawn. Model is passed via the Task tool's `model` parameter. The higher levels (`xhigh`, `max`) require an Opus model; the orchestrator stops and asks rather than pairing them with `sonnet`/`haiku`.

```json
{
  "worktree_mode": "always",
  "agent_model": "sonnet",
  "agent_model_overrides": { "planner": "opus", "code-reviewer": "opus" },
  "agent_effort": "medium",
  "agent_effort_overrides": { "code-reviewer": "high", "qa": "high" }
}
```

Agent names: `clarifier`, `premise-challenge`, `planner`, `plan-reviewer-1`, `plan-reviewer-2`, `implementer`, `code-reviewer`, `fixer`, `qa`. Models: `sonnet`, `opus`, `haiku`. Effort: `low`, `medium`, `high`, `xhigh`, `max` (`xhigh`/`max` are Opus-only). Edit `maw/settings.json` directly to change the defaults later.

**Per-task override.** A task can override both for itself via optional `task.md` header lines, which beat `settings.json` for that task only:

```markdown
Models: default=opus, code-reviewer=opus
Effort: code-reviewer=high, qa=high
```

Each line is comma-separated tokens: `default=<v>` sets the task-wide value, `<agent>=<v>` sets one agent. When you create a task with `/maw-tasks`, MAW may itself propose reinforcing specific agents (stronger model / higher effort) for risky tasks — auth, payments, migrations, concurrency — which you confirm, edit, or decline. Resolution precedence: task.md per-agent → task.md task-wide → settings.json overrides → settings.json default → built-in (`sonnet`/`medium`).

## License

MIT
