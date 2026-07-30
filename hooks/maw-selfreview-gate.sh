#!/bin/sh
# MAW self-review gate (Claude Code `PreToolUse` hook on Bash).
#
# Fires when the session is about to run `git commit` and the staged diff is
# either large or touches invariant-bearing paths. Blocks the commit until a
# self-review has been run on that exact diff.
#
# DESIGN CONSTRAINTS, all learned the hard way and all load-bearing:
#
# 1. Speed. Industry reports are consistent: a pre-commit hook slower than
#    ~15s gets routed around with --no-verify, permanently, and then it
#    protects nothing. This script does no model calls itself - it only
#    decides whether a review is required and whether a fresh one exists.
#
# 2. A cheap, visible bypass. A gate that cannot be skipped gets disabled
#    wholesale. MAW_SKIP_SELFREVIEW=1 skips it, and the skip is recorded, so
#    the escape hatch stays honest instead of becoming silent muscle memory.
#
# 3. Freshness is keyed to the diff, not to time. A review of a previous diff
#    tells you nothing about this one.
set -eu

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJECT_DIR" ] || exit 0
cd "$PROJECT_DIR" 2>/dev/null || exit 0

# Only interested in commit attempts. The tool input arrives as JSON on stdin;
# read it without a JSON parser, since this must stay fast and dependency-free.
INPUT=$(cat 2>/dev/null || true)
case "$INPUT" in
  *"git commit"*) : ;;
  *) exit 0 ;;
esac

# Amending or continuing an in-flight commit is not new work.
case "$INPUT" in
  *--amend*|*--no-verify*) exit 0 ;;
esac

if [ "${MAW_SKIP_SELFREVIEW:-0}" = "1" ]; then
  mkdir -p maw
  printf '%s skipped: MAW_SKIP_SELFREVIEW=1\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> maw/.selfreview-skips
  echo "maw self-review: skipped by MAW_SKIP_SELFREVIEW (recorded in maw/.selfreview-skips)" >&2
  exit 0
fi

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
[ -n "$STAGED" ] || exit 0            # nothing staged: not our business

LINES=$(git diff --cached --numstat 2>/dev/null | awk '{a+=$1; d+=$2} END {print a+d+0}')
THRESHOLD="${MAW_SELFREVIEW_LINES:-60}"

# Invariant-bearing paths: configurable, one glob per line. A change here is
# reviewed regardless of size, because small edits to contracts are exactly the
# ones that look harmless.
INV_FILE="maw/selfreview-invariants"
TOUCHES_INVARIANT=0
if [ -f "$INV_FILE" ]; then
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in \#*) continue ;; esac
    if printf '%s\n' "$STAGED" | grep -q -- "$pat"; then TOUCHES_INVARIANT=1; break; fi
  done < "$INV_FILE"
fi

if [ "$LINES" -lt "$THRESHOLD" ] && [ "$TOUCHES_INVARIANT" -eq 0 ]; then
  exit 0                              # small and touches nothing load-bearing
fi

# A review counts only if it was run against THIS diff.
DIGEST=$(git diff --cached 2>/dev/null | sha256sum | cut -c1-16)
MARK="maw/.selfreview/$DIGEST"
if [ -f "$MARK" ]; then
  if grep -qi "^BLOCKING" "$MARK"; then
    echo "maw self-review: this diff was reviewed and BLOCKING findings stand." >&2
    echo "" >&2
    sed -n '1,20p' "$MARK" >&2
    echo "" >&2
    echo "Fix them and re-review, or commit with MAW_SKIP_SELFREVIEW=1 to override on the record." >&2
    exit 2
  fi
  exit 0                              # reviewed, nothing blocking
fi

REASON="diff is $LINES lines (threshold $THRESHOLD)"
[ "$TOUCHES_INVARIANT" -eq 1 ] && REASON="it touches an invariant-bearing path"

echo "maw self-review: this commit needs a review because $REASON." >&2
echo "" >&2
echo "Run /maw-selfreview — it is one spawn on a different vendor, about a minute," >&2
echo "and it writes its verdict to $MARK so this gate lets the commit through." >&2
echo "" >&2
echo "To skip deliberately: MAW_SKIP_SELFREVIEW=1 (recorded in maw/.selfreview-skips)." >&2
exit 2
