# Adversarial deliberation — `/maw-reason` (experimental, Claude Code only)

A third surface, beside task intake and task execution. It answers a **question** instead of running a work item: no task folder, no branch, no worktree, no status moves. Opt-in at install (`--with-reason`) because **no chain has yet been run end to end** — see the `maw-reason` rows in [ACCEPTANCE.md](ACCEPTANCE.md) for what is unverified.

```
/maw-reason "should we shard this table or partition it?"
/maw-reason --fast "..."             # lower compressor/attacker/synthesizer effort
/maw-reason --keep "..."             # persist the trace for audit
/maw-reason --high-assurance "..."   # two generators on distinct profiles (+1 spawn)
/maw-reason --seed 2751937183 "..."  # reproduce a previous run's role assignment
```

**Which model plays which role is drawn, not chosen.** A standing preference — generator on claude, attacker on codex — fixes the chain's blind spot in place, where it stays invisible because it never moves. So each run draws a 32-bit seed from OS entropy, records it in `RUN.json`, and uses it to decide the provider orientation; explicit per-role pins in settings are decisions and are left alone. The seed is printed in the synthesis, so a run can be repeated identically (`--seed`) or deliberately flipped to see whether the answer survives swapping who held which role.

Five spawns: **premise check → generator → compressor → attacker → synthesizer**. The compressor is what makes it a dialectic rather than an ensemble — a non-author decides which claims are load-bearing and proposes the `attack_vector`, so the attacker cannot pick its own exemption surface. The vector is a floor: an off-vector scan is mandatory.

Output is a synthesis with an explicit **disagreement ledger** (unresolved conflicts stay unresolved), stated confidence tied to what survived attack, and concrete what-would-change-my-mind triggers.

**The calling session does not author the chain's prompts.** It captures the question verbatim, then spawns a coordinator that cannot see the calling conversation and builds every downstream prompt itself. Your own tentative answer goes into a `CALLER_POSITION.md` that reaches the **attacker only** — not to protect it, but so it gets attacked like everything else.

That invariant is narrower than it sounds, and the skill says so: the caller still writes the fact allowlist and the constraints, and the coordinator routing `CALLER_POSITION.md` correctly is an instruction, not an enforcement. What the coordinator does record is the file list and prompt hash it fed each role, so a deviation is visible after the fact. Auditable exclusion, not a mechanical seal — a real seal needs a non-LLM dispatcher.

**Two effort profiles.** `deep` (default) runs the compressor and synthesizer at `medium` and the attacker at `high`; `--fast` drops them for speed. The split exists because "low is mechanical" is false for exactly two roles: the compressor decides what gets attacked and the synthesizer decides what the attack established. A `fast` run can miss a problem by never aiming at it, and no attacker effort recovers a target that was never selected — so depth is the default and speed is the flag you type. Roughly 200–350k tokens (240–420k with `--high-assurance`); the synthesis prints which profile ran so a quiet attacker can be weighed correctly.

**The premise check can stop the run.** A `QUESTION SUSPECT` verdict halts the chain after one spawn and hands the human the specific mis-posing plus a proposed reframing. The reframing is a proposal, never a substitution: proceed on the original question (`--force-premise`), restart with a reworded one, or drop it. Catching a badly posed question costs one spawn here and four downstream.

## The gate hook

A simulated chain and a real one look identical in their output text — that is what makes this surface different from the task pipeline, where a missing implementation is visible in the diff. `install.sh --claude --with-hooks` adds a `Stop` hook that blocks the turn unless the run's own manifest is satisfied: every expected artifact present and newer than the question, and a ledger with the expected number of distinct successful role spawns. It reads `RUN.json`, so a five-spawn run cannot pass as a claimed `--high-assurance` one.

The hook raises the cost of faking a chain from "write some prose" to "fabricate a consistent evidence set on purpose". A model that can write files can still forge all of it. It is not a security boundary, and describing it as one would be the same overclaim the chain exists to catch — what it does is turn an accidental shortcut into a deliberate lie.

Back to the [README](../README.md).
