#!/usr/bin/env zsh
# tests/bs-zsh.zsh - Test suite for bs.zsh
# Run: zsh tests/bs-zsh.zsh

emulate -L zsh
setopt KSH_ARRAYS

# ── Test harness ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bs.zsh"

_pass=0 _fail=0 _total=0

bs_run() {
    eval "$(bs "$1")"
    result="$__bs_last_display"
}

assert() {
    local desc="$1" actual="$2" expected="$3"
    (( _total++ ))
    if [[ "$actual" == "$expected" ]]; then
        (( _pass++ ))
        printf 'ok %d %s\n' "$_total" "$desc"
    else
        (( _fail++ ))
        printf 'not ok %d %s\n' "$_total" "$desc"
        printf '  expected: [%s]\n  got:      [%s]\n' "$expected" "$actual"
    fi
}

# ── 1. Literals & self-evaluating forms ──────────────────────────────────────
bs-reset
bs_run '42'; assert "integer literal" "$result" "42"
bs_run '-7'; assert "negative integer" "$result" "-7"
bs_run '#t'; assert "boolean #t" "$__bs_last" "b:#t"
bs_run '#f'; assert "boolean #f" "$__bs_last" "b:#f"
bs_run '"hello"'; assert "string literal" "$__bs_last" "s:hello"
bs_run "'()"; assert "empty list" "$__bs_last" "n:()"

# ── 2. Arithmetic ────────────────────────────────────────────────────────────
bs-reset
bs_run '(+ 1 2)'; assert "addition" "$result" "3"
bs_run '(- 10 3)'; assert "subtraction" "$result" "7"
bs_run '(* 6 7)'; assert "multiplication" "$result" "42"
bs_run '(/ 10 3)'; assert "integer division" "$result" "3"
bs_run '(+ (* 2 3) (- 10 4))'; assert "nested arithmetic" "$result" "12"
bs_run '(quotient 13 4)'; assert "quotient" "$result" "3"
bs_run '(remainder 13 4)'; assert "remainder" "$result" "1"
bs_run '(modulo 13 4)'; assert "modulo positive" "$result" "1"
bs_run '(modulo -13 4)'; assert "modulo negative dividend" "$result" "3"
bs_run '(abs 5)'; assert "abs positive" "$result" "5"
bs_run '(abs -5)'; assert "abs negative" "$result" "5"
bs_run '(expt 2 10)'; assert "expt" "$result" "1024"
bs_run '(max 3 1 4 1 5 9 2 6)'; assert "max" "$result" "9"
bs_run '(min 3 1 4 1 5)'; assert "min" "$result" "1"
bs_run '(gcd 32 -36)'; assert "gcd" "$result" "4"
bs_run '(+ 1 2 3 4 5)'; assert "multi-arg addition" "$result" "15"
bs_run '(- 5)'; assert "unary negation" "$result" "-5"

# ── 3. Comparisons ───────────────────────────────────────────────────────────
bs-reset
bs_run '(= 3 3)'; assert "= true" "$__bs_last" "b:#t"
bs_run '(= 3 4)'; assert "= false" "$__bs_last" "b:#f"
bs_run '(< 1 2)'; assert "< true" "$__bs_last" "b:#t"
bs_run '(> 5 3)'; assert "> true" "$__bs_last" "b:#t"
bs_run '(<= 3 3)'; assert "<= equal" "$__bs_last" "b:#t"
bs_run '(>= 5 3)'; assert ">= greater" "$__bs_last" "b:#t"
bs_run "(eq? 'a 'a)"; assert "eq? same symbol" "$__bs_last" "b:#t"
bs_run "(equal? '(1 2 3) '(1 2 3))"; assert "equal? lists" "$__bs_last" "b:#t"
bs_run "(equal? '(1 2) '(1 3))"; assert "equal? lists false" "$__bs_last" "b:#f"

# ── 4. Boolean operations ────────────────────────────────────────────────────
bs-reset
bs_run '(not #f)'; assert "not false -> true" "$__bs_last" "b:#t"
bs_run '(not #t)'; assert "not true -> false" "$__bs_last" "b:#f"
bs_run '(not 42)'; assert "not non-false -> false" "$__bs_last" "b:#f"
bs_run '(and 1 2 3)'; assert "and all true" "$result" "3"
bs_run '(and 1 #f 3)'; assert "and short-circuits on false" "$__bs_last" "b:#f"
bs_run '(and)'; assert "and empty" "$__bs_last" "b:#t"
bs_run '(or #f #f 5)'; assert "or first true" "$result" "5"
bs_run '(or #f #f)'; assert "or all false" "$__bs_last" "b:#f"
bs_run '(or)'; assert "or empty" "$__bs_last" "b:#f"

# ── 5. define / set! / variable lookup ────────────────────────────────────────
bs-reset
eval "$(bs '(define x 99)')"; assert "define and read variable" "$x" "i:99"
eval "$(bs '(define (square n) (* n n))')"; bs_run '(square 7)'; assert "define function shorthand" "$result" "49"
bs-reset
eval "$(bs '(define counter 0)')"; eval "$(bs '(set! counter (+ counter 1))')"; eval "$(bs '(set! counter (+ counter 1))')"; assert "set! updates variable" "$counter" "i:2"
bs-reset
eval "$(bs '(define v 1)')"; eval "$(bs '(define v 2)')"; assert "define overwrites" "$v" "i:2"

# ── 6. if expression ─────────────────────────────────────────────────────────
bs-reset
bs_run '(if #t 10 20)'; assert "if true branch" "$result" "10"
bs_run '(if #f 10 20)'; assert "if false branch" "$result" "20"
bs_run '(if #f 42)'; assert "if no else, condition false" "$__bs_last" "n:()"
bs_run '(if (zero? 0) "yes" "no")'; assert "if with zero? predicate" "$result" "yes"

# ── 7. begin ──────────────────────────────────────────────────────────────────
bs-reset
bs_run '(begin 1 2 3)'; assert "begin returns last" "$result" "3"
bs_run '(begin (define a 5) (define b 6) (+ a b))'; assert "begin with side effects" "$result" "11"

# ── 8. lambda / closures ─────────────────────────────────────────────────────
bs-reset
bs_run '((lambda (x) (* x x)) 5)'; assert "simple lambda" "$result" "25"
eval "$(bs '(define make-adder (lambda (n) (lambda (x) (+ x n))))')"; eval "$(bs '(define add5 (make-adder 5))')"; bs_run '(add5 37)'; assert "closure captures environment" "$result" "42"
bs_run '((lambda (a b c) (+ a b c)) 1 2 3)'; assert "multi-arg lambda" "$result" "6"
bs_run '((lambda args (length args)) 1 2 3 4)'; assert "variadic lambda" "$result" "4"
bs_run '((lambda (x . rest) (cons x rest)) 1 2 3)'; assert "dotted rest args" "$__bs_last_display" "(1 2 3)"

# ── 9. let / let* / letrec ───────────────────────────────────────────────────
bs-reset
bs_run '(let ((a 3) (b 4)) (+ a b))'; assert "let basic" "$result" "7"
eval "$(bs '(define z 100)')"; bs_run '(let ((a 1) (b (+ z 1))) (+ a b))'; assert "let does not see siblings" "$result" "102"
bs_run '(let* ((a 2) (b (* a 3))) b)'; assert "let* sequential" "$result" "6"
bs_run '(letrec
    ((even? (lambda (n) (if (= n 0) #t (odd?  (- n 1)))))
     (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
  (even? 10))'; assert "letrec mutual recursion" "$__bs_last" "b:#t"
bs_run '(let loop ((i 1) (acc 0))
           (if (> i 100) acc (loop (+ i 1) (+ acc i))))'; assert "named let loop" "$result" "5050"

# ── 10. cond / case / when / unless ──────────────────────────────────────────
bs-reset
bs_run '(cond ((= 1 2) "no") ((= 2 2) "yes") (else "other"))'; assert "cond first match" "$result" "yes"
bs_run '(cond (#f 1) (#f 2) (else 99))'; assert "cond else" "$result" "99"
bs_run '(cond (#f 1))'; assert "cond no else no match" "$__bs_last" "n:()"
bs_run '(case (* 2 3) ((2 3 5 7) "prime") ((1 4 6 8 9) "composite") (else "other"))'; assert "case match" "$result" "composite"
bs_run '(case 99 ((1 2) "low") (else "high"))'; assert "case else" "$result" "high"
bs_run '(when (= 1 1) 42)'; assert "when condition true" "$result" "42"
bs_run '(when (= 1 2) 42)'; assert "when condition false" "$__bs_last" "n:()"
bs_run '(unless #f 77)'; assert "unless condition false" "$result" "77"
bs_run '(unless #t 77)'; assert "unless condition true" "$__bs_last" "n:()"

# ── 11. Type predicates ──────────────────────────────────────────────────────
bs-reset
bs_run '(number? 42)'; assert "number? true" "$__bs_last" "b:#t"
bs_run '(number? "x")'; assert "number? false" "$__bs_last" "b:#f"
bs_run '(string? "hi")'; assert "string?" "$__bs_last" "b:#t"
bs_run "(symbol? 'foo)"; assert "symbol?" "$__bs_last" "b:#t"
bs_run '(boolean? #t)'; assert "boolean? true" "$__bs_last" "b:#t"
bs_run '(boolean? 1)'; assert "boolean? false" "$__bs_last" "b:#f"
bs_run '(procedure? car)'; assert "procedure? true" "$__bs_last" "b:#t"
bs_run '(procedure? 42)'; assert "procedure? false" "$__bs_last" "b:#f"
bs_run '(zero? 0)'; assert "zero?" "$__bs_last" "b:#t"
bs_run '(positive? 5)'; assert "positive?" "$__bs_last" "b:#t"
bs_run '(negative? -3)'; assert "negative?" "$__bs_last" "b:#t"
bs_run '(even? 4)'; assert "even?" "$__bs_last" "b:#t"
bs_run '(odd? 7)'; assert "odd?" "$__bs_last" "b:#t"

# ── 12. List operations ──────────────────────────────────────────────────────
bs-reset
bs_run '(car (cons 1 2))'; assert "cons car" "$result" "1"
bs_run '(cdr (cons 1 2))'; assert "cons cdr" "$result" "2"
bs_run "(null? '())"; assert "null? true" "$__bs_last" "b:#t"
bs_run "(null? '(1))"; assert "null? false" "$__bs_last" "b:#f"
bs_run "(pair? '(1 2))"; assert "pair? true" "$__bs_last" "b:#t"
bs_run "(pair? '())"; assert "pair? false" "$__bs_last" "b:#f"
bs_run '(list 1 2 3)'; assert "list" "$__bs_last_display" "(1 2 3)"
bs_run "(length '(a b c d))"; assert "length" "$result" "4"
bs_run "(append '(1 2) '(3 4))"; assert "append two lists" "$__bs_last_display" "(1 2 3 4)"
bs_run "(append '(1) '(2) '(3))"; assert "append three lists" "$__bs_last_display" "(1 2 3)"
bs_run "(reverse '(1 2 3))"; assert "reverse" "$__bs_last_display" "(3 2 1)"
bs_run "(list-ref '(a b c d) 2)"; assert "list-ref" "$result" "c"
bs_run "(list-tail '(a b c d) 2)"; assert "list-tail" "$__bs_last_display" "(c d)"
bs_run '(map (lambda (x) (* x x)) (list 1 2 3 4 5))'; assert "map squares" "$__bs_last_display" "(1 4 9 16 25)"
bs_run '(for-each (lambda (x) x) (list 1 2 3))'; assert "for-each" "$__bs_last" "n:()"
bs_run '(filter odd? (list 1 2 3 4 5))'; assert "filter odd" "$__bs_last_display" "(1 3 5)"
bs_run "(assoc 'b '((a 1) (b 2) (c 3)))"; assert "assoc" "$__bs_last_display" "(b 2)"
bs_run "(member 3 '(1 2 3 4))"; assert "member" "$__bs_last_display" "(3 4)"

# ── 13. String operations ────────────────────────────────────────────────────
bs-reset
bs_run '(string-length "hello")'; assert "string-length" "$result" "5"
bs_run '(string-append "foo" "bar" "baz")'; assert "string-append" "$__bs_last" "s:foobarbaz"
bs_run '(substring "hello world" 6 11)'; assert "substring" "$__bs_last" "s:world"
bs_run '(string->number "123")'; assert "string->number integer" "$result" "123"
bs_run '(string->number "abc")'; assert "string->number not a number" "$__bs_last" "b:#f"
bs_run '(number->string 42)'; assert "number->string" "$__bs_last" "s:42"
bs_run '(string->symbol "foo")'; assert "string->symbol" "$__bs_last" "y:foo"
bs_run "(symbol->string 'hello)"; assert "symbol->string" "$__bs_last" "s:hello"
bs_run '(string=? "abc" "abc")'; assert "string=? true" "$__bs_last" "b:#t"
bs_run '(string=? "abc" "ABC")'; assert "string=? false" "$__bs_last" "b:#f"
bs_run '(string<? "abc" "abd")'; assert "string<?" "$__bs_last" "b:#t"
bs_run '(string-upcase "hello")'; assert "string-upcase" "$__bs_last" "s:HELLO"
bs_run '(string-downcase "WORLD")'; assert "string-downcase" "$__bs_last" "s:world"

# ── 14. I/O ──────────────────────────────────────────────────────────────────
bs-reset
output="$(eval "$(bs '(display 42)')" 2>&1)"; assert "display writes to stderr" "$output" "42"
output="$(eval "$(bs '(begin (display 1) (newline) (display 2))')" 2>&1)"; assert "newline writes newline" "$output" $'1\n2'
output="$(eval "$(bs '(write "hello")')" 2>&1)"; assert "write strings with quotes" "$output" '"hello"'

# ── 15. quote ─────────────────────────────────────────────────────────────────
bs-reset
bs_run "'foo"; assert "quote symbol" "$__bs_last" "y:foo"
bs_run "'(1 2 3)"; assert "quote list" "$__bs_last_display" "(1 2 3)"
bs_run "'(a (b c) d)"; assert "quote nested" "$__bs_last_display" "(a (b c) d)"

# ── 16. Recursion ─────────────────────────────────────────────────────────────
bs-reset
eval "$(bs '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))')"; bs_run '(fact 10)'; assert "factorial recursive" "$result" "3628800"
eval "$(bs '(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))')"; bs_run '(fib 15)'; assert "fibonacci recursive" "$result" "610"
bs_run '(let loop ((n 100) (acc 0))
           (if (= n 0) acc (loop (- n 1) (+ acc n))))'; assert "sum via named let" "$result" "5050"
bs-reset
eval "$(bs '(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))')"; eval "$(bs '(define (my-odd?  n) (if (= n 0) #f (my-even? (- n 1))))')"; bs_run '(my-even? 20)'; assert "mutual recursion even" "$__bs_last" "b:#t"
bs_run '(my-odd? 21)'; assert "mutual recursion odd" "$__bs_last" "b:#t"
bs-reset
eval "$(bs '(define make-counter
               (lambda ()
                 (let ((n 0))
                   (lambda () (set! n (+ n 1)) n))))')"; eval "$(bs '(define c (make-counter))')"; bs_run '(c)'; assert "accumulator closure 1" "$result" "1"
bs_run '(c)'; assert "accumulator closure 2" "$result" "2"
bs_run '(c)'; assert "accumulator closure 3" "$result" "3"

# ── 17. apply ─────────────────────────────────────────────────────────────────
bs-reset
bs_run "(apply + '(1 2 3 4 5))"; assert "apply with list" "$result" "15"
bs_run "(apply list 1 2 '(3 4))"; assert "apply with leading args" "$__bs_last_display" "(1 2 3 4)"

# ── 18. do loop ───────────────────────────────────────────────────────────────
bs-reset
bs_run '(do ((i 1 (+ i 1))
              (s 0 (+ s i)))
             ((> i 10) s))'; assert "do loop sum" "$result" "55"

# ── 19. Persistence across calls ─────────────────────────────────────────────
bs-reset
eval "$(bs '(define x 1)')"; eval "$(bs '(set! x (+ x 41))')"; assert "variable persists" "$x" "i:42"
bs-reset
eval "$(bs '(define adder (lambda (n) (lambda (x) (+ x n))))')"; eval "$(bs '(define plus7 (adder 7))')"; bs_run '(plus7 35)'; assert "closure persists" "$result" "42"
bs-reset
eval "$(bs '(define (double x) (* 2 x))')"; bs_run '(double 21)'; assert "define then use in next call" "$result" "42"

# ── 20. Multi-expression source ──────────────────────────────────────────────
bs-reset
eval "$(bs '(define a 10) (define b 32) (+ a b)')"; assert "multiple top-level a" "$a" "i:10"
assert "multiple top-level b" "$b" "i:32"
assert "multiple top-level last" "$__bs_last" "i:42"

# ── 21. Higher-order functions ────────────────────────────────────────────────
bs-reset
eval "$(bs '(define (compose f g) (lambda (x) (f (g x))))')"; eval "$(bs '(define inc (lambda (x) (+ x 1)))')"; eval "$(bs '(define double (lambda (x) (* 2 x)))')"; bs_run '((compose inc double) 20)'; assert "compose" "$result" "41"
bs_run "(foldl (lambda (x acc) (+ x acc)) 0 '(1 2 3 4 5))"; assert "fold-left sum" "$result" "15"

# ── 22. Vector operations ────────────────────────────────────────────────────
bs-reset
bs_run '(let ((v (make-vector 3 0))) (vector-ref v 1))'; assert "make-vector and vector-ref" "$result" "0"
bs_run '(let ((v (make-vector 3 42))) (vector-ref v 2))'; assert "make-vector with fill" "$result" "42"
bs_run '(let ((v (vector 10 20 30))) (vector-ref v 1))'; assert "vector constructor" "$result" "20"
bs_run '(let ((v (make-vector 3 0)))
           (vector-set! v 1 99)
           (vector-ref v 1))'; assert "vector-set! and read back" "$result" "99"
bs_run '(vector-length (vector 1 2 3 4 5))'; assert "vector-length" "$result" "5"
bs_run '(vector->list (vector 1 2 3))'; assert "vector->list" "$__bs_last_display" "(1 2 3)"
bs_run "(let ((v (list->vector '(10 20 30)))) (vector-ref v 2))"; assert "list->vector round-trip" "$result" "30"
bs_run '(vector? (vector 1 2))'; assert "vector? true" "$__bs_last" "b:#t"
bs_run '(vector? 42)'; assert "vector? false" "$__bs_last" "b:#f"

# ── 23. Character operations ─────────────────────────────────────────────────
bs-reset
bs_run '#\a'; assert "char literal" "$__bs_last" "c:a"
bs_run '#\space'; assert "char space literal" "$__bs_last" "c: "
bs_run '(char->integer #\A)'; assert "char->integer" "$result" "65"
bs_run '(integer->char 65)'; assert "integer->char" "$__bs_last" "c:A"
bs_run '(char=? #\a #\a)'; assert "char=? true" "$__bs_last" "b:#t"
bs_run '(char=? #\a #\b)'; assert "char=? false" "$__bs_last" "b:#f"
bs_run '(char<? #\a #\b)'; assert "char<? true" "$__bs_last" "b:#t"
bs_run '(char<? #\b #\a)'; assert "char<? false" "$__bs_last" "b:#f"
bs_run '(char-alphabetic? #\a)'; assert "char-alphabetic? true" "$__bs_last" "b:#t"
bs_run '(char-alphabetic? #\1)'; assert "char-alphabetic? false" "$__bs_last" "b:#f"
bs_run '(char-numeric? #\5)'; assert "char-numeric? true" "$__bs_last" "b:#t"
bs_run '(char-numeric? #\x)'; assert "char-numeric? false" "$__bs_last" "b:#f"

# ── 24. Quasiquote ───────────────────────────────────────────────────────────
bs-reset
bs_run '`(1 2 3)'; assert "quasiquote without unquote" "$__bs_last_display" "(1 2 3)"
eval "$(bs '(define x 42)')"; bs_run '`(a ,x b)'; assert "quasiquote with unquote" "$__bs_last_display" "(a 42 b)"
eval "$(bs '(define y 10)')"; bs_run '`(1 ,(+ y 5) 3)'; assert "quasiquote nested" "$__bs_last_display" "(1 15 3)"

# ── 25. Additional list operations ───────────────────────────────────────────
bs-reset
bs_run '(let ((p (cons 1 2))) (set-car! p 99) (car p))'; assert "set-car!" "$result" "99"
bs_run '(let ((p (cons 1 2))) (set-cdr! p 99) (cdr p))'; assert "set-cdr!" "$result" "99"
bs_run "(list? '(1 2 3))"; assert "list? proper list" "$__bs_last" "b:#t"
bs_run '(list? (cons 1 2))'; assert "list? dotted pair" "$__bs_last" "b:#f"
bs_run "(list? '())"; assert "list? empty list" "$__bs_last" "b:#t"
bs_run "(foldr cons '() '(1 2 3))"; assert "fold-right" "$__bs_last_display" "(1 2 3)"

# ── 26. Additional string operations ─────────────────────────────────────────
bs-reset
bs_run '(string-ref "hello" 1)'; assert "string-ref" "$__bs_last" "c:e"
bs_run '(string>? "b" "a")'; assert "string>? true" "$__bs_last" "b:#t"
bs_run '(string>? "a" "b")'; assert "string>? false" "$__bs_last" "b:#f"
bs_run '(string<=? "a" "b")'; assert "string<=? less" "$__bs_last" "b:#t"
bs_run '(string<=? "a" "a")'; assert "string<=? equal" "$__bs_last" "b:#t"
bs_run '(string>=? "b" "a")'; assert "string>=? greater" "$__bs_last" "b:#t"
bs_run '(string>=? "b" "b")'; assert "string>=? equal" "$__bs_last" "b:#t"
bs_run '(make-string 5 #\x)'; assert "make-string" "$__bs_last" "s:xxxxx"
bs_run '(string-copy "hello")'; assert "string-copy" "$__bs_last" "s:hello"
bs_run '(string #\h #\i)'; assert "string constructor from chars" "$__bs_last" "s:hi"
bs_run '(string->list "abc")'; assert "string->list" "$result" "(a b c)"
bs_run '(string->list "")'; assert "string->list empty" "$result" "()"
bs_run '(list->string (list #\h #\i))'; assert "list->string" "$__bs_last" "s:hi"
bs_run '(list->string (list))'; assert "list->string empty" "$__bs_last" "s:"
bs_run '(list->string (string->list "scheme"))'; assert "string->list->string roundtrip" "$__bs_last" "s:scheme"

# ── 27. Additional arithmetic ────────────────────────────────────────────────
bs-reset
bs_run '(lcm 4 6)'; assert "lcm" "$result" "12"
bs_run '(exact->inexact 42)'; assert "exact->inexact identity" "$result" "42"
bs_run '(floor 7)'; assert "floor identity" "$result" "7"
bs_run '(ceiling 7)'; assert "ceiling identity" "$result" "7"
bs_run '(round 7)'; assert "round identity" "$result" "7"
bs_run '(truncate 7)'; assert "truncate identity" "$result" "7"

# ── 28. letrec* ──────────────────────────────────────────────────────────────
bs-reset
bs_run '(letrec* ((a 1) (b (+ a 1))) (+ a b))'; assert "letrec* basic" "$result" "3"

# ── 29. error primitive ──────────────────────────────────────────────────────
bs-reset
output="$(eval "$(bs '(error "oops" 42)')" 2>&1)"
[[ "$output" == *"oops"* ]]
(( _total++ ))
if [[ $? -eq 0 ]]; then
    (( _pass++ )); printf 'ok %d error outputs message\n' "$_total"
else
    (( _fail++ )); printf 'not ok %d error outputs message\n' "$_total"
fi

# ── 30. do loop (additional) ─────────────────────────────────────────────────
bs-reset
bs_run '(let ((v (make-vector 5 0)))
           (do ((i 0 (+ i 1)))
               ((= i 5) v)
             (vector-set! v i (* i i)))
           (vector->list v))'; assert "do loop vector fill" "$__bs_last_display" "(0 1 4 9 16)"

# ── 31. Edge cases ───────────────────────────────────────────────────────────
bs-reset
bs_run '(+ (+ (+ 1 2) (+ 3 4)) (+ (+ 5 6) (+ 7 8)))'; assert "deeply nested arithmetic" "$result" "36"
bs_run '(let ((f (lambda (x) (* x 2)))) (f 21))'; assert "lambda in let binding" "$result" "42"
bs_run '(begin)'; assert "empty begin" "$__bs_last" "n:()"
bs_run '(if 0 "yes" "no")'; assert "boolean as condition (non-false is truthy)" "$result" "yes"
bs_run '(< 1 2 3 4 5)'; assert "chained comparisons true" "$__bs_last" "b:#t"
bs_run '(< 1 2 2 4 5)'; assert "chained comparisons false" "$__bs_last" "b:#f"
bs_run '(map (lambda (x) (+ x 10)) (list 1 2 3))'; assert "map with lambda" "$__bs_last_display" "(11 12 13)"
bs_run '(filter (lambda (x) (> x 3)) (list 1 2 3 4 5))'; assert "filter with lambda" "$__bs_last_display" "(4 5)"
bs-reset
eval "$(bs '(define (make-pair a b) (lambda (sel) (if sel a b)))')"; eval "$(bs '(define p (make-pair 10 20))')"; bs_run '(p #t)'; assert "nested define and closure true" "$result" "10"
bs_run '(p #f)'; assert "nested define and closure false" "$result" "20"
bs_run "(append '() '() '())"; assert "append empty lists" "$__bs_last" "n:()"
bs_run "(reverse '())"; assert "reverse empty list" "$__bs_last" "n:()"
bs_run "(length '())"; assert "length empty list" "$result" "0"
bs_run "(cond ((assoc 'b '((a 1) (b 2) (c 3))) => cdr))"; assert "cond => syntax" "$__bs_last_display" "(2)"

# ── 32. I/O Builtins ─────────────────────────────────────────────────────────

# Helper: extract the direct-stdout portion from $(bs ...) output.
# zsh's bs() emits typeset assignments to stdout after any write-stdout content;
# this strips them so we can compare just the user-visible output.
bs_stdout() {
    local _raw
    _raw=$(bs "$1")
    printf '%s' "${_raw%%typeset*}"
}

# -- write-stdout --
bs-reset
_wout=$(bs_stdout '(write-stdout "hello zsh")');  assert "write-stdout string"      "$_wout"     "hello zsh"
_wout=$(bs_stdout '(write-stdout "")');            assert "write-stdout empty"       "$_wout"     ""
# write-stdout returns nil: can't use bs_run (raw stdout corrupts eval);
# match the typeset line in raw bs output instead
(( _total++ ))
_raw=$(bs '(write-stdout "x")')
if [[ "$_raw" == *'__bs_last=n:\(\)'* ]]; then
    (( _pass++ )); printf 'ok %d write-stdout returns nil\n' "$_total"
else
    (( _fail++ )); printf 'not ok %d write-stdout returns nil\n' "$_total"
    printf '  output: %q\n' "$_raw"
fi

# -- file-read / file-write / file-write-atomic / file-directory? / file-glob --
_IO_TMP=$(mktemp -d)
printf 'hello world'           > "$_IO_TMP/simple.txt"
printf 'line 1\nline 2\nline 3' > "$_IO_TMP/multi.txt"

bs-reset
bs_run "(file-read \"$_IO_TMP/simple.txt\")";
    assert "file-read simple"       "$result"    "hello world"
bs_run "(file-read \"$_IO_TMP/multi.txt\")";
    assert "file-read multiline"    "$result"    "line 1
line 2
line 3"
bs_run "(file-read \"$_IO_TMP/no-such-file\")";
    assert "file-read nonexistent"  "$__bs_last" "b:#f"
bs_run "(file-read \"$_IO_TMP\")";
    assert "file-read directory"    "$__bs_last" "b:#f"

bs_run "(file-write \"$_IO_TMP/out.txt\" \"written\")";
    assert "file-write #t"          "$__bs_last" "b:#t"
bs_run "(file-write \"/no/such/dir/x\" \"data\")";
    assert "file-write bad path #f" "$__bs_last" "b:#f"
bs_run "(file-write \"$_IO_TMP/out.txt\" \"hello\")";
    bs_run "(file-read \"$_IO_TMP/out.txt\")";
    assert "file-write roundtrip"   "$result"    "hello"

bs_run "(file-write-atomic \"$_IO_TMP/a.txt\" \"atomic\")";
    assert "file-write-atomic #t"        "$__bs_last" "b:#t"
bs_run "(file-read \"$_IO_TMP/a.txt\")";
    assert "file-write-atomic roundtrip" "$result"    "atomic"

bs_run "(file-directory? \"$_IO_TMP\")";
    assert "file-directory? dir"         "$__bs_last" "b:#t"
bs_run "(file-directory? \"$_IO_TMP/simple.txt\")";
    assert "file-directory? file"        "$__bs_last" "b:#f"
bs_run "(file-directory? \"$_IO_TMP/nonexistent\")";
    assert "file-directory? nonexistent" "$__bs_last" "b:#f"

bs_run "(list? (file-glob \"$_IO_TMP/\"))";
    assert "file-glob returns list" "$__bs_last" "b:#t"
_IO_EMPTY=$(mktemp -d)
bs_run "(null? (file-glob \"$_IO_EMPTY/\"))";
    assert "file-glob empty dir"    "$__bs_last" "b:#t"
rmdir "$_IO_EMPTY"

# -- terminal-size --
bs-reset
bs_run '(pair? (terminal-size))';     assert "terminal-size pair"         "$__bs_last" "b:#t"
bs_run '(> (car (terminal-size)) 0)'; assert "terminal-size rows > 0"     "$__bs_last" "b:#t"
bs_run '(> (cdr (terminal-size)) 0)'; assert "terminal-size cols > 0"     "$__bs_last" "b:#t"

# -- terminal-raw! / terminal-restore! / terminal-suspend! --
bs-reset
bs_run '(procedure? terminal-raw!)';     assert "terminal-raw! procedure"     "$__bs_last" "b:#t"
bs_run '(procedure? terminal-restore!)'; assert "terminal-restore! procedure"  "$__bs_last" "b:#t"
bs_run '(procedure? terminal-suspend!)'; assert "terminal-suspend! procedure"  "$__bs_last" "b:#t"
bs_run '(terminal-restore!)';            assert "terminal-restore! no-op nil"  "$__bs_last" "n:()"

# -- read-byte --
bs-reset
result=$(echo -n "A"  | bs-eval '(read-byte)'); assert "read-byte A=65"       "$result" "65"
result=$(printf '\n'  | bs-eval '(read-byte)'); assert "read-byte newline=10"  "$result" "10"
result=$(echo -n ""   | bs-eval '(read-byte)'); assert "read-byte EOF=#f"      "$result" "#f"
result=$(printf '\0'  | bs-eval '(read-byte)'); assert "read-byte NUL=0"       "$result" "0"
result=$(printf ' '   | bs-eval '(read-byte)'); assert "read-byte space=32"    "$result" "32"

# -- read-byte-timeout --
result=$(echo -n "Z"  | bs-eval '(read-byte-timeout "1")')   ; assert "read-byte-timeout Z=90"     "$result" "90"
result=$(echo -n ""   | bs-eval '(read-byte-timeout "0.01")'); assert "read-byte-timeout empty=#f"  "$result" "#f"

# -- shell-capture / shell-exec --
bs-reset
bs_run "(shell-capture \"printf '%s' hello\")"; assert "shell-capture output"  "$result"    "hello"
bs_run "(shell-capture \"exit 1\")";            assert "shell-capture fail #f" "$__bs_last" "b:#f"

# -- eval-string --
bs-reset
eval "$(bs '(eval-string "(+ 1 2 3)")')";
    assert "eval-string arithmetic"     "$__bs_last_display" "(#t . 6)"
eval "$(bs '(car (eval-string "(+ 1 2)"))')";
    assert "eval-string car #t"         "$__bs_last"         "b:#t"
eval "$(bs '(cdr (eval-string "(+ 1 2 3)"))')";
    assert "eval-string result in cdr"  "$__bs_last_display" "6"
eval "$(bs '(cdr (eval-string "\"hello\""))')";
    assert "eval-string string result"  "$__bs_last_display" "hello"
eval "$(bs '(cdr (eval-string "(define (sq x) (* x x)) (sq 5)"))')";
    assert "eval-string with define"    "$__bs_last_display" "25"
eval "$(bs '(car (eval-string "(+ 1 undefined-var)"))' 2>/dev/null)";
    assert "eval-string error car #f"   "$__bs_last"         "b:#f"
(( _total++ ))
eval "$(bs '(cdr (eval-string "(+ 1 undefined-var)"))' 2>/dev/null)"
if [[ "$__bs_last" == s:* && -n "${__bs_last:2}" ]]; then
    (( _pass++ )); printf 'ok %d eval-string error message non-empty\n' "$_total"
else
    (( _fail++ )); printf 'not ok %d eval-string error message non-empty\n' "$_total"
    printf '  expected: s:<non-empty>  got: [%s]\n' "$__bs_last"
fi
bs-reset
eval "$(bs '(define outer-val 42)')"; eval "$(bs '(eval-string "(+ 1 1)")')"; eval "$(bs 'outer-val')"
    assert "eval-string preserves outer state" "$__bs_last_display" "42"
eval "$(bs '(eval-string "")')";
    assert "eval-string empty string"   "$__bs_last_display" "(#t . ())"
eval "$(bs '(cdr (eval-string "(+ 1 1) (+ 1 2)"))')";
    assert "eval-string multiple exprs" "$__bs_last_display" "3"

# -- Integration: file + eval-string --
bs-reset
eval "$(bs "(file-write \"$_IO_TMP/fact.scm\" \"(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)\")")"
eval "$(bs "(cdr (eval-string (file-read \"$_IO_TMP/fact.scm\")))")"
    assert "file + eval-string roundtrip"       "$__bs_last_display" "120"
bs-reset
eval "$(bs '(define a 10)')"; eval "$(bs '(eval-string "(define b 20)")')"; eval "$(bs 'a')"
    assert "eval-string no tokenizer corruption" "$__bs_last_display" "10"

rm -rf "$_IO_TMP"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────"
printf '%d tests: %d passed, %d failed\n' "$_total" "$_pass" "$_fail"
echo "──────────────────────────────────────"
(( _fail == 0 )) && exit 0 || exit 1
