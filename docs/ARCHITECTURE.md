# Architecture

## The problem

You can paste the best coding guidelines into your system prompt. The LLM will read them, agree they're important, and then drift from them under complex context. An agent that writes code and reviews its own output has the same blind spots in both passes.

Compare:

| Approach | How it works | Failure mode |
|---|---|---|
| Prompt rules (Karpathy-style) | Tell the agent "be careful" | Agent drifts from rules under complex context |
| Self-review | Agent checks its own work | Same blind spots that caused the error review the error |
| **MAW** | Independent agents verify against code | Reviewers get no shared conversation and verify code plus searchable evidence; the premise audit and both plan reviews are additionally isolated from prior transcripts and the log |

## Pipeline

![MAW pipeline architecture](../assets/maw_pipeline_architecture.svg)

*(The diagram shows the stage flow; the provider dispatch layer — which harness runs each stage — is described in [CONFIGURATION.md](CONFIGURATION.md).)*

Key design decisions:
- **Fresh by default, evidence shared through the task folder** — no conversation history crosses a stage. Agents can search harness-written transcripts, reuse executable evidence in scratch, and append only decisions or dead ends to a minimal log. Native continuity exists only for same-profile timeout/transient retries and an implementer re-run after the user amends a `PLAN_BLOCKED` plan; no premise, plan, code, fixer, or QA judging role is ever continued.
- **Adversarial by default** — each agent's prompt includes the assumption that the previous agent was unreliable. Not hostile, but skeptical.
- **Premise challenge** — before planning, an isolated agent fed only the task and the real system (never the orchestrator's framing, the plan, or any summary) tests whether the *premise itself* is wrong, and halts to the human if it is. Every other stage verifies the solution within the premise and inherits its lineage; this is the one structural check that attacks the frame. It reduces — does not eliminate — the "pipeline faithfully executes a wrong premise" failure; the human remains the last line.
- **Task-local state** — artifacts live in the task folder on a feature branch. Text artifacts and scratch source follow normal `maw/` persistence; privacy-sensitive transcript payloads are deliberately gitignored and rescued locally before worktree removal.

Back to the [README](../README.md).
