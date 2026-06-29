# sheme examples

Each example is a self-contained host script that sources the corresponding
interpreter from the repo root. Run the Bash examples from the **repo root**:

```bash
bash examples/<name>.sh
```

The maintained zsh showcase is `zsh examples/demo.zsh`. The `make` shortcuts
listed below select the correct shell explicitly.

## Current validation status

- `demo.sh` and `demo.zsh` are the maintained smoke examples run together by
  `make example` (or separately by `make example-bash` / `make example-zsh`).
- `repl.sh` is a small interactive Bash wrapper and is not automated.
- `algorithms.sh` and `channels.sh` are maintained, non-interactive examples;
  their `make algorithms` and `make channels` targets complete successfully.
- `todo.sh` supports persisted add/list/status workflows and is exposed by
  `make todo`. `make test-examples` covers persistence, completion/deletion,
  invalid IDs, and verifies that the long-running daemon blocks between
  checks. Desktop notification and user-supplied command branches remain
  host-dependent and are not fired by the automated gate.

---

## demo.sh — Feature showcase

```bash
bash examples/demo.sh
# or: make example
```

A guided tour of sheme's core capabilities: arithmetic, list processing,
higher-order functions, closures, string operations, and vector manipulation.
Good starting point if you've never used sheme before.

## demo.zsh — zsh feature showcase

```zsh
zsh examples/demo.zsh
# or: make example-zsh
```

Exercises arithmetic, top-level definitions, closures, higher-order
functions, strings, lists, and vectors through the zsh calling convention.

---

## repl.sh — Interactive Scheme REPL

```bash
bash examples/repl.sh
# or: make repl
```

A read-eval-print loop written in ~15 lines of bash.  Type any Scheme
expression and see the result.  State persists across lines so you can
`define` something and use it on the next prompt.  Exit with `Ctrl-D`
or `(quit)`.

```
sheme REPL  (Ctrl-D or (quit) to exit)
scm> (define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
scm> (fib 10)
55
scm> (quit)
```

---

## algorithms.sh — Classic algorithms in Scheme

```bash
bash examples/algorithms.sh
# or: make algorithms
```

Demonstrates that sheme is expressive enough for non-trivial programs:

- **Merge sort** — recursive sort over lists
- **Quicksort** — recursive partitioning with `filter`
- **Binary search** — over a sorted vector
- **Sieve of Eratosthenes** — prime numbers as a list filter
- **Towers of Hanoi** — recursive move generation

---

## channels.sh — Scheme + shell message passing

```bash
bash examples/channels.sh
# or: make channels
```

Shows the Scheme-and-shell cooperation model: Scheme constructs task messages,
dispatches workers, computes results, and formats output while Bash hosts the
interpreter. The example includes worker-style request/response messages and a
Scheme insertion sort; it is illustrative message passing rather than a
persistent concurrent queue.

---

## todo.sh — Task manager with reminders and shell automation

```bash
# Add a task (interactive prompts)
bash examples/todo.sh add

# List all tasks
bash examples/todo.sh list

# Start the background daemon (fires tasks when they come due)
bash examples/todo.sh daemon &

# Mark a task done / remove it / edit it
bash examples/todo.sh done  <id>
bash examples/todo.sh del   <id>
bash examples/todo.sh edit  <id>

# Fire all currently-due tasks right now (skip the timer)
bash examples/todo.sh fire

# Check daemon status
bash examples/todo.sh status

# Gracefully stop the daemon
bash examples/todo.sh stop
```

Each task has **two arms** that fire when it comes due:

- **Human arm** — a plain-language reminder printed to the terminal (and sent
  as a desktop notification via `notify-send` or `osascript` if available)
- **Shell arm** — a shell command run automatically (open a URL, run a
  script, send a curl request, anything)

Tasks are stored as Scheme source in `~/.local/share/sheme/todo.scm` (or
`$SHEME_TODO_FILE`).  The daemon is event-driven — it uses `inotifywait`
(Linux) or `fswatch` (macOS) so it wakes up instantly when the file changes,
and computes the exact sleep duration until the next due task rather than
polling on a fixed interval.

For deliberately simple source serialization and safe notification quoting,
interactive task fields strip double quotes, backslashes, and apostrophes.
Dollar signs and backticks are preserved; the shell-command arm is still
intentional executable input and must be treated accordingly.

**Exercised sheme features:** `file-read`, `file-write-atomic`,
`eval-string`, `shell-capture`, `shell-exec`, closures as struct accessors,
`filter`/`map`/`for-each`/`foldl`.

**Dependencies:** Bash 4.3+, standard date/process/file utilities, and
optionally `inotifywait` (Linux) or `fswatch` (macOS) for instant daemon wakeup
on file change; it falls back to a 300-second poll if neither is installed.
