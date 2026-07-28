# Acceptance matrix — harness-agnostic MAW (status as of 2026-07-22)

Honest status ledger. GREEN = executed on this machine (Windows 11, codex-cli 0.145.0, claude 2.1.217). RED = not yet executed — release-gating unless marked deferrable. Each row: check, how, status.

## Isolation (ship gate)

| Row | How | Status |
|---|---|---|
| codex **project**-doc suppression, repo root | canary AGENTS.md, `--ignore-user-config -c project_doc_max_bytes=0` | GREEN (NO-PROJECT-DOCS) |
| codex **user-level** doc suppression (`$CODEX_HOME/AGENTS.md`) | flags alone vs. private `CODEX_HOME` (auth.json only), canary asks about home-directory instructions | GREEN — flags alone LEAK (child quotes the user AGENTS.md under both `project_doc_max_bytes=0` and `--ignore-user-config`); private CODEX_HOME reports `NONE` (2026-07-27, re-verified auth.json-only 2026-07-28, codex 0.145) |
| private CODEX_HOME does not break workspace-write | `workspace-write` spawn writes an in-workspace file from an auth.json-only home | GREEN — writes with `-c windows.sandbox="unelevated"` on the command line; no `config.toml` copy needed (2026-07-28) |
| write-refusal cause matrix (retires the "Windows degrades to read-only" claim) | one variable at a time on an **untrusted** path, private home: `--ignore-user-config` × `[projects.*] trust_level` × `[windows] sandbox` | GREEN — `[windows] sandbox` is the only gate (untrusted+key → writes; trusted+no key → refused); `--ignore-user-config` breaks writes only by discarding that key, and `-c windows.sandbox=…` restores them with the flag kept (2026-07-28) |
| out-of-workspace write is refused by design | same spawn, target in `$SPAWN_TMP` vs. in cwd | GREEN — temp-dir target refused (`Unable to write outside the permitted workspace`), in-workspace target written; the old probe wrote to the temp dir and so failed unconditionally (2026-07-28) |
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
| ~~codex Windows workspace-write degradation → read-only~~ | live observation | **RETRACTED 2026-07-28** — misdiagnosis. The refusals came from an out-of-workspace probe target and an unset `windows.sandbox`; see the two isolation rows above. Materialization remains contractual but as a fallback for genuinely read-only environments, not as the Windows norm |
| codex writes on Windows through the corrected invocation (implementer/fixer viable) | `workspace-write` spawn, private home, `-c windows.sandbox="unelevated"`, in-workspace target | GREEN (2026-07-28) — both `unelevated` and `elevated` write successfully |
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
| counts (3 shared skills + maw-reason on claude, 9 + 6 bodies, 75 variants) | static check | GREEN (2026-07-28) |
| `--with-hooks` arg parsing (multi-flag loop, ignored without --claude, unknown flag) | live installer invocations | GREEN (2026-07-28) |
| idempotent re-run, fetch-failure rollback, interruption | live installer runs in a scratch repo | RED |
| `.agents/skills` discovery by installed codex | install into a test repo, invoke skill | GREEN (live: TASK-004 — codex host read and executed both maw-tasks and maw-execute-task skills) |
| shared SKILL.md frontmatter loads in both harnesses | same test repo | GREEN (live: same files driven by both hosts across TASK-001..004) |
| Codex-hosted full pipeline E2E (deep-research) | live run | GREEN (live: TASK-004 — 4 stages, cross-vendor chain, materialization mode, per-provider metrics; Windows requires sandbox-off host, see Hosting) |
| claude -p as external provider under a Codex host | live run | GREEN (live: TASK-004 planner = fable/high via claude -p, 12m48s; usage columns n/a pending fixture) |
| sandboxed-Codex-host auth wall documented | live observation | GREEN (contract: sandbox-off hosting requirement on Windows). The "nested codex read-only degradation" half of this row is **RETRACTED 2026-07-28** — see the write-refusal cause matrix; the credential finding is unaffected |
| Codex-hosted E2E re-run under the corrected invocation (writing stages on codex) | live run of a mode that reaches implementer/fixer | RED — TASK-004 predates the fix and ran single-artifact stages only |
| install.ps1 twin | not shipped (documented: use Git Bash) | DEFERRED by decision |

## maw-reason (experimental, Claude Code only)

Reviewed adversarially by Codex on 2026-07-28 (`.brainstorm/CODEX_REASON_V1_REVIEW.md`): verdict NO-GO, 1 blocker + 17 major. The blocker and every gate/consistency finding are fixed below; the trust-boundary findings were resolved by narrowing the claim rather than by new enforcement.

| Row | How | Status |
|---|---|---|
| **B1** external role writes to an out-of-repo run dir | live `claude -p`, `acceptEdits`, cwd at repo, target in temp | GREEN (2026-07-28) — refused without `--add-dir` ("I don't have permission to write outside the project directory"), writes with it. `--add-dir "$RUN_DIR"` is now mandatory on every role spawn, and the preflight canary writes into the run dir instead of the workspace |
| subagent can spawn external CLIs | docs + Codex cross-check | GREEN — `Bash` survives both subagent tool filters; `Agent` does not, so nested subagents are impossible and the external runner is the only path (this is why the design uses it) |
| gate hook branch coverage | 14 live invocations incl. forged ledger, duplicate stems, empty CHAIN_FAILURE, equal mtimes, manifest mismatch, unset CLAUDE_PROJECT_DIR | GREEN (2026-07-28) |
| gate: forged-ledger resistance | 5 lines containing `"stem"` only; 5 duplicate stems | GREEN — both blocked; a record now needs stem + `exit:0` + `fresh:true`, and all five distinct stems must appear |
| gate: topology awareness | manifest claiming 6 spawns against a 5-spawn ledger | GREEN — blocked; gate reads `RUN.json` rather than assuming the default |
| gate: no permanent bypass | `.gate-cleared` removed; enforcement keyed to `maw/.reason-active` | GREEN — a finished run is silent, a stale pointer from an old session no longer blocks |
| gate blocks via exit 2 + stderr, not JSON | Windows run paths contain backslashes; sh-side JSON escaping broke on them (observed) | GREEN (2026-07-28) |
| gate hook auto-wiring into settings.json, **without jq** | 4 live cases: no settings file, rerun, existing file with an unrelated Stop hook, rerun on existing | GREEN (2026-07-28) — cascade is write-whole-file → already-wired → jq → Python; other keys preserved, idempotent (no duplicate entries) |
| same wiring via the `jq` branch | — | RED — unverified, `jq` is absent on this machine; the Python branch covers it here |
| skill install without jq | `--with-reason` on a machine with no jq | GREEN — jq was only ever needed for hook wiring; skill, role bodies, and subagents are plain copies |
| gate hook wired into a real session and observed blocking a turn | live | GREEN (2026-07-28) — fired for real during the first chain launch, with the intended message |
| gate hook must not block sessions that did not start the chain | live | **Defect found and fixed 2026-07-28.** A second session in the same repo could not end its turn while a chain ran in the first. `maw/.reason-active` now carries `session=$CLAUDE_CODE_SESSION_ID`; the hook enforces only for the owning session and fails open when the line is absent. Re-verified as silent for a non-owning session; owning-session enforcement RED until the next run |
| chain E2E: real spawns, artifacts pass their contracts | live run `m9ADwC` (self-referential question, trace kept) | GREEN (2026-07-28) — 6 successful spawns (5 roles + one compressor retry), every artifact met its contract, gate passed silently at the end |
| self-referential first run ("what is wrong with maw-reason") | live run, output reviewed | GREEN (2026-07-28) — produced findings absent from both the Codex review and the caller position, incl. an off-vector discovery that the installed `.claude/` copy had diverged from HEAD |
| caller-position isolation (attacker sees it, others do not) | `SPAWNS.jsonl` `inputs` per role, plus phrase-level grep of every artifact | GREEN **with a caught violation** — final ledger shows `CALLER_POSITION.md` only in the attacker's inputs, and no caller phrasing leaked into other artifacts. But compressor attempt 1 self-reported reading `CALLER_POSITION.md`, `FACTS.md`, `CONSTRAINTS.md` outside its allowlist; the coordinator discarded that claim map and respawned the role. Isolation held **because it was policed**, not because it was enforced |
| depth-1 guard refuses a nested chain | live nested invocation; guard is the `maw/.reason-active` file (Task tool has no env field) | RED |
| coordinator re-derives the independence label instead of trusting it | live | GREEN (2026-07-28) — ledger records the derivation and its basis, not just the label |
| seeded role assignment | live | GREEN (2026-07-28) — `seed 1477492483`, `mod 2 = 1`, generator→codex / compressor+attacker→claude, arithmetic recorded in the ledger. Opposite-orientation and `--seed` reproduction runs still RED |
| `--high-assurance` refuses a single-profile run | invoke with only one eligible profile | RED |
| `deep` (default) vs `--fast` output quality | same question at both profiles, compared | RED |
| premise halt: `QUESTION SUSPECT` stops the chain | live run on a deliberately mis-posed question | RED — this run returned `WELL-POSED` (correctly, with cited reasoning), so the halt branch never executed |
| gate accepts a premise halt only with real evidence | 5 live cases: halt without PREMISE.md, without a spawn record, empty HALTED.md, legitimate halt, unrelated incomplete chain | GREEN (2026-07-28) |
| cost range 200–350k | metrics from real runs | RED — **and blocked by a defect**: `usage` is `{}` on every ledger line, so nothing was measured. Rough reconstruction from artifact volume and input material puts run `m9ADwC` at 150–280k, consistent with the published range |

### Defects found by the first live run (all open)

| Defect | Evidence | Severity |
|---|---|---|
| `inputs` are recorded, never enforced against a per-role allowlist | compressor attempt 1 read three files outside its scope and was only caught because it said so | high — this is the chain's central claim |
| ~~requested effort does not reach the transport~~ | measured 2026-07-28: claude `low`=218 vs `max`=1034 output tokens; codex rejects an invalid effort value, so the key is parsed | **RETRACTED** — the run's synthesis inferred this without transport visibility. Effort is applied. Replaced by the row below |
| codex effort is flat across low→high | measured: `gpt-5.6-sol` reasoning tokens 510 (low) / 516 (high) / 1552 (xhigh), single sample each | medium — `fast` vs `deep` barely moves a codex role; documented, needs `xhigh` to bite |
| `usage` never populated | every ledger line has `usage: {}` | **fixed 2026-07-28** — coordinator must parse provider usage and write `{"parse_failed":true}` rather than `{}` |
| repo changes attributed to roles without proof, then reverted with `git checkout` | two `contract_violation` records blamed the generator for edits made by a human in another session; a third invented a plausible story about a role applying a patch from the run dir | **fixed 2026-07-28** — coordinator is now absolutely forbidden from modifying the working tree, including to "restore" it; unattributed diffs are logged as `observation`, remediation is a human's call |
| gate counts a `contract_violation` line as role presence | that line carries `"stem":"<role>"`, which satisfied the distinct-stem check | **fixed 2026-07-28** — distinct-stem check now runs only over records with `exit:0` and `fresh:true`; verified live that a role named solely in an incident record is blocked |
| installed copy can lag HEAD silently | the chain's own attacker found `.claude/` running `fast` and lacking `HALTED.md` handling | fixed — `install.sh` now installs from the working copy when run inside a checkout |

## State machine

| Row | How | Status |
|---|---|---|
| Windows-native (PowerShell host) full lifecycle pending→in_progress→done|blocked, both persistence modes × branch/worktree, paths with spaces | E2E run under Codex host | PARTIAL — git-tracked × branch-only GREEN (live test-bed on Windows, claude -p host: TASK-001 small-fix incl. QA retry, TASK-002 deep-research incl. cross-provider stage); worktree, local-only, spaces, Codex host all RED |
| local-only + worktree copy-back on done/blocked | E2E | RED (rule now specified in Step 10) |
| mode-slice grid (4 modes × 2 persistence × worktree/branch) | E2E matrix | RED (small-fix and deep-research covered on git-tracked × branch-only only) |
| deep-research TASK_FINAL fallback | single deep-research run | GREEN (live: TASK-002 — orchestrator wrote TASK_FINAL.md on mode-gate skip, reviewers consumed it) |

RED rows are the work queue for the verification phase; none of the cross-provider or Codex-host paths should be advertised as production-ready until their rows are green. Two RED rows also touch the Claude-native path: the deep-research `TASK_FINAL.md` fallback and the local-only+worktree copy-back are newly specified rules that need one E2E run each; the rest of the native path's mechanics are unchanged.
