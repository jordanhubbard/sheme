# sheme examples

Each example is a self-contained bash script that sources `bs.sh` from the
repo root and exercises a different facet of the interpreter.  Run any of them
from the **repo root**:

```bash
bash examples/<name>.sh
```

or via the `make` shortcuts listed below.

---

## demo.sh — Feature showcase

```bash
bash examples/demo.sh
# or: make example
```

A guided tour of sheme's core capabilities: arithmetic, list processing,
higher-order functions, closures, string operations, and vector manipulation.
Good starting point if you've never used sheme before.

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
scm> (fib 20)
6765
scm> (quit)
```

---

## algorithms.sh — Classic algorithms in Scheme

```bash
bash examples/algorithms.sh
# or: make algorithms
```

Demonstrates that sheme is expressive enough for non-trivial programs.
Implements and runs:

- **Merge sort** — recursive sort over lists
- **Binary search** — over a sorted vector
- **Sieve of Eratosthenes** — prime numbers as a list filter
- **Tree operations** — binary search tree insert/search using cons cells
- **Ackermann function** — stress test for deep recursion

---

## channels.sh — CSP-style producer/consumer via shell pipes

```bash
bash examples/channels.sh
```

Shows the Scheme-and-shell cooperation model: Scheme handles computation
(generating work queues, transforming data, accumulating results) while bash
orchestrates processes and I/O.  Uses temp files as message channels between
a Scheme producer and shell consumer stages — a minimal communicating
sequential processes pattern without any C or external tools.

---

## todo.sh — Task manager with cron arms and shell automation

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

**sheme features demonstrated:** `file-read`, `file-write-atomic`,
`eval-string`, `shell-capture`, `shell-exec`, closures as struct accessors,
`filter`/`map`/`for-each`/`foldl`.

**Dependencies:** bash 4+, and optionally `inotifywait` (Linux) or
`fswatch` (macOS) for instant daemon wakeup on file change; falls back to
a 300-second poll if neither is installed.
