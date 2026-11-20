#!/bin/sh
# Mechanical helpers for the project-context (PCTX) wrap-up. Contract: maw-context Step 3b.
# Usage: sh pctx-sleep.sh check|untagged|refs|holder|restore|validate|migrate-check|state ...
# Exit: 0 ok, 1 negative result, 10 overflow, 2 usage error.
# A PCTX argument that is not a directory is a no-op (exit 0, no output; untagged prints untagged=0).
set -eu

DOMAIN_MAX=${MAW_PCTX_DOMAIN_MAX:-200}
TOTAL_MAX=${MAW_PCTX_TOTAL_MAX:-1500}
TAG_RE='^- \[(law|procedure|lesson class=[a-z0-9-]+)\] '

usage() { printf '%s\n' "pctx-sleep: $*" >&2; exit 2; }
today() { date -u +%Y-%m-%d; }
line_count() { awk 'END { print NR }' "$1"; }

# Prints README.md, domains/*.md and agents/*.md that exist (relative to $1), one per line.
counted_files() {
    [ -f "$1/README.md" ] && printf '%s\n' README.md
    for f in "$1"/domains/*.md "$1"/agents/*.md; do
        [ -f "$f" ] && printf '%s\n' "${f#"$1"/}"
    done
    return 0
}

# Top-level bullets of the three tagged sections: prints "<line>\t<text>".
section_bullets() {
    awk '
        /^## / { s = ($0 == "## Invariants" || $0 == "## Procedures" || $0 == "## Risk lessons"); next }
        s && /^- / { printf "%d\t%s\n", NR, $0 }
    ' "$1"
}

# code_has ROOT TOKEN: 0 when the token is present in code or is never checked.
code_has() {
    root=$1; tok=$2
    case "$tok" in
        *[[:space:]]*|*://*|*'{'*|*'<'*|*'$'*|*'*'*|*'?'*|*'['*|maw/*|'') return 0 ;;
    esac
    paren=0
    case "$tok" in *'()') paren=1 ;; esac
    tok=$(printf '%s\n' "$tok" | sed -e 's|^\./||' -e 's|()$||' -e 's|#.*$||' -e 's|:[0-9][0-9]*\(-[0-9][0-9]*\)\{0,1\}$||')
    [ -n "$tok" ] || return 0
    case "$tok" in maw/*) return 0 ;; esac
    if printf '%s\n' "$tok" | grep -Eq '/|\.[A-Za-z0-9]+$'; then
        [ -e "$root/$tok" ] && return 0
        case "$tok" in */*) return 1 ;; esac
        # Versions and decimals (gpt-5.5, 1.0) are never checked.
        printf '%s\n' "$tok" | grep -Eq '\.[A-Za-z][A-Za-z0-9]*$' || return 0
        hits=$(git -C "$root" ls-files -- "$tok" "*/$tok" ':(exclude)maw' 2>/dev/null | head -n 1) || hits=
        [ -n "$hits" ] && return 0
        # Member access (self.health) counts as present when the text occurs in code.
        git -C "$root" grep -qwF -e "$tok" -- . ':(exclude)maw' 2>/dev/null
        return
    fi
    if [ "$paren" -eq 1 ] || printf '%s\n' "$tok" | grep -Eq '_|::|[a-z0-9][A-Z]'; then
        git -C "$root" grep -qwF -e "$tok" -- . ':(exclude)maw' 2>/dev/null
        return
    fi
    return 0
}

holder_ok() {
    root=$1; spec=$2
    path=${spec%%#*}
    sym=
    case "$spec" in *'#'*) sym=${spec#*#} ;; esac
    case "$path" in maw/*|'') return 1 ;; esac
    [ -f "$root/$path" ] || return 1
    [ -z "$sym" ] || grep -qwF -e "$sym" "$root/$path"
}

cmd_check() {
    pctx=$1
    [ -d "$pctx" ] || return 0
    over=0; total=0
    for rel in $(counted_files "$pctx" | tr ' ' '\001'); do
        rel=$(printf '%s' "$rel" | tr '\001' ' ')
        n=$(line_count "$pctx/$rel")
        total=$((total + n))
        case "$rel" in
            domains/*)
                if [ "$n" -gt "$DOMAIN_MAX" ]; then
                    printf 'overflow file=%s lines=%s limit=%s\n' "$rel" "$n" "$DOMAIN_MAX"; over=1
                fi ;;
        esac
    done
    if [ "$total" -gt "$TOTAL_MAX" ]; then
        printf 'overflow file=TOTAL lines=%s limit=%s\n' "$total" "$TOTAL_MAX"; over=1
    fi
    [ "$over" -eq 0 ] || exit 10
}

cmd_untagged() {
    pctx=$1; n=0
    if [ -d "$pctx" ]; then
        for f in "$pctx"/domains/*.md; do
            [ -f "$f" ] || continue
            k=$(section_bullets "$f" | cut -f2- | grep -Evc "$TAG_RE" || true)
            n=$((n + k))
        done
    fi
    printf 'untagged=%s\n' "$n"
}

cmd_refs() {
    pctx=$1; root=$2
    [ -d "$pctx" ] || return 0
    git -C "$root" rev-parse --git-dir > /dev/null 2>&1 || usage "refs: $root is not a git work tree"
    counted_files "$pctx" | while IFS= read -r rel; do
        awk '
            /^[ \t]*(```|~~~)/ { fence = !fence; next }
            fence { next }
            {
                line = $0
                while (match(line, /`[^`]+`/)) {
                    printf "%d\t%s\n", NR, substr(line, RSTART + 1, RLENGTH - 2)
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        ' "$pctx/$rel" | while IFS='	' read -r ln tok; do
            orig=$tok
            code_has "$root" "$orig" || printf 'missing %s:%s %s\n' "$rel" "$ln" "$orig"
        done
    done
}

cmd_holder() {
    [ "$#" -eq 2 ] || usage 'holder <ROOT> <path>[#symbol]'
    holder_ok "$1" "$2" || exit 1
}

# insert_lesson DOMAIN_FILE LINE: append LINE at the end of "## Risk lessons" (created when absent).
insert_lesson() {
    tmp="$1.pctx-tmp"
    awk -v add="$2" '
        { lines[NR] = $0 }
        /^## / { if ($0 == "## Risk lessons") { sec = NR } else if (sec && !end) { end = NR } }
        END {
            if (!sec) {
                for (i = 1; i <= NR; i++) print lines[i]
                print ""; print "## Risk lessons"; print add; exit
            }
            if (!end) end = NR + 1
            last = end - 1
            while (last > sec && lines[last] == "") last--
            for (i = 1; i <= last; i++) print lines[i]
            print add
            for (i = last + 1; i <= NR; i++) print lines[i]
        }
    ' "$1" > "$tmp"
    mv "$tmp" "$1"
}

cmd_restore() {
    dry=0
    if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi
    [ "$#" -eq 3 ] || usage 'restore [--dry-run] <PCTX> <ROOT> <task_dir>'
    pctx=$1; root=$2; task=$3
    [ -d "$pctx" ] || return 0
    task_id=$(basename "$task")
    reports=
    for r in "$task/IMPL_REVIEW.md" "$task/QA_REPORT.md"; do
        [ -f "$r" ] && reports="$reports$r
"
    done
    restored=0; candidates=0; date_now=$(today)
    for arch in "$pctx"/archive/*.md; do
        [ -f "$arch" ] || continue
        domain=$(basename "$arch" .md)
        dfile="$pctx/domains/$domain.md"
        keep="$arch.pctx-keep"
        : > "$keep"
        while IFS= read -r line || [ -n "$line" ]; do
            slug=$(printf '%s\n' "$line" | sed -n 's/^- \[lesson class=\([a-z0-9-][a-z0-9-]*\)\] .*/\1/p')
            if [ -z "$slug" ]; then printf '%s\n' "$line" >> "$keep"; continue; fi
            hold=$(printf '%s\n' "$line" | sed -n 's/.* | holder: \([^ ]*\) *$/\1/p')
            reason=
            if [ -n "$reports" ] && printf '%s' "$reports" | while IFS= read -r r; do
                    grep -Eq "class=$slug([^a-z0-9-]|\$)" "$r" && exit 0
                done; then
                reason=miss
            elif [ -z "$hold" ] || ! holder_ok "$root" "$hold"; then
                reason=holder-missing
            elif [ -n "$reports" ] && printf '%s' "$reports" | while IFS= read -r r; do
                    grep -qF -e "${hold%%#*}" "$r" && exit 0
                done; then
                printf 'candidate %s %s\n' "$slug" "$hold"; candidates=$((candidates + 1))
            fi
            if [ -z "$reason" ]; then printf '%s\n' "$line" >> "$keep"; continue; fi
            if [ ! -f "$dfile" ]; then
                printf 'orphan %s %s\n' "$slug" "$domain"; printf '%s\n' "$line" >> "$keep"; continue
            fi
            restored=$((restored + 1))
            if [ "$dry" -eq 1 ]; then
                printf 'would-restore %s reason=%s\n' "$slug" "$reason"
                printf '%s\n' "$line" >> "$keep"; continue
            fi
            lesson=${line%% | archived: *}
            insert_lesson "$dfile" "$lesson | restored: $date_now by $task_id reason=$reason holder=$hold"
        done < "$arch"
        if [ "$dry" -eq 1 ]; then rm -f "$keep"; else mv "$keep" "$arch"; fi
    done
    printf 'restored=%s candidates=%s\n' "$restored" "$candidates"
}

cmd_validate() {
    [ "$#" -eq 2 ] || usage 'validate <PCTX> <ROOT>'
    pctx=$1; root=$2
    [ -d "$pctx" ] || return 0
    out=$(mktemp)
    for f in "$pctx"/domains/*.md; do
        [ -f "$f" ] || continue
        rel=${f#"$pctx"/}
        section_bullets "$f" | while IFS='	' read -r ln text; do
            if printf '%s\n' "$text" | grep -Eq '^- \[(law|procedure|lesson)' \
                && ! printf '%s\n' "$text" | grep -Eq "$TAG_RE"; then
                printf 'invalid-tag %s:%s\n' "$rel" "$ln"
            fi
        done
    done > "$out"
    for f in "$pctx"/archive/*.md; do
        [ -f "$f" ] || continue
        rel=${f#"$pctx"/}
        awk '/^- / { printf "%d\t%s\n", NR, $0 }' "$f" | while IFS='	' read -r ln text; do
            if ! printf '%s\n' "$text" | grep -Eq '^- \[lesson class=[a-z0-9-]+\] .+ \| archived: [0-9]{4}-[0-9]{2}-[0-9]{2} \| reason: .+ \| holder: [^ ]+ *$'; then
                printf 'bad-archive-line %s:%s\n' "$rel" "$ln"; continue
            fi
            case "$text" in *'[lesson class=untagged]'*) printf 'untagged-in-archive %s:%s\n' "$rel" "$ln"; continue ;; esac
            hold=$(printf '%s\n' "$text" | sed -n 's/.* | holder: \([^ ]*\) *$/\1/p')
            holder_ok "$root" "$hold" || printf 'holder-missing %s:%s %s\n' "$rel" "$ln" "$hold"
        done
    done >> "$out"
    rc=0
    [ -s "$out" ] && rc=1
    cat "$out"
    rm -f -- "$out"
    exit "$rc"
}

list_tree() { (CDPATH= cd -- "$1" && find . -type f ! -path '*/.*' | sed 's|^\./||' | LC_ALL=C sort); }

cmd_migrate_check() {
    [ "$#" -eq 2 ] || usage 'migrate-check <BEFORE> <AFTER>'
    before=$1; after=$2
    [ -d "$before" ] || return 0
    [ -d "$after" ] || { printf 'changed %s\n' .; exit 1; }
    work=$(mktemp -d)
    list_tree "$before" > "$work/b"
    list_tree "$after" > "$work/a"
    LC_ALL=C comm -3 "$work/b" "$work/a" | sed 's/^[[:space:]]*/changed /' > "$work/out"
    LC_ALL=C comm -12 "$work/b" "$work/a" | while IFS= read -r rel; do
        sed -E 's/^- \[(law|procedure|lesson class=[a-z0-9-]+)\] /- /' "$before/$rel" > "$work/x"
        sed -E 's/^- \[(law|procedure|lesson class=[a-z0-9-]+)\] /- /' "$after/$rel" > "$work/y"
        if ! cmp -s "$work/x" "$work/y"; then printf 'changed %s\n' "$rel"; continue; fi
        # Lines align 1:1 here; a line tagged before must be byte-identical after.
        RE=$TAG_RE awk 'BEGIN { re = ENVIRON["RE"] } NR == FNR { b[FNR] = $0; next } b[FNR] ~ re && b[FNR] != $0 { bad = 1 } END { exit bad }' \
            "$before/$rel" "$after/$rel" || printf 'changed %s\n' "$rel"
    done >> "$work/out"
    rc=0
    [ -s "$work/out" ] && rc=1
    cat "$work/out"
    rm -rf -- "$work"
    exit "$rc"
}

cmd_state() {
    [ "$#" -eq 3 ] || usage 'state <PCTX> <TASK_ID> <result-line>'
    [ -d "$1" ] || return 0
    printf 'last_pass=%s task=%s %s\n' "$(today)" "$2" "$3" > "$1/.sleep-state.tmp"
    mv "$1/.sleep-state.tmp" "$1/.sleep-state"
}

[ "$#" -ge 1 ] || usage 'missing subcommand'
sub=$1; shift
case "$sub" in
    check) [ "$#" -eq 1 ] || usage 'check <PCTX>'; cmd_check "$1" ;;
    untagged) [ "$#" -eq 1 ] || usage 'untagged <PCTX>'; cmd_untagged "$1" ;;
    refs) [ "$#" -eq 2 ] || usage 'refs <PCTX> <ROOT>'; cmd_refs "$1" "$2" ;;
    holder) cmd_holder "$@" ;;
    restore) cmd_restore "$@" ;;
    validate) cmd_validate "$@" ;;
    migrate-check) cmd_migrate_check "$@" ;;
    state) cmd_state "$@" ;;
    *) usage "unknown subcommand $sub" ;;
esac
