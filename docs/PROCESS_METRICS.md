# MAW process metrics — obfuscated aggregate

Source: per-task `metrics.md` agent ledgers in completed task folders.
No task titles, descriptions, paths, or artifact text are included.

## Corpus

- projects scanned: **6**
- tasks by status: pending **170**, in_progress **5**, done **340**, blocked **3**
- done folders scanned: **340**
- of those, with a parseable ledger: **235** (69.1%)

| project | pending | in_progress | done | blocked | done w/ ledger |
|---|---|---|---|---|---|
| `P-107312bf` | 0 | 1 | 0 | 0 | 0 |
| `P-31709d34` | 3 | 0 | 1 | 0 | 1 |
| `P-50f0cebe` | 0 | 0 | 2 | 0 | 2 |
| `P-5f587a71` | 35 | 2 | 111 | 0 | 78 |
| `P-74490cb0` | 132 | 2 | 225 | 3 | 154 |
| `P-7b118da6` | 0 | 0 | 1 | 0 | 0 |

## Did review find anything?

The question the SWE-bench harness cannot answer: when the pipeline ran a
reviewing stage, how often did that stage object?

Denominators count only tasks where the stage returned a judgement. A spawn
that died on an API error neither approved nor objected and is excluded, so
transport failures cannot inflate a clean rate.

| signal | n | denominator | rate |
|---|---|---|---|
| code review objected | 62 | 178 | 34.8% |
| QA objected | 20 | 165 | 12.1% |
| QA reached SHIP | 100 | 165 | 60.6% |
| QA deferred the rest to a human | 58 | 165 | 35.2% |
| any review stage objected | 70 | 178 | 39.3% |
| fixer needed a 2nd round | 9 | 169 | 5.3% |
| fixer had nothing to do | 25 | 169 | 14.8% |
| premise was challenged | 48 | 211 | 22.7% |

## Same rates, per project

Aggregates hide the thing that matters most here: what a project *is* decides
what QA can even check. A game's headless gates cover build, tests and
invariants; feel, timing and anything visual can only be judged by a person
playing it. Read the QA columns against the `human gate` column, not alone.

| project | ledgered | code rev objected | QA objected | QA SHIP | QA -> human gate | fixer 2nd round |
|---|---|---|---|---|---|---|
| `P-31709d34` | 1 | 0.0% | 100.0% | 100.0% | 0.0% | 0.0% |
| `P-50f0cebe` | 2 | n/a | n/a | n/a | n/a | n/a |
| `P-5f587a71` | 78 | 33.8% | 16.2% | 94.1% | 0.0% | 10.4% |
| `P-74490cb0` | 154 | 35.8% | 8.3% | 36.5% | 60.4% | 2.0% |

## Transport reliability

- done tasks with at least one spawn that died without a verdict (API error, stream timeout, kill, no output): **36** of 235 (15.3%)

This is a floor, not a count: only failures the orchestrator wrote into the
ledger are visible here. A run that died before writing its row leaves no trace.

## Outcomes per stage

| stage | DONE | FAIL | FIXED | FOUND_DEFECTS | INFRA | NEEDS_FIXES | NEEDS_WORK | NO_OP | OK | PASS | PREMISE_CHALLENGED | PREMISE_HOLDS | REJECT | SHIP | SHIP_PENDING_HUMAN | UNKNOWN |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| clarifier | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| code-reviewer | 0 | 9 | 0 | 10 | 2 | 5 | 37 | 1 | 0 | 119 | 0 | 2 | 2 | 0 | 0 | 4 |
| fixer | 3 | 3 | 29 | 4 | 3 | 0 | 0 | 28 | 91 | 19 | 0 | 0 | 3 | 0 | 0 | 39 |
| implementer | 19 | 6 | 0 | 1 | 10 | 0 | 0 | 0 | 140 | 20 | 0 | 0 | 9 | 1 | 0 | 6 |
| plan-reviewer-1 | 0 | 1 | 10 | 31 | 12 | 0 | 38 | 1 | 24 | 31 | 0 | 3 | 12 | 0 | 0 | 62 |
| plan-reviewer-2 | 1 | 0 | 7 | 17 | 1 | 0 | 8 | 2 | 23 | 127 | 0 | 1 | 11 | 0 | 0 | 20 |
| planner | 2 | 1 | 0 | 0 | 10 | 0 | 0 | 7 | 218 | 1 | 0 | 0 | 4 | 0 | 1 | 10 |
| premise-challenge | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 50 | 179 | 0 | 0 | 1 | 0 |
| qa | 1 | 2 | 0 | 0 | 7 | 25 | 0 | 1 | 0 | 0 | 0 | 0 | 2 | 103 | 58 | 2 |

**Classifier coverage:** 1613 of 1757 ledger rows (91.8%) matched a known outcome pattern; **144 (8.2%) did not** and are counted in neither the objection nor the clean column above.

The Outcome column is free text written per run, not an enum the orchestrator
enforces, so this residue is a property of the corpus and not a parsing bug to
tune away. Rates above should be read as bounded by it.

## Loop depth (max round reached per task, per stage)

| stage | r1 | r2 | r3 | r5 | r7 | r8 |
|---|---|---|---|---|---|---|
| clarifier | 2 | 0 | 0 | 0 | 0 | 0 |
| code-reviewer | 176 | 2 | 0 | 0 | 0 | 0 |
| fixer | 161 | 6 | 1 | 1 | 1 | 0 |
| implementer | 175 | 1 | 0 | 0 | 0 | 0 |
| plan-reviewer-1 | 206 | 1 | 0 | 0 | 0 | 0 |
| plan-reviewer-2 | 206 | 1 | 0 | 0 | 0 | 0 |
| planner | 206 | 2 | 0 | 0 | 0 | 0 |
| premise-challenge | 211 | 0 | 0 | 0 | 0 | 0 |
| qa | 158 | 5 | 1 | 1 | 0 | 1 |

Row totals here can exceed the denominators in the rates above by a task or
two. This table counts every task that ran the stage; the rates count only
tasks where the stage returned a judgement, so a task whose every spawn at
that stage died appears here and not there.

## Configuration actually used

**provider** (spawn rows, n=1757): `unrecorded` 1638 (93.2%), `claude` 61 (3.5%), `codex` 56 (3.2%), `builtin` 1 (0.1%), `builtin/codex` 1 (0.1%)

**model** (spawn rows, n=1757): `opus` 1272 (72.4%), `fable` 315 (17.9%), `sonnet` 100 (5.7%), `gpt-5.6-sol` 56 (3.2%), `—` 9 (0.5%), `(none)` 2 (0.1%), `inherited` 2 (0.1%), `n/a` 1 (0.1%)

**effort** (spawn rows, n=1757): `high` 722 (41.1%), `medium` 569 (32.4%), `xhigh` 423 (24.1%), `max` 22 (1.3%), `—` 12 (0.7%), `low` 6 (0.3%), `inherited` 2 (0.1%), `n/a` 1 (0.1%)

## Task classification

**Mode** (n=319): `full` 217, `brainstorm` 41, `small-fix` 39, `deep-research` 22

**Type** (n=338): `feature` 168, `refactor` 81, `bugfix` 65, `chore` 23, `perf` 1

## Artifact presence across done folders

| artifact | folders |
|---|---|
| `task.md` | 338 |
| `PLAN_FINAL.md` | 281 |
| `PLAN.md` | 279 |
| `PLAN_V2.md` | 279 |
| `TASK_FINAL.md` | 271 |
| `IMPL_SUMMARY.md` | 250 |
| `IMPL_REVIEW.md` | 242 |
| `metrics.md` | 237 |
| `FIX_SUMMARY.md` | 232 |
| `QA_REPORT.md` | 221 |
| `PREMISE_CHALLENGE.md` | 212 |
| `PCTX_PROPOSALS.md` | 54 |
| `PLAN_REVIEW_2.md` | 14 |
| `PLAN_REVIEW_1.md` | 9 |
| `QA_REPORT.prev-1.md` | 6 |
| `CLOSE_NOTE.md` | 6 |
| `FIX_SUMMARY.prev-1.md` | 5 |
| `FIX_SUMMARY_R2.md` | 4 |
| `PLAN_REVIEW.md` | 4 |
| `QA_REPORT.prev-2.md` | 3 |
| `PLAN_ORIGINAL_RESEARCH.md` | 3 |
| `EXTENSION_PROMPT.md` | 3 |
| `PROCESSING_PROMPT.md` | 3 |
| `DB_PUSH.md` | 3 |
| `FIX_SUMMARY_R3.md` | 3 |

