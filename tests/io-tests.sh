#!/usr/bin/env bash
# tests/io-tests.sh - Tests for terminal I/O and file builtins (bash only)
# Outputs TAP (Test Anything Protocol) format.
# Exit code 1 if any tests fail, 0 otherwise.

set -u

# ── Locate and source the interpreter ─────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERP="$SCRIPT_DIR/../bs.sh"

if [[ ! -f "$INTERP" ]]; then
    echo "Bail out! Cannot find bs.sh at $INTERP"
    exit 1
fi

# shellcheck disable=SC1090
source "$INTERP"

# ── Test harness ──────────────────────────────────────────────────────
__test_num=0
__test_pass=0
__test_fail=0
__test_skip=0

test_equal() {
    local desc="$1" expr="$2" expected="$3"
    (( __test_num++ ))
    bs-reset
    bs "$expr"
    local actual="$__bs_last_display"
    if [[ "$actual" == "$expected" ]]; then
        echo "ok $__test_num - $desc"
        (( __test_pass++ ))
    else
        echo "not ok $__test_num - $desc"
        echo "#   expression: $expr"
        echo "#   expected:   '$expected'"
        echo "#   actual:     '$actual'"
        (( __test_fail++ ))
    fi
}

test_raw() {
    local desc="$1" expr="$2" expected="$3"
    (( __test_num++ ))
    bs-reset
    bs "$expr"
    local actual="$__bs_last"
    if [[ "$actual" == "$expected" ]]; then
        echo "ok $__test_num - $desc"
        (( __test_pass++ ))
    else
        echo "not ok $__test_num - $desc"
        echo "#   expression: $expr"
        echo "#   expected:   '$expected'"
        echo "#   actual:     '$actual'"
        (( __test_fail++ ))
    fi
}

# test_multi: evaluate expressions in order, check last result display form
test_multi() {
    local desc="$1" expected="$2"
    shift 2
    (( __test_num++ ))
    bs-reset
    for _expr in "$@"; do
        bs "$_expr"
    done
    local actual="$__bs_last_display"
    if [[ "$actual" == "$expected" ]]; then
        echo "ok $__test_num - $desc"
        (( __test_pass++ ))
    else
        echo "not ok $__test_num - $desc"
        echo "#   expected:   '$expected'"
        echo "#   actual:     '$actual'"
        (( __test_fail++ ))
    fi
}

# test_multi_raw: evaluate expressions in order, check last result raw tag
test_multi_raw() {
    local desc="$1" expected="$2"
    shift 2
    (( __test_num++ ))
    bs-reset
    for _expr in "$@"; do
        bs "$_expr"
    done
    local actual="$__bs_last"
    if [[ "$actual" == "$expected" ]]; then
        echo "ok $__test_num - $desc"
        (( __test_pass++ ))
    else
        echo "not ok $__test_num - $desc"
        echo "#   expected:   '$expected'"
        echo "#   actual:     '$actual'"
        (( __test_fail++ ))
    fi
}

# test_stdout: evaluate expression with bs (silent), check what it wrote to stdout
test_stdout() {
    local desc="$1" expr="$2" expected="$3"
    (( __test_num++ ))
    bs-reset
    local actual
    actual=$(bs "$expr")
    if [[ "$actual" == "$expected" ]]; then
        echo "ok $__test_num - $desc"
        (( __test_pass++ ))
    else
        echo "not ok $__test_num - $desc"
        echo "#   expression: $expr"
        echo "#   expected:   $(printf '%q' "$expected")"
        echo "#   actual:     $(printf '%q' "$actual")"
        (( __test_fail++ ))
    fi
}

skip_test() {
    local desc="$1" reason="$2"
    (( __test_num++ ))
    (( __test_skip++ ))
    echo "ok $__test_num - # SKIP $desc ($reason)"
}

# ── Temp directory for file tests ─────────────────────────────────────
TMPDIR_IO=$(mktemp -d "${TMPDIR:-/tmp}/bs-io-tests.XXXXXX")
trap 'rm -rf "$TMPDIR_IO"' EXIT

# ── Plan ──────────────────────────────────────────────────────────────
echo "TAP version 13"
echo "# I/O builtin tests for bad-scheme (bash only)"
echo ""

# ======================================================================
# WRITE-STDOUT
# ======================================================================
echo "# -- write-stdout --"

test_stdout "write-stdout simple string" \
    '(write-stdout "hello")' \
    "hello"

test_stdout "write-stdout empty string" \
    '(write-stdout "")' \
    ""

test_stdout "write-stdout with special chars" \
    '(write-stdout "a\tb\nc")' \
    "$(printf 'a\tb\nc')"

# write-stdout returns nil — verify via raw tag (bs is silent, so stdout only has write-stdout output)
test_raw "write-stdout returns nil" \
    '(write-stdout "x")' \
    "n:()"

# ======================================================================
# FILE-READ
# ======================================================================
echo "# -- file-read --"

# Create test files
printf 'hello world' > "$TMPDIR_IO/simple.txt"
printf 'line 1\nline 2\nline 3' > "$TMPDIR_IO/multi.txt"
printf '' > "$TMPDIR_IO/empty.txt"

test_equal "file-read simple file" \
    "(file-read \"$TMPDIR_IO/simple.txt\")" \
    "hello world"

test_equal "file-read multiline file" \
    "(file-read \"$TMPDIR_IO/multi.txt\")" \
    "line 1
line 2
line 3"

test_equal "file-read empty file" \
    "(file-read \"$TMPDIR_IO/empty.txt\")" \
    ""

test_raw "file-read nonexistent file returns #f" \
    "(file-read \"$TMPDIR_IO/no-such-file.txt\")" \
    "b:#f"

test_raw "file-read directory returns #f" \
    "(file-read \"$TMPDIR_IO\")" \
    "b:#f"

# ======================================================================
# FILE-WRITE
# ======================================================================
echo "# -- file-write --"

test_raw "file-write returns #t on success" \
    "(file-write \"$TMPDIR_IO/out1.txt\" \"test content\")" \
    "b:#t"

# Verify content was actually written (with trailing newline from file-write)
(( __test_num++ ))
bs-reset
bs "(file-write \"$TMPDIR_IO/out2.txt\" \"hello from scheme\")"
actual_content=$(cat "$TMPDIR_IO/out2.txt")
expected_content="hello from scheme"
if [[ "$actual_content" == "$expected_content" ]]; then
    echo "ok $__test_num - file-write content is correct"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - file-write content is correct"
    echo "#   expected: '$expected_content'"
    echo "#   actual:   '$actual_content'"
    (( __test_fail++ ))
fi

# Write then read back
test_multi "file-write then file-read roundtrip" \
    "round trip data" \
    "(file-write \"$TMPDIR_IO/roundtrip.txt\" \"round trip data\")" \
    "(file-read \"$TMPDIR_IO/roundtrip.txt\")"

# Write empty string
test_raw "file-write empty string" \
    "(file-write \"$TMPDIR_IO/empty-out.txt\" \"\")" \
    "b:#t"

# Write multiline content
test_multi "file-write multiline roundtrip" \
    "line A
line B
line C" \
    "(file-write \"$TMPDIR_IO/multi-out.txt\" \"line A\nline B\nline C\")" \
    "(file-read \"$TMPDIR_IO/multi-out.txt\")"

# Write to invalid path
test_raw "file-write to invalid path returns #f" \
    "(file-write \"/no/such/directory/file.txt\" \"data\")" \
    "b:#f"

# ======================================================================
# EVAL-STRING
# ======================================================================
echo "# -- eval-string --"

# Successful evaluation
(( __test_num++ ))
bs-reset
bs '(eval-string "(+ 1 2 3)")'
if [[ "$__bs_last_display" == "(#t . 6)" ]]; then
    echo "ok $__test_num - eval-string simple arithmetic"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - eval-string simple arithmetic"
    echo "#   expected: '(#t . 6)'"
    echo "#   actual:   '$__bs_last_display'"
    (( __test_fail++ ))
fi

# eval-string success: car is #t
test_multi "eval-string success car is #t" \
    "#t" \
    '(eval-string "(+ 1 2)")' \
    '(car (eval-string "(+ 1 2)"))'

# eval-string result in cdr
test_multi "eval-string result in cdr" \
    "6" \
    '(cdr (eval-string "(+ 1 2 3)"))'

# eval-string with string result
test_multi "eval-string with string result" \
    "hello" \
    '(cdr (eval-string "\"hello\""))'

# eval-string with define
test_multi "eval-string with define" \
    "25" \
    '(cdr (eval-string "(define (sq x) (* x x)) (sq 5)"))'

# eval-string error: car is #f
test_multi "eval-string error car is #f" \
    "#f" \
    '(car (eval-string "(+ 1 undefined-var)"))'

# eval-string error: cdr is error message string
(( __test_num++ ))
bs-reset
bs '(cdr (eval-string "(+ 1 undefined-var)"))'
if [[ "$__bs_last" == s:* && -n "${__bs_last:2}" ]]; then
    echo "ok $__test_num - eval-string error message is non-empty string"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - eval-string error message is non-empty string"
    echo "#   result: $__bs_last"
    (( __test_fail++ ))
fi

# eval-string preserves outer state
test_multi "eval-string preserves outer state" \
    "42" \
    '(define outer-val 42)' \
    '(eval-string "(+ 1 1)")' \
    'outer-val'

# eval-string empty program
test_multi "eval-string empty string" \
    "(#t . ())" \
    '(eval-string "")'

# eval-string with multiple expressions returns last
test_multi "eval-string multiple expressions returns last" \
    "3" \
    '(cdr (eval-string "(+ 1 1) (+ 1 2)"))'

# ======================================================================
# TERMINAL-SIZE
# ======================================================================
echo "# -- terminal-size --"

# terminal-size returns a pair
test_multi "terminal-size returns a pair" \
    "#t" \
    '(pair? (terminal-size))'

# terminal-size car is positive integer (rows)
(( __test_num++ ))
bs-reset
bs '(car (terminal-size))'
local_rows="$__bs_last_display"
if [[ "$__bs_last" == i:* ]] && (( ${__bs_last:2} > 0 )); then
    echo "ok $__test_num - terminal-size rows is positive integer"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - terminal-size rows is positive integer"
    echo "#   result: $__bs_last ($__bs_last_display)"
    (( __test_fail++ ))
fi

# terminal-size cdr is positive integer (cols)
(( __test_num++ ))
bs-reset
bs '(cdr (terminal-size))'
if [[ "$__bs_last" == i:* ]] && (( ${__bs_last:2} > 0 )); then
    echo "ok $__test_num - terminal-size cols is positive integer"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - terminal-size cols is positive integer"
    echo "#   result: $__bs_last ($__bs_last_display)"
    (( __test_fail++ ))
fi

# ======================================================================
# READ-BYTE
# ======================================================================
echo "# -- read-byte --"

# read-byte with piped input
(( __test_num++ ))
bs-reset
local_result=$(echo -n "A" | bs-eval '(read-byte)')
if [[ "$local_result" == "65" ]]; then
    echo "ok $__test_num - read-byte reads ASCII 'A' as 65"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - read-byte reads ASCII 'A' as 65"
    echo "#   expected: 65"
    echo "#   actual:   $local_result"
    (( __test_fail++ ))
fi

# read-byte null byte
(( __test_num++ ))
bs-reset
local_result=$(printf '\0' | bs-eval '(read-byte)')
if [[ "$local_result" == "0" ]]; then
    echo "ok $__test_num - read-byte reads null byte as 0"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - read-byte reads null byte as 0"
    echo "#   expected: 0"
    echo "#   actual:   $local_result"
    (( __test_fail++ ))
fi

# read-byte EOF returns #f
(( __test_num++ ))
bs-reset
local_result=$(echo -n "" | bs-eval '(read-byte)')
if [[ "$local_result" == "#f" ]]; then
    echo "ok $__test_num - read-byte EOF returns #f"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - read-byte EOF returns #f"
    echo "#   expected: #f"
    echo "#   actual:   $local_result"
    (( __test_fail++ ))
fi

# read-byte newline
(( __test_num++ ))
bs-reset
local_result=$(printf '\n' | bs-eval '(read-byte)')
if [[ "$local_result" == "10" ]]; then
    echo "ok $__test_num - read-byte reads newline as 10"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - read-byte reads newline as 10"
    echo "#   expected: 10"
    echo "#   actual:   $local_result"
    (( __test_fail++ ))
fi

# read-byte space
(( __test_num++ ))
bs-reset
local_result=$(printf ' ' | bs-eval '(read-byte)')
if [[ "$local_result" == "32" ]]; then
    echo "ok $__test_num - read-byte reads space as 32"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - read-byte reads space as 32"
    echo "#   expected: 32"
    echo "#   actual:   $local_result"
    (( __test_fail++ ))
fi

# ======================================================================
# READ-BYTE-TIMEOUT
# ======================================================================
echo "# -- read-byte-timeout --"

# read-byte-timeout with data available
(( __test_num++ ))
bs-reset
local_result=$(echo -n "Z" | bs-eval '(read-byte-timeout "1")')
if [[ "$local_result" == "90" ]]; then
    echo "ok $__test_num - read-byte-timeout reads 'Z' as 90"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - read-byte-timeout reads 'Z' as 90"
    echo "#   expected: 90"
    echo "#   actual:   $local_result"
    (( __test_fail++ ))
fi

# read-byte-timeout returns #f on timeout (empty stdin)
(( __test_num++ ))
bs-reset
local_result=$(echo -n "" | bs-eval '(read-byte-timeout "0.01")')
if [[ "$local_result" == "#f" ]]; then
    echo "ok $__test_num - read-byte-timeout returns #f on empty stdin"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - read-byte-timeout returns #f on empty stdin"
    echo "#   expected: #f"
    echo "#   actual:   $local_result"
    (( __test_fail++ ))
fi

# ======================================================================
# TERMINAL-RAW! / TERMINAL-RESTORE!
# ======================================================================
echo "# -- terminal-raw! / terminal-restore! --"

# These are hard to test non-interactively without a real tty,
# but we can verify they exist and return the right types

test_raw "terminal-raw! is a known builtin" \
    '(procedure? terminal-raw!)' \
    "b:#t"

test_raw "terminal-restore! is a known builtin" \
    '(procedure? terminal-restore!)' \
    "b:#t"

# We can also verify __bs_stty_saved behavior indirectly:
# terminal-restore! on a clean state should be a no-op returning nil
test_raw "terminal-restore! returns nil" \
    '(terminal-restore!)' \
    "n:()"

# ======================================================================
# INTEGRATION: file-write + eval-string
# ======================================================================
echo "# -- integration tests --"

# Write Scheme code to a file, read it back, eval it
test_multi "write scheme, read, eval roundtrip" \
    "120" \
    "(file-write \"$TMPDIR_IO/fact.scm\" \"(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)\")" \
    "(cdr (eval-string (file-read \"$TMPDIR_IO/fact.scm\")))"

# eval-string does not corrupt outer tokenizer state
test_multi "eval-string does not corrupt tokenizer" \
    "10" \
    '(define a 10)' \
    '(eval-string "(define b 20)")' \
    'a'

# Multiple file operations in sequence
test_multi "sequential file operations" \
    "hello world" \
    "(file-write \"$TMPDIR_IO/seq1.txt\" \"hello\")" \
    "(file-write \"$TMPDIR_IO/seq2.txt\" \"world\")" \
    "(string-append (file-read \"$TMPDIR_IO/seq1.txt\") \" \" (file-read \"$TMPDIR_IO/seq2.txt\"))"

# ======================================================================
# Print TAP plan and summary
# ======================================================================
echo ""
echo "1..$__test_num"
echo ""
echo "# ── Summary ──"
echo "# Total:   $__test_num"
echo "# Passed:  $__test_pass"
echo "# Failed:  $__test_fail"
echo "# Skipped: $__test_skip"

if (( __test_fail > 0 )); then
    echo "# RESULT: FAIL"
    exit 1
else
    echo "# RESULT: PASS"
    exit 0
fi
