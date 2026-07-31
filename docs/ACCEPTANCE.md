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
| PowerShell stdin/CRLF/UTF-8 through both pipes | canary with non-ASCII content | RED for PowerShell specifically, but the **Git Bash case is now measured**: shell redirection encodes the prompt in the console codepage (cp1251 here) and corrupts non-ASCII before the spawn. `codex exec` rejects it (`input is not valid UTF-8, invalid byte at offset N`); `claude -p` accepts the corrupted text silently. Contract now requires writing the prompt file with an explicit UTF-8 encoder (2026-07-29) |

## Metrics

| Row | How | Status |
|---|---|---|
| codex usage arithmetic (cached/reasoning are subsets) | fixture from live `turn.completed` + vendor issues | GREEN (rule encoded; verify on next live run) |
| claude -p JSON usage field mapping | success + failure fixtures | RED (columns stay n/a until green) |
| `maw-execute-task` outcome quality on a held-out benchmark | SWE-bench Multilingual, 70-instance stratified subset, gold patches held out of the solver's view, deterministic leak audit (HEAD == base_commit, single reachable commit, no remote refs) | PARTIAL — **7 resolved / 12 actually run**; the other 58 subset instances produced empty patches and were never attempted. All on `claude-sonnet-4-6`, effort medium, `small-fix` mode, ~4 spawns and ~$3.8 per instance. **No same-model single-agent baseline was run**, so the figure has nothing to be compared against; Sonnet does not appear on the benchmark's leaderboard either. Harness lives outside this repo (2026-07-31) |
| `maw-execute-task` process behaviour on the live corpus | a local collector (not in this repo — `tools/` is gitignored) over 6 projects, 340 done task folders, 235 with a parseable `metrics.md` ledger; see `docs/PROCESS_METRICS.md` | GREEN as a measurement, and it is a measurement of process, not of correctness — no ground truth is involved. Headline, all rates conditional on the stage having returned a verdict: a reviewing stage objected in **39.3%** (70/178; over the whole 235-task ledgered corpus that is 29.8%), code review 34.8% (62/178), QA 12.1% (20/165), the fixer needed a second round in only **5.3%** (9/169), and the premise challenge rejected the premise in **22.7%** (48/211). Classifier coverage 91.8% of 1757 ledger rows (2026-07-31) |
| transport reliability under real load | same collector, INFRA outcomes counted separately from verdicts | RED — **15.3%** of ledgered tasks contain at least one spawn that died without returning a verdict (API 529, stream timeout, operator kill, no output). First reported here as 29.4%, which was wrong: the classifier matched `pending` as INFRA before it could match `SHIP-PENDING-RUNTIME` as a human gate, so a game project's normal QA verdict was scored as a dead spawn. This is a floor: a spawn that died before its ledger row was written leaves no trace at all (2026-07-31) |
| QA autonomy differs sharply between the two projects large enough to compare | per-project split in the same collector; `SHIP_PENDING_HUMAN` classified separately from `SHIP` | GREEN **as an observation on two projects**, not as a general law. Backend project (78 ledgered tasks): QA reached SHIP in **94.1%** with a **0%** human gate. Game project (154): QA closed **36.5%** by itself and handed **60.4%** to a person (`SHIP-PENDING-RUNTIME` and variants). Code review objected at a similar rate in both (33.8% vs 35.8%). The obvious reading — that a game's feel, timing and visuals are not headless-checkable, so the ceiling is set by subject matter rather than by pipeline quality — is **a hypothesis this data is consistent with, not one it establishes**: n=2 projects, no ground truth, no controlled variation, and similar review rates do not by themselves rule out other causes. The four other projects have too few ledgered tasks to compare (2026-07-31) |
| do closed tasks leave repair traffic behind? | a local commit-linkage script (not in this repo — `tools/` is gitignored) over 2 repos, 2859 commits; first later task to touch a task's non-magnet files, ordered by when the candidate FIRST touched anything, compared against the repo's base rate of `Type: bugfix` tasks | GREEN as a null result — lift **1.02x** (p=0.93) and **1.20x** (p=0.24); neither is distinguishable from the base rate at these sample sizes. No detectable clustering of repair behind shipped work. This is an underpowered non-rejection, not evidence of absence: the 1.20x would need roughly 4x the sample to be called either way. An earlier revision reported 0.89x/1.03x from a successor rule that ranked candidates by their LAST commit, which let a task that started before the subject be scored as its successor (2026-07-31) |
| `maw-context` overlay: does it improve outcomes? | — | RED — still no rows and no controlled comparison. `docs/PROJECT_CONTEXT_FIELD_NOTES.md` documents what two production overlays contain and how they were built, which is description, not evidence (2026-07-31) |

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
| coordinator re-derives the independence label instead of trusting it | live, on a genuinely mislabelled run | GREEN (2026-07-28) — the caller wrote `conforming` into RUN.json; the coordinator overwrote it with `reduced-independence` and the reason (compressor and attacker resolved to an identical profile). It fired against the caller, not a hypothetical adversary |
| `conforming` is reachable with two providers | — | **NO — documentation defect found 2026-07-28.** All three of generator/compressor/attacker must be distinct profiles. With two providers and one effort pinned per role, compressor and attacker collapse onto the same tuple and every run is `reduced-independence`. SKILL.md implies two providers suffice; a third distinct profile (different model or effort) is required |
| seeded role assignment | live | GREEN (2026-07-28) — `seed 1477492483`, `mod 2 = 1`, generator→codex / compressor+attacker→claude, arithmetic recorded in the ledger. Opposite-orientation and `--seed` reproduction runs still RED |
| `--high-assurance` refuses a single-profile run | invoke with only one eligible profile | RED |
| `deep` (default) vs `--fast` output quality | same question at both profiles, compared | RED |
| premise halt: `QUESTION SUSPECT` stops the chain | live run `213319` | GREEN (2026-07-28) — fired on its first real opportunity, on a question that was *not* deliberately mis-posed. The verdict was substantive: the question asked how to validate the coordinator's **declared** inputs — the very artifact the contract calls untrusted — while excluding the cell mechanism the repo already runs. Chain stopped after 1 spawn of 5 |
| gate accepts a premise halt only with real evidence | 5 live cases: halt without PREMISE.md, without a spawn record, empty HALTED.md, legitimate halt, unrelated incomplete chain | GREEN (2026-07-28) |
| **MMLU-Pro pilot vs single-agent baselines** | 8 items, 3 conditions (cot / self-consistency×5 / heterogeneous chain), M3MAD-Bench protocol, trace in `.brainstorm/bench-mmlupro/` | **NO MEASURED ADVANTAGE (2026-07-29).** chain 8/8, cot 7/8, sc5 7/8 — exact McNemar p=1.000 against both, CIs overlap. Chain cost 6.6× cot and 2.8× sc5, the latter inside the 2.1–3.4× multiplier the literature reports. 7 of 8 items unanimous, so the topology bought nothing on 88% of the sample. One item (q6) had both baselines wrong in different directions and the chain right, with the attacker breaking 2 claims — suggestive, not evidence |
| **hard-set comparison: chain vs single-check variants** | 220 items screened with claude/opus/low (89.5% baseline, near the 91.6% public ceiling); the 23 it failed became the test set, every condition starting at 0/23. Trace in `.brainstorm/bench-hardset/` | **GREEN, and the first significant result (2026-07-30).** chain 8/23 (35%), critic-with-arbiter 2/23, critic-with-author 1/23. Exact McNemar chain vs critic: 7 chain-only, 0 critic-only, **p = 0.0156**; vs arbiter p = 0.0703. Cost $7.90 vs $1.22 |
| critic does not damage correct answers | 23 control items the baseline already got right | GREEN (2026-07-30) — **0/23 broken**. Two objections raised there, both rejected by the model, correct answers kept. False-objection rate 8.7% |
| damage-control arm for the **chain** | same control items, chain instead of critic | RED — the chain is measured on gain only, so its 8/23 is not yet comparable to the critic's 1/23 on equal terms |
| answer key unreachable from role sandboxes | move the harness out of OS temp; grader reads ground truth separately | RED — no cheating occurred (`num_turns==1` on all 77 claude calls, no file access in codex events) but the key was readable in principle |
| cost range 200–350k | metrics from real runs | RED — **and blocked by a defect**: `usage` is `{}` on every ledger line, so nothing was measured. Rough reconstruction from artifact volume and input material puts run `m9ADwC` at 150–280k, consistent with the published range |

### Defects found by the second live run (`213319`)

| Defect | Evidence | Status |
|---|---|---|
| gate blocks the owning session for the entire run | a backgrounded coordinator left its caller unable to end any turn while the chain legitimately worked | **fixed 2026-07-28** — the gate now treats a run dir touched within an idle window (default 420s, `MAW_REASON_IDLE_SECONDS`) as in progress and defers enforcement to a later turn. Abandoned runs still block |
| halt recorded as a ledger event but not as `HALTED.md` | run `213319` has `{"event":"halt"}` and no file; the gate looks for the file | **fixed 2026-07-28** — coordinator body now states the file is required and the ledger event is not a substitute |
| per-role `cell/` directories were not created | no `cell/` in the run dir, though the coordinator otherwise used the current body (it parsed usage and honoured the premise halt, both added the same day) | RED — cause unclear: either the cell step was skipped or the body was partially stale. Needs a clean-session run to separate the two |
| Skill tool served a stale skill body mid-session | after reinstalling from the working copy, the disk copy had the new run-dir rule while the Skill invocation returned the previous revision | RED — reinstalling mid-session updates the disk, not the session. Install output should say so |

### Defects found by the first live run

| Defect | Evidence | Severity |
|---|---|---|
| `inputs` are recorded, never enforced against a per-role allowlist | compressor attempt 1 read three files outside its scope and was only caught because it said so | high — this is the chain's central claim |
| ~~requested effort does not reach the transport~~ | measured 2026-07-28: claude `low`=218 vs `max`=1034 output tokens; codex rejects an invalid effort value, so the key is parsed | **PARTLY RETRACTED** — the flag works in isolation, so the synthesis's claim was inference without transport visibility. But measuring the flag does not prove the coordinator passed it in that run, and no argv is recorded in the ledger. Both claim and retraction remain unproven for run `m9ADwC`; only the general capability is established |
| codex effort may be flat across low→high | `gpt-5.6-sol` reasoning tokens 510 (low) / 516 (high) / 1552 (xhigh) — **one task, one draw per level**, and the claude row counts output tokens while this one counts reasoning tokens | RED as a measurement — a smoke test, not a response curve; cannot separate a flat band from variance. Documented as a suggestion with the caveat attached |
| **input scoping is voided by the OS temp tree** | live: role granted `--add-dir` to a cell read a sibling file anyway when the run dir was under temp; the same layout outside temp refused the read (`"you haven't granted it yet"`); home and Desktop refused throughout | **root cause of the compressor violation, fixed 2026-07-28** — run dir moves to `~/.maw/reason-runs/`, each role gets `--add-dir` to its own `cell/<stem>/` holding only its allowed files. Prevention, not detection. Live re-verification on a real chain still RED |
| `usage` populated on a live run | run `213319` ledger: `input_tokens 114, output_tokens 4924, cost_usd 0.325` | GREEN (2026-07-28) — the parsing requirement took effect on the next run |
| ~~`usage` never populated~~ | every ledger line has `usage: {}` | **PARTLY addressed 2026-07-28** — the coordinator is now required to parse provider usage (`{"parse_failed":true}` instead of `{}`), and the gate rejects impossible arithmetic: non-integer or negative fields, `cached > input`, `reasoning > output`. What remains open and cannot be closed without a non-LLM runner: nothing proves the numbers came from the provider at all. Plausible invented figures pass every check, because the same coordinator both spawns the role and writes the record |
| repo changes attributed to roles without proof, then reverted with `git checkout` | two `contract_violation` records blamed the generator for edits made by a human in another session; a third invented a plausible story about a role applying a patch from the run dir | **fixed 2026-07-28** — coordinator is now absolutely forbidden from modifying the working tree, including to "restore" it; unattributed diffs are logged as `observation`, remediation is a human's call |
| gate counts a `contract_violation` line as role presence | that line carries `"stem":"<role>"` | **fixed properly on the second attempt 2026-07-28.** The first fix (two chained greps) was defeated by adversarial review: `{"event":"contract_violation","stem":"attacker","exit":0,"fresh":true}` and a nested-`detail` variant both passed, key reordering broke legitimate runs, and the intermediate file sat in a role-writable directory as a symlink target. The gate now parses JSONL, accepts only top-level spawn records, and additionally rejects impossible usage arithmetic. Six live cases |
| gate exits 2 on every failure path | live | **defect found and fixed 2026-07-28** — `set -e` aborted the script on the checker's non-zero exit before the message was printed, so the hook died with codes 1/3/4. A Stop hook blocks only on 2, so every ledger failure would have silently let the turn end |
| source drift during a run | live ledger shows the working tree changing twice mid-run | **fixed 2026-07-28** — coordinator records `HEAD` + a `git status --porcelain` digest before the first spawn and after each one; a change ends the chain with `source-drift` rather than letting roles argue about different versions of the code |
| installed copy can lag HEAD silently | the chain's own attacker found `.claude/` running `fast` and lacking `HALTED.md` handling | fixed — `install.sh` now installs from the working copy when run inside a checkout |

## maw-selfreview (inline gate, Claude Code only)

| Row | How | Status |
|---|---|---|
| gate branch coverage | 17 live invocations: non-commit command, nothing staged, under threshold, over threshold, `--no-verify`, `--amend`, explicit skip, reviewed-clean, reviewed-blocking, stale mark after the diff changed, invariant path at 2 lines; plus the full cycle at a threshold the diff crosses — unreviewed blocks, clean verdict passes, blocking verdict blocks, edited-after-review blocks, explicit skip passes and is logged | GREEN (2026-07-30) |
| freshness is keyed to the diff, not to time | review mark is `sha256(staged diff)`; editing after review re-triggers | GREEN (2026-07-30) |
| gate stays fast enough not to be bypassed | industry threshold is ~15s before `--no-verify` becomes habit | GREEN — **279ms**, no model call in the gate itself |
| bypass is cheap and recorded | `MAW_SKIP_SELFREVIEW=1` appends to `maw/.selfreview-skips` | GREEN (2026-07-30) |
| PreToolUse wiring into settings.json | installer cascade, `matcher: Bash` | GREEN (2026-07-30) — after fixing a generated-code bug where a newline literal broke the python branch silently |
| live review actually run through the skill | codex reviewer on the real staged README diff, 69s, one spawn | GREEN (2026-07-30) — and it **found a genuine defect**: the README said the gate fires when the diff *exceeds* the threshold, while `maw-selfreview-gate.sh:67` exits only on `LINES < THRESHOLD`, so a diff of exactly 60 lines already triggers. Reported as MINOR with a `file:line`, not inflated to a blocker. Verdict `NO_BLOCKING_FINDINGS`. Trace in `.brainstorm/selfreview-run1/` |
| convergence rule (BLOCKER/MAJOR block, MINOR/TRACKED do not) validated on a real loop | run a change through several review rounds | RED — the rule is taken from the literature on review paralysis, not yet observed here |

## State machine

| Row | How | Status |
|---|---|---|
| Windows-native (PowerShell host) full lifecycle pending→in_progress→done|blocked, both persistence modes × branch/worktree, paths with spaces | E2E run under Codex host | PARTIAL — git-tracked × branch-only GREEN (live test-bed on Windows, claude -p host: TASK-001 small-fix incl. QA retry, TASK-002 deep-research incl. cross-provider stage); worktree, local-only, spaces, Codex host all RED |
| local-only + worktree copy-back on done/blocked | E2E | RED (rule now specified in Step 10) |
| mode-slice grid (4 modes × 2 persistence × worktree/branch) | E2E matrix | RED (small-fix and deep-research covered on git-tracked × branch-only only) |
| deep-research TASK_FINAL fallback | single deep-research run | GREEN (live: TASK-002 — orchestrator wrote TASK_FINAL.md on mode-gate skip, reviewers consumed it) |

RED rows are the work queue for the verification phase; none of the cross-provider or Codex-host paths should be advertised as production-ready until their rows are green. Two RED rows also touch the Claude-native path: the deep-research `TASK_FINAL.md` fallback and the local-only+worktree copy-back are newly specified rules that need one E2E run each; the rest of the native path's mechanics are unchanged.
