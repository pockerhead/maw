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

# A premise halt is a legitimate one-spawn ending: the premise check found the
# question mis-posed and stopped the chain on purpose. Still requires evidence -
# the premise artifact and a real spawn record - so "halted" cannot become a
# free exit from any incomplete run.
HALTED="$RUN_DIR/HALTED.md"
if [ -f "$HALTED" ]; then
  [ -s "$HALTED" ] || fail "HALTED.md is empty. A halt names the verdict, the mis-posing and the proposed reframing."
  grep -qi "premise-suspect" "$HALTED" || fail "HALTED.md does not name a halt reason."
  [ -s "$RUN_DIR/PREMISE.md" ] || fail "HALTED.md claims a premise halt but PREMISE.md is missing - the premise check did not actually run."
  grep -q '"stem"[[:space:]]*:[[:space:]]*"premise-check"' "$RUN_DIR/SPAWNS.jsonl" 2>/dev/null \
    || fail "HALTED.md claims a premise halt but no premise-check spawn is recorded."
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

# Ledger validation must PARSE the records, not grep them. Substring matching
# was bypassable in three separate ways, all found by adversarial review:
#   - {"event":"contract_violation","detail":{"stem":"attacker","exit":0,"fresh":true}}
#     satisfies every substring test while recording that a role did NOT run;
#   - a legitimate record with keys in a different order failed the ordered
#     stem→exit→fresh pattern, so serialization order changed the verdict;
#   - the intermediate file lived in the run dir, which every role can write,
#     making a fixed name a symlink target for a hostile role.
# Top-level fields only, real JSON, no temp file.
LEDGER_CHECK='
import json, sys
path, expected = sys.argv[1], int(sys.argv[2])
required = {"premise-check", "generator", "compressor", "attacker", "synthesizer"}
ok, stems, malformed = 0, set(), 0
for line in open(path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except Exception:
        malformed += 1
        continue
    if not isinstance(rec, dict):
        continue
    # A spawn record is one with no competing event type and real top-level
    # status fields. Nested copies of these keys are ignored by construction.
    if rec.get("event") not in (None, "spawn"):
        continue
    stem = rec.get("stem")
    if not isinstance(stem, str):
        continue
    if rec.get("exit") != 0 or rec.get("fresh") is not True:
        continue
    ok += 1
    stems.add(stem)
    u = rec.get("usage")
    if isinstance(u, dict):
        i, o = u.get("input_tokens"), u.get("output_tokens")
        c, r = u.get("cached_input_tokens"), u.get("reasoning_output_tokens")
        if isinstance(i, int) and isinstance(c, int) and c > i:
            print(f"USAGE_ARITHMETIC {stem}: cached_input {c} > input {i}"); sys.exit(3)
        if isinstance(o, int) and isinstance(r, int) and r > o:
            print(f"USAGE_ARITHMETIC {stem}: reasoning_output {r} > output {o}"); sys.exit(3)
missing = sorted(required - stems)
if malformed:
    print(f"MALFORMED {malformed}"); sys.exit(4)
if ok < expected:
    print(f"COUNT {ok}"); sys.exit(1)
if missing:
    print("MISSING " + ",".join(missing)); sys.exit(2)
print("OK")
'
LEDGER_RESULT=""
LEDGER_RC=0
for PY in python3 python; do
  command -v "$PY" >/dev/null 2>&1 || continue
  # `set -e` would abort the script the moment the checker exits non-zero,
  # skipping the case below entirely: the hook would die with python's exit
  # code instead of 2, and a Stop hook only blocks on 2. So the run is
  # deliberately unguarded here and the status captured by hand.
  set +e
  LEDGER_RESULT=$("$PY" -c "$LEDGER_CHECK" "$LEDGER" "$EXPECTED_SPAWNS" 2>/dev/null)
  LEDGER_RC=$?
  set -e
  break
done

if [ -z "$LEDGER_RESULT" ]; then
  # No interpreter: say so rather than pretending the ledger was checked.
  echo "maw-reason gate: no python available; artifacts verified but SPAWNS.jsonl was NOT validated." >&2
  exit 0
fi

case "$LEDGER_RC" in
  0) : ;;
  1) fail "only ${LEDGER_RESULT#COUNT } successful spawn record(s); this run's manifest expects $EXPECTED_SPAWNS. A record needs a top-level stem, exit 0 and fresh:true, and must not be an incident record." ;;
  2) fail "no successful spawn recorded for: ${LEDGER_RESULT#MISSING }. Being named inside an incident record does not count as having run." ;;
  3) fail "ledger usage figures are internally inconsistent — ${LEDGER_RESULT#USAGE_ARITHMETIC }. Numbers that cannot be true were not parsed from the provider." ;;
  4) fail "${LEDGER_RESULT#MALFORMED } malformed line(s) in SPAWNS.jsonl. A ledger that does not parse is not evidence." ;;
  *) fail "ledger validation failed unexpectedly ($LEDGER_RESULT)." ;;
esac

exit 0
