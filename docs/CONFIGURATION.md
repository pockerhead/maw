# Configuration

First run asks two things, both saved to `maw/settings.json`.

**Branching** (`worktree_mode`):

| Value | Behavior |
|---|---|
| `always` | Git worktree per task (default) |
| `never` | Feature branch only |
| `ask` | Prompt each time |

**Agent provider, model, and effort.** Every agent resolves an atomic profile `(provider, model, effort)`. Zero-config default: every agent runs on the host harness's provider with that provider's defaults (`claude: sonnet/medium`, `codex: gpt-6.1-sol/medium`). On the Claude-native path, effort is a **real Claude Code effort level** baked into each generated subagent variant (`maw-<stem>-<effort>` in `.claude/agents/`) and model is the Task tool's `model` parameter; on the external path (cross-provider stages, or a Codex host) both are CLI flags on a one-shot headless spawn.

```json
{
  "worktree_mode": "always",
  "default_provider": "host",
  "providers": {
    "claude": { "default_model": "sonnet",      "default_effort": "medium" },
    "codex":  { "default_model": "gpt-6.1-sol", "default_effort": "medium" }
  },
  "agents": {
    "code-reviewer": { "provider": "codex", "model": "gpt-6.1-sol", "effort": "xhigh" },
    "planner":       { "model": "opus" }
  }
}
```

(Legacy v1 settings — `agent_model`/`agent_effort` + override maps — are migrated automatically on first run, preserving behavior. Other keys: `spawn_timeout_min` — wall-clock cap per external spawn, default 30; `allow_unverified_profile` — pass unknown models through with a warning instead of rejecting, default false; `auto_invoke_guard` — per-skill map gating model-chosen invocation, e.g. `{ "maw-execute-task": true }`, values `true` (confirm first, default when absent) | `false` (unattended) | `"never"` (decline).)

**Spending fewer tokens.** Two optional keys, both default `true`:

```json
{ "shared_memory": false, "runner_progress": false }
```

`shared_memory: false` turns off `transcripts/`, `scratch/`, and `log.jsonl` for the whole run: nothing is scaffolded or harvested, the log is not validated, and every stage gets a one-line "disabled" notice instead of the shared-memory block. Stages go back to seeing only the task artifacts, so a fixer or QA no longer learns what earlier stages already tried. `runner_progress: false` makes the external runner print only its start and exit lines; the full event stream is still captured to disk.

Agent names: `clarifier`, `premise-challenge`, `planner`, `plan-reviewer-1`, `plan-reviewer-2`, `implementer`, `code-reviewer`, `fixer`, `qa`. Models are provider-scoped — claude: `sonnet`, `opus`, `haiku`, `fable`; codex: `gpt-6-astra` (OpenAI premium tier), `gpt-6.1-sol`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5` (retires 2026-10-14). Effort: `low`, `medium`, `high`, `xhigh`, `max` (plus `ultra` on codex Astra, the Sol models, and `gpt-5.6-terra`; never Luna). Effort validity depends on the model (claude `haiku` caps at `high`; codex `gpt-5.5` caps at `xhigh`) — the orchestrator clamps against its versioned capability catalog and **stops with a report on an invalid pair; nothing silently downgrades**. Edit `maw/settings.json` directly to change the defaults later.

**Cross-provider agents (experimental).** Any pipeline stage can run on a different harness than the orchestrator — e.g. code review on Codex while everything else runs on Claude. A cross-vendor reviewer brings a genuinely different prior, so its blind spots correlate less with the implementer's. External spawns are one-shot headless CLI runs with ambient-context isolation (the child loads neither the project's AGENTS.md/CLAUDE.md nor your personal one — for codex that takes a private per-spawn `CODEX_HOME` holding only a copy of `auth.json`, since no CLI flag suppresses `~/.codex/AGENTS.md`; suppression is canary-tested per machine as part of preflight), a fresh context, and per-spawn usage accounting where the CLI provides it (codex: yes; claude external: pending fixture — recorded as `n/a` until then). The external path uses the installed `maw-execute-task/scripts/runner.sh` to capture output and show live event/tool-call activity. It uses POSIX sh and standard shell utilities (Git Bash on Windows), with no extra language runtime or platform binaries. The host still owns process-tree timeouts, JSON validation, and transcript retention. Requirements: the other CLI installed and logged in; the orchestrator preflights binary, auth, and a transport probe before a task leaves `pending/`. Token subtotals in `metrics.md` are per-provider — cross-provider counts are never summed (different tokenizers). **Status:** the cross-provider and Codex-host paths are experimental until the acceptance checklist in [ACCEPTANCE.md](ACCEPTANCE.md) is green. Newly specified native shared-memory mechanisms—transcript harvest and `SendMessage` continuation—also remain RED until live runs exercise them, alongside the existing deep-research fallback and local-only worktree copy-back rows.

`gpt-6-astra` is the OpenAI premium option; selecting it at any effort uses the existing one-time premium-cost confirmation, as do Claude `fable` and Codex `ultra`. A profile already approved for this task does not require another confirmation. The default is `gpt-6.1-sol/medium`; it needs codex CLI ≥ 0.159.1. On an older CLI, update it or set `gpt-6-sol` explicitly.

**Per-task override.** A task can override all three via optional `task.md` header lines, which beat `settings.json` for that task only:

```markdown
Providers: code-reviewer=codex
Models: default=opus, code-reviewer=gpt-6.1-sol
Effort: code-reviewer=xhigh, qa=high
```

Each line is comma-separated tokens: `default=<v>` sets the task-wide value, `<agent>=<v>` sets one agent. An explicit per-agent value that contradicts the resolved provider (e.g. `Providers: code-reviewer=codex` + `Models: code-reviewer=opus`) is a hard stop, not a silent substitution; inherited task-wide values simply don't apply to agents on another provider. When you create a task with `/maw-tasks`, MAW may itself propose reinforcing specific agents (stronger model / higher effort / cross-provider review) for risky tasks — auth, payments, migrations, concurrency — which you confirm, edit, or decline. Resolution precedence: task.md per-agent → task.md task-wide → settings.json `agents` → settings.json defaults → built-in.

Back to the [README](../README.md).
