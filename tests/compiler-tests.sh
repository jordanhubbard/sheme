#!/usr/bin/env bash
# Focused regressions for the Scheme-to-shell compiler targets.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../bs.sh
source "$ROOT/bs.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/sheme-compiler-tests.XXXXXXXX")
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
check() {
    local description="$1"
    shift
    if "$@"; then
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$((pass + fail))" "$description"
    else
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$((pass + fail))" "$description"
    fi
}

SOURCE='(define (char-at s i) (string-ref s i))
        (define (slice s start end) (substring s start end))
        (define (say s) (write-stdout s))
        (define (roundtrip path content)
          (if (file-write path content) (file-read path) "write failed"))
        (define (specials path status prompt commands HOME)
          (string-append path status prompt commands HOME))'

bs-reset
bs-compile "$SOURCE" > "$TMP/generated.bash"
check "Bash target has valid syntax" bash -n "$TMP/generated.bash"
check "Bash target supports dynamic string offsets" \
    bash -c 'source "$1" 2>"$2"; char_at hello 1; [[ "$__r" == e ]]; slice hello 1 4; [[ "$__r" == ell ]]' \
    _ "$TMP/generated.bash" "$TMP/bash.stderr"
check "Bash target preserves whitespace in output" \
    bash -c 'source "$1"; [[ "$(say "hello world")" == "hello world" ]]' \
    _ "$TMP/generated.bash"
check "Bash target quotes file paths and content" \
    bash -c 'source "$1"; roundtrip "$2" "hello world"; [[ "$__r" == "hello world" ]]' \
    _ "$TMP/generated.bash" "$TMP/bash path.txt"
check "Bash cache load has no NUL warning" test ! -s "$TMP/bash.stderr"

bs-reset
bs-compile-zsh "$SOURCE" > "$TMP/generated.zsh"
check "zsh target has valid syntax" zsh -n "$TMP/generated.zsh"
check "zsh target supports dynamic string offsets" \
    zsh -fc 'source "$1" 2>"$2"; char_at hello 1; [[ "$__r" == e ]]; slice hello 1 4; [[ "$__r" == ell ]]' \
    _ "$TMP/generated.zsh" "$TMP/zsh.stderr"
check "zsh target preserves whitespace in output" \
    zsh -fc 'source "$1"; [[ "$(say "hello world")" == "hello world" ]]' \
    _ "$TMP/generated.zsh"
check "zsh target quotes file paths and content" \
    zsh -fc 'source "$1"; roundtrip "$2" "hello world"; [[ "$__r" == "hello world" ]]' \
    _ "$TMP/generated.zsh" "$TMP/zsh path.txt"
check "zsh target isolates bindings from special shell parameters" \
    zsh -fc 'source "$1"; original=$PATH; specials a b c d e; [[ "$__r" == abcde && "$PATH" == "$original" ]]' \
    _ "$TMP/generated.zsh"
check "zsh cache load has no NUL warning" test ! -s "$TMP/zsh.stderr"

printf '%s\n' \
    'provided() {' \
    '    __r="runtime:$1"' \
    '}' > "$TMP/runtime.sh"
bs-reset
bs-compile --runtime "$TMP/runtime.sh" \
    '(define (provided value) "scheme")
     (define (use-runtime value) (provided value))' > "$TMP/with-runtime.bash"
check "injected runtime replaces its Scheme definition automatically" \
    bash -c 'source "$1"; use_runtime example; [[ "$__r" == runtime:example ]]' \
    _ "$TMP/with-runtime.bash"

bs-reset
bs-compile-zsh --runtime "$TMP/runtime.sh" \
    '(define (provided value) "scheme")
     (define (use-runtime value) (provided value))' > "$TMP/with-runtime.zsh"
check "zsh target injects and selects the application runtime" \
    zsh -fc 'source "$1"; use_runtime example; [[ "$__r" == runtime:example ]]' \
    _ "$TMP/with-runtime.zsh"

printf '%s\n' \
    'function explicit_runtime {' \
    '    __r="explicit:$1"' \
    '}' > "$TMP/explicit-runtime.sh"
bs-reset
bs-compile --runtime "$TMP/explicit-runtime.sh" \
    --replace-functions "explicit-runtime" \
    '(define (explicit-runtime value) "scheme")
     (define (use-explicit value) (explicit-runtime value))' > "$TMP/explicit.bash"
check "explicit replacement supports alternate function declaration styles" \
    bash -c 'source "$1"; use_explicit example; [[ "$__r" == explicit:example ]]' \
    _ "$TMP/explicit.bash"

bs-reset
if bs-compile '(define (broken x) (+ x 1)' > "$TMP/partial" 2>/dev/null; then
    check "invalid source fails compilation" false
else
    check "invalid source fails compilation" true
fi
check "failed compilation publishes no partial program" test ! -s "$TMP/partial"

printf '1..%d\n' "$((pass + fail))"
printf '# %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
