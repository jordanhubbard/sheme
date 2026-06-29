<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the
repo root), reach for it before grep/find or reading files when you need to
understand or locate code:

- MCP tools (when available): `codegraph_explore` answers most code questions
  in one call; `codegraph_node` returns one symbol or a whole file.
- Shell (always works): `codegraph explore "<symbol names or question>"` and
  `codegraph node <symbol-or-file>` provide the same information.

If there is no `.codegraph/` directory, skip CodeGraph entirely; indexing is
the user's decision.
<!-- CODEGRAPH_END -->

# AGENTS.md — sheme

## Project Summary

sheme is a Scheme interpreter implemented entirely in Bash and zsh. It
evaluates Scheme source code and exposes top-level bindings as shell
variables. Its purpose is to be an intermediate language for shell
scripts — a way to write complex logic in a real programming language
without installing an external runtime.

The editor that was once part of this repo (`em.scm`) has been spun out
to [shemacs](https://github.com/jordanhubbard/shemacs). sheme now owns the
interpreters and the AOT compiler consumed by shemacs.

License: BSD 2-Clause. Author: Jordan Hubbard.

## Repository Layout

```
bs.sh           — Bash interpreter plus Bash/zsh AOT compiler
bs.zsh          — zsh interpreter
examples/       — Scheme programs demonstrating sheme features
  demo.sh       — Feature demonstration
  demo.zsh      — zsh feature demonstration
  algorithms.sh — Sorting and algorithmic examples
  channels.sh   — Message-passing/channel example
  repl.sh       — Interactive Scheme REPL
  todo.sh       — Persistent task-manager example
tests/          — Test suites
  bs.bats       — Bash interpreter tests (bats framework)
  bs-zsh.zsh    — Zsh interpreter tests
  compiler-tests.sh — Bash/zsh AOT compiler regressions
  examples-tests.sh — Non-interactive larger-example regressions
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

There are two runtime source files, with intentionally different host-shell
mechanics:

- `bs.sh` — Bash interpreter and the only AOT compiler host. It defines
  `bs-compile` (Scheme to Bash) and `bs-compile-zsh` (Scheme to zsh).
- `bs.zsh` — zsh interpreter. It does not contain the AOT compiler.

Both interpreters are expected to implement the same Scheme semantics and the
same terminal/file/shell extension layer. Their public calling conventions and
state storage differ, so fixes often need shell-specific implementations and
tests rather than a mechanical copy.

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

Pairs use parallel associative arrays `__bs_car` and `__bs_cdr`, keyed by a
tagged ID such as `p:3`. Closures use `__bs_closure_params`,
`__bs_closure_body`, and `__bs_closure_env`, keyed by a tagged ID such as
`f:7`. Vectors store their length and elements in `__bs_env` under a `v:<id>`
prefix.

### Environments

Lexical bindings are stored in `__bs_env` under `<envid>:<varname>`. Parent
pointers live in the separate `__bs_env_parent` associative array.

### Backend State and Public Calls

- Bash evaluates inline. Interpreter arrays and helper functions are global
  `__bs_*` names in the caller, and top-level `define`/`set!` bindings are
  exported directly with `declare -g` when the Scheme name is a valid shell
  identifier.
- zsh expects ordinary `bs` calls to be captured as `eval "$(bs ...)"`.
  Internals are local to `bs`, while heap/environment state is serialized to
  an owner-only random file under `${TMPDIR:-/tmp}` between calls. The file is
  retained for the life of the zsh process and removed by a `zshexit` hook.
  `bs-eval` performs the `eval` internally. `bs-run` is the zsh-only
  direct-terminal entry point.

### Top-Level Output

In Bash, `bs` sets top-level shell variables and `__bs_last` /
`__bs_last_display` directly. In zsh, `bs` emits `typeset -g` commands for
those values; the caller imports them with `eval`. Because zsh uses stdout for
those commands, interactive expressions that also call `write-stdout` should
use `bs-run` rather than `eval "$(bs ...)"`.

### AOT Compiler

The AOT compiler occupies the second half of `bs.sh`. It lowers Scheme values
to unboxed shell values and arrays and can target Bash or zsh. Its public
entry points accept `--runtime FILE` and `--replace-functions "names..."` so
applications can inject portable runtime helpers for data structures that do
not map cleanly to the compiler's flat representation. Runtime-defined
functions are replaced automatically when their names can be discovered.

Keep the compiler application-neutral. shemacs owns its buffer/undo runtime in
`../shemacs/em.aot-runtime.sh` and passes that file at compile time. Changes to
the runtime-injection contract require coordinated tests in both projects, but
editor state fields and implementations do not belong in `bs.sh`.

`tests/compiler-tests.sh` covers syntax, dynamic offsets, whitespace-preserving
output, invalid-source behavior, runtime replacement, and both output targets.
shemacs provides the larger interactive integration test for generated code.
The compiler intentionally supports a pragmatic subset of the interpreter;
do not assume an interpreted form has an AOT lowering without checking it.
Compiled `eval-string` also requires the matching interpreter to be loaded and
returns display text because interpreter heap objects cannot cross into the
AOT array representation.

### Terminal, File, and Shell Extensions

These extensions are implemented in both interpreters:

- `(read-byte)` / `(read-byte-timeout secs)`
- `(write-stdout str)`
- `(terminal-size)`, `(terminal-raw!)`, `(terminal-restore!)`,
  `(terminal-suspend!)`
- `(file-read path)`, `(file-write path content)`,
  `(file-write-atomic path content)`, `(file-glob prefix)`,
  `(file-directory? path)`
- `(shell-capture command)`, `(shell-exec command input)`
- `(eval-string code)`

They rely on standard external utilities. Shell variables and command
substitution also mean file content is text-oriented: NUL bytes cannot be
preserved and trailing newlines are stripped on reads.

## Key Invariants

- `bs.sh` and `bs.zsh` should have semantic parity, including I/O extensions.
- Core arithmetic and collection evaluation should use shell facilities;
  terminal/file/shell extensions may invoke the documented utilities.
- Bash top-level bindings must appear directly in the caller. zsh top-level
  bindings must appear after `eval "$(bs ...)"` or a `bs-eval` call.
- Any AOT change must be checked against both generated Bash and generated zsh.
- Before pushing, run `make test-all` and `make example` once from the
  repository root; the Makefile selects the appropriate host shell.

## Testing

```bash
make test          # Bash + zsh interpreter suites and both AOT targets
make test-compiler # focused Bash/zsh compiler regressions
make test-io       # dedicated 41-case Bash I/O harness
make test-r5rs     # 123 R5RS-subset checks against Bash (6 skips)
make test-examples # algorithms, channels, todo persistence/daemon checks
make test-all      # all suites above
make example       # maintained Bash and zsh demos
```

Tests live in `tests/`. The bats framework is required for `bs.bats`.
The example suite uses isolated todo storage and verifies that its daemon
blocks between checks instead of exercising desktop notifications or commands.

## Common Modification Patterns

**Adding a new builtin function**: Add a `case` arm to the primitives
dispatch in both `bs.sh` and `bs.zsh`. Add test cases in `tests/bs.bats`
and `tests/bs-zsh.zsh`.

**Adding a new special form**: Add a `case` arm to the evaluator's
special-form dispatch (the large `case "$head"` block in `__bs_eval`).
Propagate to both shell versions.

**Adding a new I/O builtin**: Implement interpreter behavior in both `bs.sh`
and `bs.zsh`, add Bash coverage to `tests/io-tests.sh` or `tests/bs.bats`, and
add zsh coverage to `tests/bs-zsh.zsh`. If compiled programs need it, also add
the corresponding AOT emitter in `bs.sh` and test both output targets.

**Changing AOT behavior used by shemacs**: Preserve the generic runtime
injection interface in `bs.sh`. If shemacs's state model changes, edit
`../shemacs/em.aot-runtime.sh`, not the compiler. Regenerate and syntax-check
both cache targets, then run shemacs integration tests under both shells.

**Fixing a parser bug**: The tokenizer is a single-pass loop over the
input string. The parser is recursive descent building heap nodes. Both
live near the top of each source file.

## Gotchas

- zsh state loss: any new persistent interpreter field inside `bs()` must be
  written to and restored from `__BS_STATE_FILE`. Bash does not use that file.
- The zsh state file must remain owner-only, randomly named, and registered for
  exit cleanup. `bs-reset` truncates the reserved file instead of replacing it
  with a predictable pathname.
- Integer arithmetic only: there is no floating-point support. Operations
  that would produce inexact results truncate.
- No tail-call optimization: deep recursion will exhaust the host shell's call
  stack. Practical limits are a few hundred recursive calls.
- `eval-string` re-enters the interpreter recursively. Avoid deeply nested
  `eval-string` calls.
- On success, `eval-string` returns the raw Scheme value in the pair's cdr; on
  failure, it returns an error string. Keep structured values structured.
- `shell-capture` and `shell-exec` intentionally call shell `eval`; never feed
  them untrusted command text.
- Names such as `call/cc`, exception handlers, and macro forms include stubs or
  simplified behavior. Do not infer R5RS conformance from name presence.
