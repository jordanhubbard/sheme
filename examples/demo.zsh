#!/usr/bin/env zsh
# demo.zsh - zsh-hosted sheme feature showcase
#
# Run: zsh examples/demo.zsh
#   or: make example-zsh

emulate -L zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL KSH_ARRAYS

SCRIPT_DIR="${0:A:h:h}"
source "$SCRIPT_DIR/bs.zsh"
bs-reset

banner() { printf '\n\033[1;36m── %s ──\033[0m\n' "$1"; }
run() { eval "$(bs "$1")"; }

banner "Basic arithmetic"
bs-eval '(+ 1 2 3 4 5)'
bs-eval '(* 6 7)'
bs-eval '(expt 2 10)'

banner "Definitions exported to zsh"
run '(define x 1)'
run '(set! x (+ x 41))'
print -r -- "x = ${x#i:}"

banner "Functions and persistent closures"
run '(define (factorial n)
       (if (= n 0) 1 (* n (factorial (- n 1)))))'
bs-eval '(factorial 10)'
run '(define make-counter
       (lambda ()
         (let ((n 0))
           (lambda () (set! n (+ n 1)) n))))
     (define counter (make-counter))'
bs-eval '(counter)'
bs-eval '(counter)'

banner "Higher-order functions"
bs-eval '(map (lambda (n) (* n n)) (list 1 2 3 4 5))'
bs-eval '(filter odd? (list 1 2 3 4 5 6 7 8 9 10))'
bs-eval "(foldl + 0 '(1 2 3 4 5))"

banner "Strings, lists, and vectors"
bs-eval '(substring "hello zsh" 6 9)'
bs-eval "'(the quick brown fox)"
run '(define v (vector 10 20 30 40 50))'
bs-eval '(vector->list v)'

print
print "Done! The zsh-hosted examples ran successfully."
