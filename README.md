<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo/maw-lockup-dark.png">
    <img src="assets/logo/maw-lockup-light.png" alt="MAW logo" width="360">
  </picture>
</p>

# MAW — Multi-Agent Workflow for Claude Code & Codex CLI

**Prompt rules tell an LLM what to do. MAW adds a verification layer for when it doesn't listen.**

MAW is a set of skills that runs a coding task through a chain of independent agents. Each agent checks the previous one's work against the actual code, not against its summary, and assumes the previous agent made mistakes. It complements prompt guidelines like Karpathy's rather than replacing them: it catches what slips through despite the rules.

| Approach | How it works | Failure mode |
|---|---|---|
| Prompt rules | Tell the agent "be careful" | The agent drifts from the rules under complex context |
| Self-review | The agent checks its own work | The blind spots that caused the error review the error |
| **MAW** | Independent agents verify against the code | Reviewers share no conversation with the author and check the code itself |

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/pockerhead/maw/main/install.sh | sh
```

The installer finds `claude` and `codex` and sets MAW up for each one it finds. On Windows, run it from Git Bash. **Restart the harness afterwards**: skills and subagents are only picked up at session start.

For Claude Code, add the skills to your project's `CLAUDE.md`:

```markdown
## Skills
@.claude/skills/maw-execute-task/SKILL.md
@.claude/skills/maw-tasks/SKILL.md
@.claude/skills/maw-context/SKILL.md
```

Then describe the work and run it:

```
/maw-tasks "fix 404 on the profile page"   # MAW suggests a mode, you confirm
/maw-execute-task                          # runs the highest-priority pending task
```

Codex has no custom slash commands, so ask in words: "run maw-execute-task for task 3".

Install flags, upgrades and Windows notes: [docs/INSTALL.md](docs/INSTALL.md). Every command and flag: [docs/USAGE.md](docs/USAGE.md).

## How it works

![MAW pipeline architecture](assets/maw_pipeline_architecture.svg)

- **Fresh agents.** No conversation history crosses a stage. Evidence travels through the task folder.
- **Adversarial by default.** Every agent assumes the previous one was unreliable. Skeptical, not hostile.
- **Premise challenge.** Before planning, an isolated agent checks whether the task's premise itself is wrong, and stops for a human if it is.
- **Tasks are folders.** Status is the folder a task sits in: `pending/`, `in_progress/`, `done/` or `blocked/`. Work happens on a feature branch or a git worktree.

Design details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Modes

Not every task needs the whole pipeline.

| Mode | Stages | Use for | Tokens | Cost (Sonnet) |
|---|---|---|---|---|
| `full` | Clarifier → Premise Challenge → Planner → Plan Review ×2 → Implementer → Code Review → Fixer → QA | Features, migrations, auth, payments | 280–560k | $1–4 |
| `small-fix` | Implementer → Code Review → Fixer → QA | Bug fixes with a clear scope | 120–200k | $0.5–1.5 |
| `brainstorm` | Clarifier → Premise Challenge → Planner → Plan Review ×2 | Exploring approaches before writing code | 100–180k | $0.4–1.2 |
| `deep-research` | Premise Challenge → Planner (web search) → Plan Review ×2 | Comparing solutions, auditing approaches | 80–150k | $0.3–1 |

The rule of thumb: if shipping a bug costs more than running the pipeline, use MAW. Opus costs more; Codex stages are billed by your Codex plan. Cost details: [docs/USAGE.md](docs/USAGE.md#cost).

## What you get

Every run leaves an audit trail in the task folder:

```
maw/tasks/done/TASK-001/
├── TASK_FINAL.md          clarified requirements
├── PREMISE_CHALLENGE.md   premise audit
├── PLAN_FINAL.md          plan after two reviews
├── IMPL_SUMMARY.md        what was implemented
├── IMPL_REVIEW.md         code review findings
├── FIX_SUMMARY.md         what was fixed
├── QA_REPORT.md           test results
└── metrics.md             tokens, tool uses and time per agent
```

The full list for each mode: [docs/USAGE.md](docs/USAGE.md#what-gets-produced).

## Any stage on Claude or Codex

Each stage can have its own provider, model and effort. For example, code review on Codex while everything else runs on Claude: a reviewer from another vendor has different blind spots.

```json
{
  "agents": {
    "code-reviewer": { "provider": "codex", "model": "gpt-6.1-sol", "effort": "xhigh" }
  }
}
```

An invalid model and effort pair stops the run instead of being silently downgraded. The cross-provider path is still experimental. All settings: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## More skills

- **`/maw-selfreview`**: a one-stage review of your own staged diff by a different vendor, fired by a pre-commit gate. Claude Code only. [docs/SELFREVIEW.md](docs/SELFREVIEW.md)
- **`/maw-reason`** (experimental): adversarial deliberation over a question rather than a task. Five isolated roles end in a synthesis with an explicit disagreement ledger. Claude Code only. [docs/REASON.md](docs/REASON.md)
- **`/maw-context`**: optional project knowledge (invariants, domains, tooling) injected into the agents. [docs/PROJECT_CONTEXT.md](docs/PROJECT_CONTEXT.md)

## What has been measured

Numbers from real use, with their caveats in [docs/RESULTS.md](docs/RESULTS.md):

- **A review stage objected in 39.3% of tasks** where one returned a verdict (70 of 178).
- **The fixer needed a second round in 5.3% of tasks** (9 of 169), so review rarely turns into a loop.
- **SWE-bench Multilingual: 7 resolved out of 12 instances run**, on Sonnet in `small-fix` mode. There is no same-model single-agent baseline, so this is a data point, not a claim of superiority.
- **15.3% of tasks had at least one spawn die** without a verdict (API errors, timeouts, kills).

## How it compares

| | MAW | Claude Forge | adversarial-dev | Forge AI | adversarial-review (ng) |
|---|---|---|---|---|---|
| Approach | Sequential adversarial | GAN-style loops | GAN 3-agent harness | Competing architects + judge | Dual-agent consensus |
| Scope | Task → QA (full cycle) | Feature + audit + docs | Planning → building → eval | Planning + execution | Code review only |
| Modes | 4 (full, small-fix, brainstorm, deep-research) | brainstorm + audit | — | --fast flag | Cost-gating by diff score |
| Task management | Built-in (pending/done/blocked) | No | No | No | No |
| Provider | Claude Code + Codex CLI (per-stage) | Claude Code | Claude SDK + Codex SDK | Claude/Codex/Cursor/API | Claude Code |
| Install | One curl | cp -r | git clone + pip | pip install | /plugin marketplace |

MAW's niche is the full lifecycle with built-in task tracking, mode-based cost control and per-stage providers. If you only need code review, ng/adversarial-review is more focused.

## License

MIT

<!-- one more line -->

<!-- x -->
