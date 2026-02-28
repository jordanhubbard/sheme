#!/usr/bin/env bash
# em.sh - Emacs-like editor powered by bad-scheme
#
# Usage: bash examples/em.sh [filename]
#
# The editor logic lives in examples/em.scm (Scheme).
# This wrapper handles terminal I/O and file operations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Source the Scheme interpreter (try installed location, then repo)
if [[ -f "$HOME/.bs.sh" ]]; then
    source "$HOME/.bs.sh"
elif [[ -f "$SCRIPT_DIR/bs.sh" ]]; then
    source "$SCRIPT_DIR/bs.sh"
else
    echo "em: cannot find bs.sh" >&2; exit 1
fi
bs-reset

# ── Load the Scheme editor code (try installed location, then repo) ──
if [[ -f "$HOME/.em.scm" ]]; then
    _em_scm="$(cat "$HOME/.em.scm")"
elif [[ -f "$SCRIPT_DIR/examples/em.scm" ]]; then
    _em_scm="$(cat "$SCRIPT_DIR/examples/em.scm")"
else
    echo "em: cannot find em.scm" >&2; exit 1
fi
bs "$_em_scm"

# ── Terminal state ──
_em_stty_saved=""
_em_rows=24
_em_cols=80
_em_key=""
_em_abc="abcdefghijklmnopqrstuvwxyz"

_em_cleanup() {
    printf '\e[0m\e[?25h\e[?1049l'
    [[ -n "$_em_stty_saved" ]] && stty "$_em_stty_saved" 2>/dev/null || stty sane 2>/dev/null
}

_em_handle_resize() {
    _em_rows=$(tput lines 2>/dev/null) || _em_rows=24
    _em_cols=$(tput cols 2>/dev/null) || _em_cols=80
}

# ── Key reading (ported from bad-emacs) ──
_em_read_key() {
    local char="" char2="" char3="" char4=""
    local -i rc ord

    IFS= read -rsn1 -d '' char
    rc=$?

    if ((rc != 0)) && [[ -z "$char" ]]; then
        IFS= read -rsn1 -d '' char
        rc=$?
    fi

    if [[ -z "$char" ]]; then
        if ((rc != 0)); then
            _em_key="QUIT"
            return
        fi
        _em_key="C-SPC"
        return
    fi

    printf -v ord '%d' "'$char" 2>/dev/null || ord=0

    if ((ord == 27)); then
        IFS= read -rsn1 -d '' -t 0.05 char2
        if [[ -z "$char2" ]]; then
            _em_key="ESC"
            return
        fi
        if [[ "$char2" == "[" ]]; then
            IFS= read -rsn1 -d '' -t 0.05 char3
            case "$char3" in
                A) _em_key="UP"; return;;
                B) _em_key="DOWN"; return;;
                C) _em_key="RIGHT"; return;;
                D) _em_key="LEFT"; return;;
                H) _em_key="HOME"; return;;
                F) _em_key="END"; return;;
                [0-9])
                    local seq="$char3"
                    while IFS= read -rsn1 -d '' -t 0.05 char4; do
                        seq+="$char4"
                        [[ "$char4" == "~" || "$char4" == [A-Za-z] ]] && break
                    done
                    case "$seq" in
                        3~) _em_key="DEL"; return;;
                        5~) _em_key="PGUP"; return;;
                        6~) _em_key="PGDN"; return;;
                        2~) _em_key="INS"; return;;
                        1~) _em_key="HOME"; return;;
                        4~) _em_key="END"; return;;
                        *) _em_key="UNKNOWN"; return;;
                    esac
                    ;;
                *) _em_key="UNKNOWN"; return;;
            esac
        elif [[ "$char2" == "O" ]]; then
            IFS= read -rsn1 -d '' -t 0.05 char3
            case "$char3" in
                A) _em_key="UP";; B) _em_key="DOWN";;
                C) _em_key="RIGHT";; D) _em_key="LEFT";;
                H) _em_key="HOME";; F) _em_key="END";;
                *) _em_key="UNKNOWN";;
            esac
            return
        else
            local -i ord2
            printf -v ord2 '%d' "'$char2" 2>/dev/null || ord2=0
            if ((ord2 == 127 || ord2 == 8)); then
                _em_key="M-DEL"
            else
                _em_key="M-${char2}"
            fi
            return
        fi
    elif ((ord >= 1 && ord <= 26)); then
        local letter="${_em_abc:ord-1:1}"
        _em_key="C-${letter}"
        return
    elif ((ord == 127 || ord == 8)); then
        _em_key="BACKSPACE"
        return
    elif ((ord == 0)); then
        _em_key="C-SPC"
        return
    else
        _em_key="SELF:${char}"
        return
    fi
}

# ── Escape a string for safe embedding in Scheme ──
_em_escape_for_scheme() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# ── Initialize terminal ──
_em_stty_saved=$(stty -g 2>/dev/null)
trap '_em_cleanup' EXIT INT TERM
trap '_em_handle_resize' WINCH

stty raw -echo -isig -ixon -ixoff -icrnl intr undef quit undef susp undef lnext undef 2>/dev/null
printf '\e[?1049h\e[?25h'
_em_handle_resize

# ── Helper: extract tagged Scheme values ──
# Scheme strings are stored as s:content, integers as i:N
_em_str() { printf '%s' "${1:2}"; }
_em_int() { printf '%s' "${1:2}"; }

# ── Initialize editor ──
_em_file="${1:-}"
if [[ -n "$_em_file" ]]; then
    _em_escaped_name="$(_em_escape_for_scheme "$(basename "$_em_file")")"
    _em_escaped_path="$(_em_escape_for_scheme "$_em_file")"
    if [[ -f "$_em_file" ]]; then
        _em_content=$(< "$_em_file") || _em_content=""
        _em_escaped_content="$(_em_escape_for_scheme "$_em_content")"
        bs "(begin (em-init $_em_rows $_em_cols) (set! em-filename \"$_em_escaped_path\") (set! em-bufname \"$_em_escaped_name\") (em-load-content \"$_em_escaped_content\") (set! em-message \"em: bad emacs (C-x C-c to quit, C-h b for help)\") (em-render))"
    else
        bs "(begin (em-init $_em_rows $_em_cols) (set! em-filename \"$_em_escaped_path\") (set! em-bufname \"$_em_escaped_name\") (set! em-message \"em: bad emacs (C-x C-c to quit, C-h b for help)\") (em-render))"
    fi
else
    bs "(em-init $_em_rows $_em_cols)"
fi
printf '%s' "$(_em_str "$__em_render")"

# ── Main loop ──
while true; do
    # Check running state (integer tagged as i:0 or i:1)
    [[ "$(_em_int "${em_running:-i:1}")" == "0" ]] && break

    _em_read_key
    [[ "$_em_key" == "QUIT" ]] && break

    # Escape the key name for Scheme
    _em_escaped_key="$(_em_escape_for_scheme "$_em_key")"

    bs "(em-handle-key \"$_em_escaped_key\" $_em_rows $_em_cols)"
    printf '%s' "$(_em_str "$__em_render")"

    # Handle eval-buffer requests (C-j / M-x eval-buffer)
    local_eval_req="$(_em_str "${__em_eval_request:-s:}")"
    if [[ -n "$local_eval_req" ]]; then
        # Evaluate the buffer content as Scheme
        local_eval_result=""
        if bs "$local_eval_req" 2>/tmp/em_eval_err; then
            local_eval_result="$__bs_last_display"
        else
            local_eval_result="Error: $(cat /tmp/em_eval_err 2>/dev/null)"
        fi
        local_escaped_result="$(_em_escape_for_scheme "$local_eval_result")"
        bs "(em-eval-done \"$local_escaped_result\")"
        printf '%s' "$(_em_str "$__em_render")"
    fi

    # Handle file save requests
    local_save_req="$(_em_str "${em_save_request:-s:}")"
    if [[ -n "$local_save_req" ]]; then
        # Write buffer content to file
        local_save_data="$(_em_str "${em_save_data:-s:}")"
        printf '%s\n' "$local_save_data" > "$local_save_req" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            bs "(em-save-done)"
            printf '%s' "$(_em_str "$__em_render")"
        else
            bs "(begin (set! em-message \"Error writing file\") (set! em_save_request \"\") (em-render))"
            printf '%s' "$(_em_str "$__em_render")"
        fi
    fi
done

exit 0
