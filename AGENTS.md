# AGENTS.md — sheme

## Project Summary

sheme is a Scheme interpreter implemented entirely in bash and zsh. It
evaluates Scheme source code and exposes top-level bindings as shell
variables. Its purpose is to be an intermediate language for shell
scripts — a way to write complex logic in a real programming language
without installing an external runtime.

The editor that was once part of this repo (`em.scm`) has been spun out
to [shemacs](https://github.com/jordanhubbard/shemacs). sheme is now a
pure interpreter project.

License: BSD 2-Clause. Author: Jordan Hubbard.

## Repository Layout

```
bs.sh           — The interpreter, bash implementation
bs.zsh          — The interpreter, zsh implementation
examples/       — Scheme programs demonstrating sheme features
  demo.sh       — Feature demonstration
  algorithms.sh — Sorting and algorithmic examples
  channels.sh   — Message-passing / channels example
  repl.sh       — Interactive Scheme REPL
tests/          — Test suites
  bs.bats       — Bash interpreter tests (bats framework)
  bs-zsh.zsh    — Zsh interpreter tests
  io-tests.sh   — Terminal/file I/O builtin tests
  r5rs-tests.sh — R5RS compatibility tests
  benchmark.sh  — Performance benchmarks
scripts/        — Release automation
  release.sh    — Version bump, tag, GitHub release
Makefile        — Build, test, install targets
README.md       — User-facing documentation
CHANGELOG.md    — Version history
AGENTS.md       — This file (LLM-oriented project documentation)
```

## Source Files to Maintain

There are **two source files** that implement the interpreter:

- `bs.sh` — bash implementation
- `bs.zsh` — zsh implementation

Both must implement identical interpreter semantics. Any bug fix or
feature added to one must be propagated to the other.

## Architecture

### Value Representation

All Scheme values are represented as tagged strings:

| Type    | Tag  | Example     |
|---------|------|-------------|
| Integer | `i:` | `i:42`      |
| Boolean | `b:` | `b:#t`      |
| Null    | `n:` | `n:()`      |
| String  | `s:` | `s:hello`   |
| Symbol  | `y:` | `y:foo`     |
| Pair    | `p:` | `p:3`       |
| Closure | `f:` | `f:7`       |
| Char    | `c:` | `c:a`       |
| Vector  | `v:` | `v:2`       |

### Heap

Pairs and closures are stored on a heap: two parallel associative arrays
`__bs_car` and `__bs_cdr` (for pairs) keyed by integer ID. Closures are
stored with keys like `__bs_fn_<id>_params`, `__bs_fn_<id>_body`, etc.

### Environments

Lexical environments are a flat associative array keyed by
`<envid>:<varname>`. Each environment has a parent pointer stored under
`<envid>:__parent__`.

### State Persistence

`bs` and `bs-eval` run in subshells (`$(...)`). To survive subshell
boundaries, heap and environment state is serialized to a temp file
(`/tmp/__bs_state_<PID>`) on every call and reloaded at the start of
each call.

### Top-Level Output

After evaluating an expression, the interpreter emits shell `declare -g`
statements for any `define`/`set!` bindings, plus `declare -g __bs_last`
for the result value. These are `eval`'d by the caller to bring bindings
into the parent shell.

### Terminal I/O Builtins

These builtins provide direct terminal and file access from Scheme.
They are implemented in bash only (require direct file descriptor access):

- `(read-byte)` / `(read-byte-timeout secs)`
- `(write-stdout str)`
- `(terminal-size)`, `(terminal-raw!)`, `(terminal-restore!)`
- `(file-read path)`, `(file-write path content)`
- `(eval-string code)`

## Key Invariants

- `bs.sh` and `bs.zsh` must pass identical test suites for all non-I/O tests.
- I/O builtins are bash-only; zsh may stub or skip those tests.
- The interpreter must not fork external processes for arithmetic or
  string operations — all evaluation is pure shell builtins.
- Top-level `define`/`set!` side-effects must be reflected in the
  caller's shell environment via `eval "$(bs ...)"`.

## Testing

```bash
make test          # bash + zsh interpreter tests
make test-io       # I/O builtin tests (bash only)
make test-r5rs     # R5RS compatibility suite
make test-all      # everything above
```

Tests live in `tests/`. The bats framework is required for `bs.bats`.

## Common Modification Patterns

**Adding a new builtin function**: Add a `case` arm to the primitives
dispatch in both `bs.sh` and `bs.zsh`. Add test cases in `tests/bs.bats`
and `tests/bs-zsh.zsh`.

**Adding a new special form**: Add a `case` arm to the evaluator's
special-form dispatch (the large `case "$head"` block in `_bs_eval`).
Propagate to both shell versions.

**Adding a new I/O builtin**: Implement in `bs.sh` only. Document the
bash-only limitation. Add tests in `tests/io-tests.sh`.

**Fixing a parser bug**: The tokenizer is a single-pass loop over the
input string. The parser is recursive descent building heap nodes. Both
live near the top of each source file.

## Gotchas

- Subshell state loss: any change to heap/env inside `$(...)` must be
  written to the state file before the subshell exits, or it is lost.
- Integer arithmetic only: there is no floating-point support. Operations
  that would produce inexact results truncate.
- No tail-call optimization: deep recursion will exhaust bash's call
  stack. Practical limit is a few hundred recursive calls.
- `eval-string` re-enters the interpreter recursively. Avoid deeply nested
  `eval-string` calls.
- The zsh version uses `typeset -A` instead of `declare -A` for associative
  arrays, and `typeset -g` instead of `declare -g` for global declarations.
