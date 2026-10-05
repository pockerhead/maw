# Project context overlay

The base pipeline is 100% generic — it contains no knowledge of your project. Project-specific knowledge lives in `maw/project-context/`, authored with `/maw-context`.

```
/maw-context            # scaffold, or add an invariant / domain / lesson / tool
/maw-context --review   # fold pending agent proposals into the overlay
```

If `maw/project-context/` does not exist, the pipeline behaves byte-for-byte as with no overlay — this is the default and requires nothing. If it exists, three tiers are injected, each gated on a different axis:

- `README.md` — **constant**, into every agent every stage. Only what is true regardless of subsystem or stage: a short orientation, universal invariants, and a **domain catalog** (observable `trigger → domains/<name>.md` lines plus a hard rule to self-load a module on a matching trigger). Bounded by domain count, not free — kept disciplined.
- `domains/<name>.md` — **domain-gated**, normative. Injected into every running stage (planner and reviewers included — planning correctness needs it) when the task is in that domain. It gets there two ways: pre-injected because `task.md` declared `Domains:` (a recorded decision `/maw-tasks` proposes and the user confirms), or self-loaded when an agent hits an observable catalog trigger a task did not predict (the recall safety net). Subsystem invariants, risk lessons, and pointers to bulky docs live here.
- `agents/<stem>.md` — **stage-gated**, into one agent only. Build/test/runtime-QA tooling and stage skills — clarifier and planners do not carry tooling they never use.

A native named subagent starts with a fresh conversation and no parent history, but it does receive the loaded `CLAUDE.md` hierarchy, memory, and a git-status snapshot. The parent's task artifacts, PCTX overlay, and conversation still do not reach it, so dynamic inputs must be injected or read from explicit disk paths; `@`-imports are not a task-context transport. External spawns retain explicit ambient-context suppression. Project context is normative as **law to satisfy, not a claim to audit** — review agents verify the code satisfies it; whether the law itself is right is human-gated via `/maw-context --review`. Agents never edit the overlay: they append dated entries to that task's `PCTX_PROPOSALS.md`, folded in deliberately.

This is reduced, human-authored machinery — a hand-written catalog and human-declared `Domains:`, no resolution engine, no token-budget gate, no includes. The base change is the orchestrator plus the `maw-context`/`maw-tasks` skills; the overlay seam never modifies the agent prompts.

What these overlays turn into after a year of real use — including why nearly
every invariant in them is a fossilised bug report rather than a design document,
and why the two projects examined differ by a factor of six in size for no reason
connected to codebase size — is written up in
[`PROJECT_CONTEXT_FIELD_NOTES.md`](PROJECT_CONTEXT_FIELD_NOTES.md).
Nothing there measures whether the overlay improves outcomes; `maw-context` has
no acceptance rows and no controlled comparison, which stays open work.

Back to the [README](../README.md).
