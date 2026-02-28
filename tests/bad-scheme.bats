#!/usr/bin/env bats
# tests/bad-scheme.bats - Test suite for bad-scheme.sh

# ────────────────────────────────────────────────────────────────────────────
# Setup / teardown
# ────────────────────────────────────────────────────────────────────────────
setup() {
    # Absolute path to the interpreter regardless of where bats is invoked from
    INTERP="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bad-scheme.sh"
    # shellcheck disable=SC1090
    source "$INTERP"
    bs-reset          # fresh heap for every test
}

teardown() {
    bs-reset          # clean up state file
}

# Convenience: evaluate expr and expose $result (display form) and $__bs_last
bs_run() {
    eval "$(bs "$1")"
    __bs_display "$__bs_last"
    result="$__bs_ret"
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
    eval "$(bs '(define x 99)')"
    [[ "$x" == "i:99" ]]
}

@test "define function shorthand" {
    eval "$(bs '(define (square n) (* n n))')"
    bs_run '(square 7)'
    [[ "$result" == "49" ]]
}

@test "set! updates variable" {
    eval "$(bs '(define counter 0)')"
    eval "$(bs '(set! counter (+ counter 1))')"
    eval "$(bs '(set! counter (+ counter 1))')"
    [[ "$counter" == "i:2" ]]
}

@test "define overwrites" {
    eval "$(bs '(define v 1)')"
    eval "$(bs '(define v 2)')"
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
    eval "$(bs '(define make-adder (lambda (n) (lambda (x) (+ x n))))')"
    eval "$(bs '(define add5 (make-adder 5))')"
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
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 2 3)" ]]
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
    eval "$(bs '(define z 100)')"
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
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 2 3)" ]]
}

@test "length" {
    bs_run "(length '(a b c d))"
    [[ "$result" == "4" ]]
}

@test "append two lists" {
    bs_run "(append '(1 2) '(3 4))"
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 2 3 4)" ]]
}

@test "append three lists" {
    bs_run "(append '(1) '(2) '(3))"
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 2 3)" ]]
}

@test "reverse" {
    bs_run "(reverse '(1 2 3))"
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(3 2 1)" ]]
}

@test "list-ref" {
    bs_run "(list-ref '(a b c d) 2)"
    [[ "$result" == "c" ]]
}

@test "list-tail" {
    bs_run "(list-tail '(a b c d) 2)"
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(c d)" ]]
}

@test "map squares" {
    bs_run '(map (lambda (x) (* x x)) (list 1 2 3 4 5))'
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 4 9 16 25)" ]]
}

@test "for-each" {
    bs_run '(for-each (lambda (x) x) (list 1 2 3))'
    [[ "$__bs_last" == "n:()" ]]
}

@test "filter odd" {
    bs_run '(filter odd? (list 1 2 3 4 5))'
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 3 5)" ]]
}

@test "assoc" {
    bs_run "(assoc 'b '((a 1) (b 2) (c 3)))"
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(b 2)" ]]
}

@test "member" {
    bs_run "(member 3 '(1 2 3 4))"
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(3 4)" ]]
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
    output="$(eval "$(bs '(display 42)')" 2>&1)"
    [[ "$output" == "42" ]]
}

@test "newline writes newline to stderr" {
    output="$(eval "$(bs '(begin (display 1) (newline) (display 2))')" 2>&1)"
    [[ "$output" == $'1\n2' ]]
}

@test "write strings with quotes" {
    output="$(eval "$(bs '(write "hello")')" 2>&1)"
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
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 2 3)" ]]
}

@test "quote nested" {
    bs_run "'(a (b c) d)"
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(a (b c) d)" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 16. Recursion
# ────────────────────────────────────────────────────────────────────────────
@test "factorial recursive" {
    eval "$(bs '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))')"
    bs_run '(fact 10)'
    [[ "$result" == "3628800" ]]
}

@test "fibonacci recursive" {
    eval "$(bs '(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))')"
    bs_run '(fib 15)'
    [[ "$result" == "610" ]]
}

@test "sum via named let" {
    bs_run '(let loop ((n 100) (acc 0))
              (if (= n 0) acc (loop (- n 1) (+ acc n))))'
    [[ "$result" == "5050" ]]
}

@test "mutual recursion even/odd" {
    eval "$(bs '(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))')"
    eval "$(bs '(define (my-odd?  n) (if (= n 0) #f (my-even? (- n 1))))')"
    bs_run '(my-even? 20)'
    [[ "$__bs_last" == "b:#t" ]]
    bs_run '(my-odd? 21)'
    [[ "$__bs_last" == "b:#t" ]]
}

@test "accumulator closure" {
    eval "$(bs '(define make-counter
                  (lambda ()
                    (let ((n 0))
                      (lambda () (set! n (+ n 1)) n))))')"
    eval "$(bs '(define c (make-counter))')"
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
    __bs_display "$__bs_last"; [[ "$__bs_ret" == "(1 2 3 4)" ]]
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
    eval "$(bs '(define x 1)')"
    eval "$(bs '(set! x (+ x 41))')"
    [[ "$x" == "i:42" ]]
}

@test "closure persists across bs calls" {
    eval "$(bs '(define adder (lambda (n) (lambda (x) (+ x n))))')"
    eval "$(bs '(define plus7 (adder 7))')"
    bs_run '(plus7 35)'
    [[ "$result" == "42" ]]
}

@test "define then use in next call" {
    eval "$(bs '(define (double x) (* 2 x))')"
    bs_run '(double 21)'
    [[ "$result" == "42" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 20. Multi-expression source
# ────────────────────────────────────────────────────────────────────────────
@test "multiple top-level expressions" {
    eval "$(bs '(define a 10) (define b 32) (+ a b)')"
    [[ "$__bs_last" == "i:42" ]]
    [[ "$a" == "i:10" ]]
    [[ "$b" == "i:32" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# 21. Higher-order functions
# ────────────────────────────────────────────────────────────────────────────
@test "compose" {
    eval "$(bs '(define (compose f g) (lambda (x) (f (g x))))')"
    eval "$(bs '(define inc (lambda (x) (+ x 1)))')"
    eval "$(bs '(define double (lambda (x) (* 2 x)))')"
    bs_run '((compose inc double) 20)'
    [[ "$result" == "41" ]]
}

@test "fold-left sum" {
    bs_run "(foldl (lambda (x acc) (+ x acc)) 0 '(1 2 3 4 5))"
    [[ "$result" == "15" ]]
}
