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

# pctx-sleep.sh fixtures: overflow, refs, holder, restore, validate, migrate-check.
pctx="$repo/skills/maw-execute-task/scripts/pctx-sleep.sh"
mkdir "$test_root/pctx space"
pt="$test_root/pctx space"
out="$pt/out"
lines() { i=0; while [ "$i" -lt "$2" ]; do echo "line $i"; i=$((i + 1)); done > "$1"; }
code="$pt/code"
ov="$code/maw/project-context"
mkdir -p "$code/src" "$code/skills/x/scripts" "$ov/domains" "$ov/archive"
printf 'fn verify_token() {}\n' > "$code/src/here.rs"
printf 'echo\n' > "$code/skills/x/scripts/runner.sh"
cat > "$ov/domains/core.md" <<'MD'
# Core
## Invariants
- `src/here.rs` and `src/gone.rs`
- `verify_token` `dead_fn_name` `make`
- `runner.sh` `src/here.rs:12` `src/**` `maw/settings.json`
## Risk lessons
- old lesson
MD
(cd "$code" && git init -q && git add -A)

# T1-T3: check
export MAW_PCTX_DOMAIN_MAX=5 MAW_PCTX_TOTAL_MAX=1000
mkdir -p "$pt/c1/domains"
lines "$pt/c1/domains/a.md" 5
expect_exit 0 sh "$pctx" check "$pt/c1" > "$out"; [ ! -s "$out" ]
lines "$pt/c1/domains/a.md" 6
expect_exit 10 sh "$pctx" check "$pt/c1" > "$out"; grep -q 'overflow file=domains/a.md' "$out"
export MAW_PCTX_TOTAL_MAX=10
mkdir -p "$pt/c3/domains" "$pt/c3/archive"
lines "$pt/c3/domains/a.md" 4; lines "$pt/c3/README.md" 2; lines "$pt/c3/archive/a.md" 100
expect_exit 0 sh "$pctx" check "$pt/c3" > "$out"; [ ! -s "$out" ]
lines "$pt/c3/README.md" 8
expect_exit 10 sh "$pctx" check "$pt/c3" > "$out"; grep -q 'file=TOTAL' "$out"
unset MAW_PCTX_DOMAIN_MAX MAW_PCTX_TOTAL_MAX

# T4: an absent overlay is a no-op for every subcommand
na="$pt/absent"
expect_exit 0 sh "$pctx" check "$na" > "$out"; [ ! -s "$out" ]
expect_exit 0 sh "$pctx" refs "$na" "$code" > "$out"; [ ! -s "$out" ]
expect_exit 0 sh "$pctx" restore "$na" "$code" "$pt" > "$out"; [ ! -s "$out" ]
expect_exit 0 sh "$pctx" restore --dry-run "$na" "$code" "$pt" > "$out"; [ ! -s "$out" ]
expect_exit 0 sh "$pctx" validate "$na" "$code" > "$out"; [ ! -s "$out" ]
expect_exit 0 sh "$pctx" migrate-check "$na" "$pt/c1" > "$out"; [ ! -s "$out" ]
expect_exit 0 sh "$pctx" state "$na" TASK-1 ok > "$out"; [ ! -s "$out" ]
[ "$(sh "$pctx" untagged "$na")" = untagged=0 ]
[ ! -e "$na" ]

# T5 + T18: refs reports only real misses
expect_exit 0 sh "$pctx" refs "$ov" "$code" > "$out"
[ "$(wc -l < "$out" | tr -d ' ')" = 2 ]
grep -q '^missing domains/core.md:3 src/gone.rs$' "$out"
grep -q '^missing domains/core.md:4 dead_fn_name$' "$out"
cat > "$ov/domains/extra.md" <<'MD'
- `src/gone.rs:12` `./src/gone2.rs` `gone_fn()` `gpt-5.5` `1.0` `self.health` `obj.verify_token`
MD
printf 'self.health = 1
' > "$code/src/obj.rs"; (cd "$code" && git add -A)
expect_exit 0 sh "$pctx" refs "$ov" "$code" > "$out"
grep -q '^missing domains/extra.md:1 src/gone.rs:12$' "$out"
grep -q '^missing domains/extra.md:1 \./src/gone2.rs$' "$out"
grep -q '^missing domains/extra.md:1 gone_fn()$' "$out"
grep -q '^missing domains/extra.md:1 obj.verify_token$' "$out"
[ "$(grep -c 'extra.md' "$out")" = 4 ]
rm "$ov/domains/extra.md"
mkdir "$pt/nogit"; expect_exit 2 sh "$pctx" refs "$ov" "$pt/nogit" 2> /dev/null

# T6: holder
expect_exit 0 sh "$pctx" holder "$code" 'src/here.rs#verify_token'
expect_exit 1 sh "$pctx" holder "$code" 'src/here.rs#nope'
expect_exit 1 sh "$pctx" holder "$code" maw/project-context/x.md

# T7-T10, T19: restore
task="$pt/TASK-007"
mkdir "$task"
arch_entry() { printf -- '- [lesson class=float-eq] compare with eps | archived: 2026-01-01 | reason: enforced | holder: %s\n' "$1" > "$ov/archive/core.md"; }
arch_entry 'src/here.rs#verify_token'
printf 'finding class=float-eq here\n' > "$task/QA_REPORT.md"
expect_exit 0 sh "$pctx" restore "$ov" "$code" "$task" > "$out"
grep -q '^restored=1 ' "$out"
grep -q '^- \[lesson class=float-eq\] compare with eps | restored: .* by TASK-007 reason=miss holder=[^ ]*$' "$ov/domains/core.md"
[ "$(tail -n 1 "$ov/domains/core.md" | cut -c1-24)" = '- [lesson class=float-eq' ]
[ ! -s "$ov/archive/core.md" ]
git -C "$code" checkout -q -- maw/project-context/domains/core.md
arch_entry 'src/here.rs#verify_token'
printf 'touches src/here.rs only\n' > "$task/QA_REPORT.md"
before=$(cksum "$ov/domains/core.md" "$ov/archive/core.md")
expect_exit 0 sh "$pctx" restore "$ov" "$code" "$task" > "$out"
grep -q '^candidate float-eq src/here.rs#verify_token$' "$out"
[ "$before" = "$(cksum "$ov/domains/core.md" "$ov/archive/core.md")" ]
arch_entry 'src/deleted.rs'
printf 'nothing\n' > "$task/QA_REPORT.md"
expect_exit 0 sh "$pctx" restore "$ov" "$code" "$task" > "$out"
grep -q 'reason=holder-missing holder=[^ ]*$' "$ov/domains/core.md"
git -C "$code" checkout -q -- maw/project-context/domains/core.md
arch_entry 'src/here.rs#verify_token'
printf 'class=float-eq\n' > "$task/QA_REPORT.md"
before=$(cksum "$ov/domains/core.md" "$ov/archive/core.md")
expect_exit 0 sh "$pctx" restore --dry-run "$ov" "$code" "$task" > "$out"
grep -q '^would-restore float-eq reason=miss$' "$out"
[ "$before" = "$(cksum "$ov/domains/core.md" "$ov/archive/core.md")" ]
printf 'class=float-eq-strict\n' > "$task/QA_REPORT.md"
expect_exit 0 sh "$pctx" restore "$ov" "$code" "$task" > "$out"
grep -q '^restored=0 ' "$out"
[ "$before" = "$(cksum "$ov/domains/core.md" "$ov/archive/core.md")" ]

# T11, T12, T17: validate
mkdir -p "$pt/v/domains"
printf '## Invariants\n- a\n## Procedures\n- b\n## Risk lessons\n- c\n  - sub\n' > "$pt/v/domains/d.md"
expect_exit 0 sh "$pctx" validate "$pt/v" "$code"
mkdir "$pt/v/archive"
printf -- '- [lesson class=x] t | archived: 2026-01-01 | reason: r\n' > "$pt/v/archive/d.md"
expect_exit 1 sh "$pctx" validate "$pt/v" "$code" > "$out"
printf -- '- [lesson class=untagged] t | archived: 2026-01-01 | reason: r | holder: src/here.rs\n' > "$pt/v/archive/d.md"
expect_exit 1 sh "$pctx" validate "$pt/v" "$code" > "$out"
rm -r "$pt/v/archive"
printf '## Risk lessons\n- [law] always x\n- [lesson class=a-b] y\n' > "$pt/v/domains/d.md"
expect_exit 0 sh "$pctx" validate "$pt/v" "$code"

# T14: untagged counts only top-level untagged bullets in the tagged sections
printf '## Invariants\n- a\n- [law] b\n  - sub\n## Risk lessons\n- c\n- d\n## Pointers\n- e\n' > "$pt/v/domains/d.md"
[ "$(sh "$pctx" untagged "$pt/v")" = untagged=3 ]

# T15-T16: migrate-check
mkdir -p "$pt/mb/domains" "$pt/ma/domains"
printf '## Invariants\n- keep `tok` here\n- two\n' > "$pt/mb/domains/d.md"
printf '## Invariants\n- [law] keep `tok` here\n- [lesson class=z] two\n' > "$pt/ma/domains/d.md"
expect_exit 0 sh "$pctx" migrate-check "$pt/mb" "$pt/ma"
mkdir "$pt/ma/archive"; printf 'x\n' > "$pt/ma/archive/x.md"
expect_exit 1 sh "$pctx" migrate-check "$pt/mb" "$pt/ma" > "$out"; grep -q '^changed archive/x.md$' "$out"
rm -r "$pt/ma/archive"
printf '## Invariants\n- [law] keep here\n- [lesson class=z] two\n' > "$pt/ma/domains/d.md"
expect_exit 1 sh "$pctx" migrate-check "$pt/mb" "$pt/ma" > "$out"; grep -q '^changed domains/d.md$' "$out"
printf '## Invariants
- [lesson class=a] keep
' > "$pt/mb/domains/d.md"
printf '## Invariants
- [law] keep
' > "$pt/ma/domains/d.md"
expect_exit 1 sh "$pctx" migrate-check "$pt/mb" "$pt/ma" > "$out"; grep -q '^changed domains/d.md$' "$out"

# Both surfaces and a second install must ship the exact runner and role bodies.
mkdir "$test_root/install space"
(
    cd "$test_root/install space"
    sh "$repo/install.sh" --all > "$test_root/install.log"
    sh "$repo/install.sh" --all >> "$test_root/install.log"
    for surface in .claude .agents; do
        cmp "$runner" "$surface/skills/maw-execute-task/scripts/runner.sh"
        cmp "$pctx" "$surface/skills/maw-execute-task/scripts/pctx-sleep.sh"
        for body in "$repo"/skills/maw-execute-task/agents/*.md; do
            cmp "$body" "$surface/skills/maw-execute-task/agents/$(basename "$body")"
        done
    done
)
printf 'PASS: %s runner and pctx-sleep cases; both installation surfaces and reinstall\n' "$count"
