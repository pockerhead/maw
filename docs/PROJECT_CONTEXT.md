# Project context overlay

The base pipeline is 100% generic — it contains no knowledge of your project. Project-specific knowledge lives in `maw/project-context/`, authored with `/maw-context`.

```
/maw-context            # scaffold, or add an invariant / domain / lesson / tool
/maw-context --review   # fold pending agent proposals into the overlay
/maw-context --migrate  # add law/procedure/lesson tags to an untagged overlay (diff reviewed)
```

If `maw/project-context/` does not exist, the pipeline behaves byte-for-byte as with no overlay — this is the default and requires nothing. If it exists, three tiers are injected, each gated on a different axis:

- `README.md` — **constant**, into every agent every stage. Only what is true regardless of subsystem or stage: a short orientation, universal invariants, and a **domain catalog** (observable `trigger → domains/<name>.md` lines plus a hard rule to self-load a module on a matching trigger). Bounded by domain count, not free — kept disciplined.
- `domains/<name>.md` — **domain-gated**, normative. Injected into every running stage (planner and reviewers included — planning correctness needs it) when the task is in that domain. It gets there two ways: pre-injected because `task.md` declared `Domains:` (a recorded decision `/maw-tasks` proposes and the user confirms), or self-loaded when an agent hits an observable catalog trigger a task did not predict (the recall safety net). Subsystem invariants, risk lessons, and pointers to bulky docs live here.
- `agents/<stem>.md` — **stage-gated**, into one agent only. Build/test/runtime-QA tooling and stage skills — clarifier and planners do not carry tooling they never use.

A native named subagent starts with a fresh conversation and no parent history, but it does receive the loaded `CLAUDE.md` hierarchy, memory, and a git-status snapshot. The parent's task artifacts, PCTX overlay, and conversation still do not reach it, so dynamic inputs must be injected or read from explicit disk paths; `@`-imports are not a task-context transport. External spawns retain explicit ambient-context suppression. Project context is normative as **law to satisfy, not a claim to audit** — review agents verify the code satisfies it; whether the law itself is right is decided outside the pipeline agents. Agents never edit the overlay: they append dated entries to that task's `PCTX_PROPOSALS.md`. A human folds them with `/maw-context --review` (the default, `pctx_fold: "manual"`), or, with `pctx_fold: "auto"`, the orchestrator folds the finishing task's proposals at wrap-up into `domains/` and `agents/` only; README is never auto-written.

This is reduced, human-authored machinery — a hand-written catalog and human-declared `Domains:`, no resolution engine, no includes, and one mechanical gate: the overflow check (`pctx-sleep.sh check`, limits from `maw/settings.json`). The base change is the orchestrator plus the `maw-context`/`maw-tasks` skills; the overlay seam never modifies the agent prompts.

## Tags, archive and the sleep pass

Top-level lines under `## Invariants`, `## Procedures` and `## Risk lessons` of `domains/*.md` carry one tag: `[law]` (must always hold), `[procedure]` (how to do something) or `[lesson class=<slug>]` (came from a defect; the slug names the defect class). Untagged legacy lines stay valid and count as `[lesson class=untagged]`.

`archive/<domain>.md` holds lessons moved out of the injected overlay, each with `archived`, `reason` and a `holder`: a file (optionally `#symbol`) in code that now enforces the class. The archive is never injected; stages can grep it, and a reviewer who hits a matching defect writes `class=<slug>` in the finding.

The wrap-up (orchestrator Step 10, contract in `maw-context` Step 3b) uses the installed helper `maw-execute-task/scripts/pctx-sleep.sh`:

- `restore` brings an archived lesson back when this task's `IMPL_REVIEW.md` / `QA_REPORT.md` names its class (`reason=miss`) or its holder no longer exists (`reason=holder-missing`).
- With `pctx_fold: "auto"` and a `done/` task, the task's proposals are folded with tags and checked by `validate`; a failure reverts the fold.
- When `check` reports overflow (default 200 lines per domain file, 1500 in total), a pass runs. The first pass on an overlay with untagged lines is a **migration pass**: it only adds tags, and `migrate-check` proves that by comparing the tree with the tags stripped. Later passes are **consolidation passes**: merge lessons of one class into a `[law]` or `[procedure]` line, archive a lesson only when `holder` passes, and drop backticked references that `refs` finds missing (the line stays, marked `(ref removed <date>)`).
- Any failed check reverts that stage. In git-tracked mode the fold and the pass are separate commits, and the pass is also saved as `<task folder>/pctx-pass.patch`, so `git apply -R` undoes it after a squash merge. Local-only mode keeps a full snapshot in `<task folder>/pctx-before/`.
- The final report carries one `pctx:` line (`folded=… archived=… merged=… restored=… cleaned=…`, `migrated …`, `reverted …`, `overflow …`, `error …` or `ok`). `blocked/` tasks and `manual` mode only report.

Why it is shaped this way:

| Decision | Source |
|---|---|
| Two stores: fast proposals and a slow overlay, consolidated offline in batches | McClelland, McNaughton & O'Reilly 1995, *Psychological Review* 102(3):419-457, doi:10.1037/0033-295X.102.3.419; Kumaran, Hassabis & McClelland 2016, "What Learning Systems do Intelligent Agents Need? Complementary Learning Systems Theory Updated", *Trends Cogn. Sci.* 20(7):512-534, doi:10.1016/j.tics.2016.05.004 |
| Trigger is an accumulation threshold | Park et al. 2023, "Generative Agents", arXiv:2304.03442, Sec. 4.2: reflection runs when the summed importance of recent events exceeds a threshold. The analogy covers the mechanism only; 200/1500 are owner-set values. |
| Sort into law / procedure / lesson | Sumers et al. 2023, CoALA, arXiv:2309.02427, Sec. 4.1 (episodic, semantic and procedural memory) |
| Migrate tags first, consolidate on the next pass | Tse et al. 2007, "Schemas and memory consolidation", *Science* 316(5821):76-82, doi:10.1126/science.1135935: new information consolidates quickly when a relevant schema exists. The tags are the schema. |
| Archive only with an executable holder | CoALA Sec. 4.1 (a holder in code is procedural memory); Shinn et al. 2023, Reflexion, arXiv:2303.11366 (agents keep reflective text in an episodic memory buffer instead of updating weights) |
| Never drop without a holder; fail closed | Kirkpatrick et al. 2017, "Overcoming catastrophic forgetting in neural networks", *PNAS* 114(13):3521-3526, doi:10.1073/pnas.1611835114 |
| Archive tier on disk, not in context | Packer et al. 2023, MemGPT, arXiv:2310.08560 (virtual context management, data movement between fast and slow memory) |
| Restore on a matching miss | Nader, Schafe & LeDoux 2000, *Nature* 406:722, doi:10.1038/35021052: reactivating a consolidated memory makes it labile again |

What these overlays turn into after a year of real use — including why nearly
every invariant in them is a fossilised bug report rather than a design document,
and why the two projects examined differ by a factor of six in size for no reason
connected to codebase size — is written up in
[`PROJECT_CONTEXT_FIELD_NOTES.md`](PROJECT_CONTEXT_FIELD_NOTES.md).
Nothing there measures whether the overlay improves outcomes; `maw-context` has
no acceptance rows and no controlled comparison, which stays open work.

Back to the [README](../README.md).
