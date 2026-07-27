# Acceptance matrix — harness-agnostic MAW (status as of 2026-07-22)

Honest status ledger. GREEN = executed on this machine (Windows 11, codex-cli 0.145.0, claude 2.1.217). RED = not yet executed — release-gating unless marked deferrable. Each row: check, how, status.

## Isolation (ship gate)

| Row | How | Status |
|---|---|---|
| codex **project**-doc suppression, repo root | canary AGENTS.md, `--ignore-user-config -c project_doc_max_bytes=0` | GREEN (NO-PROJECT-DOCS) |
| codex **user-level** doc suppression (`$CODEX_HOME/AGENTS.md`) | flags alone vs. private `CODEX_HOME` (auth.json + config.toml copied), canary asks about home-directory instructions | GREEN — flags alone LEAK (child quotes the user AGENTS.md under both `project_doc_max_bytes=0` and `--ignore-user-config`); private CODEX_HOME reports no instruction blocks at all (2026-07-27, codex 0.145) |
| private CODEX_HOME does not break workspace-write | same `workspace-write` spawn writes a file, with and without `config.toml` copied | GREEN — writes with config.toml copied; read-only rejection without it (Windows `[windows] sandbox` lost) |
| codex **host** ambient docs | no suppression mechanism exists in an interactive session | ACCEPTED BY DESIGN — host carries operator AGENTS.md; contract precedence + no-paraphrase rule in SKILL.md Hosting |
| claude project-doc suppression | canary CLAUDE.md, `--setting-sources user` | GREEN (project suppressed) |
| claude FULL isolation (user+project) via empty value | `--setting-sources ""` (sh) / `"--setting-sources="` (PS) canary | RED — equals-form parse-accepted (exit 0), canary not yet run |
| nested-directory canaries, both CLIs | canary file in a subdir of WORK_ROOT | RED |

## Transport & runner

| Row | How | Status |
|---|---|---|
| `--search` placement | `codex exec --search` rejected; `codex --search exec` accepted | GREEN |
| codex exec headless + `--json` usage event | live run, `turn.completed` parsed | GREEN |
| codex `--ephemeral` flag exists | `codex exec --help` | GREEN |
| claude `--effort`, `--no-session-persistence`, `auth status` | `claude --help` / live auth status | GREEN |
| claude -p external spawn writes artifact in WORK_ROOT (cwd correctness) | probe spawn with cd/Push-Location, worktree path | RED |
| transport probe through full runner path (temp dir + stdin + isolation + artifact) | Step 0.65 probe executed end-to-end | GREEN (live: TASK-002 resume preflight, canary NO-PROJECT-DOCS) |
| codex external spawn: artifact + usage parsing (events.jsonl) | live cross-provider stage | GREEN (live: TASK-002 PR2 — usage parsed, artifact delivered) |
| codex Windows workspace-write degradation → read-only + materialization fallback | live observation | GREEN (observed + handled live; fallback now contractual for single-artifact stages) |
| per-role capability profiles (review-only / implement / research / QA) under real parent sandbox | prototype spawns per role class | RED |
| timeout kill + cleanup on success/failure/timeout/cancel | forced-timeout test | RED |
| PowerShell stdin/CRLF/UTF-8 through both pipes | canary with non-ASCII content | RED |

## Metrics

| Row | How | Status |
|---|---|---|
| codex usage arithmetic (cached/reasoning are subsets) | fixture from live `turn.completed` + vendor issues | GREEN (rule encoded; verify on next live run) |
| claude -p JSON usage field mapping | success + failure fixtures | RED (columns stay n/a until green) |

## Install

| Row | How | Status |
|---|---|---|
| sh -n install.sh | syntax pass | GREEN |
| layout matches SKILL.md expectations (agents/<stem>.md beside SKILL.md) | reviewed statically by Codex | GREEN |
| counts (3 skills, 9 bodies, 45 variants) | static check | GREEN |
| idempotent re-run, fetch-failure rollback, interruption | live installer runs in a scratch repo | RED |
| `.agents/skills` discovery by installed codex | install into a test repo, invoke skill | GREEN (live: TASK-004 — codex host read and executed both maw-tasks and maw-execute-task skills) |
| shared SKILL.md frontmatter loads in both harnesses | same test repo | GREEN (live: same files driven by both hosts across TASK-001..004) |
| Codex-hosted full pipeline E2E (deep-research) | live run | GREEN (live: TASK-004 — 4 stages, cross-vendor chain, materialization mode, per-provider metrics; Windows requires sandbox-off host, see Hosting) |
| claude -p as external provider under a Codex host | live run | GREEN (live: TASK-004 planner = fable/high via claude -p, 12m48s; usage columns n/a pending fixture) |
| nested codex read-only degradation + sandbox-user auth wall documented | live observations | GREEN (contract: materialization mode + sandbox-off hosting requirement) |
| install.ps1 twin | not shipped (documented: use Git Bash) | DEFERRED by decision |

## State machine

| Row | How | Status |
|---|---|---|
| Windows-native (PowerShell host) full lifecycle pending→in_progress→done|blocked, both persistence modes × branch/worktree, paths with spaces | E2E run under Codex host | PARTIAL — git-tracked × branch-only GREEN (live test-bed on Windows, claude -p host: TASK-001 small-fix incl. QA retry, TASK-002 deep-research incl. cross-provider stage); worktree, local-only, spaces, Codex host all RED |
| local-only + worktree copy-back on done/blocked | E2E | RED (rule now specified in Step 10) |
| mode-slice grid (4 modes × 2 persistence × worktree/branch) | E2E matrix | RED (small-fix and deep-research covered on git-tracked × branch-only only) |
| deep-research TASK_FINAL fallback | single deep-research run | GREEN (live: TASK-002 — orchestrator wrote TASK_FINAL.md on mode-gate skip, reviewers consumed it) |

RED rows are the work queue for the verification phase; none of the cross-provider or Codex-host paths should be advertised as production-ready until their rows are green. Two RED rows also touch the Claude-native path: the deep-research `TASK_FINAL.md` fallback and the local-only+worktree copy-back are newly specified rules that need one E2E run each; the rest of the native path's mechanics are unchanged.
