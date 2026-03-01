#!/usr/bin/env bash
# algorithms.sh - Classic algorithms implemented in Scheme
#
# Run:  bash examples/algorithms.sh
#   or: make algorithms

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bs.sh"
bs-reset

banner() { printf '\n\033[1;36m── %s ──\033[0m\n' "$1"; }

# ─────────────────────────────────────────────────────────────────────────────
banner "Merge sort"
bs '(define (merge lst1 lst2)
      (cond ((null? lst1) lst2)
            ((null? lst2) lst1)
            ((< (car lst1) (car lst2))
             (cons (car lst1) (merge (cdr lst1) lst2)))
            (else
             (cons (car lst2) (merge lst1 (cdr lst2))))))

    (define (split lst)
      (let loop ((fast lst) (slow lst) (acc (quote ())))
        (if (or (null? fast) (null? (cdr fast)))
            (cons (reverse acc) slow)
            (loop (cddr fast) (cdr slow) (cons (car slow) acc)))))

    (define (mergesort lst)
      (if (or (null? lst) (null? (cdr lst)))
          lst
          (let ((halves (split lst)))
            (merge (mergesort (car halves))
                   (mergesort (cdr halves))))))'
bs-eval "(mergesort '(5 3 8 1 9 2 7 4 6))"

# ─────────────────────────────────────────────────────────────────────────────
banner "Quicksort"
bs '(define (quicksort lst)
      (if (or (null? lst) (null? (cdr lst)))
          lst
          (let* ((pivot (car lst))
                 (rest  (cdr lst))
                 (less  (filter (lambda (x) (< x pivot)) rest))
                 (more  (filter (lambda (x) (>= x pivot)) rest)))
            (append (quicksort less) (list pivot) (quicksort more)))))'
bs-eval "(quicksort '(3 1 4 1 5 9 2 6 5 3 5))"

# ─────────────────────────────────────────────────────────────────────────────
banner "Binary search"
bs '(define (bsearch vec target)
      (let loop ((lo 0) (hi (- (vector-length vec) 1)))
        (if (> lo hi) -1
            (let ((mid (quotient (+ lo hi) 2)))
              (let ((val (vector-ref vec mid)))
                (cond ((= val target) mid)
                      ((< val target) (loop (+ mid 1) hi))
                      (else           (loop lo (- mid 1)))))))))'
bs '(define sorted (list->vector (list 1 3 5 7 9 11 13 15 17 19)))'
bs-eval "(bsearch sorted 11)"   ; => 5
bs-eval "(bsearch sorted 6)"    ; => -1

# ─────────────────────────────────────────────────────────────────────────────
banner "Sieve of Eratosthenes (primes up to 50)"
bs '(define (sieve limit)
      (let ((composite (make-vector (+ limit 1) #f)))
        (let loop ((i 2) (primes (quote ())))
          (if (> i limit)
              (reverse primes)
              (if (vector-ref composite i)
                  (loop (+ i 1) primes)
                  (begin
                    (let mark ((j (* i i)))
                      (when (<= j limit)
                        (vector-set! composite j #t)
                        (mark (+ j i))))
                    (loop (+ i 1) (cons i primes))))))))'
bs-eval "(sieve 50)"

# ─────────────────────────────────────────────────────────────────────────────
banner "Towers of Hanoi (3 discs)"
bs '(define moves (quote ()))
    (define (hanoi n from to via)
      (when (> n 0)
        (hanoi (- n 1) from via to)
        (set! moves (append moves (list (list from to))))
        (hanoi (- n 1) via to from)))
    (hanoi 3 (quote A) (quote C) (quote B))'
bs-eval 'moves'
bs-eval '(length moves)'

echo ""
echo "Done."
