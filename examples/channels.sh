#!/usr/bin/env bash
# channels.sh - Communicating sequential processes via Scheme + shell pipes
#
# Demonstrates sheme's shell integration: Scheme computes, bash orchestrates.
# Shows a producer/consumer pipeline using temp files as message channels.
#
# Run:  bash examples/channels.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bs.sh"
bs-reset

banner() { printf '\n\033[1;36m── %s ──\033[0m\n' "$1"; }

# ─────────────────────────────────────────────────────────────────────────────
banner "Scheme generates a work queue, shell processes it"

# Producer: generate a list of tasks in Scheme
bs '(define tasks
      (map (lambda (n)
             (string-append (number->string n) " " (number->string (* n n))))
           (list 1 2 3 4 5 6 7 8 9 10)))'

bs 'tasks' | tr -d '("")' | tr ' ' '\n' | grep -v '^$' | \
    awk 'NR%2==1{n=$1} NR%2==0{printf "  %3d squared = %s\n", n, $1}' || true

# ─────────────────────────────────────────────────────────────────────────────
banner "Scheme as a computation engine: word frequency"

TEXT="the quick brown fox jumps over the lazy dog the fox"
printf 'Input: "%s"\n' "$TEXT"

# Pass words into Scheme as a list and count frequencies
WORDS="(quote ($(echo "$TEXT" | tr ' ' ' ' | awk '{for(i=1;i<=NF;i++) printf "(quote %s) ", $i}')))"
bs "(define words $WORDS)"
bs '(define (frequencies lst)
      (let loop ((lst lst) (acc (quote ())))
        (if (null? lst) acc
            (let* ((w (car lst))
                   (entry (assoc w acc)))
              (if entry
                  (begin
                    (set-cdr! entry (+ (cdr entry) 1))
                    (loop (cdr lst) acc))
                  (loop (cdr lst) (cons (cons w 1) acc)))))))'
bs-eval '(sort (frequencies words) (lambda (a b) (> (cdr a) (cdr b))))'

# ─────────────────────────────────────────────────────────────────────────────
banner "Scheme DSL: simple stack machine"

bs '(define (run-stack-machine program)
      (let loop ((prog program) (stack (quote ())))
        (if (null? prog)
            (car stack)
            (let ((op (car prog)))
              (cond
                ((number? op) (loop (cdr prog) (cons op stack)))
                ((equal? op (quote +))
                 (loop (cdr prog)
                       (cons (+ (car stack) (cadr stack)) (cddr stack))))
                ((equal? op (quote *))
                 (loop (cdr prog)
                       (cons (* (car stack) (cadr stack)) (cddr stack))))
                ((equal? op (quote dup))
                 (loop (cdr prog) (cons (car stack) stack)))
                ((equal? op (quote swap))
                 (loop (cdr prog) (cons (cadr stack) (cons (car stack) (cddr stack)))))
                (else (error "unknown op" op)))))))'

printf 'Program: 3 4 + 2 * dup *  =>  '
bs-eval "(run-stack-machine '(3 4 + 2 * dup *))"   ; ((3+4)*2)^2 = 196

printf 'Program: 5 dup * 12 dup * +  =>  '
bs-eval "(run-stack-machine '(5 dup * 12 dup * +))" ; 5^2 + 12^2 = 169

echo ""
echo "Done."
