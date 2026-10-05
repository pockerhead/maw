# Inline review — `/maw-selfreview` (Claude Code only)

The pipeline is for work you hand over and walk away from. Most work is not that: you are in an ordinary session, you wrote something, and you are about to commit it. There you are both author and reviewer, which is not a review — you skip exactly the places you feel sure about, and you feel sure precisely where the defect is invisible to you.

One spawn fixes the structure: a reviewer **on a different vendor** gets the staged diff plus the task, reads the repo, and cannot edit anything. Nine stages become one, hours become about a minute.

```
/maw-selfreview                 # review what is staged right now
sh install.sh --claude --with-selfreview
```

**It fires on a trigger, not on request.** The gate runs on `git commit` when the diff reaches `MAW_SELFREVIEW_LINES` (default 60) or touches a path listed in `maw/selfreview-invariants`. A review you have to remember to ask for will not happen at the moment it matters. Freshness is keyed to `sha256` of the staged diff, so editing after a review invalidates it.

Bypass is one variable and it is recorded: `MAW_SKIP_SELFREVIEW=1` appends to `maw/.selfreview-skips`. That is deliberate — a gate that cannot be skipped gets disabled wholesale, and the documented failure mode across the industry is `--no-verify` becoming permanent muscle memory the first time a hook is slow. The gate itself makes no model call and runs in under 300ms.

**Findings are severity-gated so the loop terminates.** `BLOCKER` and `MAJOR` block the commit and require material evidence — a `file:line`, output of a command actually run, a named input that fails. `MINOR` and `TRACKED` are reported and never block. Convergence means *no blocking findings*, not an empty report: an adversarial reviewer always finds something, and by the fifth round it is inventing. On this project's own benchmark an adversarial checker degraded 13% of already-correct answers, so a manufactured blocker is treated as the primary failure mode rather than a nuisance.

It reads a diff, so it is blind to anything visual, anything about feel, and anything that only appears at runtime — and it is instructed to say so rather than invent a textual proxy.

Back to the [README](../README.md).
