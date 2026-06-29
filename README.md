# sheme

sheme is a Scheme interpreter for Bash and zsh, plus an ahead-of-time (AOT)
compiler that emits native shell functions. Its purpose is to be an
intermediate language for shell scripts that look less bad when written in an
HONORABLE language like Scheme.

Both interpreter backends implement the same Scheme subset, including the
terminal, file, shell-command, and runtime-evaluation extensions. The public
calling convention differs slightly because the Bash interpreter keeps state
in the current shell while the zsh interpreter isolates each `bs` call and
serializes its state between calls. The AOT compiler also has maintained Bash
and zsh targets. Both targets are covered by compiler regressions and by the
shemacs editor's interactive integration suite.

## Preface

I write a lot of Bash scripts. Bash is Turing complete (or this interpreter
would not be possible), but its scripts look ugly in my `.bashrc`. Other people
use zsh. These are people who I am sure are perfectly honorable in every way
and whose personal life choices can almost certainly be rationalized, even
when such choices include "using zsh." Both are first-class sheme runtimes;
shell-specific examples below are labeled because their invocation differs.

## Foundational premises

1. Shell functions are ugly.  They work, they work well, but they are not stylish and other programmers make fun of you when you write a lot of shell scripts that also contain complex shell functions, as if you were using a REAL programming language.
2. Scheme is a *REAL* programming language, one worthy of respect and veneration.
3. Therefore, writing shell code in Scheme will make you cool and similarly worthy of respect and veneration.
4. You don't want to have to install a full scheme interpreter though.  That's way too much work, and it involves Life Decisions after reading scheme.org in detail.  Questions like:  "*WHICH* scheme?  How *MUCH* scheme is the _right amount_?  Should I go "classic" with r5rs or should I go for *ALL THE MARBLES* with r7rs?  Wait, isn't R7rs *TOO LARGE* though?  Should I ask this question on Reddit?  Oh god!  I don't want to ask this question on Reddit!"
5. Hey! I know what I'll do! It's time for me to choose sheme! No separate
   Scheme runtime required.

## Requirements

- Bash 4.3+ for `bs.sh` and the AOT compiler
- zsh 5+ for `bs.zsh` and zsh-targeted AOT output
- Standard command-line utilities: `mktemp`, `chmod`, `cat`, and `rm` for zsh
  state transport; `stty`, `tput`, and `mv` for the extension layer; Bash
  raw-terminal mode also uses `dd`

The parser, evaluator, arithmetic, and ordinary string/list/vector operations
use shell facilities. Terminal, file, and shell-command extensions deliberately
cross that boundary and use the utilities listed above.

## Quick Start

Clone the repository first:

```bash
git clone https://github.com/jordanhubbard/sheme.git
cd sheme
```

### Bash

```bash
source ./bs.sh

bs-eval '(+ 1 2 3 4 5)'               # 15
bs-eval '(string-upcase "honorable")'  # HONORABLE

# bs evaluates inline and keeps definitions in this shell.
bs '(define (factorial n) (if (= n 0) 1 (* n (factorial (- n 1)))))'
bs-eval '(factorial 10)'                # 3628800

bs '(define x 42)'
bs 'x'
echo "$x"                  # i:42 (the tagged representation)
echo "$__bs_last_display"  # 42   (the human-readable result)
```

### zsh

```zsh
source ./bs.zsh

bs-eval '(+ 1 2 3 4 5)'               # 15
bs-eval '(string-upcase "honorable")'  # HONORABLE

# Plain bs emits typeset commands. Evaluate them to import top-level bindings
# and the result variables into the calling zsh process.
eval "$(bs '(define (factorial n) (if (= n 0) 1 (* n (factorial (- n 1)))))')"
bs-eval '(factorial 10)'                # 3628800

eval "$(bs '(define x 42)')"
eval "$(bs 'x')"
echo "$x"                  # i:42
echo "$__bs_last_display"  # 42
```

In either shell, `bs-reset` clears interpreter state. `bs-eval` prints the
display form and, under zsh, evaluates the generated parent-shell assignments
for you. Only top-level Scheme names that are valid shell identifiers are also
exported as named shell variables; all bindings remain available inside Scheme.
Tokenizer, parser, and evaluator errors stop at the first failing expression
and return a nonzero status; the message is also available in
`$__bs_last_error`.

### Public API and AOT compiler

| Entry point | Defined by | Behavior |
|---|---|---|
| `bs source` | `bs.sh`, `bs.zsh` | Evaluate source. Bash mutates the current shell; zsh emits commands for `eval`. |
| `bs-eval source` | `bs.sh`, `bs.zsh` | Evaluate and print the display form. |
| `bs-reset` | `bs.sh`, `bs.zsh` | Clear interpreter state. |
| `bs-run source` | `bs.zsh` | Run an interactive direct-I/O expression, routing output to the terminal. |
| `bs-compile [options] source` | `bs.sh` | Emit Bash from Scheme. |
| `bs-compile-zsh [options] source` | `bs.sh` | Emit zsh from Scheme; invoke the compiler under Bash. |

The AOT compiler lives in `bs.sh`; `bs.zsh` is the zsh interpreter, not the
compiler host. The compiler is a pragmatic subset rather than a promise that
every interpreted form can be compiled, but its supported operations have the
same semantics on both output targets. Dynamic string and vector indexing is
emitted portably and is exercised by the compiler suite and shemacs.

Applications can inject a portable shell runtime and replace Scheme functions
that need a specialized representation:

```bash
bs-compile \
  --runtime ./application-runtime.sh \
  --replace-functions "state-save state-restore" \
  "$(< program.scm)" > program.sh

bs-compile-zsh --runtime ./application-runtime.sh \
  "$(< program.scm)" > program.zsh
```

Functions defined by the injected runtime are automatically excluded from the
generated Scheme definitions; `--replace-functions` is available when a
runtime's public function names cannot be discovered automatically. The
runtime must be valid in the selected target shell. Application-specific code,
including shemacs's nested buffer runtime, belongs with the application rather
than in sheme's compiler.

One representation boundary is deliberate: compiled `eval-string` calls the
interpreter, but interpreter heap objects cannot be imported into the AOT
array model. Its success cdr is therefore the displayed result string, whereas
interpreted `eval-string` returns the raw Scheme value documented below. A
compiled program using that primitive must load `bs.sh` or `bs.zsh` in its host
shell, as the shemacs launchers do.

## Make Targets

| Target | Description |
|--------|-------------|
| `make install` | Copy `bs.sh` and `bs.zsh` to `~/` and add `source` lines to `~/.bashrc` and `~/.zshrc` |
| `make uninstall` | Remove the copied files and `source` lines from rc files |
| `make check` | Syntax-check both Bash and zsh versions |
| `make test` | Run the Bash interpreter, zsh interpreter/extension, and two-target compiler suites |
| `make test-compiler` | Run focused Bash/zsh AOT compiler regressions |
| `make test-io` | Run the dedicated 41-case Bash I/O harness (zsh I/O is covered by `make test`) |
| `make test-r5rs` | Run 123 R5RS-subset checks against Bash (117 pass, 6 documented skips) |
| `make test-examples` | Exercise algorithms, channels, todo persistence, and the todo daemon wait loop |
| `make test-all` | Run everything: interpreter + compiler + I/O + R5RS + example regressions |
| `make benchmark` | Run performance benchmarks for all language primitives |
| `make example` | Run maintained Bash- and zsh-hosted feature demos |
| `make release` | Run gates, update CHANGELOG, tag, and create a GitHub release (default: patch bump) |
| `make release BUMP=minor` | Same, but bump minor version |
| `make release BUMP=major` | Same, but bump major version |

## Contributor Pre-Push Checks

The Makefile selects the required shell for each suite, so run these once from
the repository root:

```bash
make test-all
make example
```

The examples include maintained Bash and zsh smoke demos plus larger Bash-hosted
programs. See [examples/README.md](examples/README.md) for the purpose and
invocation of each one.

## Terminal, File, and Shell Extensions

sheme provides the same extension primitives in both interpreters. Bash uses
`read -n` (and a `dd` coprocess in raw mode); zsh uses `read -k`. In zsh,
ordinary stateful calls use `eval "$(bs ...)"`, while interactive expressions
that call `write-stdout` should use `bs-run` so user output is not mixed with
the generated `typeset` commands on stdout.

| Builtin | Description |
|---------|-------------|
| `(read-byte)` | Read one byte from stdin (blocking). Returns integer 0–255, or `#f` on EOF. |
| `(read-byte-timeout secs)` | Read one byte with timeout (e.g. `"0.05"`). Returns integer or `#f`. |
| `(write-stdout str)` | Write a string to stdout. Returns nil. |
| `(terminal-size)` | Returns `(rows . cols)` as a pair. |
| `(terminal-raw!)` | Enter raw mode (saves previous stty state). |
| `(terminal-restore!)` | Restore terminal to saved state. |
| `(terminal-suspend!)` | Suspend the current process with `SIGTSTP`. |
| `(file-read path)` | Read entire file as a string, or `#f` on error. |
| `(file-write path content)` | Write string to file (with trailing newline). Returns `#t`/`#f`. |
| `(file-write-atomic path content)` | Write through a temporary sibling and rename it into place. |
| `(file-glob prefix)` | Return paths beginning with `prefix`. |
| `(file-directory? path)` | Return whether `path` is a directory. |
| `(shell-capture command)` | Evaluate a shell command and return captured stdout, or `#f`. |
| `(shell-exec command input)` | Pipe `input` to a shell command and return success as a boolean. |
| `(eval-string code)` | Evaluate code at runtime. Returns `(#t . value)` on success or `(#f . error-string)` on failure. |

Shell variables cannot represent NUL bytes, and command substitution removes
trailing newlines. Consequently, `file-read` and `shell-capture` are text
interfaces rather than byte-preserving binary interfaces. `shell-capture` and
`shell-exec` intentionally evaluate command strings; never pass untrusted text
to them.

## Language Scope

sheme implements an integer-only, deliberately pragmatic R5RS subset. The
compatibility suite explicitly skips unquote-splicing, `call/cc`,
`dynamic-wind`, `delay`/`force`, hygienic macros, and floating-point
arithmetic. Some names for unsupported features exist as compatibility stubs;
their presence is not an R5RS conformance claim. There is no tail-call
optimization, so deep recursion is limited by the host shell.

## The Totally True and Not At All Embellished History of sheme

### The continuing adventures of Jordan Hubbard and Sir Reginald von Fluffington III

> *Part 2 of an ongoing chronicle.  [← Part 1: shemacs](https://github.com/jordanhubbard/shemacs#the-totally-true-and-not-at-all-embellished-history-of-shemacs) | [Part 3: NanoLang →](https://github.com/jordanhubbard/nanolang#the-totally-true-and-not-at-all-embellished-history-of-nanolang)*
> *Sir Reginald von Fluffington III appears throughout.  He does not endorse any of it.*

It was a dark and stormy night in late 2024.  A lone programmer, hunched over a mass of tangled bash functions that had somehow metastasized into a text editor, stared at his screen and whispered the words that would change history: "What if I wrote a Scheme interpreter... *in bash*?"  (The result would later be renamed from `bad-scheme.sh` to `bs.sh`, because brevity is the soul of wit, and also of `source` commands.)

His cat, Sir Reginald von Fluffington III, looked up from the keyboard he was sleeping on and blinked once, slowly, in the way that cats do when they are judging you but wish to maintain plausible deniability.

"Think about it, Reggie," the programmer continued, gesturing at the 2,451 lines of bash that constituted `shemacs`.  "All these functions.  All these arrays.  All this... *string manipulation*.  What if it were... *elegant*?"

Sir Reginald yawned.  He had seen the programmer's definition of "elegant" before.  It usually involved more parentheses.

What followed was a period that historians would later call "The Great Parenthesizing" — three fevered weeks during which the programmer consumed dangerous quantities of coffee and taught bash to understand S-expressions.  The tokenizer came first, born from the unholy union of `case` statements and string slicing.  Then the parser, a recursive descent into madness that stored cons cells in associative arrays with keys like `p:47`.  Then the evaluator, which contained a `case` statement so long that it briefly achieved sentience and filed a labor complaint.

"It's alive!" the programmer cried, when `(+ 1 2)` finally returned `3`.  Sir Reginald was unimpressed.  He could count to three.  He had three functioning brain cells and each of them was dedicated to the task of procuring second breakfast.

But the programmer was not done.  "Now," he declared, with the wild-eyed certainty of a man who has Just Had An Idea, "I shall rewrite shemacs *in Scheme*.  Running on sheme.  Running on bash.  It will be a text editor, written in a language that runs inside the shell, editing files that contain more shell.  It's turtles all the way down, Reggie!"

Sir Reginald left the room.

The resulting artifact — `em.scm` — was approximately 1,200 lines of Scheme that, when loaded into 1,400 lines of bash pretending to be a Scheme interpreter, produced a functional Emacs clone that could edit files at the blistering speed of 2-3 milliseconds per keystroke.  The programmer was unreasonably proud of this number, having optimized it down from 800 milliseconds by the revolutionary technique of "not forking a subprocess for every single keypress."

When asked why anyone would want a text editor written in Scheme running on a Scheme interpreter written in bash, the programmer would smile serenely and say: "Because it's there.  And because Scheme is an HONORABLE language."

Sir Reginald, reached for comment, declined to participate but was observed shortly thereafter pushing a mass of carefully stacked papers off the desk, one sheet at a time, while maintaining eye contact.

The programmer later added zsh support, because he is, as previously established, nothing if not inclusive.  The zsh version works identically, a fact which surprised absolutely everyone, including the programmer.  "I thought for sure the associative array syntax would be different," he admitted.  "Turns out zsh just... does what bash does?  But with more... *feelings* about it?"

Then came The Great Purification.

"Reggie," the programmer announced one morning, with the serene confidence of a man who has achieved enlightenment, or possibly just hasn't slept enough.  "The editor is in Scheme.  The *logic* is in Scheme.  But the *I/O* — the key reading, the terminal control, the file saving — that's all still in bash.  Two hundred and eighty lines of bash!  Wrapping perfectly HONORABLE Scheme!  It's like putting a hot dog in a tuxedo, Reggie.  It *technically works* but *everyone can tell*."

Sir Reginald, who was at that moment wearing a small tuxedo because it was Tuesday, chose not to engage.

What followed was The Great Extraction — a surgical operation in which nine terminal I/O primitives were implanted directly into the interpreter's spinal column.  `read-byte`.  `write-stdout`.  `terminal-raw!`.  Each one a tiny bridge between the world of cons cells and the world of file descriptors.  The 280-line bash wrapper collapsed like a dying star into a 30-line shim that did nothing but load the Scheme file and whisper `(em-main)`.

The editor was now *pure*.  Shell-neutral.  1,300 lines of Scheme that handled everything — reading keys, drawing screens, saving files, even evaluating itself.  If you squinted at it in just the right light, from just the right angle, it was almost... *beautiful*.

"It's the most elegant thing I've ever written," the programmer said, wiping away what was definitely not a tear.

Sir Reginald knocked the programmer's coffee off the desk.  Not out of malice.  Out of *editorial judgment*.

The editor itself has since moved to its own home at [shemacs](https://github.com/jordanhubbard/shemacs), where the same Scheme source is compiled to Bash and zsh. sheme continues as a Scheme interpreter and AOT compiler for shell programmers, and the terminal I/O builtins remain for anyone who wants to write *real programs* entirely in Scheme.

As of this writing, sheme implements a reasonable subset of R5RS Scheme. The
full test gate covers both interpreters, both AOT output targets, terminal/file
I/O, and the R5RS subset; six unsupported R5RS features are explicitly skipped.
The zsh suite includes its own terminal/file I/O coverage, while the dedicated
I/O and R5RS harnesses currently run against Bash. It has been used in
production by exactly one person, who also wrote it. Sir Reginald continues to
withhold his endorsement, citing "procedural concerns" and "insufficient tuna."

The project motto remains: **"It's not about whether you *should*.  It's about whether you *can*.  And also whether your cat respects you.  (He doesn't.)"**

The programmer did not stop at Scheme.  What he did next — and why he felt the need to design an entirely new programming language from first principles, prove it correct in Coq, and build it a virtual machine with 178 opcodes — is documented in the [NanoLang repository](https://github.com/jordanhubbard/nanolang#the-totally-true-and-not-at-all-embellished-history-of-nanolang).  Sir Reginald continues to withhold comment.

## Suggested Projects

sheme now has terminal I/O, file I/O, and runtime eval.  This means you can write *real programs* — entirely in Scheme, entirely in your shell.  Here are some ideas, ranked roughly from "reasonable weekend project" to "cry for help."

### The Plausible

**A Shell-Native REPL** — Write a Scheme REPL in Scheme.  Use `read-byte` for line editing with history, `eval-string` for evaluation, and `write-stdout` for output.  You'd have a REPL for the language that's running the REPL.  It's turtles, but *tasteful* turtles.

**A TODO App / Personal Wiki** — A terminal UI for managing notes, with files stored as S-expressions.  sheme already has full list and string processing; add `file-read`/`file-write` and you've got persistent storage.  Incremental search comes free from the editor code.

**A Hex Editor** — `read-byte` returns raw integers.  `file-read` gives you file contents.  `write-stdout` can output anything.  Write a hex viewer/editor in Scheme.  If it feels too easy, add undo.

**A Diff Viewer** — Read two files with `file-read`, implement the longest common subsequence algorithm in Scheme, render the diff with ANSI colors via `write-stdout`.  Bonus: make it interactive so you can accept/reject hunks.

### The Ambitious

**A Terminal Multiplexer** — Like tmux, but in Scheme, running in bash.  Use `terminal-raw!` for input, `write-stdout` for split-pane rendering, and implement your own window manager.  When someone asks what terminal multiplexer you use, you can say "I wrote my own.  In Scheme.  In bash."  Then watch their face.

**A Roguelike** — You have everything you need: raw key input, direct terminal output, and a language with proper recursion for procedural generation.  Generate dungeons using BSP trees implemented as cons cells.  Store save games as S-expressions.  Die on level 3 because your @ walked into a D and you forgot to implement combat.

**A Git TUI** — A terminal interface for git.  Shell out to `git` commands, parse the output in Scheme, render status/diff/log views with ANSI.  You're already *in* bash — the git commands are right there.  Add interactive staging and you'll never need `git add -p` again.

**A Markdown Renderer** — Parse Markdown in Scheme, render it to the terminal with ANSI formatting.  Headers in bold, code blocks with background colors, lists with proper indentation.  Pipe it to `write-stdout` and you've got a terminal-native Markdown reader.

### The Unhinged

**A Scheme-Powered Shell** — Replace bash with Scheme.  Read commands with `read-byte`, parse them, fork processes.  Your prompt is an S-expression.  Your `.bashrc` is a `.schemerc`.  Tab completion is implemented as a higher-order function.  You have become the ouroboros: a shell running an interpreter that is itself a shell.

**A Terminal Web Browser** — Use `curl` (shelling out from Scheme) to fetch pages, write an HTML tokenizer in Scheme, render a simplified DOM to the terminal.  Links are navigable.  Forms... exist, conceptually.  You browse the web inside a Scheme running inside bash.  Tim Berners-Lee weeps, but he can't tell if it's from joy or horror.

**A Self-Hosted Sheme** — Write a Scheme interpreter in Scheme, running on sheme, running on bash.  Use `eval-string` for the bootstrap, but then implement your own tokenizer, parser, and evaluator in the hosted language.  If it can run `em.scm`, you have achieved peak recursion and are legally required to stop.

**A Music Tracker** — Use `write-stdout` to render a tracker-style grid interface.  Compose sequences of shell commands that produce sound (`printf '\a'` for the purists, `afplay` or `aplay` for the pragmatists).  Save compositions as S-expressions.  Perform live by editing patterns in real time.  Your DAW is bash.  Your synthesizer is `/dev/audio`.  Your audience has left.

**A Conference Talk Slide Deck** — Write a presentation tool in Scheme.  Each slide is an S-expression.  Render with ANSI art.  Support transitions (implemented as recursive functions that redraw the screen).  Give your talk about sheme *using* sheme.  If the live demo crashes, it's not a bug, it's *performance art*.

## Addendum: I Got Bored and Built One

> **Current status:** `todo.sh` is a maintained example. Its persisted
> add/list/done/delete paths and daemon wait behavior run under
> `make test-examples`; desktop notifications and user commands remain
> host-dependent. See [the examples status](examples/README.md#current-validation-status).

Look, the list above was meant as inspiration.  Aspirational.  A gentle nudge toward the horizon.

Then I got bored.

The "TODO App / Personal Wiki" entry caught my eye specifically because it seemed like a reasonable thing to actually build — file I/O, list processing, maybe a daemon.  Fine.  Straightforward.  And then one thing led to another, and what started as a weekend sketch turned into something with a full event-driven synchronization model, two-armed tasks (a *human* arm that notifies you and a *shell* arm that runs a command), inotifywait/fswatch integration so the daemon wakes up instantly instead of polling, and a Scheme function that computes the exact number of seconds until the next due task so the sleep is precise.

It is, to be clear, a TODO app implemented as a Scheme interpreter embedded in bash, where the task list is stored as Scheme source that gets eval'd back at startup. The daemon blocks in `wait -n` on a precise timer and an optional filesystem watcher; other todo processes send SIGUSR1 to interrupt that wait immediately after a mutation. This is either an elegant demonstration of sheme's capabilities or a cry for help. Possibly both.

Sir Reginald has reviewed it.  He knocked it off the desk.  I choose to interpret this as approval.

The implementation lives in `examples/todo.sh`.  All the examples — including a REPL, a classic-algorithms showcase, and a CSP-style producer/consumer demo — are documented in [`examples/README.md`](examples/README.md).
