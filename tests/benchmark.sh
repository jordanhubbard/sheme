#!/usr/bin/env bash
# benchmark.sh - Performance tests for sheme primitives
#
# Measures the time for each category of operation to identify bottlenecks.
# Run:  bash tests/benchmark.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bs.sh"

# ── Timing helper ──
_bm_time() {
    local desc="$1" expr="$2" n="${3:-1}"
    local start end elapsed per_call
    bs-reset
    # Warm up (load function definitions if needed)
    bs "$expr" 2>/dev/null
    bs-reset

    start=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    for ((i = 0; i < n; i++)); do
        bs "$expr" 2>/dev/null
    done
    end=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')

    elapsed=$(( (end - start) / 1000000 ))  # ms
    per_call=$(( elapsed / n ))
    printf '  %-45s %4d ms total  (%d ms/call, n=%d)\n' "$desc" "$elapsed" "$per_call" "$n"
}

echo "=== sheme Performance Benchmarks ==="
echo ""
echo "All operations run inline (no subshell fork)."
echo ""

echo "── Baseline (empty/trivial) ──"
_bm_time "empty expression (just 1)" "1" 5
_bm_time "simple addition (+ 1 2)" "(+ 1 2)" 5

echo ""
echo "── Arithmetic ──"
_bm_time "nested arithmetic" "(+ (* 3 4) (- 10 5) (/ 20 4))" 5
_bm_time "expt 2^10" "(expt 2 10)" 5
_bm_time "modulo" "(modulo 17 5)" 5

echo ""
echo "── String operations ──"
_bm_time "string-append" '(string-append "hello" " " "world")' 5
_bm_time "string-length" '(string-length "hello world")' 5
_bm_time "substring" '(substring "hello world" 0 5)' 5
_bm_time "string-upcase" '(string-upcase "hello")' 5

echo ""
echo "── List operations ──"
_bm_time "cons + car" "(car (cons 1 2))" 5
_bm_time "list 5 elements" "(list 1 2 3 4 5)" 5
_bm_time "list 10 elements" "(list 1 2 3 4 5 6 7 8 9 10)" 5
_bm_time "map square 5" "(map (lambda (x) (* x x)) (list 1 2 3 4 5))" 3
_bm_time "append two lists" "(append (list 1 2 3) (list 4 5 6))" 5
_bm_time "reverse 5" "(reverse (list 1 2 3 4 5))" 5

echo ""
echo "── Vector operations ──"
_bm_time "make-vector 10" "(make-vector 10 0)" 3
_bm_time "vector-ref" "(begin (define v (make-vector 10 0)) (vector-ref v 5))" 3

echo ""
echo "── Closures & higher-order ──"
_bm_time "lambda call" "((lambda (x) (+ x 1)) 5)" 5
_bm_time "define + call function" "(begin (define (f x) (+ x 1)) (f 5))" 5
_bm_time "closure (counter)" "(begin (define c (let ((n 0)) (lambda () (set! n (+ n 1)) n))) (c))" 3

echo ""
echo "── State accumulation ──"
bs-reset
bs '(define x 0)' 2>/dev/null
_bm_time "define on fresh state" "(define x 0)" 3
# Build up some state
bs-reset
bs '(define a 1) (define b 2) (define c 3) (define d 4) (define e 5)' 2>/dev/null
bs '(define f 6) (define g 7) (define h 8) (define i 9) (define j 10)' 2>/dev/null
_bm_time "eval with 10 defs in state" "(+ a b)" 3

echo ""
echo "── Complex expressions ──"
_bm_time "factorial 10" "(begin (define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 10))" 3
_bm_time "fib 10" "(begin (define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 10))" 3
_bm_time "named let sum 1-100" "(let loop ((i 1) (acc 0)) (if (> i 100) acc (loop (+ i 1) (+ acc i))))" 3

echo ""
echo "── Editor-like operations ──"
# Simulate what em.scm does: load code, then handle a key
bs-reset
_em_scm="$(cat "$SCRIPT_DIR/examples/em.scm")"
echo "  Loading em.scm (one-time cost)..."
start=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
bs "$_em_scm" 2>/dev/null
end=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
elapsed=$(( (end - start) / 1000000 ))
printf '  %-45s %4d ms\n' "Load em.scm" "$elapsed"

bs '(em-init 24 80)' 2>/dev/null
_bm_time "em-handle-key (self-insert)" '(em-handle-key "SELF:a" 24 80)' 3
_bm_time "em-handle-key (C-f)" '(em-handle-key "C-f" 24 80)' 3
_bm_time "em-handle-key (C-a)" '(em-handle-key "C-a" 24 80)' 3

echo ""
echo "Done."
