#!/usr/bin/env bash
# tests/r5rs-tests.sh - R5RS compatibility test suite for sheme
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

test_true() {
    local desc="$1" expr="$2"
    (( __test_num++ ))
    bs-reset
    bs "$expr"
    if [[ "$__bs_last" == "b:#t" ]]; then
        echo "ok $__test_num - $desc"
        (( __test_pass++ ))
    else
        echo "not ok $__test_num - $desc"
        echo "#   expression: $expr"
        echo "#   expected:   #t"
        echo "#   actual:     $__bs_last ($__bs_last_display)"
        (( __test_fail++ ))
    fi
}

test_false() {
    local desc="$1" expr="$2"
    (( __test_num++ ))
    bs-reset
    bs "$expr"
    if [[ "$__bs_last" == "b:#f" ]]; then
        echo "ok $__test_num - $desc"
        (( __test_pass++ ))
    else
        echo "not ok $__test_num - $desc"
        echo "#   expression: $expr"
        echo "#   expected:   #f"
        echo "#   actual:     $__bs_last ($__bs_last_display)"
        (( __test_fail++ ))
    fi
}

skip_test() {
    local desc="$1" reason="$2"
    (( __test_num++ ))
    (( __test_skip++ ))
    echo "ok $__test_num - # SKIP $desc ($reason)"
}

# Helper: evaluate multiple expressions in order (preserving state, no reset)
bs_multi() {
    for _expr in "$@"; do
        bs "$_expr"
    done
}

# ── Plan ──────────────────────────────────────────────────────────────
echo "TAP version 13"
echo "# R5RS compatibility tests for sheme"
echo ""

# ======================================================================
# LAMBDA AND CLOSURES
# ======================================================================
echo "# -- Lambda and closures --"

test_equal "basic lambda application" \
    "((lambda (x) (* x x)) 5)" "25"

test_equal "multi-arg lambda" \
    "((lambda (a b c) (+ a (* b c))) 1 2 3)" "7"

# Closure: capture free variable
(( __test_num++ ))
bs-reset
bs '(define make-adder (lambda (n) (lambda (x) (+ x n))))'
bs '(define add10 (make-adder 10))'
bs '(add10 32)'
if [[ "$__bs_last_display" == "42" ]]; then
    echo "ok $__test_num - closure captures environment"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - closure captures environment"
    echo "#   expected: 42, actual: $__bs_last_display"
    (( __test_fail++ ))
fi

# Nested closures
(( __test_num++ ))
bs-reset
bs '(define (compose f g) (lambda (x) (f (g x))))'
bs '(define inc (lambda (x) (+ x 1)))'
bs '(define dbl (lambda (x) (* x 2)))'
bs '((compose inc dbl) 20)'
if [[ "$__bs_last_display" == "41" ]]; then
    echo "ok $__test_num - nested closures (compose)"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - nested closures (compose)"
    echo "#   expected: 41, actual: $__bs_last_display"
    (( __test_fail++ ))
fi

# Higher-order: map with lambda
test_equal "higher-order: map with lambda" \
    "(map (lambda (x) (* x x)) (list 1 2 3 4 5))" "(1 4 9 16 25)"

# Variadic lambda (rest args)
test_equal "variadic lambda (rest args)" \
    "((lambda args (length args)) 1 2 3 4)" "4"

# Dotted rest args
test_equal "dotted rest args" \
    "((lambda (x . rest) (cons x rest)) 1 2 3)" "(1 2 3)"

# ======================================================================
# CONDITIONALS
# ======================================================================
echo "# -- Conditionals --"

test_equal "if true branch" "(if #t 10 20)" "10"
test_equal "if false branch" "(if #f 10 20)" "20"

# cond
test_equal "cond first match" \
    '(cond ((= 1 2) "no") ((= 2 2) "yes") (else "other"))' "yes"

test_equal "cond else clause" \
    '(cond (#f 1) (#f 2) (else 99))' "99"

# case
test_equal "case matching clause" \
    '(case (* 2 3) ((2 3 5 7) "prime") ((1 4 6 8 9) "composite") (else "other"))' "composite"

# and short-circuit
test_equal "and returns last truthy value" "(and 1 2 3)" "3"

(( __test_num++ ))
bs-reset
bs '(and 1 #f 3)'
if [[ "$__bs_last" == "b:#f" ]]; then
    echo "ok $__test_num - and short-circuits on #f"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - and short-circuits on #f"
    (( __test_fail++ ))
fi

# or short-circuit
test_equal "or returns first truthy value" "(or #f #f 5)" "5"

(( __test_num++ ))
bs-reset
bs '(or #f #f)'
if [[ "$__bs_last" == "b:#f" ]]; then
    echo "ok $__test_num - or returns #f when all false"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - or returns #f when all false"
    (( __test_fail++ ))
fi

# ======================================================================
# BINDING FORMS
# ======================================================================
echo "# -- Binding forms --"

test_equal "let basic binding" "(let ((a 3) (b 4)) (+ a b))" "7"

test_equal "let* sequential binding" "(let* ((a 2) (b (* a 3))) b)" "6"

# letrec (mutual recursion)
test_true "letrec mutual recursion" \
    '(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1))))) (odd? (lambda (n) (if (= n 0) #f (even? (- n 1)))))) (even? 10))'

# Named let (loop)
test_equal "named let loop (sum 1..100)" \
    "(let loop ((i 1) (acc 0)) (if (> i 100) acc (loop (+ i 1) (+ acc i))))" "5050"

# ======================================================================
# ITERATION
# ======================================================================
echo "# -- Iteration --"

test_equal "do loop (sum 1..10)" \
    "(do ((i 1 (+ i 1)) (s 0 (+ s i))) ((> i 10) s))" "55"

# ======================================================================
# QUASIQUOTE
# ======================================================================
echo "# -- Quasiquote --"

test_equal "basic quasiquote" '`(1 2 3)' "(1 2 3)"

(( __test_num++ ))
bs-reset
bs '(define x 42)'
bs '`(a ,x b)'
if [[ "$__bs_last_display" == "(a 42 b)" ]]; then
    echo "ok $__test_num - quasiquote with unquote"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - quasiquote with unquote"
    echo "#   expected: (a 42 b), actual: $__bs_last_display"
    (( __test_fail++ ))
fi

(( __test_num++ ))
bs-reset
bs '(define y 10)'
bs '`(1 ,(+ y 5) 3)'
if [[ "$__bs_last_display" == "(1 15 3)" ]]; then
    echo "ok $__test_num - quasiquote with computed unquote"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - quasiquote with computed unquote"
    echo "#   expected: (1 15 3), actual: $__bs_last_display"
    (( __test_fail++ ))
fi

skip_test "unquote-splicing" "not implemented in sheme"

# ======================================================================
# EQUIVALENCE PREDICATES
# ======================================================================
echo "# -- Equivalence predicates --"

test_true "eq? same symbol" "(eq? 'a 'a)"
test_false "eq? different symbols" "(eq? 'a 'b)"
test_true "eq? same integer" "(eq? 42 42)"
test_true "eqv? same integer" "(eqv? 7 7)"
test_false "eqv? different integers" "(eqv? 7 8)"
test_true "equal? same lists" "(equal? '(1 2 3) '(1 2 3))"
test_false "equal? different lists" "(equal? '(1 2) '(1 3))"
test_true "equal? nested lists" "(equal? '(1 (2 3)) '(1 (2 3)))"
test_true "equal? same strings" '(equal? "abc" "abc")'

# ======================================================================
# ARITHMETIC
# ======================================================================
echo "# -- Arithmetic --"

test_equal "addition" "(+ 1 2 3)" "6"
test_equal "subtraction" "(- 10 3)" "7"
test_equal "unary negation" "(- 5)" "-5"
test_equal "multiplication" "(* 6 7)" "42"
test_equal "integer division" "(/ 10 3)" "3"
test_equal "quotient" "(quotient 13 4)" "3"
test_equal "remainder" "(remainder 13 4)" "1"
test_equal "modulo positive" "(modulo 13 4)" "1"
test_equal "modulo negative dividend" "(modulo -13 4)" "3"
test_true "= equal" "(= 5 5)"
test_false "= not equal" "(= 5 6)"
test_true "< less than" "(< 1 2)"
test_false "< not less" "(< 3 2)"
test_true "> greater than" "(> 5 3)"
test_true "<= less or equal (less)" "(<= 2 3)"
test_true "<= less or equal (equal)" "(<= 3 3)"
test_true ">= greater or equal" "(>= 5 3)"
test_true "zero? on 0" "(zero? 0)"
test_false "zero? on non-zero" "(zero? 5)"
test_true "positive?" "(positive? 5)"
test_true "negative?" "(negative? -3)"
test_equal "abs positive" "(abs 5)" "5"
test_equal "abs negative" "(abs -5)" "5"
test_equal "min" "(min 3 1 4 1 5)" "1"
test_equal "max" "(max 3 1 4 1 5 9 2 6)" "9"
test_equal "gcd" "(gcd 32 -36)" "4"

# ======================================================================
# BOOLEANS
# ======================================================================
echo "# -- Booleans --"

test_true "not #f is #t" "(not #f)"
test_false "not #t is #f" "(not #t)"
test_false "not non-false is #f" "(not 42)"
test_true "boolean? #t" "(boolean? #t)"
test_true "boolean? #f" "(boolean? #f)"
test_false "boolean? on integer" "(boolean? 42)"

# ======================================================================
# PAIRS AND LISTS
# ======================================================================
echo "# -- Pairs and lists --"

test_equal "cons" "(cons 1 2)" "(1 . 2)"
test_equal "car" "(car (cons 1 2))" "1"
test_equal "cdr" "(cdr (cons 1 2))" "2"
test_equal "list" "(list 1 2 3)" "(1 2 3)"
test_true "null? on empty list" "(null? '())"
test_false "null? on non-empty" "(null? '(1))"
test_true "pair? on pair" "(pair? '(1 2))"
test_false "pair? on empty list" "(pair? '())"
test_equal "length" "(length '(a b c d))" "4"
test_equal "append two lists" "(append '(1 2) '(3 4))" "(1 2 3 4)"
test_equal "reverse" "(reverse '(1 2 3))" "(3 2 1)"
test_equal "list-ref" "(list-ref '(a b c d) 2)" "c"

# map
test_equal "map" "(map (lambda (x) (+ x 10)) (list 1 2 3))" "(11 12 13)"

# for-each (returns void/unspecified)
(( __test_num++ ))
bs-reset
bs "(for-each (lambda (x) x) (list 1 2 3))"
if [[ "$__bs_last" == "n:()" ]]; then
    echo "ok $__test_num - for-each returns void"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - for-each returns void"
    (( __test_fail++ ))
fi

# assoc
test_equal "assoc" "(assoc 'b '((a 1) (b 2) (c 3)))" "(b 2)"

# assv
test_equal "assv" "(assv 2 '((1 a) (2 b) (3 c)))" "(2 b)"

# ======================================================================
# CHARACTERS
# ======================================================================
echo "# -- Characters --"

test_true "char?" "(char? #\\a)"
test_false "char? on integer" "(char? 42)"
test_true "char=? same" "(char=? #\\a #\\a)"
test_false "char=? different" "(char=? #\\a #\\b)"
test_true "char<?" "(char<? #\\a #\\b)"
test_true "char-alphabetic?" "(char-alphabetic? #\\a)"
test_false "char-alphabetic? on digit" "(char-alphabetic? #\\1)"
test_true "char-numeric?" "(char-numeric? #\\5)"
test_false "char-numeric? on letter" "(char-numeric? #\\x)"
test_equal "char->integer" "(char->integer #\\A)" "65"

(( __test_num++ ))
bs-reset
bs '(integer->char 65)'
if [[ "$__bs_last" == "c:A" ]]; then
    echo "ok $__test_num - integer->char"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - integer->char"
    echo "#   expected: c:A, actual: $__bs_last"
    (( __test_fail++ ))
fi

# ======================================================================
# STRINGS
# ======================================================================
echo "# -- Strings --"

test_true "string?" '(string? "hello")'
test_false "string? on integer" "(string? 42)"
test_equal "string-length" '(string-length "hello")' "5"

(( __test_num++ ))
bs-reset
bs '(string-ref "hello" 1)'
if [[ "$__bs_last" == "c:e" ]]; then
    echo "ok $__test_num - string-ref"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - string-ref"
    echo "#   expected: c:e, actual: $__bs_last"
    (( __test_fail++ ))
fi

(( __test_num++ ))
bs-reset
bs '(substring "hello world" 6 11)'
if [[ "$__bs_last" == "s:world" ]]; then
    echo "ok $__test_num - substring"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - substring"
    echo "#   expected: s:world, actual: $__bs_last"
    (( __test_fail++ ))
fi

(( __test_num++ ))
bs-reset
bs '(string-append "foo" "bar" "baz")'
if [[ "$__bs_last" == "s:foobarbaz" ]]; then
    echo "ok $__test_num - string-append"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - string-append"
    echo "#   expected: s:foobarbaz, actual: $__bs_last"
    (( __test_fail++ ))
fi

test_equal "string->list" '(string->list "abc")' "(a b c)"
test_equal "list->string" '(list->string (list #\a #\b #\c))' "abc"

(( __test_num++ ))
bs-reset
bs '(string-upcase "hello")'
if [[ "$__bs_last" == "s:HELLO" ]]; then
    echo "ok $__test_num - string-upcase"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - string-upcase"
    echo "#   expected: s:HELLO, actual: $__bs_last"
    (( __test_fail++ ))
fi

(( __test_num++ ))
bs-reset
bs '(string-downcase "WORLD")'
if [[ "$__bs_last" == "s:world" ]]; then
    echo "ok $__test_num - string-downcase"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - string-downcase"
    echo "#   expected: s:world, actual: $__bs_last"
    (( __test_fail++ ))
fi

(( __test_num++ ))
bs-reset
bs '(string-copy "hello")'
if [[ "$__bs_last" == "s:hello" ]]; then
    echo "ok $__test_num - string-copy"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - string-copy"
    echo "#   expected: s:hello, actual: $__bs_last"
    (( __test_fail++ ))
fi

# ======================================================================
# VECTORS
# ======================================================================
echo "# -- Vectors --"

test_true "vector?" "(vector? (vector 1 2))"
test_false "vector? on integer" "(vector? 42)"
test_equal "make-vector and vector-ref" "(let ((v (make-vector 3 0))) (vector-ref v 1))" "0"
test_equal "vector constructor" "(let ((v (vector 10 20 30))) (vector-ref v 1))" "20"

(( __test_num++ ))
bs-reset
bs '(let ((v (make-vector 3 0))) (vector-set! v 1 99) (vector-ref v 1))'
if [[ "$__bs_last_display" == "99" ]]; then
    echo "ok $__test_num - vector-set!"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - vector-set!"
    echo "#   expected: 99, actual: $__bs_last_display"
    (( __test_fail++ ))
fi

test_equal "vector-length" "(vector-length (vector 1 2 3 4 5))" "5"
test_equal "vector->list" "(vector->list (vector 1 2 3))" "(1 2 3)"
test_equal "list->vector round-trip" "(let ((v (list->vector '(10 20 30)))) (vector-ref v 2))" "30"

# ======================================================================
# APPLY
# ======================================================================
echo "# -- Apply --"

test_equal "apply with list" "(apply + '(1 2 3 4 5))" "15"
test_equal "apply with leading args" "(apply list 1 2 '(3 4))" "(1 2 3 4)"

(( __test_num++ ))
bs-reset
bs '(define (sum . args) (apply + args))'
bs '(sum 1 2 3 4 5)'
if [[ "$__bs_last_display" == "15" ]]; then
    echo "ok $__test_num - apply with varargs"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - apply with varargs"
    echo "#   expected: 15, actual: $__bs_last_display"
    (( __test_fail++ ))
fi

# ======================================================================
# TAIL CALLS / RECURSION
# ======================================================================
echo "# -- Tail calls and recursion --"

# Proper tail recursion: mutual recursion that would blow the stack without TCO
(( __test_num++ ))
bs-reset
bs '(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))'
bs '(define (my-odd?  n) (if (= n 0) #f (my-even? (- n 1))))'
bs '(my-even? 200)'
if [[ "$__bs_last" == "b:#t" ]]; then
    echo "ok $__test_num - mutual recursion (even?/odd? 200)"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - mutual recursion (even?/odd? 200)"
    echo "#   expected: #t, actual: $__bs_last ($__bs_last_display)"
    (( __test_fail++ ))
fi

# Factorial (classic recursion)
(( __test_num++ ))
bs-reset
bs '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))'
bs '(fact 10)'
if [[ "$__bs_last_display" == "3628800" ]]; then
    echo "ok $__test_num - recursive factorial"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - recursive factorial"
    echo "#   expected: 3628800, actual: $__bs_last_display"
    (( __test_fail++ ))
fi

# Accumulator closure
(( __test_num++ ))
bs-reset
bs '(define make-counter (lambda () (let ((n 0)) (lambda () (set! n (+ n 1)) n))))'
bs '(define c (make-counter))'
bs '(c)'
local_r1="$__bs_last_display"
bs '(c)'
local_r2="$__bs_last_display"
bs '(c)'
local_r3="$__bs_last_display"
if [[ "$local_r1" == "1" && "$local_r2" == "2" && "$local_r3" == "3" ]]; then
    echo "ok $__test_num - accumulator closure"
    (( __test_pass++ ))
else
    echo "not ok $__test_num - accumulator closure"
    echo "#   expected: 1,2,3; actual: $local_r1,$local_r2,$local_r3"
    (( __test_fail++ ))
fi

# ======================================================================
# SKIPPED R5RS FEATURES
# ======================================================================
echo "# -- Skipped features (not in sheme) --"

skip_test "call/cc" "not implemented"
skip_test "dynamic-wind" "not implemented"
skip_test "delay/force" "not implemented"
skip_test "define-syntax / syntax-rules" "not implemented"
skip_test "floating point arithmetic" "integer-only interpreter"

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
