# bad-scheme: A Scheme Interpreter in Bash

## Overview

`bad-scheme` is a Scheme interpreter implemented entirely in Bash. It evaluates
Scheme source code and exposes top-level bindings as Bash variables.

## Intended Usage

```bash
source bad-scheme.sh
eval "$(bs '(define x 1)')"
eval "$(bs '(set! x (+ x 41))')"
echo "$x"   # => i:42 (tagged integer)
```

## Implementation Phases

### Phase 1 – Core Infrastructure
- Tagged value representation (`i:`, `b:`, `n:`, `s:`, `y:`, `p:`, `f:`, `c:`, `v:`)
- Heap for pairs (`__bs_car`, `__bs_cdr`) and closures
- Lexical environments as an associative array keyed by `envid:varname`
- State persistence via a per-session temp file (`/tmp/__bs_state_<PID>`)
  so that heap objects survive across `$(bs ...)` subshell calls

### Phase 2 – Tokenizer & Parser
- Single-pass tokenizer: whitespace, `;` comments, strings, `#t`/`#f`,
  `#\<char>`, numbers, symbols, `'` (quote abbreviation)
- Recursive-descent parser producing a Scheme list/atom AST stored on the heap

### Phase 3 – Evaluator
Core special forms:
`quote`, `if`, `define`, `set!`, `lambda`, `begin`

Derived forms (desugared in the evaluator):
`let`, `let*`, `letrec`, `letrec*`, `cond`, `and`, `or`,
`when`, `unless`, `case`, `do`, named `let`

### Phase 4 – Primitives
- Arithmetic: `+` `-` `*` `/` `quotient` `remainder` `modulo` `expt` `abs` `max` `min` `gcd`
- Comparison: `=` `<` `>` `<=` `>=` `eq?` `eqv?` `equal?`
- Logic: `not`
- Type predicates: `number?` `string?` `symbol?` `boolean?` `procedure?` `pair?` `null?`
  `zero?` `positive?` `negative?` `even?` `odd?`
- List: `cons` `car` `cdr` `list` `length` `append` `reverse`
  `map` `for-each` `filter` `assoc` `member` `list-ref` `list-tail`
- String: `string-append` `string-length` `substring` `string->number` `number->string`
  `string->symbol` `symbol->string` `string=?` `string<?` `string-upcase` `string-downcase`
- Vector: `vector` `make-vector` `vector-ref` `vector-set!` `vector-length` `vector->list`
- I/O: `display` `write` `newline`
- Misc: `apply` `error` `exact->inexact` `char->integer`

### Phase 5 – Output & Persistence
- `bs` runs inside `$(...)` (a subshell); heap mutations are saved to the state file
- Top-level `define`/`set!` output `declare -g varname=taggedvalue` lines
- `declare -g __bs_last=<value>` always emitted

### Phase 6 – Tests & CI
- `tests/bad-scheme.bats` using the [bats](https://github.com/bats-core/bats-core) framework
- `.github/workflows/ci.yml` GitHub Actions pipeline

## Value Representation

| Type      | Tagged form       | Example        |
|-----------|-------------------|----------------|
| Fixnum    | `i:<n>`           | `i:42`         |
| Boolean   | `b:#t` / `b:#f`   | `b:#t`         |
| Null      | `n:()`            | `n:()`         |
| String    | `s:<str>`         | `s:hello`      |
| Symbol    | `y:<sym>`         | `y:foo`        |
| Pair      | `p:<id>`          | `p:3`          |
| Closure   | `f:<id>`          | `f:7`          |
| Char      | `c:<ch>`          | `c:a`          |
| Vector    | `v:<id>`          | `v:2`          |

## Limitations
- No proper tail-call optimisation (TCO); deep recursion may hit Bash's stack limit
- No continuations (`call/cc` is a no-op stub)
- Arithmetic is integer-only (Bash `(( ))`)
- No macro system beyond the built-in derived forms
