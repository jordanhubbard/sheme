#!/usr/bin/env bash
# repl.sh - Interactive Scheme REPL using sheme
#
# Run:  bash examples/repl.sh
#   or: make repl

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bs.sh"
bs-reset

printf 'sheme REPL  (Ctrl-D or (quit) to exit)\n'

while IFS= read -r -p 'scm> ' line || { printf '\n'; break; }; do
    [[ -z "$line" ]] && continue
    case "$line" in
        quit|'(quit)'|exit|'(exit)') break ;;
    esac
    bs-eval "$line"
done
