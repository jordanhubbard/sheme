#!/usr/bin/env bats
# tests/bs.bats - Test suite for bs.sh

# ────────────────────────────────────────────────────────────────────────────
# Setup / teardown
# ────────────────────────────────────────────────────────────────────────────
setup() {
    # Absolute path to the interpreter regardless of where bats is invoked from
    INTERP="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bs.sh"
    # shellcheck disable=SC1090
    source "$INTERP"
    bs-reset          # fresh heap for every test
}

teardown() {
    bs-reset
}

# Convenience: evaluate expr and expose $result (display form) and $__bs_last
bs_run() {
    bs "$1"
    result="$__bs_last_display"
}

# ────────────────────────────────────────────────────────────────────────────
# 1. Literals & self-evaluating forms
# ────────────────────────────────────────────────────────────────────────────
@test "integer literal" {
    bs_run '42'
    [[ "$result" == "42" ]]
}

@test "negative integer" {
    bs_run '-7'
    [[ "$result" == "-7" ]]
}

@test "boolean #t" {
    bs_run '#t'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "boolean #f" {
    bs_run '#f'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "string literal" {
    bs_run '"hello"'
    [[ "$__bs_last" == 's:hello' ]]
}

@test "empty list" {
    bs_run "'()"
    [[ "$__bs_last" == 'n:()' ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 2. Arithmetic
# ────────────────────────────────────────────────────────────────────────────
@test "addition" {
    bs_run '(+ 1 2)'
    [[ "$result" == "3" ]]
}

@test "subtraction" {
    bs_run '(- 10 3)'
    [[ "$result" == "7" ]]
}

@test "multiplication" {
    bs_run '(* 6 7)'
    [[ "$result" == "42" ]]
}

@test "integer division" {
    bs_run '(/ 10 3)'
    [[ "$result" == "3" ]]
}

@test "nested arithmetic" {
    bs_run '(+ (* 2 3) (- 10 4))'
    [[ "$result" == "12" ]]
}

@test "quotient" {
    bs_run '(quotient 13 4)'
    [[ "$result" == "3" ]]
}

@test "remainder" {
    bs_run '(remainder 13 4)'
    [[ "$result" == "1" ]]
}

@test "modulo positive" {
    bs_run '(modulo 13 4)'
    [[ "$result" == "1" ]]
}

@test "modulo negative dividend" {
    bs_run '(modulo -13 4)'
    [[ "$result" == "3" ]]
}

@test "abs positive" {
    bs_run '(abs 5)'
    [[ "$result" == "5" ]]
}

@test "abs negative" {
    bs_run '(abs -5)'
    [[ "$result" == "5" ]]
}

@test "expt" {
    bs_run '(expt 2 10)'
    [[ "$result" == "1024" ]]
}

@test "max" {
    bs_run '(max 3 1 4 1 5 9 2 6)'
    [[ "$result" == "9" ]]
}

@test "min" {
    bs_run '(min 3 1 4 1 5)'
    [[ "$result" == "1" ]]
}

@test "gcd" {
    bs_run '(gcd 32 -36)'
    [[ "$result" == "4" ]]
}

@test "multi-arg addition" {
    bs_run '(+ 1 2 3 4 5)'
    [[ "$result" == "15" ]]
}

@test "unary negation" {
    bs_run '(- 5)'
    [[ "$result" == "-5" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 3. Comparisons
# ────────────────────────────────────────────────────────────────────────────
@test "= true" {
    bs_run '(= 3 3)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "= false" {
    bs_run '(= 3 4)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "< true" {
    bs_run '(< 1 2)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "> true" {
    bs_run '(> 5 3)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "<= equal" {
    bs_run '(<= 3 3)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test ">= greater" {
    bs_run '(>= 5 3)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "eq? same symbol" {
    bs_run "(eq? 'a 'a)"
    [[ "$__bs_last" == "b:#t" ]]
}

@test "equal? lists" {
    bs_run "(equal? '(1 2 3) '(1 2 3))"
    [[ "$__bs_last" == "b:#t" ]]
}

@test "equal? lists false" {
    bs_run "(equal? '(1 2) '(1 3))"
    [[ "$__bs_last" == "b:#f" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 4. Boolean operations
# ────────────────────────────────────────────────────────────────────────────
@test "not false → true" {
    bs_run '(not #f)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "not true → false" {
    bs_run '(not #t)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "not non-false → false" {
    bs_run '(not 42)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "and all true" {
    bs_run '(and 1 2 3)'
    [[ "$result" == "3" ]]
}

@test "and short-circuits on false" {
    bs_run '(and 1 #f 3)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "and empty" {
    bs_run '(and)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "or first true" {
    bs_run '(or #f #f 5)'
    [[ "$result" == "5" ]]
}

@test "or all false" {
    bs_run '(or #f #f)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "or empty" {
    bs_run '(or)'
    [[ "$__bs_last" == "b:#f" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 5. define / set! / variable lookup
# ────────────────────────────────────────────────────────────────────────────
@test "define and read variable" {
    bs '(define x 99)'
    [[ "$x" == "i:99" ]]
}

@test "define function shorthand" {
    bs '(define (square n) (* n n))'
    bs_run '(square 7)'
    [[ "$result" == "49" ]]
}

@test "set! updates variable" {
    bs '(define counter 0)'
    bs '(set! counter (+ counter 1))'
    bs '(set! counter (+ counter 1))'
    [[ "$counter" == "i:2" ]]
}

@test "define overwrites" {
    bs '(define v 1)'
    bs '(define v 2)'
    [[ "$v" == "i:2" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 6. if expression
# ────────────────────────────────────────────────────────────────────────────
@test "if true branch" {
    bs_run '(if #t 10 20)'
    [[ "$result" == "10" ]]
}

@test "if false branch" {
    bs_run '(if #f 10 20)'
    [[ "$result" == "20" ]]
}

@test "if no else, condition false" {
    bs_run '(if #f 42)'
    [[ "$__bs_last" == "n:()" ]]
}

@test "if with zero? predicate" {
    bs_run '(if (zero? 0) "yes" "no")'
    [[ "$result" == "yes" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 7. begin
# ────────────────────────────────────────────────────────────────────────────
@test "begin returns last" {
    bs_run '(begin 1 2 3)'
    [[ "$result" == "3" ]]
}

@test "begin with side effects" {
    bs_run '(begin (define a 5) (define b 6) (+ a b))'
    [[ "$result" == "11" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 8. lambda / closures
# ────────────────────────────────────────────────────────────────────────────
@test "simple lambda" {
    bs_run '((lambda (x) (* x x)) 5)'
    [[ "$result" == "25" ]]
}

@test "closure captures environment" {
    bs '(define make-adder (lambda (n) (lambda (x) (+ x n))))'
    bs '(define add5 (make-adder 5))'
    bs_run '(add5 37)'
    [[ "$result" == "42" ]]
}

@test "multi-arg lambda" {
    bs_run '((lambda (a b c) (+ a b c)) 1 2 3)'
    [[ "$result" == "6" ]]
}

@test "variadic lambda" {
    bs_run '((lambda args (length args)) 1 2 3 4)'
    [[ "$result" == "4" ]]
}

@test "dotted rest args" {
    bs_run '((lambda (x . rest) (cons x rest)) 1 2 3)'
    [[ "$__bs_last_display" == "(1 2 3)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 9. let / let* / letrec
# ────────────────────────────────────────────────────────────────────────────
@test "let basic" {
    bs_run '(let ((a 3) (b 4)) (+ a b))'
    [[ "$result" == "7" ]]
}

@test "let does not see siblings" {
    # In regular let, bindings see parent scope, not siblings
    bs '(define z 100)'
    bs_run '(let ((a 1) (b (+ z 1))) (+ a b))'
    [[ "$result" == "102" ]]
}

@test "let* sequential" {
    bs_run '(let* ((a 2) (b (* a 3))) b)'
    [[ "$result" == "6" ]]
}

@test "letrec mutual recursion" {
    bs_run '(letrec
               ((even? (lambda (n) (if (= n 0) #t (odd?  (- n 1)))))
                (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
             (even? 10))'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "named let loop" {
    bs_run '(let loop ((i 1) (acc 0))
              (if (> i 100) acc (loop (+ i 1) (+ acc i))))'
    [[ "$result" == "5050" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 10. cond / case / when / unless
# ────────────────────────────────────────────────────────────────────────────
@test "cond first match" {
    bs_run '(cond ((= 1 2) "no") ((= 2 2) "yes") (else "other"))'
    [[ "$result" == "yes" ]]
}

@test "cond else" {
    bs_run '(cond (#f 1) (#f 2) (else 99))'
    [[ "$result" == "99" ]]
}

@test "cond no else no match" {
    bs_run '(cond (#f 1))'
    [[ "$__bs_last" == "n:()" ]]
}

@test "case match" {
    bs_run '(case (* 2 3) ((2 3 5 7) "prime") ((1 4 6 8 9) "composite") (else "other"))'
    [[ "$result" == "composite" ]]
}

@test "case else" {
    bs_run '(case 99 ((1 2) "low") (else "high"))'
    [[ "$result" == "high" ]]
}

@test "when condition true" {
    bs_run '(when (= 1 1) 42)'
    [[ "$result" == "42" ]]
}

@test "when condition false" {
    bs_run '(when (= 1 2) 42)'
    [[ "$__bs_last" == "n:()" ]]
}

@test "unless condition false" {
    bs_run '(unless #f 77)'
    [[ "$result" == "77" ]]
}

@test "unless condition true" {
    bs_run '(unless #t 77)'
    [[ "$__bs_last" == "n:()" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 11. Type predicates
# ────────────────────────────────────────────────────────────────────────────
@test "number?" {
    bs_run '(number? 42)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(number? "x")'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "string?" {
    bs_run '(string? "hi")'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "symbol?" {
    bs_run "(symbol? 'foo)"
    [[ "$__bs_last" == "b:#t" ]]
}

@test "boolean?" {
    bs_run '(boolean? #t)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(boolean? 1)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "procedure?" {
    bs_run '(procedure? car)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(procedure? 42)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "zero? positive? negative?" {
    bs_run '(zero? 0)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(positive? 5)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(negative? -3)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "even? odd?" {
    bs_run '(even? 4)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(odd? 7)'
    [[ "$__bs_last" == "b:#t" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 12. List operations
# ────────────────────────────────────────────────────────────────────────────
@test "cons car cdr" {
    bs_run '(car (cons 1 2))'
    [[ "$result" == "1" ]]
    bs_run '(cdr (cons 1 2))'
    [[ "$result" == "2" ]]
}

@test "null?" {
    bs_run "(null? '())"
    [[ "$__bs_last" == "b:#t" ]]
    bs_run "(null? '(1))"
    [[ "$__bs_last" == "b:#f" ]]
}

@test "pair?" {
    bs_run "(pair? '(1 2))"
    [[ "$__bs_last" == "b:#t" ]]
    bs_run "(pair? '())"
    [[ "$__bs_last" == "b:#f" ]]
}

@test "list" {
    bs_run '(list 1 2 3)'
    [[ "$__bs_last_display" == "(1 2 3)" ]]
}

@test "length" {
    bs_run "(length '(a b c d))"
    [[ "$result" == "4" ]]
}

@test "append two lists" {
    bs_run "(append '(1 2) '(3 4))"
    [[ "$__bs_last_display" == "(1 2 3 4)" ]]
}

@test "append three lists" {
    bs_run "(append '(1) '(2) '(3))"
    [[ "$__bs_last_display" == "(1 2 3)" ]]
}

@test "reverse" {
    bs_run "(reverse '(1 2 3))"
    [[ "$__bs_last_display" == "(3 2 1)" ]]
}

@test "list-ref" {
    bs_run "(list-ref '(a b c d) 2)"
    [[ "$result" == "c" ]]
}

@test "list-tail" {
    bs_run "(list-tail '(a b c d) 2)"
    [[ "$__bs_last_display" == "(c d)" ]]
}

@test "map squares" {
    bs_run '(map (lambda (x) (* x x)) (list 1 2 3 4 5))'
    [[ "$__bs_last_display" == "(1 4 9 16 25)" ]]
}

@test "for-each" {
    bs_run '(for-each (lambda (x) x) (list 1 2 3))'
    [[ "$__bs_last" == "n:()" ]]
}

@test "filter odd" {
    bs_run '(filter odd? (list 1 2 3 4 5))'
    [[ "$__bs_last_display" == "(1 3 5)" ]]
}

@test "assoc" {
    bs_run "(assoc 'b '((a 1) (b 2) (c 3)))"
    [[ "$__bs_last_display" == "(b 2)" ]]
}

@test "member" {
    bs_run "(member 3 '(1 2 3 4))"
    [[ "$__bs_last_display" == "(3 4)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 13. String operations
# ────────────────────────────────────────────────────────────────────────────
@test "string-length" {
    bs_run '(string-length "hello")'
    [[ "$result" == "5" ]]
}

@test "string-append" {
    bs_run '(string-append "foo" "bar" "baz")'
    [[ "$__bs_last" == "s:foobarbaz" ]]
}

@test "substring" {
    bs_run '(substring "hello world" 6 11)'
    [[ "$__bs_last" == "s:world" ]]
}

@test "string->number integer" {
    bs_run '(string->number "123")'
    [[ "$result" == "123" ]]
}

@test "string->number not a number" {
    bs_run '(string->number "abc")'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "number->string" {
    bs_run '(number->string 42)'
    [[ "$__bs_last" == "s:42" ]]
}

@test "string->symbol" {
    bs_run '(string->symbol "foo")'
    [[ "$__bs_last" == "y:foo" ]]
}

@test "symbol->string" {
    bs_run "(symbol->string 'hello)"
    [[ "$__bs_last" == "s:hello" ]]
}

@test "string=?" {
    bs_run '(string=? "abc" "abc")'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(string=? "abc" "ABC")'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "string<?" {
    bs_run '(string<? "abc" "abd")'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "string-upcase" {
    bs_run '(string-upcase "hello")'
    [[ "$__bs_last" == "s:HELLO" ]]
}

@test "string-downcase" {
    bs_run '(string-downcase "WORLD")'
    [[ "$__bs_last" == "s:world" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 14. I/O (display writes to stderr; captured via redirection)
# ────────────────────────────────────────────────────────────────────────────
@test "display writes to stderr" {
    output="$(bs '(display 42)' 2>&1)"
    [[ "$output" == "42" ]]
}

@test "newline writes newline to stderr" {
    output="$(bs '(begin (display 1) (newline) (display 2))' 2>&1)"
    [[ "$output" == $'1\n2' ]]
}

@test "write strings with quotes" {
    output="$(bs '(write "hello")' 2>&1)"
    [[ "$output" == '"hello"' ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 15. quote
# ────────────────────────────────────────────────────────────────────────────
@test "quote symbol" {
    bs_run "'foo"
    [[ "$__bs_last" == "y:foo" ]]
}

@test "quote list" {
    bs_run "'(1 2 3)"
    [[ "$__bs_last_display" == "(1 2 3)" ]]
}

@test "quote nested" {
    bs_run "'(a (b c) d)"
    [[ "$__bs_last_display" == "(a (b c) d)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 16. Recursion
# ────────────────────────────────────────────────────────────────────────────
@test "factorial recursive" {
    bs '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))'
    bs_run '(fact 10)'
    [[ "$result" == "3628800" ]]
}

@test "fibonacci recursive" {
    bs '(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))'
    bs_run '(fib 15)'
    [[ "$result" == "610" ]]
}

@test "sum via named let" {
    bs_run '(let loop ((n 100) (acc 0))
              (if (= n 0) acc (loop (- n 1) (+ acc n))))'
    [[ "$result" == "5050" ]]
}

@test "mutual recursion even/odd" {
    bs '(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))'
    bs '(define (my-odd?  n) (if (= n 0) #f (my-even? (- n 1))))'
    bs_run '(my-even? 20)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(my-odd? 21)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "accumulator closure" {
    bs '(define make-counter
                  (lambda ()
                    (let ((n 0))
                      (lambda () (set! n (+ n 1)) n))))'
    bs '(define c (make-counter))'
    bs_run '(c)'; [[ "$result" == "1" ]]
    bs_run '(c)'; [[ "$result" == "2" ]]
    bs_run '(c)'; [[ "$result" == "3" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 17. apply
# ────────────────────────────────────────────────────────────────────────────
@test "apply with list" {
    bs_run "(apply + '(1 2 3 4 5))"
    [[ "$result" == "15" ]]
}

@test "apply with leading args" {
    bs_run "(apply list 1 2 '(3 4))"
    [[ "$__bs_last_display" == "(1 2 3 4)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 18. do loop
# ────────────────────────────────────────────────────────────────────────────
@test "do loop sum" {
    bs_run '(do ((i 1 (+ i 1))
                 (s 0 (+ s i)))
                ((> i 10) s))'
    [[ "$result" == "55" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 19. Persistence across calls
# ────────────────────────────────────────────────────────────────────────────
@test "variable persists across bs calls" {
    bs '(define x 1)'
    bs '(set! x (+ x 41))'
    [[ "$x" == "i:42" ]]
}

@test "closure persists across bs calls" {
    bs '(define adder (lambda (n) (lambda (x) (+ x n))))'
    bs '(define plus7 (adder 7))'
    bs_run '(plus7 35)'
    [[ "$result" == "42" ]]
}

@test "define then use in next call" {
    bs '(define (double x) (* 2 x))'
    bs_run '(double 21)'
    [[ "$result" == "42" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 20. Multi-expression source
# ────────────────────────────────────────────────────────────────────────────
@test "multiple top-level expressions" {
    bs '(define a 10) (define b 32) (+ a b)'
    [[ "$__bs_last" == "i:42" ]]
    [[ "$a" == "i:10" ]]
    [[ "$b" == "i:32" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 21. Higher-order functions
# ────────────────────────────────────────────────────────────────────────────
@test "compose" {
    bs '(define (compose f g) (lambda (x) (f (g x))))'
    bs '(define inc (lambda (x) (+ x 1)))'
    bs '(define double (lambda (x) (* 2 x)))'
    bs_run '((compose inc double) 20)'
    [[ "$result" == "41" ]]
}

@test "fold-left sum" {
    bs_run "(foldl (lambda (x acc) (+ x acc)) 0 '(1 2 3 4 5))"
    [[ "$result" == "15" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 22. Vector operations
# ────────────────────────────────────────────────────────────────────────────
@test "make-vector and vector-ref" {
    bs_run '(let ((v (make-vector 3 0))) (vector-ref v 1))'
    [[ "$result" == "0" ]]
}

@test "make-vector with fill" {
    bs_run '(let ((v (make-vector 3 42))) (vector-ref v 2))'
    [[ "$result" == "42" ]]
}

@test "vector constructor" {
    bs_run '(let ((v (vector 10 20 30))) (vector-ref v 1))'
    [[ "$result" == "20" ]]
}

@test "vector-set! and read back" {
    bs_run '(let ((v (make-vector 3 0)))
              (vector-set! v 1 99)
              (vector-ref v 1))'
    [[ "$result" == "99" ]]
}

@test "vector-length" {
    bs_run '(vector-length (vector 1 2 3 4 5))'
    [[ "$result" == "5" ]]
}

@test "vector->list" {
    bs_run '(vector->list (vector 1 2 3))'
    [[ "$__bs_last_display" == "(1 2 3)" ]]
}

@test "list->vector round-trip" {
    bs_run "(let ((v (list->vector '(10 20 30)))) (vector-ref v 2))"
    [[ "$result" == "30" ]]
}

@test "vector?" {
    bs_run '(vector? (vector 1 2))'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(vector? 42)'
    [[ "$__bs_last" == "b:#f" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 23. Character operations
# ────────────────────────────────────────────────────────────────────────────
@test "char literal" {
    bs_run '#\a'
    [[ "$__bs_last" == "c:a" ]]
}

@test "char space literal" {
    bs_run '#\space'
    [[ "$__bs_last" == "c: " ]]
}

@test "char->integer" {
    bs_run '(char->integer #\A)'
    [[ "$result" == "65" ]]
}

@test "integer->char" {
    bs_run '(integer->char 65)'
    [[ "$__bs_last" == "c:A" ]]
}

@test "char=?" {
    bs_run '(char=? #\a #\a)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(char=? #\a #\b)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "char<?" {
    bs_run '(char<? #\a #\b)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(char<? #\b #\a)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "char-alphabetic?" {
    bs_run '(char-alphabetic? #\a)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(char-alphabetic? #\1)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "char-numeric?" {
    bs_run '(char-numeric? #\5)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(char-numeric? #\x)'
    [[ "$__bs_last" == "b:#f" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 24. Quasiquote
# ────────────────────────────────────────────────────────────────────────────
@test "quasiquote without unquote" {
    bs_run '`(1 2 3)'
    [[ "$__bs_last_display" == "(1 2 3)" ]]
}

@test "quasiquote with unquote" {
    bs '(define x 42)'
    bs_run '`(a ,x b)'
    [[ "$__bs_last_display" == "(a 42 b)" ]]
}

@test "quasiquote nested" {
    bs '(define y 10)'
    bs_run '`(1 ,(+ y 5) 3)'
    [[ "$__bs_last_display" == "(1 15 3)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 25. Additional list operations
# ────────────────────────────────────────────────────────────────────────────
@test "set-car!" {
    bs_run '(let ((p (cons 1 2))) (set-car! p 99) (car p))'
    [[ "$result" == "99" ]]
}

@test "set-cdr!" {
    bs_run '(let ((p (cons 1 2))) (set-cdr! p 99) (cdr p))'
    [[ "$result" == "99" ]]
}

@test "list? proper list" {
    bs_run "(list? '(1 2 3))"
    [[ "$__bs_last" == "b:#t" ]]
}

@test "list? dotted pair" {
    bs_run '(list? (cons 1 2))'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "list? empty list" {
    bs_run "(list? '())"
    [[ "$__bs_last" == "b:#t" ]]
}

@test "fold-right" {
    bs_run "(foldr cons '() '(1 2 3))"
    [[ "$__bs_last_display" == "(1 2 3)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 26. Additional string operations
# ────────────────────────────────────────────────────────────────────────────
@test "string-ref" {
    bs_run '(string-ref "hello" 1)'
    [[ "$__bs_last" == "c:e" ]]
}

@test "string>?" {
    bs_run '(string>? "b" "a")'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(string>? "a" "b")'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "string<=?" {
    bs_run '(string<=? "a" "b")'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(string<=? "a" "a")'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "string>=?" {
    bs_run '(string>=? "b" "a")'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(string>=? "b" "b")'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "make-string" {
    bs_run '(make-string 5 #\x)'
    [[ "$__bs_last" == "s:xxxxx" ]]
}

@test "string-copy" {
    bs_run '(string-copy "hello")'
    [[ "$__bs_last" == "s:hello" ]]
}

@test "string constructor from chars" {
    bs_run '(string #\h #\i)'
    [[ "$__bs_last" == "s:hi" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 27. Additional arithmetic
# ────────────────────────────────────────────────────────────────────────────
@test "lcm" {
    bs_run '(lcm 4 6)'
    [[ "$result" == "12" ]]
}

@test "exact->inexact identity" {
    bs_run '(exact->inexact 42)'
    [[ "$result" == "42" ]]
}

@test "floor identity" {
    bs_run '(floor 7)'
    [[ "$result" == "7" ]]
}

@test "ceiling identity" {
    bs_run '(ceiling 7)'
    [[ "$result" == "7" ]]
}

@test "round identity" {
    bs_run '(round 7)'
    [[ "$result" == "7" ]]
}

@test "truncate identity" {
    bs_run '(truncate 7)'
    [[ "$result" == "7" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 28. letrec*
# ────────────────────────────────────────────────────────────────────────────
@test "letrec* basic" {
    bs_run '(letrec* ((a 1) (b (+ a 1))) (+ a b))'
    [[ "$result" == "3" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 29. error primitive
# ────────────────────────────────────────────────────────────────────────────
@test "error outputs message to stderr" {
    run bash -c 'source bs.sh; bs-reset; bs '\''(error "oops" 42)'\'' 2>&1'
    [[ "$output" == *"oops"* ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 30. do loop (additional)
# ────────────────────────────────────────────────────────────────────────────
@test "do loop vector fill" {
    bs_run '(let ((v (make-vector 5 0)))
              (do ((i 0 (+ i 1)))
                  ((= i 5) v)
                (vector-set! v i (* i i)))
              (vector->list v))'
    [[ "$__bs_last_display" == "(0 1 4 9 16)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 31. Edge cases
# ────────────────────────────────────────────────────────────────────────────
@test "deeply nested arithmetic" {
    bs_run '(+ (+ (+ 1 2) (+ 3 4)) (+ (+ 5 6) (+ 7 8)))'
    [[ "$result" == "36" ]]
}

@test "lambda in let binding" {
    bs_run '(let ((f (lambda (x) (* x 2)))) (f 21))'
    [[ "$result" == "42" ]]
}

@test "empty begin" {
    bs_run '(begin)'
    [[ "$__bs_last" == "n:()" ]]
}

@test "boolean as condition (non-false is truthy)" {
    bs_run '(if 0 "yes" "no")'
    [[ "$result" == "yes" ]]
}

@test "chained comparisons" {
    bs_run '(< 1 2 3 4 5)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(< 1 2 2 4 5)'
    [[ "$__bs_last" == "b:#f" ]]
}

@test "map with lambda" {
    bs_run '(map (lambda (x) (+ x 10)) (list 1 2 3))'
    [[ "$__bs_last_display" == "(11 12 13)" ]]
}

@test "filter with lambda" {
    bs_run '(filter (lambda (x) (> x 3)) (list 1 2 3 4 5))'
    [[ "$__bs_last_display" == "(4 5)" ]]
}

@test "nested define and closure" {
    bs '(define (make-pair a b) (lambda (sel) (if sel a b)))'
    bs '(define p (make-pair 10 20))'
    bs_run '(p #t)'
    [[ "$result" == "10" ]]
    bs_run '(p #f)'
    [[ "$result" == "20" ]]
}

@test "append empty lists" {
    bs_run "(append '() '() '())"
    [[ "$__bs_last" == "n:()" ]]
}

@test "reverse empty list" {
    bs_run "(reverse '())"
    [[ "$__bs_last" == "n:()" ]]
}

@test "length empty list" {
    bs_run "(length '())"
    [[ "$result" == "0" ]]
}

@test "cond => syntax" {
    bs_run "(cond ((assoc 'b '((a 1) (b 2) (c 3))) => cdr))"
    [[ "$__bs_last_display" == "(2)" ]]
}
