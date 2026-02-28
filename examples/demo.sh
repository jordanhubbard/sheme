#!/usr/bin/env bash
# demo.sh - Showcase bad-scheme features
#
# Run:  bash examples/demo.sh
#   or: make example

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bad-scheme.sh"
bs-reset

banner() { printf '\n\033[1;36m── %s ──\033[0m\n' "$1"; }

# ─────────────────────────────────────────────────────────────────────────────
banner "Basic arithmetic"
bs-eval '(+ 1 2 3 4 5)'
bs-eval '(* 6 7)'
bs-eval '(expt 2 10)'

# ─────────────────────────────────────────────────────────────────────────────
banner "Defining variables (exported to your shell)"
eval "$(bs '(define x 1)')"
eval "$(bs '(set! x (+ x 41))')"
echo "x = $x"

# ─────────────────────────────────────────────────────────────────────────────
banner "Functions"
eval "$(bs '(define (factorial n)
              (if (= n 0) 1
                  (* n (factorial (- n 1)))))')"
bs-eval '(factorial 10)'

eval "$(bs '(define (fib n)
              (if (< n 2) n
                  (+ (fib (- n 1)) (fib (- n 2)))))')"
bs-eval '(fib 20)'

# ─────────────────────────────────────────────────────────────────────────────
banner "Higher-order functions"
bs-eval '(map (lambda (x) (* x x)) (list 1 2 3 4 5))'
bs-eval '(filter odd? (list 1 2 3 4 5 6 7 8 9 10))'
bs-eval "(foldl + 0 '(1 2 3 4 5))"

# ─────────────────────────────────────────────────────────────────────────────
banner "Closures"
eval "$(bs '(define make-counter
              (lambda ()
                (let ((n 0))
                  (lambda () (set! n (+ n 1)) n))))')"
eval "$(bs '(define counter (make-counter))')"
bs-eval '(counter)'
bs-eval '(counter)'
bs-eval '(counter)'

# ─────────────────────────────────────────────────────────────────────────────
banner "Lists and quasiquote"
bs-eval "'(the quick brown fox)"
eval "$(bs '(define color "red")')"
bs-eval '`(roses are ,color)'

# ─────────────────────────────────────────────────────────────────────────────
banner "Named let (loop)"
bs-eval '(let loop ((i 1) (acc 0))
           (if (> i 100) acc
               (loop (+ i 1) (+ acc i))))'

# ─────────────────────────────────────────────────────────────────────────────
banner "Strings"
bs-eval '(string-append "Hello" ", " "World!")'
bs-eval '(string-upcase "bad-scheme is honorable")'
bs-eval '(string-length "Scheme")'

# ─────────────────────────────────────────────────────────────────────────────
banner "Vectors"
eval "$(bs '(define v (vector 10 20 30 40 50))')"
bs-eval '(vector-ref v 2)'
bs-eval '(vector->list v)'

echo ""
echo "Done! All examples ran successfully."
