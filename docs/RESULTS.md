# What has actually been measured

Three separate measurements, none of them a marketing number. Full detail in
[`PROCESS_METRICS.md`](PROCESS_METRICS.md),
[`TASK_COMMIT_ANALYSIS.md`](TASK_COMMIT_ANALYSIS.md) and
[`ACCEPTANCE.md`](ACCEPTANCE.md).

**Held-out benchmark — partial.** SWE-bench Multilingual, 70-instance stratified
subset with gold patches held out of the solver's view and a deterministic leak
audit: **7 resolved out of 12 instances actually run**. The other 58 produced
empty patches and were never attempted. All on Sonnet in `small-fix` mode.
There is **no same-model single-agent baseline**, so this figure has nothing to be
compared against — it is a data point, not a claim of superiority.

**Process behaviour — 340 completed tasks across 6 real projects**, 235 with a
parseable stage ledger:

Every rate below is conditional on the stage having returned a verdict at all —
a spawn that died neither approved nor objected, so it is excluded from both
sides rather than counted as approval. The denominators differ per row and are
given explicitly.

| | | |
|---|---|---|
| a reviewing stage objected | **39.3%** | 70 of 178 tasks that got a verdict from one |
| code review objected | 34.8% | 62 of 178 |
| QA objected | 12.1% | 20 of 165 |
| fixer needed a second round | **5.3%** | 9 of 169 |
| premise challenge rejected the premise | 22.7% | 48 of 211 |

The 39.3% is the case for the pipeline: in four out of ten tasks where a review
stage reached a verdict, it found something worth answering. Over the whole
235-task ledgered corpus that is 29.8%, the difference being tasks where no
review stage returned anything. The 5.3% is the case against review
paralysis — the loop converges on the first pass almost always. Of the 170 tasks
that ran a fixer, 161 finished in one round and 6 needed two; three went further,
to a third, a fifth and a seventh round. The 5.3% rate is over the 169 where the
fixer returned a verdict at all. A long tail exists and is not hidden: QA reached
an eighth round once.

Project type decides what QA can even check, and the gap is much larger than the
aggregate suggests. On the backend project QA reached SHIP in **94.1%** of tasks
with a **0%** human gate. On the game project QA closed only **36.5%** by itself
and handed **60.4%** to a person — `SHIP-PENDING-RUNTIME` and its variants, where
headless gates covered build, tests and invariants and feel, timing and anything
visual could not be judged without playing it.

Code review, meanwhile, objected at nearly the same rate in both (33.8% vs 35.8%).
The natural reading is that reviewing code is domain-independent while verifying
behaviour is not, so on a game the QA stage is structurally a partial verifier —
but that is a hypothesis this data is consistent with, not one it establishes.
Two projects, no ground truth, nothing varied deliberately. What the numbers do
support without interpretation: **QA numbers from one project do not transfer to
another**, and an aggregate across project types hides a factor-of-two difference.

**Did tasks leave damage behind? No detectable signal.** For each task, the first
later task to touch its files (magnet files excluded) was a bugfix at **1.02x and
1.20x the repo's base rate of bugfix tasks** — p=0.93 and p=0.24 against that base
rate, so neither is distinguishable from chance at these sample sizes. Repair
traffic does not measurably cluster behind shipped work. Note what this is not: an
underpowered test failing to reject is weak evidence, and the game project's 1.20x
would need roughly four times the sample before it could be called either way.

**What is not good.** **15.3%** of ledgered tasks contain at least one spawn that
died without returning a verdict — API errors, stream timeouts, kills. That is a
floor: a spawn that died before writing its ledger row leaves no trace at all.

That figure was published at 29.4% in the first draft of this section and was
wrong. The outcome classifier matched `pending` as an infrastructure failure
before it could match `SHIP-PENDING-RUNTIME` as a human gate, so the game
project's most common QA verdict was scored as a dead spawn — which simultaneously
erased the human-gate rate and doubled the apparent transport failure rate. The
self-review gate caught it before the commit landed.

Back to the [README](../README.md).
