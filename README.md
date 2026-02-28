# bad-scheme
This is a bad scheme interpreter written in bash / zsh.  Its purpose is to be an intermediate language for other bad bash / zsh scripts that will look less bad when written in an HONORABLE language like scheme.

## Preface

I write a lot of bash scripts.  Bash is turing complete (or this "transpiler" would not be possible) but its scripts look ugly in my .bashrc.  Other people use zsh.  These are people who I am sure are perfectly honorable in every way and who's personal life choices can almost certainly be rationalized, even when such choices include "using zsh."  In support of these people, and I am fully prepared to defend their status as people, I wish to therefore make it perfectly clear up-front that when I say "bash" in the rest of this README, I mean "bash and zsh" because there is a version of this for *them*, too.  I am nothing if not inclusive!

## Foundational premises

1. Shell functions are ugly.  They work, they work well, but they are not stylish and other programmers make fun of you when you write a lot of shell scripts that also contain complex shell functions, as if you were using a REAL programming language.
2. Scheme is a *REAL* programming language, one worthy of respect and veneration.
3. Therefore, writing shell code in Scheme will make you cool and similarly worthy of respect and veneration.
4. You don't want to have to install a full scheme interpreter though.  That's way too much work, and it involves Life Decisions after reading scheme.org in detail.  Questions like:  "*WHICH* scheme?  How *MUCH* scheme is the _right amount_?  Should I go "classic" with r5rs or should I go for *ALL THE MARBLES* with r7rs?  Wait, isn't R7rs *TOO LARGE* though?  Should I ask this question on Reddit?  Oh god!  I don't want to ask this question on Reddit!"
5. Hey!  I know what I'll do!  It's time for me to choose jkh's BAD SCHEME!

## Quick Start

```bash
# Clone the repository
git clone https://github.com/jordanhubbard/bad-scheme.git
cd bad-scheme

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
| `make install-em` | Install bad-scheme AND copy `em.sh`/`em.scm` to `~/` with shell integration |
| `make uninstall-em` | Remove the em files and `source` lines |
| `make check` | Syntax-check both bash and zsh versions |
| `make test` | Run the interpreter test suite (177 bash + 202 zsh tests) |
| `make test-em` | Run the Scheme editor expect tests (5 tests) |
| `make test-r5rs` | Run the R5RS compatibility test suite (~123 tests) |
| `make test-all` | Run everything: interpreter tests + editor tests + R5RS tests |
| `make benchmark` | Run performance benchmarks for all language primitives |
| `make example` | Run the feature demo script |

## Running bad-emacs (em)

bad-scheme ships with `em`, an Emacs-like text editor written entirely in Scheme.  The editor logic (~1200 lines of Scheme) lives in `examples/em.scm` and is loaded by a thin bash wrapper that handles terminal I/O.

```bash
# Run directly from the repo
bash examples/em.sh [filename]

# Or install the em command
make install-em
em myfile.txt
```

### Editor Commands

| Key | Action |
|-----|--------|
| C-f / C-b | Forward / backward character |
| C-n / C-p | Next / previous line |
| C-a / C-e | Beginning / end of line |
| C-v / M-v | Page down / page up |
| M-f / M-b | Forward / backward word |
| C-d | Delete character |
| Backspace | Delete backward |
| C-k | Kill line |
| C-y | Yank (paste) |
| C-w | Kill region |
| M-w | Copy region |
| C-SPC | Set mark |
| C-/ | Undo |
| C-s / C-r | Incremental search forward / backward |
| M-u / M-l / M-c | Upcase / downcase / capitalize word |
| C-j | Evaluate buffer as Scheme (eval-buffer) |
| M-x | Execute named command (e.g. `eval-buffer`) |
| C-x C-s | Save file |
| C-x C-c | Quit |

## The Totally True and Not At All Embellished History of bad-scheme

It was a dark and stormy night in late 2024.  A lone programmer, hunched over a mass of tangled bash functions that had somehow metastasized into a text editor, stared at his screen and whispered the words that would change history: "What if I wrote a Scheme interpreter... *in bash*?"  (The result would later be renamed from `bad-scheme.sh` to `bs.sh`, because brevity is the soul of wit, and also of `source` commands.)

His cat, Sir Reginald von Fluffington III, looked up from the keyboard he was sleeping on and blinked once, slowly, in the way that cats do when they are judging you but wish to maintain plausible deniability.

"Think about it, Reggie," the programmer continued, gesturing at the 2,451 lines of bash that constituted `bad-emacs`.  "All these functions.  All these arrays.  All this... *string manipulation*.  What if it were... *elegant*?"

Sir Reginald yawned.  He had seen the programmer's definition of "elegant" before.  It usually involved more parentheses.

What followed was a period that historians would later call "The Great Parenthesizing" — three fevered weeks during which the programmer consumed dangerous quantities of coffee and taught bash to understand S-expressions.  The tokenizer came first, born from the unholy union of `case` statements and string slicing.  Then the parser, a recursive descent into madness that stored cons cells in associative arrays with keys like `p:47`.  Then the evaluator, which contained a `case` statement so long that it briefly achieved sentience and filed a labor complaint.

"It's alive!" the programmer cried, when `(+ 1 2)` finally returned `3`.  Sir Reginald was unimpressed.  He could count to three.  He had three functioning brain cells and each of them was dedicated to the task of procuring second breakfast.

But the programmer was not done.  "Now," he declared, with the wild-eyed certainty of a man who has Just Had An Idea, "I shall rewrite bad-emacs *in Scheme*.  Running on bad-scheme.  Running on bash.  It will be a text editor, written in a language that runs inside the shell, editing files that contain more shell.  It's turtles all the way down, Reggie!"

Sir Reginald left the room.

The resulting artifact — `em.scm` — was approximately 1,200 lines of Scheme that, when loaded into 1,400 lines of bash pretending to be a Scheme interpreter, produced a functional Emacs clone that could edit files at the blistering speed of 2-3 milliseconds per keystroke.  The programmer was unreasonably proud of this number, having optimized it down from 800 milliseconds by the revolutionary technique of "not forking a subprocess for every single keypress."

When asked why anyone would want a text editor written in Scheme running on a Scheme interpreter written in bash, the programmer would smile serenely and say: "Because it's there.  And because Scheme is an HONORABLE language."

Sir Reginald, reached for comment, declined to participate but was observed shortly thereafter pushing a mass of carefully stacked papers off the desk, one sheet at a time, while maintaining eye contact.

The programmer later added zsh support, because he is, as previously established, nothing if not inclusive.  The zsh version works identically, a fact which surprised absolutely everyone, including the programmer.  "I thought for sure the associative array syntax would be different," he admitted.  "Turns out zsh just... does what bash does?  But with more... *feelings* about it?"

As of this writing, bad-scheme implements a reasonable subset of R5RS Scheme, passes 502 tests across both shells (including 123 R5RS compatibility tests), and has been used in production by exactly one person, who also wrote it.  Sir Reginald continues to withhold his endorsement, citing "procedural concerns" and "insufficient tuna."

The project motto remains: **"It's not about whether you *should*.  It's about whether you *can*.  And also whether your cat respects you.  (He doesn't.)"**
