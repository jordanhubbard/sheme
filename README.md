# bad-scheme
This is a bad scheme interpreter written in bash / zsh.  Its purpose is to be an intermediate language for other bad bash / zsh scripts that will look less bad when written in an HONORABLE language like scheme.

## Preface

I write a lot of bash scripts.  Bash is turing complete (or this "transpiler" would not be possible) but its scripts look ugly in my .bashrc.  Other people use zsh.  People who I am sure are also perfectly honorable in every way and who make life choices that can almost certainly be rationalized, even when those life choices include "using zsh".  In support of such people, I wish to therefore make it perfectly clear up-front that when I say "bash" in the rest of this README, I mean "bash and zsh" because there is a version of this for them, too.

## Foundational premises

1. Shell functions are ugly.  They work, they work well, but they are not stylish and other programmers make fun of you when you write a lot of shell scripts that also contain complex shell functions, as if you were using a REAL programming language.
2. Scheme is a REAL programming language, one worthy of respect and veneration.
3. Therefore, writing shell code in Scheme will make you cool and similarly worthy of respect and veneration.
4. You don't want to have to install a full scheme interpreter though.  That's way too much work, and it involves Life Decisions after reading scheme.org in detail.  Questions like:  "WHICH scheme?  How MUCH scheme?  Should I go "classic" with r5rs or should I go for ALL THE MARBLES with r7rs?  Wait, isn't R7rs TOO LARGE though?  Should I ask this question on Reddit?  Oh god I don't want to ask this question on Reddit!"
5. Hey!  I know what I'll do!  It's time for BAD SCHEME!
