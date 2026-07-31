# Task-to-commit analysis — obfuscated

Did tasks leave damage behind? Git is the only witness, and it answers
indirectly: a later `Type: bugfix` task touching the same files as an earlier
task is *evidence* of a repair, not proof of one. Busy modules attract
unrelated changes. Compare the rates across projects rather than reading any
single number as a defect count.

| project | commits | naming a task | tasks in history | fix commits |
|---|---|---|---|---|
| `P-5f587a71` | 1242 | 151 (12.2%) | 82 | 227 (18.3%) |
| `P-74490cb0` | 1617 | 1265 (78.2%) | 289 | 104 (6.4%) |

## Is repair traffic attracted to what a task shipped?

For each task: who was the *first* later task to touch one of its files,
excluding magnet files that a fifth of all tasks touch? If the pipeline left
no damage, the chance that successor is a bugfix should equal the repo's base
rate of bugfix tasks. Higher means repair clusters behind shipped work.

The denominator is successors whose task folder declares a `Type:`. A task
that appears in git history but has no readable header cannot be counted as
a bugfix or as anything else, so it is excluded from both sides of the ratio
rather than silently scored as not-a-bugfix.

| project | successor is a bugfix | base rate of bugfix tasks | lift |
|---|---|---|---|
| `P-5f587a71` | 24/70 (34.3%) | 33.8% | 1.02x |
| `P-74490cb0` | 35/219 (16.0%) | 13.3% | 1.20x |

### `P-5f587a71`

- of 82 tasks: **71** had a non-magnet successor, 8 were never followed into their own files, 3 touched only magnet files and were skipped (sums to 82)
- magnet files excluded: **3** (of 1299 touched)
- declared task types: `feature` 43, `bugfix` 27, `chore` 7, `refactor` 3
- `fix:`-prefixed commits that name a task: **43** of 227 fix commits — repair *inside* a task's own window, which is the pipeline correcting itself before the task closed, not damage that escaped

### `P-74490cb0`

- of 289 tasks: **220** had a non-magnet successor, 68 were never followed into their own files, 1 touched only magnet files and were skipped (sums to 289)
- magnet files excluded: **2** (of 4728 touched)
- declared task types: `feature` 144, `refactor` 88, `bugfix` 38, `chore` 14, `perf` 1
- `fix:`-prefixed commits that name a task: **39** of 104 fix commits — repair *inside* a task's own window, which is the pipeline correcting itself before the task closed, not damage that escaped

**What this cannot show.** A bugfix task following a feature task into the
same file may be repairing it, extending it, or fixing a defect that predates
it. Only the comparison against the base rate carries information, and even
that is an association. Nothing here establishes causation.
