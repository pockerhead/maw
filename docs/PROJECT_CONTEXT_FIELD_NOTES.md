# Project context in the field

`maw-context` describes how to author the `maw/project-context/` overlay. This
file is the other half: what the overlay actually turns into after a year of use
on real projects, observed on two of them. Names and code are withheld; the
structure and the shape of the rules are not.

The two overlays compared here are a Rust/Godot game (1385 lines) and a Go
microservice monorepo (218 lines). Both follow the same three-part layout the
skill specifies — a constant `README.md` injected into every stage, domain
modules gated by observable triggers, and (in the game's case) per-stage agent
files. Everything below is what the projects added on their own.

## 1. Invariants are fossilised bug reports, not design documents

The single strongest pattern. Almost no rule in either overlay reads like it was
written in advance. They read like postmortems compressed to one paragraph, and
most carry the task number that produced them.

The game's overlay literally uses the word `scar:` as a marker:

> `"legacy"/deprecated in a NAME is the status of a CODE PATH, never of the
> content/feature it serves. Do not derive content coverage/quality/scope
> decisions from code-path naming (scar: [two POI types] are first-class
> exploration features living on a "legacy" per-chunk shim — a plan proposed
> leaving a cross-chunk hole there from the label alone, TASK-NNN).`

That is not a coding standard. It is a specific plan that went wrong, generalised
exactly one step and no further, with a pointer back to the evidence.

The backend overlay does the same in a different voice (translated; that overlay
is written in the team's working language):

> When closing a class of defect, inventory EVERY site of that class, not only the
> one named in the task. Otherwise you ship a release that looks like it closed the
> hole: across one epic the same entry point was fixed twice while the identical one
> next to it was left alone. Put the site list in an artifact, not in your head.

**Implication for the skill:** the overlay's value is not that someone wrote down
the architecture. It is that a defect which cost real time got converted into a
sentence that reaches the planner before it happens again. An overlay authored
in one sitting from the codebase would contain none of this.

## 2. Second-order lessons are where the value concentrates

The most useful rules are not about the code. They are about how the *previous
rule* got misapplied, or about the reliability of the project's own documents.

> Check paths and directory names against `git ls-files`, not against the prose.
> The root `CLAUDE.md` described the frontend as a directory that does not exist
> for six months; the error leaked into a plan and stopped implementation halfway.
> A document describing structure is as much a source of errors as code is.
> *(translated)*

The rule is not "check paths". It is *the instruction file itself is an
untrusted source*. Same class, different target: the game's overlay caps comment
verbosity because its own earlier rule about justified comments produced the
repo's number-one over-documentation pattern — agents transcribing plan rationale
into inline blocks.

**Implication:** an overlay that only accumulates first-order rules will grow
monotonically and start contradicting itself. The ones that hold up are the ones
that record how an earlier rule failed.

## 3. Triggers must be zero-knowledge-observable, and both projects enforce it

The game's domain catalog carries this as an HTML comment above the list:

> `<!-- trigger MUST be zero-knowledge-observable (path glob / literal token),
> never a concept. -->`

In practice every trigger is a path glob or a literal identifier — `Query<`,
`Changed<`, `.gdshader`, `services/gateway/**`, `Gd<`. Never "when working on
rendering". The reason is mechanical: the agent deciding whether to load a
module has not read the module, so a conceptual trigger asks it to classify work
it does not yet understand. A token it can grep for needs no understanding at
all.

Both catalogs end with the same hard rule, which the skill supplies and neither
project weakened:

> `before you plan or write any part whose work matches a trigger above — even if
> this task was not framed as being in that domain — you MUST Read the mapped
> module first and treat it as normative.`

The "even if this task was not framed as being in that domain" clause is the
load-bearing half. Domain leakage — a task framed as UI work that quietly edits
a determinism-critical path — is the case the gate exists for.

## 4. Domain modules are normative, and say so in their own header

> `# NORMATIVE when active — a constraint to satisfy, not a claim for you to
> audit.`

Without that line an adversarial reviewer treats the domain module as another
artifact to challenge, which is exactly wrong: the module encodes decisions
already made and paid for. The pipeline's adversarial framing has to be switched
off for this one input class, explicitly, or the reviewer spends its budget
re-litigating settled architecture.

The same module shows how precise these get. Its determinism rules distinguish
CPU float behaviour (correctly rounded, safe to rely on) from GPU (vendor-variable,
`OpFDiv` 2.5 ULP, `fma()` not guaranteed fused) and mark the reviewer-corrected
wording as **use it verbatim**. That level of specificity cannot be produced by
reading the codebase; it came out of a task that had to establish it.

## 5. Stage-gated agent files carry tool procedure, not values

The game's overlay has one file per pipeline stage. They are short and almost
entirely operational — which skill to load, which LSP call to make, which script
to run, what counts as a hard blocker:

> `LSP-first for verification: findReferences — confirm nothing was missed by the
> implementer; prepareCallHierarchy/incomingCalls — understand vessel functions
> before judging a change; goToImplementation — when a trait impl changed.`
>
> `A BLOCKING SIGNAL (naked block_on, i.e. blocking-to-completion not
> block_on(poll_once(...))) is a hard blocker.`

No exhortation to be careful. Each line is a command with a defined outcome.
The backend project has no agent files at all and works fine without them —
they earn their place only where a stage has a repeatable mechanical procedure
worth encoding.

## 6. The overlays are wildly different sizes, and it is not about codebase size

1385 lines against 218, for two projects of comparable scale. The difference is
how long each has been running MAW and how many defects have been converted into
rules. The overlay grows with *operating history*, not with lines of code.

This has a practical consequence for anyone starting: an overlay that is thin at
the beginning is not misconfigured. The constant README plus a couple of domain
modules is the correct starting state, and the rest arrives one scar at a time.

## What none of this establishes

No measurement here shows the overlay improves outcomes. It shows what the
overlays contain and how they got that way. The `maw-context` surface has no
acceptance rows and no controlled comparison against running without it —
that remains open work, and it is the honest caveat to attach to everything above.
