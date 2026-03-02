# sheme
sheme — a Scheme interpreter in bash/zsh.  Its purpose is to be an intermediate language for shell scripts that will look less bad when written in an HONORABLE language like scheme.

## Preface

I write a lot of bash scripts.  Bash is turing complete (or this "transpiler" would not be possible) but its scripts look ugly in my .bashrc.  Other people use zsh.  These are people who I am sure are perfectly honorable in every way and who's personal life choices can almost certainly be rationalized, even when such choices include "using zsh."  In support of these people, and I am fully prepared to defend their status as people, I wish to therefore make it perfectly clear up-front that when I say "bash" in the rest of this README, I mean "bash and zsh" because there is a version of this for *them*, too.  I am nothing if not inclusive!

## Foundational premises

1. Shell functions are ugly.  They work, they work well, but they are not stylish and other programmers make fun of you when you write a lot of shell scripts that also contain complex shell functions, as if you were using a REAL programming language.
2. Scheme is a *REAL* programming language, one worthy of respect and veneration.
3. Therefore, writing shell code in Scheme will make you cool and similarly worthy of respect and veneration.
4. You don't want to have to install a full scheme interpreter though.  That's way too much work, and it involves Life Decisions after reading scheme.org in detail.  Questions like:  "*WHICH* scheme?  How *MUCH* scheme is the _right amount_?  Should I go "classic" with r5rs or should I go for *ALL THE MARBLES* with r7rs?  Wait, isn't R7rs *TOO LARGE* though?  Should I ask this question on Reddit?  Oh god!  I don't want to ask this question on Reddit!"
5. Hey!  I know what I'll do!  It's time for me to choose sheme!  The no-compromise, no executables option!

## Quick Start

```bash
# Clone the repository
git clone https://github.com/jordanhubbard/sheme.git
cd sheme

# Source it in your current shell
source bs.sh    # or bs.zsh for The Other People

# bs-eval evaluates an expression and prints the result to stdout
bs-eval '(+ 1 2 3 4 5)'               # prints: 15
bs-eval '(string-upcase "honorable")'  # prints: HONORABLE

# bs evaluates silently — use it to define things and build up state.
# Top-level define/set! values are exported as bash globals.
bs '(define (factorial n) (if (= n 0) 1 (* n (factorial (- n 1)))))'
bs-eval '(factorial 10)'   # prints: 3628800

# After any bs or bs-eval call, the raw tagged result is in $__bs_last
# and the display form is in $__bs_last_display
bs '(define x 42)'
echo "$x"                  # => i:42  (tagged: "i:" prefix means integer)
echo "$__bs_last_display"  # => 42    (human-readable)

# bs-reset wipes all interpreter state
bs-reset

# Or just run the demo
make example
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make install` | Copy `bs.sh` and `bs.zsh` to `~/` and add `source` lines to `~/.bashrc` and `~/.zshrc` |
| `make uninstall` | Remove the copied files and `source` lines from rc files |
| `make check` | Syntax-check both bash and zsh versions |
| `make test` | Run the interpreter test suite (177 bash + 202 zsh tests) |
| `make test-io` | Run the I/O builtin test suite (41 tests, bash only) |
| `make test-r5rs` | Run the R5RS compatibility test suite (~123 tests) |
| `make test-all` | Run everything: interpreter + I/O + R5RS tests |
| `make benchmark` | Run performance benchmarks for all language primitives |
| `make example` | Run the feature demo script |
| `make release` | Generate CHANGELOG, run tests, tag, and create GitHub release (default: patch bump) |
| `make release BUMP=minor` | Same, but bump minor version |
| `make release BUMP=major` | Same, but bump major version |

## Terminal I/O Builtins

sheme provides terminal I/O primitives as builtins, enabling Scheme
programs to interact directly with the terminal.  **Bash only** (requires
bash 4+) — these builtins need direct file descriptor access.

| Builtin | Description |
|---------|-------------|
| `(read-byte)` | Read one byte from stdin (blocking). Returns integer 0–255, or `#f` on EOF. |
| `(read-byte-timeout secs)` | Read one byte with timeout (e.g. `"0.05"`). Returns integer or `#f`. |
| `(write-stdout str)` | Write a string to stdout. Returns nil. |
| `(terminal-size)` | Returns `(rows . cols)` as a pair. |
| `(terminal-raw!)` | Enter raw mode (saves previous stty state). |
| `(terminal-restore!)` | Restore terminal to saved state. |
| `(file-read path)` | Read entire file as a string, or `#f` on error. |
| `(file-write path content)` | Write string to file (with trailing newline). Returns `#t`/`#f`. |
| `(eval-string code)` | Evaluate Scheme code at runtime. Returns `(#t . result)` or `(#f . error)`. |

## The Totally True and Not At All Embellished History of sheme

> *A note on provenance: This section exists as the author's official memory marker for projects that have been substantially co-developed with an AI assistant.  The author will not remember which projects these are in ten years.  He will also not remember this note.  He will, however, be able to grep for it, and that is the point.  All future AI-assisted projects will include an equally implausible origin story as a breadcrumb.  The convention is simple: if a project has one of these sections, an AI was meaningfully involved.  If it doesn't, the author did it alone, and it will show.*
>
> *This is Part 2 of a two-part chronicle.  The story begins in the [shemacs repository](https://github.com/jordanhubbard/shemacs), where a perfectly reasonable desire for a text editor on an editorless server leads, inevitably, to 2,451 lines of bash.  Both stories can be read in either order.  Sir Reginald von Fluffington III appears in both.  He does not endorse either.*

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

The editor itself has since moved to its own home at [shemacs](https://github.com/jordanhubbard/shemacs), where it lives alongside its bash and zsh siblings.  sheme continues as a pure Scheme interpreter for shell programmers, and the terminal I/O builtins remain for anyone who wants to write *real programs* entirely in Scheme.

As of this writing, sheme implements a reasonable subset of R5RS Scheme, passes 548 tests across both shells (including 123 R5RS compatibility tests and 41 I/O builtin tests).  It has been used in production by exactly one person, who also wrote it.  Sir Reginald continues to withhold his endorsement, citing "procedural concerns" and "insufficient tuna."

The project motto remains: **"It's not about whether you *should*.  It's about whether you *can*.  And also whether your cat respects you.  (He doesn't.)"**

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

Look, the list above was meant as inspiration.  Aspirational.  A gentle nudge toward the horizon.

Then I got bored.

The "TODO App / Personal Wiki" entry caught my eye specifically because it seemed like a reasonable thing to actually build — file I/O, list processing, maybe a daemon.  Fine.  Straightforward.  And then one thing led to another, and what started as a weekend sketch turned into something with a full event-driven synchronization model, two-armed tasks (a *human* arm that notifies you and a *shell* arm that runs a command), inotifywait/fswatch integration so the daemon wakes up instantly instead of polling, and a Scheme function that computes the exact number of seconds until the next due task so the sleep is precise.

It is, to be clear, a TODO app implemented as a Scheme interpreter embedded in bash, where the task list is stored as Scheme source that gets eval'd back at startup, and the daemon receives SIGUSR1 to interrupt its `read -t` sleep whenever the file changes.  This is either an elegant demonstration of sheme's capabilities or a cry for help.  Possibly both.

Sir Reginald has reviewed it.  He knocked it off the desk.  I choose to interpret this as approval.

The implementation lives in `examples/todo.sh`.  All the examples — including a REPL, a classic-algorithms showcase, and a CSP-style producer/consumer demo — are documented in [`examples/README.md`](examples/README.md).
