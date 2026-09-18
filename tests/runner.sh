#!/bin/sh
# Local transport/installation fixtures. No provider calls or additional runtime.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
runner=${1:-"$repo/skills/maw-execute-task/scripts/runner.sh"}
temp_parent=$(CDPATH= cd -- "${TMPDIR:-/tmp}" && pwd -P)
test_root=$(mktemp -d "$temp_parent/maw-runner-test.XXXXXX")
cleanup() {
    case "$test_root" in "$temp_parent"/maw-runner-test.*) rm -rf -- "$test_root" ;; esac
}
trap cleanup EXIT
mkdir "$test_root/work space"
work="$test_root/work space"
count=0
expect_exit() {
    expected=$1; shift
    actual=0
    "$@" || actual=$?
    [ "$actual" -eq "$expected" ] || { echo "expected exit $expected, got $actual" >&2; exit 1; }
    count=$((count + 1))
}
attempt() {
    spawn="$test_root/spawn $1"
    mkdir "$spawn"
    # Octal UTF-8 bytes and CRLF exercise byte preservation without console encoding.
    printf '\320\237\321\200\320\270\320\262\320\265\321\202 \302\260\r\n' > "$spawn/prompt.md"
}

attempt success
expect_exit 0 sh "$runner" "$work" "$spawn" result.json "$work/artifact.md" -- sh -c '
    [ "$PWD" = "$1" ] && [ -f "$2/runner/started" ] || exit 9
    [ "$3" = "literal \$(no-exec); *" ] && [ "$4" = "" ] || exit 10
    cat > "$1/artifact.md"
    cat "$1/artifact.md"
    printf diagnostic >&2
' fixture "$work" "$spawn" 'literal $(no-exec); *' ''
cmp "$spawn/prompt.md" "$work/artifact.md"
cmp "$spawn/prompt.md" "$spawn/result.json"
[ "$(cat "$spawn/stderr.log")" = diagnostic ]
[ "$(cat "$spawn/runner/exit-code")" = 0 ]
[ "$(cat "$spawn/runner/artifact")" = present ]
[ -s "$spawn/runner/finished" ]
expect_exit 64 sh "$runner" "$work" "$spawn" result.json - -- true

attempt stale
expect_exit 64 sh "$runner" "$work" "$spawn" result.json "$work/artifact.md" -- sh -c 'exit 99'
[ ! -d "$spawn/runner" ]
cmp "$spawn/prompt.md" "$work/artifact.md"

attempt failure
expect_exit 23 sh "$runner" "$work" "$spawn" events.jsonl "$work/missing.md" -- sh -c 'printf partial; printf error >&2; exit 23'
[ "$(cat "$spawn/events.jsonl")" = partial ]
[ "$(cat "$spawn/stderr.log")" = error ]
[ "$(cat "$spawn/runner/exit-code")" = 23 ]

# The child waits for the visible progress before finishing: a buffered display
# cannot pass this case. JSONL capture must still be byte-for-byte unchanged.
attempt live
expect_exit 0 sh "$runner" "$work" "$spawn" events.jsonl "$work/live.md" -- sh -c '
    printf "%s\n" "{\"type\":\"assistant\"}"
    n=0
    until grep -q "maw: assistant" "$2"; do
        n=$((n + 1)); [ "$n" -lt 10 ] || exit 19
        sleep 1
    done
    printf "%s\n" "{\"type\":\"assistant\"}"
    sleep 1
    printf "%s\n" "{\"type\":\"result\"}"
    printf done > "$1"
' fixture "$work/live.md" "$test_root/live.log" > "$test_root/live.log"
grep -q 'maw: result' "$test_root/live.log"
printf '%s\n' '{"type":"assistant"}' '{"type":"assistant"}' '{"type":"result"}' > "$test_root/expected-live.jsonl"
cmp "$test_root/expected-live.jsonl" "$spawn/events.jsonl"
[ "$(grep -c 'maw: assistant' "$test_root/live.log")" -eq 1 ]
printf '%s\n' '{"type":"assistant"}' '{"type":"result"}' > "$test_root/expected.jsonl"

# MAW_RUNNER_PROGRESS=0 drops the event stream but keeps start/exit lines and capture.
attempt quiet
expect_exit 0 env MAW_RUNNER_PROGRESS=0 sh "$runner" "$work" "$spawn" events.jsonl "$work/quiet.md" -- sh -c '
    printf "%s\n" "{\"type\":\"assistant\"}"
    sleep 2
    printf "%s\n" "{\"type\":\"result\"}"
    printf done > "$1"
' fixture "$work/quiet.md" > "$test_root/quiet.log"
[ "$(grep -c '^maw: ' "$test_root/quiet.log")" -eq 2 ]
grep -q 'maw: starting external process' "$test_root/quiet.log"
grep -q 'maw: process exited 0; artifact present' "$test_root/quiet.log"
cmp "$test_root/expected.jsonl" "$spawn/events.jsonl"

# Closing the host stdout reader must not break the provider or truncate capture.
attempt closed-reader
(
    expect_exit 0 sh "$runner" "$work" "$spawn" events.jsonl "$work/closed-reader.md" -- sh -c '
        sleep 1
        printf "%s\n" "{\"type\":\"assistant\"}"
        sleep 1
        printf "%s\n" "{\"type\":\"result\"}"
        printf survived > "$1"
    ' fixture "$work/closed-reader.md"
    printf completed > "$test_root/wrapper-completed"
) | head -n 1
[ -f "$test_root/wrapper-completed" ]
[ "$(cat "$work/closed-reader.md")" = survived ]
cmp "$test_root/expected.jsonl" "$spawn/events.jsonl"
count=$((count + 1))

attempt umask
expected_umask=$(umask)
expect_exit 0 sh "$runner" "$work" "$spawn" result.json "$work/umask.md" -- sh -c 'umask > "$1"' fixture "$work/umask.md"
[ "$(cat "$work/umask.md")" = "$expected_umask" ]

for status in 64 65; do
    attempt "child-$status"
    expect_exit "$status" sh "$runner" "$work" "$spawn" events.jsonl - -- sh -c 'exit "$1"' fixture "$status"
    [ "$(cat "$spawn/runner/exit-code")" = "$status" ]
done

attempt missing
expect_exit 65 sh "$runner" "$work" "$spawn" result.json "$work/missing.md" -- true
[ "$(cat "$spawn/runner/exit-code")" = 0 ]
[ "$(cat "$spawn/runner/artifact")" = missing ]

attempt empty
expect_exit 65 sh "$runner" "$work" "$spawn" result.json "$work/empty.md" -- sh -c ': > "$1"' fixture "$work/empty.md"

attempt materialize
expect_exit 0 sh "$runner" "$work" "$spawn" result.json - -- sh -c 'printf final-message'
[ "$(cat "$spawn/runner/artifact")" = materialize ]
[ "$(cat "$spawn/result.json")" = final-message ]

attempt unavailable
expect_exit 127 sh "$runner" "$work" "$spawn" result.json - -- maw-no-such-provider-command
[ "$(cat "$spawn/runner/exit-code")" = 127 ]

attempt badcapture
expect_exit 64 sh "$runner" "$work" "$spawn" ../escape - -- true
[ ! -e "$test_root/escape" ]

attempt relative
expect_exit 64 sh "$runner" "$work" "$spawn" result.json relative.md -- true

attempt noprompt
mv "$spawn/prompt.md" "$spawn/other.md"
expect_exit 64 sh "$runner" "$work" "$spawn" result.json - -- true

attempt badcwd
expect_exit 64 sh "$runner" "$test_root/absent" "$spawn" result.json - -- true

# Both surfaces and a second install must ship the exact runner and role bodies.
mkdir "$test_root/install space"
(
    cd "$test_root/install space"
    sh "$repo/install.sh" --all > "$test_root/install.log"
    sh "$repo/install.sh" --all >> "$test_root/install.log"
    for surface in .claude .agents; do
        cmp "$runner" "$surface/skills/maw-execute-task/scripts/runner.sh"
        for body in "$repo"/skills/maw-execute-task/agents/*.md; do
            cmp "$body" "$surface/skills/maw-execute-task/agents/$(basename "$body")"
        done
    done
)
printf 'PASS: %s runner cases; both installation surfaces and reinstall\n' "$count"
