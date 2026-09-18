#!/bin/sh
# One synchronous external attempt. Provider flags and lifecycle belong to SKILL.md.
# Usage: sh runner.sh WORK_ROOT SPAWN_TMP CAPTURE ARTIFACT -- COMMAND [ARG...]
# ARTIFACT is an absolute path, or - for an explicitly sanctioned materialization.
set -eu
child_umask=$(umask)
umask 077

fail() { printf '%s\n' "maw runner: $*" >&2; exit 64; }

[ "$#" -ge 6 ] || fail 'expected WORK_ROOT SPAWN_TMP CAPTURE ARTIFACT -- COMMAND [ARG...]'
work_root=$1
spawn_tmp=$2
capture=$3
artifact=$4
shift 4
[ "$1" = -- ] || fail 'missing -- before command'
shift

case "$capture" in events.jsonl|result.json) ;; *) fail 'capture must be events.jsonl or result.json' ;; esac
# Resolve before changing cwd; accept Windows forward-slash paths under Git Bash.
work_root=$(CDPATH= cd -- "$work_root" && pwd -P) || fail 'invalid work root'
spawn_tmp=$(CDPATH= cd -- "$spawn_tmp" && pwd -P) || fail 'invalid spawn directory'
[ -f "$spawn_tmp/prompt.md" ] && [ -r "$spawn_tmp/prompt.md" ] || fail 'prompt.md is not readable'
if [ "$artifact" != - ]; then
    case "$artifact" in /*|[A-Za-z]:/*) ;; *) fail 'artifact must be an absolute path' ;; esac
    [ ! -e "$artifact" ] && [ ! -L "$artifact" ] || fail 'archive the existing artifact before spawning'
fi
[ ! -e "$spawn_tmp/$capture" ] && [ ! -L "$spawn_tmp/$capture" ] || fail 'capture already exists'
[ ! -e "$spawn_tmp/stderr.log" ] && [ ! -L "$spawn_tmp/stderr.log" ] || fail 'stderr.log already exists'
# mkdir is also the per-directory attempt lock: never reuse a spawn directory.
mkdir "$spawn_tmp/runner" || fail 'spawn directory already used or not writable'
cd -- "$work_root" || fail 'cannot enter work root'
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$spawn_tmp/runner/started"

# Open captures before launching. The child writes straight to files, so losing
# the host's progress reader cannot close its stdout or interrupt the attempt.
: > "$spawn_tmp/$capture"
: > "$spawn_tmp/stderr.log"
(
    umask "$child_umask"
    exec "$@"
) < "$spawn_tmp/prompt.md" > "$spawn_tmp/$capture" 2> "$spawn_tmp/stderr.log" &
child_pid=$!
# Only the supervising shell ignores SIGPIPE; the already-started child retains
# the caller's signal disposition. Display failure must never abort supervision.
trap '' PIPE
printf '%s\n' 'maw: starting external process' 2>/dev/null || :
seen=0
previous=
display=1
# MAW_RUNNER_PROGRESS=0 keeps the start/exit lines and drops the event stream.
[ "${MAW_RUNNER_PROGRESS:-1}" != 0 ] || display=0
show_progress() {
    [ "$display" -eq 1 ] || return 0
    # Cosmetic extraction only. JSON validation belongs to the orchestrator.
    if awk -v seen="$seen" -v previous="$previous" -v state="$spawn_tmp/runner/progress-state" '
        NR > seen && match($0, /"type"[[:space:]]*:[[:space:]]*"[a-zA-Z_.]+"/) {
            event = substr($0, RSTART, RLENGTH)
            sub(/^"type"[[:space:]]*:[[:space:]]*"/, "", event)
            sub(/"$/, "", event)
            if ($0 ~ /"type"[[:space:]]*:[[:space:]]*"tool_use"/) event = "tool_use"
            if ($0 ~ /"type"[[:space:]]*:[[:space:]]*"result"/) event = "result"
            if ($0 ~ /"subtype"[[:space:]]*:[[:space:]]*"thinking_tokens"/) event = "working"
            if (event != previous) print "maw: " event
            previous = event
        }
        END { print NR, previous > state }
    ' "$spawn_tmp/$capture" 2>/dev/null; then
        if ! read -r seen previous < "$spawn_tmp/runner/progress-state"; then display=0; fi
    else
        display=0
    fi
}
# This is an internal shell wait, not an orchestrator/tool-call polling loop.
# Tree cancellation still belongs to the host; the wrapper never kills a child.
while kill -0 "$child_pid" 2>/dev/null; do
    show_progress
    sleep 1
done
child_exit=0
wait "$child_pid" || child_exit=$?
printf '%s\n' "$child_exit" > "$spawn_tmp/runner/exit-code"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$spawn_tmp/runner/finished"
show_progress

artifact_state=missing
if [ "$artifact" = - ]; then
    artifact_state=materialize
elif [ -f "$artifact" ] && [ -s "$artifact" ] && [ ! -L "$artifact" ]; then
    artifact_state=present
fi
printf '%s\n' "$artifact_state" > "$spawn_tmp/runner/artifact"
printf 'maw: process exited %s; artifact %s\n' "$child_exit" "$artifact_state" 2>/dev/null || :
[ "$child_exit" -eq 0 ] || exit "$child_exit"
[ "$artifact_state" != missing ] || exit 65
# Zero means transport/file checks only; JSON and the stage contract are unchecked.
exit 0
