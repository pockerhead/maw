#!/bin/sh
# MAW Reason enforcement gate (Claude Code `Stop` hook).
#
# A simulated chain and a real one look identical in their output text. This
# hook makes the difference checkable: if a reason run is active, the turn
# cannot end until the run's own manifest is satisfied - every expected
# artifact present and fresh, and a spawn ledger with the expected number of
# distinct, successful role spawns.
#
# WHAT THIS CANNOT DO. The model can write these files. A determined simulator
# can forge a manifest, five ledger lines with distinct stems, and five
# artifacts. The gate raises the cost of faking a chain from "write some prose"
# to "fabricate a consistent evidence set on purpose", and converts an
# accidental shortcut into a deliberate lie. It is not a security boundary and
# must not be described as one.
#
# Blocking uses exit code 2 with the reason on stderr (documented Stop-hook
# behavior). Deliberately not the JSON `decision:block` form: run paths on
# Windows contain backslashes, and hand-rolled JSON escaping of them in sh is
# a bug farm.
#
# Install: install.sh --claude --with-reason --with-hooks, then wire it into
# .claude/settings.json (the installer prints the snippet).
set -eu

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  # Outside the supported hook runtime there is no reliable project root.
  # Fail open rather than block every turn on a wrong guess, but say why.
  echo "maw-reason gate: CLAUDE_PROJECT_DIR unset; not enforcing." >&2
  exit 0
fi

POINTER="$PROJECT_DIR/maw/.reason-last-run"
[ -f "$POINTER" ] || exit 0

RUN_DIR=$(head -n 1 "$POINTER" 2>/dev/null || true)
[ -n "$RUN_DIR" ] || exit 0

# A pointer naming a deleted dir is the normal end state of a run without --keep.
[ -d "$RUN_DIR" ] || exit 0

# Only an active run is enforceable. The caller deletes this marker on every
# exit path, so its absence means the run is finished or was cleaned up.
ACTIVE="$PROJECT_DIR/maw/.reason-active"
[ -f "$ACTIVE" ] || exit 0

# The marker is project-wide but the obligation is not: only the session that
# started the chain must finish it. Without this check the gate blocks every
# other Claude Code session working in the same repo - observed live, in a
# session that had nothing to do with the run.
OWNER=$(sed -n 's/^session=//p' "$ACTIVE" 2>/dev/null | head -n 1)
MY_SESSION="${CLAUDE_CODE_SESSION_ID:-}"
if [ -n "$OWNER" ]; then
  [ "$OWNER" = "$MY_SESSION" ] || exit 0    # someone else's run; not our turn to gate
else
  # Pre-session-tagging marker, or a caller that did not record ownership.
  # Fail open: blocking an uninvolved session is worse than missing one gate.
  echo "maw-reason gate: run marker has no session= line; not enforcing." >&2
  exit 0
fi

QUESTION="$RUN_DIR/QUESTION.md"
[ -f "$QUESTION" ] || exit 0

fail() {
  echo "maw-reason gate: $1" >&2
  echo "Run dir: $RUN_DIR" >&2
  echo "Every role must run as a real spawn. Writing the artifacts yourself is the" >&2
  echo "failure mode this gate exists to catch, and it is invisible in the output" >&2
  echo "text. Finish the chain properly, or write CHAIN_FAILURE.md (with the role," >&2
  echo "profile, failure class and stderr tail) and relay that instead." >&2
  exit 2
}

# A chain that failed loudly is a legitimate end state - but an empty file is
# not a failure report, it is the cheapest possible bypass.
FAILURE="$RUN_DIR/CHAIN_FAILURE.md"
if [ -f "$FAILURE" ]; then
  if [ ! -s "$FAILURE" ]; then
    fail "CHAIN_FAILURE.md exists but is empty. A failure report names the role, the resolved profile, the failure class and the stderr tail."
  fi
  grep -qi "class" "$FAILURE" || fail "CHAIN_FAILURE.md does not state a failure class."
  exit 0
fi

# The manifest says what THIS run was supposed to be. Without it we would check
# the default topology and pass a five-spawn run as a claimed high-assurance one.
MANIFEST="$RUN_DIR/RUN.json"
EXPECTED_SPAWNS=5
EXPECTED_ARTIFACTS="PREMISE.md POSITION.md CLAIM_MAP.md ATTACK.md SYNTHESIS.md"
if [ -s "$MANIFEST" ]; then
  n=$(sed -n 's/.*"expected_spawns"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$MANIFEST" | head -n 1)
  [ -n "$n" ] && EXPECTED_SPAWNS="$n"
  a=$(sed -n 's/.*"expected_artifacts"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$MANIFEST" | head -n 1 \
      | tr -d '" ' | tr ',' ' ')
  [ -n "$a" ] && EXPECTED_ARTIFACTS="$a"
else
  fail "RUN.json is missing. The manifest is what states the topology this run claimed; without it the gate cannot tell a default run from a high-assurance one."
fi

MISSING=""
for artifact in $EXPECTED_ARTIFACTS; do
  if [ ! -s "$RUN_DIR/$artifact" ]; then
    MISSING="$MISSING $artifact"
  elif [ ! "$RUN_DIR/$artifact" -nt "$QUESTION" ]; then
    # -nt, not -ot: an artifact with a timestamp equal to the question is not
    # proof of freshness. This is still only an mtime comparison - it bounds
    # sloppiness, it does not prove which process wrote the file.
    MISSING="$MISSING $artifact(not-newer-than-question)"
  fi
done
[ -n "$MISSING" ] && fail "the chain is incomplete. Missing or stale:$MISSING"

LEDGER="$RUN_DIR/SPAWNS.jsonl"
[ -s "$LEDGER" ] || fail "artifacts exist but SPAWNS.jsonl is missing or empty, so no role was actually spawned. Artifacts without spawns are a simulated chain."

# Count only lines that look like a real record: a stem, a zero exit, freshness.
OK_LINES=$(grep -c '"stem"[[:space:]]*:.*"exit"[[:space:]]*:[[:space:]]*0.*"fresh"[[:space:]]*:[[:space:]]*true' "$LEDGER" 2>/dev/null || true)
[ -n "$OK_LINES" ] || OK_LINES=0
if [ "$OK_LINES" -lt "$EXPECTED_SPAWNS" ]; then
  fail "only $OK_LINES successful spawn record(s); this run's manifest expects $EXPECTED_SPAWNS. A record needs a stem, exit 0 and fresh:true."
fi

# Distinct stems: five duplicate generator records are not a chain.
DISTINCT=$(sed -n 's/.*"stem"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$LEDGER" | sort -u | wc -l | tr -d ' ')
for required in premise-check generator compressor attacker synthesizer; do
  grep -q "\"stem\"[[:space:]]*:[[:space:]]*\"$required\"" "$LEDGER" \
    || fail "no spawn recorded for role '$required' ($DISTINCT distinct stems in the ledger). Every role in the chain must have run."
done

exit 0
