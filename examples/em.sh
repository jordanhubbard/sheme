# em.sh - Launcher for the Scheme-powered Emacs-like editor
#
# Source this file in your .bashrc:  source ~/.em.sh
# Then run:  em [filename]
# Or run standalone:  bash examples/em.sh [filename]
#
# All editor logic and I/O is in em.scm (Scheme).
# This file just loads the interpreter and calls em-main.

# Require bash 4+
if [[ "${BASH_VERSINFO:-0}" -lt 4 ]]; then
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        for _em_try_bash in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash; do
            if [[ -x "$_em_try_bash" ]] && "$_em_try_bash" -c '[[ ${BASH_VERSINFO[0]} -ge 4 ]]' 2>/dev/null; then
                exec "$_em_try_bash" "$0" "$@"
            fi
        done
    fi
    echo "em requires Bash 4+. Install via: brew install bash" >&2
    return 2>/dev/null || exit 1
fi

em() {
    local _em_script_dir
    _em_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || _em_script_dir=""

    # Source the Scheme interpreter if not already loaded
    if ! type bs &>/dev/null; then
        if [[ -f "$HOME/.bs.sh" ]]; then
            source "$HOME/.bs.sh"
        elif [[ -n "$_em_script_dir" && -f "$_em_script_dir/bs.sh" ]]; then
            source "$_em_script_dir/bs.sh"
        else
            echo "em: cannot find bs.sh (install sheme first)" >&2
            return 1
        fi
    fi
    bs-reset

    # Load the Scheme editor code
    local _em_scm_file
    if [[ -f "$HOME/.em.scm" ]]; then
        _em_scm_file="$HOME/.em.scm"
    elif [[ -n "$_em_script_dir" && -f "$_em_script_dir/examples/em.scm" ]]; then
        _em_scm_file="$_em_script_dir/examples/em.scm"
    else
        echo "em: cannot find em.scm" >&2
        return 1
    fi
    bs "$(cat "$_em_scm_file")"

    # Safety-net trap: restore terminal if killed unexpectedly
    local _em_saved_traps
    _em_saved_traps=$(trap -p INT TERM HUP 2>/dev/null)
    trap 'printf "\e[0m\e[?25h\e[?1049l"; [[ -n "$__bs_stty_saved" ]] && stty "$__bs_stty_saved" 2>/dev/null; __bs_stty_saved=""; trap - INT TERM HUP; return 130' INT
    trap 'printf "\e[0m\e[?25h\e[?1049l"; [[ -n "$__bs_stty_saved" ]] && stty "$__bs_stty_saved" 2>/dev/null; __bs_stty_saved=""; trap - INT TERM HUP; return 143' TERM
    trap 'printf "\e[0m\e[?25h\e[?1049l"; [[ -n "$__bs_stty_saved" ]] && stty "$__bs_stty_saved" 2>/dev/null; __bs_stty_saved=""; trap - INT TERM HUP; return 129' HUP

    # Escape filename for Scheme and run the editor
    local _em_escaped="${1:-}"
    _em_escaped="${_em_escaped//\\/\\\\}"
    _em_escaped="${_em_escaped//\"/\\\"}"
    bs "(em-main \"$_em_escaped\")"

    # Restore traps
    trap - INT TERM HUP
    [[ -n "$_em_saved_traps" ]] && eval "$_em_saved_traps"
    return 0
}

# Standalone execution: bash examples/em.sh [filename]
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    em "$@"
fi
