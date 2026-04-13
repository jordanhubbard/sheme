#!/usr/bin/env bash
# bs.sh - Scheme interpreter in Bash
# Source this file; then call:  bs '<scheme source>'
#
# Public API:
#   bs         <src>   - evaluate Scheme source inline (no subshell overhead)
#   bs-reset           - wipe interpreter state between sessions
#   bs-eval    <src>   - convenience: evaluate and print human-readable result

[[ -n "${_SHEME_LOADED:-}" ]] && return 0 2>/dev/null
_SHEME_LOADED=1

# ──────────────────────────────────────────────────────────────────────────────
# Internal functions (top-level, operating on global state)
# ──────────────────────────────────────────────────────────────────────────────

# ── Heap allocation helpers ───────────────────────────────────────────
__bs_cons() {                          # car cdr -> sets __bs_ret to p:<id>
    local id="p:${__bs_heap_next}"
    __bs_car["$id"]="$1"
    __bs_cdr["$id"]="$2"
    (( __bs_heap_next++ )) || true
    __bs_ret="$id"
}

__bs_make_closure() {                  # params body env -> sets __bs_ret to f:<id>
    local id="f:${__bs_heap_next}"
    __bs_closure_params["$id"]="$1"
    __bs_closure_body["$id"]="$2"
    __bs_closure_env["$id"]="$3"
    (( __bs_heap_next++ )) || true
    __bs_ret="$id"
}

# ── Environment helpers ───────────────────────────────────────────────
__bs_new_env() {                       # parent-envid -> sets __bs_ret to new envid
    local id="${__bs_env_next}"
    (( __bs_env_next++ )) || true
    __bs_env_parent["$id"]="$1"
    __bs_ret="$id"
}

__bs_env_lookup() {                    # envid varname -> sets __bs_ret; returns 1 on error
    local env="$1" var="$2"
    local cur="$env"
    while [[ -n "$cur" ]]; do
        local key="${cur}:${var}"
        if [[ -v __bs_env["$key"] ]]; then
            __bs_ret="${__bs_env[$key]}"
            return 0
        fi
        cur="${__bs_env_parent[$cur]:-}"
    done
    if __bs_is_builtin "$var"; then
        __bs_ret="f:${var}"
        return 0
    fi
    __bs_error "unbound variable: $var"
    return 1
}

__bs_env_set_existing() {             # envid varname value -> updates existing binding
    local env="$1" var="$2" val="$3"
    local cur="$env"
    while [[ -n "$cur" ]]; do
        local key="${cur}:${var}"
        if [[ -v __bs_env["$key"] ]]; then
            __bs_env["$key"]="$val"
            return 0
        fi
        cur="${__bs_env_parent[$cur]:-}"
    done
    __bs_error "set!: unbound variable: $var"
    return 1
}

__bs_env_bind() {                     # envid varname value -> creates/updates in that frame
    __bs_env["${1}:${2}"]="$3"
}

# ── Builtin name table ────────────────────────────────────────────────
__bs_is_builtin() {
    case "$1" in
        '+'|'-'|'*'|'/'|quotient|remainder|modulo|expt|abs|max|min|gcd|lcm) return 0 ;;
        '='|'<'|'>'|'<='|'>='|'eq?'|'eqv?'|'equal?') return 0 ;;
        not) return 0 ;;
        'number?'|'string?'|'symbol?'|'boolean?'|'procedure?'|'pair?'|'null?'|'list?') return 0 ;;
        'zero?'|'positive?'|'negative?'|'even?'|'odd?') return 0 ;;
        cons|car|cdr|'set-car!'|'set-cdr!'|list|length|append|reverse) return 0 ;;
        'list-tail'|'list-ref'|map|'for-each'|filter|assoc|assv|assq|member|memv|memq) return 0 ;;
        'string-length'|'string-append'|substring|'string->number'|'number->string') return 0 ;;
        'string->symbol'|'symbol->string'|'string=?'|'string<?'|'string>?') return 0 ;;
        'string<=?'|'string>=?'|'string-ref'|string|'make-string'|'string-copy') return 0 ;;
        'string-upcase'|'string-downcase'|'string->list'|'list->string') return 0 ;;
        'char?'|'char->integer'|'integer->char'|'char=?'|'char<?'|'char-alphabetic?'|'char-numeric?') return 0 ;;
        display|write|newline|apply|error|'read-line') return 0 ;;
        'read-byte'|'read-byte-timeout'|'write-stdout'|'terminal-size') return 0 ;;
        'terminal-raw!'|'terminal-restore!'|'terminal-suspend!'|'file-read'|'file-write'|'eval-string') return 0 ;;
        'file-glob'|'file-directory?'|'file-write-atomic'|'shell-capture'|'shell-exec') return 0 ;;
        'make-vector'|vector|'vector-ref'|'vector-set!'|'vector-length'|'vector->list'|'list->vector'|'vector?') return 0 ;;
        'exact->inexact'|'inexact->exact'|exact|inexact|floor|ceiling|round|truncate) return 0 ;;
        'call-with-current-continuation'|'call/cc') return 0 ;;
        'with-exception-handler'|raise|'raise-continuable') return 0 ;;
        values|'call-with-values') return 0 ;;
        'foldl'|'foldr'|'fold-left'|'fold-right') return 0 ;;
        *) return 1 ;;
    esac
}

# ── Error helper ──────────────────────────────────────────────────────
__bs_error() {
    __bs_last_error="$*"
    printf 'sheme: %s\n' "$*" >&2
    __bs_ret="n:()"
}

__bs_valid_bash_id() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

# ── Tokenizer ─────────────────────────────────────────────────────────
__bs_tokenize() {
    local src="$1"
    __bs_tokens=()
    local i=0 len=${#src} c tok

    while (( i < len )); do
        c="${src:$i:1}"

        # Whitespace
        case "$c" in ' '|$'\t'|$'\n'|$'\r')
            (( i++ )); continue ;;
        esac

        # Line comment
        if [[ "$c" == ';' ]]; then
            while (( i < len )) && [[ "${src:$i:1}" != $'\n' ]]; do
                (( i++ ))
            done
            continue
        fi

        # Parentheses
        case "$c" in
            '('|')') __bs_tokens+=("$c"); (( i++ )); continue ;;
        esac

        # Quote abbreviation
        if [[ "$c" == "'" ]]; then
            __bs_tokens+=("QUOTE"); (( i++ )); continue
        fi

        # Quasiquote abbreviation
        if [[ "$c" == '`' ]]; then
            __bs_tokens+=("QUASIQUOTE"); (( i++ )); continue
        fi

        # Unquote abbreviation
        if [[ "$c" == ',' ]]; then
            if (( i+1 < len )) && [[ "${src:$((i+1)):1}" == '@' ]]; then
                __bs_tokens+=("UNQUOTE-SPLICING"); (( i += 2 ))
            else
                __bs_tokens+=("UNQUOTE"); (( i++ ))
            fi
            continue
        fi

        # String literals
        if [[ "$c" == '"' ]]; then
            tok='"'
            (( i++ ))
            while (( i < len )); do
                c="${src:$i:1}"
                if [[ "$c" == '"' ]]; then
                    tok+='"'; (( i++ )); break
                elif [[ "$c" == $'\\' ]]; then
                    tok+="${c}${src:$((i+1)):1}"
                    (( i += 2 ))
                else
                    tok+="$c"; (( i++ ))
                fi
            done
            __bs_tokens+=("$tok")
            continue
        fi

        # Atom (numbers, symbols, booleans, #\char, dots)
        tok=""
        while (( i < len )); do
            c="${src:$i:1}"
            case "$c" in
                ' '|$'\t'|$'\n'|$'\r'|'('|')'|'"'|';') break ;;
            esac
            tok+="$c"; (( i++ ))
        done
        [[ -n "$tok" ]] && __bs_tokens+=("$tok")
    done
}

# ── Parser ────────────────────────────────────────────────────────────
__bs_parse_expr() {
    if (( __bs_tpos >= ${#__bs_tokens[@]} )); then
        __bs_error "parse: unexpected end of input"
        return 1
    fi

    local tok="${__bs_tokens[$__bs_tpos]}"
    (( __bs_tpos++ ))

    case "$tok" in
        '(')
            __bs_parse_list
            return $?
            ;;
        'QUOTE')
            __bs_parse_expr || return 1
            local inner="$__bs_ret"
            __bs_cons "$inner" "n:()"
            local args="$__bs_ret"
            __bs_cons "y:quote" "$args"
            return 0
            ;;
        'QUASIQUOTE')
            __bs_parse_expr || return 1
            local inner="$__bs_ret"
            __bs_cons "$inner" "n:()"
            local args="$__bs_ret"
            __bs_cons "y:quasiquote" "$args"
            return 0
            ;;
        'UNQUOTE')
            __bs_parse_expr || return 1
            local inner="$__bs_ret"
            __bs_cons "$inner" "n:()"
            local args="$__bs_ret"
            __bs_cons "y:unquote" "$args"
            return 0
            ;;
        'UNQUOTE-SPLICING')
            __bs_parse_expr || return 1
            local inner="$__bs_ret"
            __bs_cons "$inner" "n:()"
            local args="$__bs_ret"
            __bs_cons "y:unquote-splicing" "$args"
            return 0
            ;;
        *)
            __bs_parse_atom "$tok"
            return 0
            ;;
    esac
}

__bs_parse_list() {
    if (( __bs_tpos >= ${#__bs_tokens[@]} )); then
        __bs_ret="n:()"
        return 0
    fi

    local tok="${__bs_tokens[$__bs_tpos]}"

    if [[ "$tok" == ')' ]]; then
        (( __bs_tpos++ ))
        __bs_ret="n:()"
        return 0
    fi

    # Dotted pair  . cdr )
    if [[ "$tok" == '.' ]]; then
        (( __bs_tpos++ ))
        __bs_parse_expr || return 1
        local cdr_val="$__bs_ret"
        (( __bs_tpos++ ))     # consume closing ')'
        __bs_ret="$cdr_val"
        return 0
    fi

    __bs_parse_expr || return 1
    local car_val="$__bs_ret"

    __bs_parse_list || return 1
    local cdr_val="$__bs_ret"

    __bs_cons "$car_val" "$cdr_val"
    return 0
}

__bs_parse_atom() {
    local tok="$1"
    case "$tok" in
        '#t'|'#true')   __bs_ret="b:#t"; return 0 ;;
        '#f'|'#false')  __bs_ret="b:#f"; return 0 ;;
        '#\'*)
            local ch="${tok:2}"
            case "$ch" in
                space)   ch=' '  ;;
                newline) ch=$'\n' ;;
                tab)     ch=$'\t' ;;
                nul|null) ch=$'\0' ;;
            esac
            __bs_ret="c:${ch}"
            return 0 ;;
        '"'*)
            local s="${tok:1:${#tok}-2}"
            s="${s//\\n/$'\n'}"
            s="${s//\\t/$'\t'}"
            s="${s//\\\"/\"}"
            s="${s//\\\\/\\}"
            __bs_ret="s:${s}"
            return 0 ;;
        *)
            if [[ "$tok" =~ ^-?[0-9]+$ ]]; then
                __bs_ret="i:$tok"
            else
                __bs_ret="y:$tok"
            fi
            return 0 ;;
    esac
}

# ── Display / Write helpers ───────────────────────────────────────────
__bs_display() {                      # val -> sets __bs_ret to human string
    local val="$1"
    case "${val:0:2}" in
        'i:') __bs_ret="${val:2}" ;;
        'b:') __bs_ret="${val:2}" ;;
        'n:') __bs_ret="()" ;;
        's:') __bs_ret="${val:2}" ;;
        'y:') __bs_ret="${val:2}" ;;
        'c:') __bs_ret="${val:2}" ;;
        'f:') __bs_ret="#<procedure:${val:2}>" ;;
        'v:') __bs_ret="#<vector>" ;;
        'p:')
            local result="("
            local cur="$val"
            local first=1
            while [[ "$cur" == p:* ]]; do
                [[ $first -eq 0 ]] && result+=" "
                first=0
                __bs_display "${__bs_car[$cur]}"
                result+="$__bs_ret"
                cur="${__bs_cdr[$cur]}"
            done
            if [[ "$cur" != 'n:()' ]]; then
                result+=" . "
                __bs_display "$cur"
                result+="$__bs_ret"
            fi
            result+=")"
            __bs_ret="$result"
            ;;
        *)  __bs_ret="$val" ;;
    esac
}

__bs_write() {                        # val -> sets __bs_ret (strings quoted, chars #\x)
    local val="$1"
    case "${val:0:2}" in
        's:')
            local s="${val:2}"
            s="${s//$'\\'/$'\\\\'}"
            s="${s//\"/$'\\"'}"
            __bs_ret="\"${s}\""
            ;;
        'c:') __bs_ret="#\\${val:2}" ;;
        'p:')
            local result="("
            local cur="$val"
            local first=1
            while [[ "$cur" == p:* ]]; do
                [[ $first -eq 0 ]] && result+=" "
                first=0
                __bs_write "${__bs_car[$cur]}"
                result+="$__bs_ret"
                cur="${__bs_cdr[$cur]}"
            done
            if [[ "$cur" != 'n:()' ]]; then
                result+=" . "
                __bs_write "$cur"
                result+="$__bs_ret"
            fi
            result+=")"
            __bs_ret="$result"
            ;;
        *)  __bs_display "$val" ;;
    esac
}

__bs_equal_val() {                    # a b -> sets __bs_ret to b:#t or b:#f
    local a="$1" b="$2"
    if [[ "$a" == "$b" ]]; then
        __bs_ret="b:#t"; return
    fi
    if [[ "$a" == p:* && "$b" == p:* ]]; then
        __bs_equal_val "${__bs_car[$a]}" "${__bs_car[$b]}"
        if [[ "$__bs_ret" == 'b:#t' ]]; then
            __bs_equal_val "${__bs_cdr[$a]}" "${__bs_cdr[$b]}"
            return
        fi
    fi
    __bs_ret="b:#f"
}

# ── Evaluator ─────────────────────────────────────────────────────────
__bs_eval() {                         # expr env -> sets __bs_ret
    local expr="$1" env="$2"

    case "${expr:0:2}" in
        'i:'|'b:'|'n:'|'s:'|'c:')     # self-evaluating
            __bs_ret="$expr"; return 0 ;;
        'f:')                          # closures / builtin refs are self-evaluating
            __bs_ret="$expr"; return 0 ;;
        'v:')
            __bs_ret="$expr"; return 0 ;;
        'y:')                          # variable reference
            __bs_env_lookup "$env" "${expr:2}"
            return $? ;;
        'p:') ;;                       # fall through to list handling
        *)
            __bs_error "eval: unknown value: $expr"
            return 1 ;;
    esac

    # ── List: special form or application ──
    local head="${__bs_car[$expr]}"
    local rest="${__bs_cdr[$expr]}"

    case "$head" in

        # ── quote ─────────────────────────────────────────────────────
        'y:quote')
            __bs_ret="${__bs_car[$rest]}"
            return 0 ;;

        # ── if ────────────────────────────────────────────────────────
        'y:if')
            __bs_eval "${__bs_car[$rest]}" "$env" || return 1
            local test_val="$__bs_ret"
            local branches="${__bs_cdr[$rest]}"
            if [[ "$test_val" != 'b:#f' ]]; then
                __bs_eval "${__bs_car[$branches]}" "$env"
            else
                local else_branch="${__bs_cdr[$branches]}"
                if [[ "$else_branch" != 'n:()' ]]; then
                    __bs_eval "${__bs_car[$else_branch]}" "$env"
                else
                    __bs_ret="n:()"
                fi
            fi
            return 0 ;;

        # ── define ────────────────────────────────────────────────────
        'y:define')
            local name_part="${__bs_car[$rest]}"
            local body_rest="${__bs_cdr[$rest]}"

            if [[ "$name_part" == y:* ]]; then
                # (define var expr)
                __bs_eval "${__bs_car[$body_rest]}" "$env" || return 1
                local def_val="$__bs_ret"
                __bs_env_bind "$env" "${name_part:2}" "$def_val"
                if [[ "$env" == '0' ]] && __bs_valid_bash_id "${name_part:2}"; then
                    declare -g "${name_part:2}=$def_val"
                fi
            else
                # (define (fname params...) body...)
                local fname="${__bs_car[$name_part]}"
                local params="${__bs_cdr[$name_part]}"
                __bs_make_closure "$params" "$body_rest" "$env"
                local clos="$__bs_ret"
                __bs_env_bind "$env" "${fname:2}" "$clos"
                if [[ "$env" == '0' ]] && __bs_valid_bash_id "${fname:2}"; then
                    declare -g "${fname:2}=$clos"
                fi
            fi
            __bs_ret="n:()"
            return 0 ;;

        # ── set! ──────────────────────────────────────────────────────
        'y:set!')
            local sv="${__bs_car[$rest]}"
            __bs_eval "${__bs_car[${__bs_cdr[$rest]}]}" "$env" || return 1
            local set_val="$__bs_ret"
            __bs_env_set_existing "$env" "${sv:2}" "$set_val" || return 1
            if [[ "$env" == '0' ]] && __bs_valid_bash_id "${sv:2}"; then
                declare -g "${sv:2}=$set_val"
            else
                # Also propagate if the binding lives in the global frame
                local _cur="$env"
                while [[ -n "$_cur" ]]; do
                    if [[ -v __bs_env["${_cur}:${sv:2}"] && "$_cur" == '0' ]]; then
                        if __bs_valid_bash_id "${sv:2}"; then
                            declare -g "${sv:2}=$set_val"
                        fi
                        break
                    fi
                    _cur="${__bs_env_parent[$_cur]:-}"
                done
            fi
            __bs_ret="n:()"
            return 0 ;;

        # ── lambda ────────────────────────────────────────────────────
        'y:lambda')
            local lam_params="${__bs_car[$rest]}"
            local lam_body="${__bs_cdr[$rest]}"
            __bs_make_closure "$lam_params" "$lam_body" "$env"
            return 0 ;;

        # ── begin ─────────────────────────────────────────────────────
        'y:begin')
            __bs_eval_seq "$rest" "$env"
            return 0 ;;

        # ── let ───────────────────────────────────────────────────────
        'y:let')
            __bs_eval_let "$rest" "$env"
            return 0 ;;

        # ── let* ──────────────────────────────────────────────────────
        'y:let*')
            __bs_eval_letstar "$rest" "$env"
            return 0 ;;

        # ── letrec / letrec* ──────────────────────────────────────────
        'y:letrec'|'y:letrec*')
            __bs_eval_letrec "$rest" "$env"
            return 0 ;;

        # ── cond ──────────────────────────────────────────────────────
        'y:cond')
            __bs_eval_cond "$rest" "$env"
            return 0 ;;

        # ── and ───────────────────────────────────────────────────────
        'y:and')
            __bs_ret="b:#t"
            local and_exprs="$rest"
            while [[ "$and_exprs" != 'n:()' ]]; do
                __bs_eval "${__bs_car[$and_exprs]}" "$env" || return 1
                [[ "$__bs_ret" == 'b:#f' ]] && return 0
                and_exprs="${__bs_cdr[$and_exprs]}"
            done
            return 0 ;;

        # ── or ────────────────────────────────────────────────────────
        'y:or')
            __bs_ret="b:#f"
            local or_exprs="$rest"
            while [[ "$or_exprs" != 'n:()' ]]; do
                __bs_eval "${__bs_car[$or_exprs]}" "$env" || return 1
                [[ "$__bs_ret" != 'b:#f' ]] && return 0
                or_exprs="${__bs_cdr[$or_exprs]}"
            done
            return 0 ;;

        # ── when ──────────────────────────────────────────────────────
        'y:when')
            __bs_eval "${__bs_car[$rest]}" "$env" || return 1
            if [[ "$__bs_ret" != 'b:#f' ]]; then
                __bs_eval_seq "${__bs_cdr[$rest]}" "$env"
            else
                __bs_ret="n:()"
            fi
            return 0 ;;

        # ── unless ────────────────────────────────────────────────────
        'y:unless')
            __bs_eval "${__bs_car[$rest]}" "$env" || return 1
            if [[ "$__bs_ret" == 'b:#f' ]]; then
                __bs_eval_seq "${__bs_cdr[$rest]}" "$env"
            else
                __bs_ret="n:()"
            fi
            return 0 ;;

        # ── case ──────────────────────────────────────────────────────
        'y:case')
            __bs_eval_case "$rest" "$env"
            return 0 ;;

        # ── do ────────────────────────────────────────────────────────
        'y:do')
            __bs_eval_do "$rest" "$env"
            return 0 ;;

        # ── quasiquote ────────────────────────────────────────────────
        'y:quasiquote')
            __bs_eval_quasiquote "${__bs_car[$rest]}" "$env"
            return 0 ;;

        # ── stubs ─────────────────────────────────────────────────────
        'y:define-record-type'|'y:define-syntax'|'y:syntax-rules'|'y:let-syntax'|'y:letrec-syntax')
            __bs_ret="n:()"
            return 0 ;;

        # ── values (pass-through first value) ─────────────────────────
        'y:values')
            if [[ "$rest" != 'n:()' ]]; then
                __bs_eval "${__bs_car[$rest]}" "$env"
            else
                __bs_ret="n:()"
            fi
            return 0 ;;

        # ── apply ─────────────────────────────────────────────────────
        'y:apply')
            __bs_eval "${__bs_car[$rest]}" "$env" || return 1
            local app_proc="$__bs_ret"
            local app_rest="${__bs_cdr[$rest]}"
            local -a app_args=()
            while [[ "${__bs_cdr[$app_rest]}" != 'n:()' ]]; do
                __bs_eval "${__bs_car[$app_rest]}" "$env" || return 1
                app_args+=("$__bs_ret")
                app_rest="${__bs_cdr[$app_rest]}"
            done
            # Last element must be a list; spread it
            __bs_eval "${__bs_car[$app_rest]}" "$env" || return 1
            local spread="$__bs_ret"
            while [[ "$spread" == p:* ]]; do
                app_args+=("${__bs_car[$spread]}")
                spread="${__bs_cdr[$spread]}"
            done
            __bs_apply "$app_proc" "${app_args[@]}"
            return 0 ;;
    esac

    # ── Function application ──────────────────────────────────────────
    __bs_eval "$head" "$env" || return 1
    local proc="$__bs_ret"

    local -a call_args=()
    local arg_list="$rest"
    while [[ "$arg_list" != 'n:()' && -n "$arg_list" ]]; do
        __bs_eval "${__bs_car[$arg_list]}" "$env" || return 1
        call_args+=("$__bs_ret")
        arg_list="${__bs_cdr[$arg_list]}"
    done

    __bs_apply "$proc" "${call_args[@]}"
    return $?
}

# ── Evaluate a sequence, return last ──────────────────────────────────
__bs_eval_seq() {                     # exprs env
    local exprs="$1" env="$2"
    __bs_ret="n:()"
    while [[ "$exprs" != 'n:()' && -n "$exprs" ]]; do
        __bs_eval "${__bs_car[$exprs]}" "$env" || return 1
        exprs="${__bs_cdr[$exprs]}"
    done
}

# ── let ───────────────────────────────────────────────────────────────
__bs_eval_let() {                     # rest env
    local rest="$1" env="$2"
    local first="${__bs_car[$rest]}"

    # Named let:  (let name ((v i) ...) body...)
    if [[ "$first" == y:* ]]; then
        local loop_name="${first:2}"
        local bindings="${__bs_car[${__bs_cdr[$rest]}]}"
        local body="${__bs_cdr[${__bs_cdr[$rest]}]}"

        __bs_new_env "$env"
        local loop_env="$__bs_ret"

        local -a pnames=() ivals=()
        local b="$bindings"
        while [[ "$b" != 'n:()' ]]; do
            local bnd="${__bs_car[$b]}"
            __bs_eval "${__bs_car[${__bs_cdr[$bnd]}]}" "$env" || return 1
            pnames+=("${__bs_car[$bnd]:2}")
            ivals+=("$__bs_ret")
            b="${__bs_cdr[$b]}"
        done

        # Build param list
        local param_list="n:()"
        for (( _k=${#pnames[@]}-1; _k>=0; _k-- )); do
            __bs_cons "y:${pnames[$_k]}" "$param_list"
            param_list="$__bs_ret"
        done

        __bs_make_closure "$param_list" "$body" "$loop_env"
        local loop_proc="$__bs_ret"
        __bs_env_bind "$loop_env" "$loop_name" "$loop_proc"
        __bs_apply "$loop_proc" "${ivals[@]}"
        return 0
    fi

    # Regular let
    local bindings="$first"
    local body="${__bs_cdr[$rest]}"

    __bs_new_env "$env"
    local let_env="$__bs_ret"

    local b="$bindings"
    while [[ "$b" != 'n:()' ]]; do
        local bnd="${__bs_car[$b]}"
        local var="${__bs_car[$bnd]}"
        local init="${__bs_car[${__bs_cdr[$bnd]}]}"
        __bs_eval "$init" "$env" || return 1         # eval in ORIGINAL env
        __bs_env_bind "$let_env" "${var:2}" "$__bs_ret"
        b="${__bs_cdr[$b]}"
    done

    __bs_eval_seq "$body" "$let_env"
}

# ── let* ──────────────────────────────────────────────────────────────
__bs_eval_letstar() {                 # rest env
    local rest="$1" env="$2"
    local bindings="${__bs_car[$rest]}"
    local body="${__bs_cdr[$rest]}"

    __bs_new_env "$env"
    local cur_env="$__bs_ret"

    local b="$bindings"
    while [[ "$b" != 'n:()' ]]; do
        local bnd="${__bs_car[$b]}"
        local var="${__bs_car[$bnd]}"
        local init="${__bs_car[${__bs_cdr[$bnd]}]}"
        __bs_eval "$init" "$cur_env" || return 1     # eval in CURRENT (growing) env
        __bs_env_bind "$cur_env" "${var:2}" "$__bs_ret"
        b="${__bs_cdr[$b]}"
    done

    __bs_eval_seq "$body" "$cur_env"
}

# ── letrec ────────────────────────────────────────────────────────────
__bs_eval_letrec() {                  # rest env
    local rest="$1" env="$2"
    local bindings="${__bs_car[$rest]}"
    local body="${__bs_cdr[$rest]}"

    __bs_new_env "$env"
    local lr_env="$__bs_ret"

    local -a lr_vars=() lr_inits=()
    local b="$bindings"
    while [[ "$b" != 'n:()' ]]; do
        local bnd="${__bs_car[$b]}"
        local var="${__bs_car[$bnd]}"
        lr_vars+=("${var:2}")
        lr_inits+=("${__bs_car[${__bs_cdr[$bnd]}]}")
        __bs_env_bind "$lr_env" "${var:2}" "n:()"    # placeholder
        b="${__bs_cdr[$b]}"
    done

    for (( _k=0; _k<${#lr_vars[@]}; _k++ )); do
        __bs_eval "${lr_inits[$_k]}" "$lr_env" || return 1
        __bs_env_bind "$lr_env" "${lr_vars[$_k]}" "$__bs_ret"
    done

    __bs_eval_seq "$body" "$lr_env"
}

# ── cond ──────────────────────────────────────────────────────────────
__bs_eval_cond() {                    # clauses env
    local clauses="$1" env="$2"
    while [[ "$clauses" != 'n:()' ]]; do
        local clause="${__bs_car[$clauses]}"
        local test_e="${__bs_car[$clause]}"
        local cl_body="${__bs_cdr[$clause]}"

        if [[ "$test_e" == 'y:else' ]]; then
            __bs_eval_seq "$cl_body" "$env"
            return 0
        fi

        __bs_eval "$test_e" "$env" || return 1
        local tv="$__bs_ret"

        if [[ "$tv" != 'b:#f' ]]; then
            if [[ "$cl_body" == 'n:()' ]]; then
                __bs_ret="$tv"
                return 0
            fi
            # => syntax
            if [[ "${__bs_car[$cl_body]}" == 'y:=>' ]]; then
                local arrow_proc_e="${__bs_car[${__bs_cdr[$cl_body]}]}"
                __bs_eval "$arrow_proc_e" "$env" || return 1
                __bs_apply "$__bs_ret" "$tv"
                return 0
            fi
            __bs_eval_seq "$cl_body" "$env"
            return 0
        fi

        clauses="${__bs_cdr[$clauses]}"
    done
    __bs_ret="n:()"
}

# ── case ──────────────────────────────────────────────────────────────
__bs_eval_case() {                    # rest env
    local rest="$1" env="$2"
    __bs_eval "${__bs_car[$rest]}" "$env" || return 1
    local key="$__bs_ret"
    local clauses="${__bs_cdr[$rest]}"

    while [[ "$clauses" != 'n:()' ]]; do
        local clause="${__bs_car[$clauses]}"
        local datums="${__bs_car[$clause]}"
        local cl_body="${__bs_cdr[$clause]}"

        if [[ "$datums" == 'y:else' ]]; then
            __bs_eval_seq "$cl_body" "$env"
            return 0
        fi

        local d="$datums"
        while [[ "$d" != 'n:()' ]]; do
            local datum="${__bs_car[$d]}"
            if [[ "$key" == "$datum" ]]; then
                __bs_eval_seq "$cl_body" "$env"
                return 0
            fi
            d="${__bs_cdr[$d]}"
        done

        clauses="${__bs_cdr[$clauses]}"
    done
    __bs_ret="n:()"
}

# ── do ────────────────────────────────────────────────────────────────
__bs_eval_do() {                      # rest env
    local rest="$1" env="$2"
    local var_specs="${__bs_car[$rest]}"
    local test_clause="${__bs_car[${__bs_cdr[$rest]}]}"
    local commands="${__bs_cdr[${__bs_cdr[$rest]}]}"

    __bs_new_env "$env"
    local do_env="$__bs_ret"

    # Init vars
    local -a do_vars=() do_steps=()
    local vs="$var_specs"
    while [[ "$vs" != 'n:()' ]]; do
        local spec="${__bs_car[$vs]}"
        local dv="${__bs_car[$spec]}"
        local di="${__bs_car[${__bs_cdr[$spec]}]}"
        local ds_rest="${__bs_cdr[${__bs_cdr[$spec]}]}"
        __bs_eval "$di" "$env" || return 1
        __bs_env_bind "$do_env" "${dv:2}" "$__bs_ret"
        do_vars+=("${dv:2}")
        if [[ "$ds_rest" != 'n:()' ]]; then
            do_steps+=("${__bs_car[$ds_rest]}")
        else
            do_steps+=("")
        fi
        vs="${__bs_cdr[$vs]}"
    done

    # Loop
    while true; do
        __bs_eval "${__bs_car[$test_clause]}" "$do_env" || return 1
        if [[ "$__bs_ret" != 'b:#f' ]]; then
            local do_result_exprs="${__bs_cdr[$test_clause]}"
            if [[ "$do_result_exprs" != 'n:()' ]]; then
                __bs_eval_seq "$do_result_exprs" "$do_env"
            else
                __bs_ret="n:()"
            fi
            return 0
        fi
        __bs_eval_seq "$commands" "$do_env"
        # Step
        local -a new_vals=()
        for (( _k=0; _k<${#do_vars[@]}; _k++ )); do
            if [[ -n "${do_steps[$_k]}" ]]; then
                __bs_eval "${do_steps[$_k]}" "$do_env" || return 1
                new_vals+=("$__bs_ret")
            else
                __bs_env_lookup "$do_env" "${do_vars[$_k]}"
                new_vals+=("$__bs_ret")
            fi
        done
        for (( _k=0; _k<${#do_vars[@]}; _k++ )); do
            __bs_env_bind "$do_env" "${do_vars[$_k]}" "${new_vals[$_k]}"
        done
    done
}

# ── quasiquote ────────────────────────────────────────────────────────
__bs_eval_quasiquote() {              # tmpl env
    local tmpl="$1" env="$2"
    if [[ "$tmpl" == p:* ]]; then
        local h="${__bs_car[$tmpl]}"
        if [[ "$h" == 'y:unquote' ]]; then
            __bs_eval "${__bs_car[${__bs_cdr[$tmpl]}]}" "$env"
            return
        fi
        __bs_eval_quasiquote "$h" "$env"
        local qcar="$__bs_ret"
        __bs_eval_quasiquote "${__bs_cdr[$tmpl]}" "$env"
        __bs_cons "$qcar" "$__bs_ret"
    else
        __bs_ret="$tmpl"
    fi
}

# ── Apply ─────────────────────────────────────────────────────────────
__bs_apply() {                        # proc [args...]
    local proc="$1"; shift
    local -a args=("$@")

    case "$proc" in

        # ── Arithmetic ────────────────────────────────────────────────
        'f:+')
            local _s=0
            for _v in "${args[@]}"; do (( _s += ${_v:2} )) || true; done
            __bs_ret="i:$_s" ;;

        'f:-')
            if (( ${#args[@]} == 0 )); then __bs_ret="i:0"
            elif (( ${#args[@]} == 1 )); then __bs_ret="i:$(( -${args[0]:2} ))"
            else
                local _r="${args[0]:2}"
                for (( _k=1; _k<${#args[@]}; _k++ )); do (( _r -= ${args[$_k]:2} )) || true; done
                __bs_ret="i:$_r"
            fi ;;

        'f:*')
            local _p=1
            for _v in "${args[@]}"; do (( _p *= ${_v:2} )) || true; done
            __bs_ret="i:$_p" ;;

        'f:/')
            if (( ${#args[@]} == 1 )); then __bs_ret="i:$(( 1 / ${args[0]:2} ))"
            else
                local _r="${args[0]:2}"
                for (( _k=1; _k<${#args[@]}; _k++ )); do (( _r /= ${args[$_k]:2} )) || true; done
                __bs_ret="i:$_r"
            fi ;;

        'f:quotient')  __bs_ret="i:$(( ${args[0]:2} / ${args[1]:2} ))" ;;
        'f:remainder') __bs_ret="i:$(( ${args[0]:2} % ${args[1]:2} ))" ;;
        'f:modulo')
            local _a="${args[0]:2}" _b="${args[1]:2}"
            local _r=$(( _a % _b ))
            (( _r != 0 && (_r < 0) != (_b < 0) )) && (( _r += _b )) || true
            __bs_ret="i:$_r" ;;
        'f:expt')
            local _base="${args[0]:2}" _exp="${args[1]:2}" _res=1
            for (( _k=0; _k<_exp; _k++ )); do (( _res *= _base )) || true; done
            __bs_ret="i:$_res" ;;
        'f:abs')
            local _n="${args[0]:2}"
            __bs_ret="i:$(( _n < 0 ? -_n : _n ))" ;;
        'f:max')
            local _m="${args[0]:2}"
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                (( ${args[$_k]:2} > _m )) && _m="${args[$_k]:2}"
            done
            __bs_ret="i:$_m" ;;
        'f:min')
            local _m="${args[0]:2}"
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                (( ${args[$_k]:2} < _m )) && _m="${args[$_k]:2}"
            done
            __bs_ret="i:$_m" ;;
        'f:gcd')
            local _a="${args[0]:2}" _b="${args[1]:2}"
            _a=$(( _a < 0 ? -_a : _a )); _b=$(( _b < 0 ? -_b : _b ))
            while (( _b != 0 )); do local _t=$_b; _b=$(( _a % _b )); _a=$_t; done
            __bs_ret="i:$_a" ;;
        'f:lcm')
            local _a="${args[0]:2}" _b="${args[1]:2}"
            local _aa=$(( _a < 0 ? -_a : _a )) _bb=$(( _b < 0 ? -_b : _b ))
            local _g=$_aa _gb=$_bb
            while (( _gb != 0 )); do local _t=$_gb; _gb=$(( _g % _gb )); _g=$_t; done
            (( _g == 0 )) && __bs_ret="i:0" || __bs_ret="i:$(( _aa / _g * _bb ))" ;;

        # ── Comparisons ───────────────────────────────────────────────
        'f:=')
            local _ok=1
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                (( ${args[$((_k-1))]:2} != ${args[$_k]:2} )) && { _ok=0; break; }
            done
            [[ $_ok -eq 1 ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:<')
            local _ok=1
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                (( ${args[$((_k-1))]:2} >= ${args[$_k]:2} )) && { _ok=0; break; }
            done
            [[ $_ok -eq 1 ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:>')
            local _ok=1
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                (( ${args[$((_k-1))]:2} <= ${args[$_k]:2} )) && { _ok=0; break; }
            done
            [[ $_ok -eq 1 ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:<=')
            local _ok=1
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                (( ${args[$((_k-1))]:2} > ${args[$_k]:2} )) && { _ok=0; break; }
            done
            [[ $_ok -eq 1 ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:>=')
            local _ok=1
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                (( ${args[$((_k-1))]:2} < ${args[$_k]:2} )) && { _ok=0; break; }
            done
            [[ $_ok -eq 1 ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:eq?'|'f:eqv?')
            [[ "${args[0]}" == "${args[1]}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:equal?')
            __bs_equal_val "${args[0]}" "${args[1]}" ;;

        # ── Boolean ───────────────────────────────────────────────────
        'f:not')
            [[ "${args[0]}" == 'b:#f' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;

        # ── Type predicates ───────────────────────────────────────────
        'f:number?')   [[ "${args[0]:0:2}" == 'i:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:string?')   [[ "${args[0]:0:2}" == 's:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:symbol?')   [[ "${args[0]:0:2}" == 'y:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:boolean?')  [[ "${args[0]:0:2}" == 'b:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:char?')     [[ "${args[0]:0:2}" == 'c:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:vector?')   [[ "${args[0]:0:2}" == 'v:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:procedure?') [[ "${args[0]:0:2}" == 'f:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:pair?')     [[ "${args[0]:0:2}" == 'p:' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:null?')     [[ "${args[0]}" == 'n:()' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:list?')
            local _cur="${args[0]}"
            while [[ "$_cur" == p:* ]]; do _cur="${__bs_cdr[$_cur]}"; done
            [[ "$_cur" == 'n:()' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:zero?')     [[ "${args[0]}" == 'i:0' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:positive?') (( ${args[0]:2} > 0 )) && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:negative?') (( ${args[0]:2} < 0 )) && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:even?')     (( ${args[0]:2} % 2 == 0 )) && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:odd?')      (( ${args[0]:2} % 2 != 0 )) && __bs_ret="b:#t" || __bs_ret="b:#f" ;;

        # ── Pair / List ───────────────────────────────────────────────
        'f:cons')   __bs_cons "${args[0]}" "${args[1]}" ;;
        'f:car')
            [[ "${args[0]:0:2}" != 'p:' ]] && { __bs_error "car: not a pair: ${args[0]}"; return 1; }
            __bs_ret="${__bs_car[${args[0]}]}" ;;
        'f:cdr')
            [[ "${args[0]:0:2}" != 'p:' ]] && { __bs_error "cdr: not a pair: ${args[0]}"; return 1; }
            __bs_ret="${__bs_cdr[${args[0]}]}" ;;
        'f:set-car!')
            __bs_car["${args[0]}"]="${args[1]}"; __bs_ret="n:()" ;;
        'f:set-cdr!')
            __bs_cdr["${args[0]}"]="${args[1]}"; __bs_ret="n:()" ;;
        'f:list')
            __bs_ret="n:()"
            for (( _k=${#args[@]}-1; _k>=0; _k-- )); do
                __bs_cons "${args[$_k]}" "$__bs_ret"
            done ;;
        'f:length')
            local _cur="${args[0]}" _n=0
            while [[ "$_cur" == p:* ]]; do (( _n++ )); _cur="${__bs_cdr[$_cur]}"; done
            __bs_ret="i:$_n" ;;
        'f:append')
            if (( ${#args[@]} == 0 )); then __bs_ret="n:()"; return; fi
            if (( ${#args[@]} == 1 )); then __bs_ret="${args[0]}"; return; fi
            local _last="${args[-1]}"
            local -a _elems=()
            for (( _k=0; _k<${#args[@]}-1; _k++ )); do
                local _c="${args[$_k]}"
                while [[ "$_c" == p:* ]]; do _elems+=("${__bs_car[$_c]}"); _c="${__bs_cdr[$_c]}"; done
            done
            __bs_ret="$_last"
            for (( _k=${#_elems[@]}-1; _k>=0; _k-- )); do __bs_cons "${_elems[$_k]}" "$__bs_ret"; done ;;
        'f:reverse')
            local _cur="${args[0]}"
            __bs_ret="n:()"
            while [[ "$_cur" == p:* ]]; do
                __bs_cons "${__bs_car[$_cur]}" "$__bs_ret"
                _cur="${__bs_cdr[$_cur]}"
            done ;;
        'f:list-tail')
            local _l="${args[0]}" _n="${args[1]:2}"
            for (( _k=0; _k<_n; _k++ )); do _l="${__bs_cdr[$_l]}"; done
            __bs_ret="$_l" ;;
        'f:list-ref')
            local _l="${args[0]}" _n="${args[1]:2}"
            for (( _k=0; _k<_n; _k++ )); do _l="${__bs_cdr[$_l]}"; done
            __bs_ret="${__bs_car[$_l]}" ;;
        'f:map')
            local _proc="${args[0]}" _lst="${args[1]}"
            local -a _res=()
            while [[ "$_lst" == p:* ]]; do
                __bs_apply "$_proc" "${__bs_car[$_lst]}" || return 1
                _res+=("$__bs_ret")
                _lst="${__bs_cdr[$_lst]}"
            done
            __bs_ret="n:()"
            for (( _k=${#_res[@]}-1; _k>=0; _k-- )); do __bs_cons "${_res[$_k]}" "$__bs_ret"; done ;;
        'f:for-each')
            local _proc="${args[0]}" _lst="${args[1]}"
            while [[ "$_lst" == p:* ]]; do
                __bs_apply "$_proc" "${__bs_car[$_lst]}" || return 1
                _lst="${__bs_cdr[$_lst]}"
            done
            __bs_ret="n:()" ;;
        'f:filter')
            local _proc="${args[0]}" _lst="${args[1]}"
            local -a _res=()
            while [[ "$_lst" == p:* ]]; do
                local _elem="${__bs_car[$_lst]}"
                __bs_apply "$_proc" "$_elem" || return 1
                [[ "$__bs_ret" != 'b:#f' ]] && _res+=("$_elem")
                _lst="${__bs_cdr[$_lst]}"
            done
            __bs_ret="n:()"
            for (( _k=${#_res[@]}-1; _k>=0; _k-- )); do __bs_cons "${_res[$_k]}" "$__bs_ret"; done ;;
        'f:foldl'|'f:fold-left')
            local _proc="${args[0]}" _acc="${args[1]}" _lst="${args[2]}"
            while [[ "$_lst" == p:* ]]; do
                __bs_apply "$_proc" "${__bs_car[$_lst]}" "$_acc" || return 1
                _acc="$__bs_ret"; _lst="${__bs_cdr[$_lst]}"
            done
            __bs_ret="$_acc" ;;
        'f:foldr'|'f:fold-right')
            local _proc="${args[0]}" _init="${args[1]}" _lst="${args[2]}"
            local -a _es=()
            while [[ "$_lst" == p:* ]]; do _es+=("${__bs_car[$_lst]}"); _lst="${__bs_cdr[$_lst]}"; done
            __bs_ret="$_init"
            for (( _k=${#_es[@]}-1; _k>=0; _k-- )); do
                __bs_apply "$_proc" "${_es[$_k]}" "$__bs_ret" || return 1
            done ;;
        'f:assoc'|'f:assv'|'f:assq')
            local _key="${args[0]}" _al="${args[1]}"
            while [[ "$_al" == p:* ]]; do
                local _pair="${__bs_car[$_al]}"
                if [[ "${__bs_car[$_pair]}" == "$_key" ]]; then __bs_ret="$_pair"; return; fi
                _al="${__bs_cdr[$_al]}"
            done
            __bs_ret="b:#f" ;;
        'f:member'|'f:memv'|'f:memq')
            local _elem="${args[0]}" _lst="${args[1]}"
            while [[ "$_lst" == p:* ]]; do
                [[ "${__bs_car[$_lst]}" == "$_elem" ]] && { __bs_ret="$_lst"; return; }
                _lst="${__bs_cdr[$_lst]}"
            done
            __bs_ret="b:#f" ;;

        # ── String ────────────────────────────────────────────────────
        'f:string-length')
            local _sl="${args[0]:2}"
            __bs_ret="i:${#_sl}" ;;
        'f:string-append')
            local _r=""
            for _v in "${args[@]}"; do _r+="${_v:2}"; done
            __bs_ret="s:$_r" ;;
        'f:substring')
            local _s="${args[0]:2}" _st="${args[1]:2}" _en="${args[2]:2}"
            __bs_ret="s:${_s:$_st:$(( _en - _st ))}" ;;
        'f:string->number')
            local _s="${args[0]:2}"
            [[ "$_s" =~ ^-?[0-9]+$ ]] && __bs_ret="i:$_s" || __bs_ret="b:#f" ;;
        'f:number->string')  __bs_ret="s:${args[0]:2}" ;;
        'f:string->symbol')  __bs_ret="y:${args[0]:2}" ;;
        'f:symbol->string')  __bs_ret="s:${args[0]:2}" ;;
        'f:string=?')  [[ "${args[0]:2}" == "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:string<?')  [[ "${args[0]:2}" < "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:string>?')  [[ "${args[0]:2}" > "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:string<=?') [[ "${args[0]:2}" < "${args[1]:2}" || "${args[0]:2}" == "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:string>=?') [[ "${args[0]:2}" > "${args[1]:2}" || "${args[0]:2}" == "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:string-ref')
            local _s="${args[0]:2}" _i="${args[1]:2}"
            __bs_ret="c:${_s:$_i:1}" ;;
        'f:string')
            local _r=""
            for _v in "${args[@]}"; do _r+="${_v:2}"; done
            __bs_ret="s:$_r" ;;
        'f:make-string')
            local _n="${args[0]:2}" _fill="${args[1]:2:1}"
            [[ -z "$_fill" ]] && _fill=' '
            local _r=""
            for (( _k=0; _k<_n; _k++ )); do _r+="$_fill"; done
            __bs_ret="s:$_r" ;;
        'f:string-copy')  __bs_ret="${args[0]}" ;;
        'f:string-upcase')
            local _su="${args[0]:2}"
            __bs_ret="s:${_su^^}" ;;
        'f:string-downcase')
            local _sd="${args[0]:2}"
            __bs_ret="s:${_sd,,}" ;;
        'f:string->list')
            local _sl="${args[0]:2}" _lst="n:()"
            local _si
            for (( _si=${#_sl}-1; _si>=0; _si-- )); do
                __bs_cons "c:${_sl:$_si:1}" "$_lst"
                _lst="$__bs_ret"
            done
            __bs_ret="$_lst" ;;
        'f:list->string')
            local _ls="" _cur="${args[0]}"
            while [[ "$_cur" != "n:()" ]]; do
                _ls+="${__bs_car[$_cur]:2}"
                _cur="${__bs_cdr[$_cur]}"
            done
            __bs_ret="s:$_ls" ;;

        # ── Char ──────────────────────────────────────────────────────
        'f:char->integer')
            local _c="${args[0]:2}"
            printf -v __bs_ret 'i:%d' "'$_c" ;;
        'f:integer->char')
            local _n="${args[0]:2}"
            __bs_ret="c:$(printf "\\x$(printf '%x' "$_n")")" ;;
        'f:char=?') [[ "${args[0]:2}" == "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:char<?') [[ "${args[0]:2}" < "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:char-alphabetic?') [[ "${args[0]:2}" =~ [a-zA-Z] ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:char-numeric?') [[ "${args[0]:2}" =~ [0-9] ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;

        # ── I/O ───────────────────────────────────────────────────────
        'f:display')
            __bs_display "${args[0]}"
            printf '%s' "$__bs_ret" >&2
            __bs_ret="n:()" ;;
        'f:write')
            __bs_write "${args[0]}"
            printf '%s' "$__bs_ret" >&2
            __bs_ret="n:()" ;;
        'f:newline')
            printf '\n' >&2
            __bs_ret="n:()" ;;
        'f:read-line')
            IFS= read -r __bs_tmp_readline
            __bs_ret="s:${__bs_tmp_readline}" ;;

        # ── Terminal I/O (bash-only) ─────────────────────────────────
        'f:read-byte')
            local _ch
            IFS= read -ru${_BS_IN_FD:-0} -n1 -d '' _ch
            if [[ $? -ne 0 && -z "$_ch" ]]; then
                __bs_ret="b:#f"
            elif [[ -z "$_ch" ]]; then
                __bs_ret="i:0"
            else
                local _ord
                printf -v _ord '%d' "'$_ch" 2>/dev/null || _ord=0
                __bs_ret="i:$_ord"
            fi ;;
        'f:read-byte-timeout')
            local _secs="${args[0]:2}" _ch
            IFS= read -ru${_BS_IN_FD:-0} -n1 -d '' -t "$_secs" _ch
            if [[ $? -ne 0 && -z "$_ch" ]]; then
                __bs_ret="b:#f"
            elif [[ -z "$_ch" ]]; then
                __bs_ret="i:0"
            else
                local _ord
                printf -v _ord '%d' "'$_ch" 2>/dev/null || _ord=0
                __bs_ret="i:$_ord"
            fi ;;
        'f:write-stdout')
            printf '%s' "${args[0]:2}"
            __bs_ret="n:()" ;;
        'f:terminal-size')
            local _rows _cols
            if [[ -n "${LINES:-}" && -n "${COLUMNS:-}" ]]; then
                _rows="$LINES"
                _cols="$COLUMNS"
            else
                _rows=$(tput lines 2>/dev/null) || _rows=0
                _cols=$(tput cols 2>/dev/null) || _cols=0
            fi
            if (( _rows <= 0 || _cols <= 0 )); then
                local _sz
                _sz=$(stty size 2>/dev/null) || _sz="0 0"
                (( _rows <= 0 )) && _rows="${_sz%% *}"
                (( _cols <= 0 )) && _cols="${_sz##* }"
            fi
            (( _rows <= 0 )) && _rows=24
            (( _cols <= 0 )) && _cols=80
            __bs_cons "i:$_rows" "i:$_cols" ;;
        'f:terminal-raw!')
            __bs_stty_saved=$(stty -g 2>/dev/null)
            stty raw -echo -isig -ixon -ixoff -icrnl intr undef quit undef susp undef lnext undef 2>/dev/null
            stty dsusp undef 2>/dev/null || true   # macOS only; ignore on Linux
            # Start dd coprocess as sole TTY reader — avoids tcsetattr(TCSADRAIN) on every read-byte
            if [[ -t 0 ]]; then
                coproc __bs_tty (dd bs=1 status=none < /dev/tty 2>/dev/null)
                _BS_IN_FD=${__bs_tty[0]}
                exec 0</dev/null   # close parent's TTY stdin to avoid race with coprocess
            fi
            __bs_ret="n:()" ;;
        'f:terminal-restore!')
            if [[ -n "${__bs_tty_PID:-}" ]]; then
                kill "$__bs_tty_PID" 2>/dev/null; wait "$__bs_tty_PID" 2>/dev/null || true
                exec 0</dev/tty   # reattach stdin to controlling terminal
                _BS_IN_FD=0
            fi
            if [[ -n "$__bs_stty_saved" ]]; then
                stty "$__bs_stty_saved" 2>/dev/null || stty sane 2>/dev/null
                __bs_stty_saved=""
            fi
            __bs_ret="n:()" ;;
        'f:file-read')
            local _path="${args[0]:2}" _content
            if [[ -f "$_path" ]] && _content=$(cat "$_path" 2>/dev/null); then
                __bs_ret="s:$_content"
            else
                __bs_ret="b:#f"
            fi ;;
        'f:file-write')
            local _path="${args[0]:2}" _content="${args[1]:2}"
            if { printf '%s\n' "$_content" > "$_path"; } 2>/dev/null; then
                __bs_ret="b:#t"
            else
                __bs_ret="b:#f"
            fi ;;
        'f:eval-string')
            local _src="${args[0]:2}"
            local -a _saved_tokens=("${__bs_tokens[@]}")
            local _saved_tpos="$__bs_tpos"
            __bs_last_error=""
            __bs_tokenize "$_src"
            __bs_tpos=0
            __bs_ret="n:()"
            local _eval_ok=1
            while (( __bs_tpos < ${#__bs_tokens[@]} )); do
                if ! __bs_parse_expr; then _eval_ok=0; break; fi
                if ! __bs_eval "$__bs_ret" "0"; then _eval_ok=0; break; fi
            done
            local _result_val="$__bs_ret"
            __bs_tokens=("${_saved_tokens[@]}")
            __bs_tpos="$_saved_tpos"
            if (( _eval_ok )); then
                __bs_display "$_result_val"
                local _disp="$__bs_ret"
                __bs_cons "b:#t" "s:$_disp"
            else
                local _err="${__bs_last_error:-unknown error}"
                __bs_cons "b:#f" "s:$_err"
            fi ;;

        # ── Terminal / File / Shell extensions ────────────────────────
        'f:terminal-suspend!')
            kill -TSTP $$ 2>/dev/null
            __bs_ret="n:()" ;;
        'f:file-glob')
            local _pat="${args[0]:2}" _f
            local -a _matches=()
            for _f in ${_pat}*; do
                [[ -e "$_f" ]] || continue
                _matches+=("$_f")
            done
            local _list="n:()"
            local -i _gi
            for (( _gi=${#_matches[@]}-1; _gi>=0; _gi-- )); do
                __bs_cons "s:${_matches[$_gi]}" "$_list"
                _list="$__bs_ret"
            done
            __bs_ret="$_list" ;;
        'f:file-directory?')
            [[ -d "${args[0]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:file-write-atomic')
            local _path="${args[0]:2}" _content="${args[1]:2}"
            local _tmp="${_path}.em$$"
            if { printf '%s\n' "$_content" > "$_tmp"; } 2>/dev/null && mv -f "$_tmp" "$_path" 2>/dev/null; then
                __bs_ret="b:#t"
            else
                rm -f "$_tmp" 2>/dev/null
                __bs_ret="b:#f"
            fi ;;
        'f:shell-capture')
            local _out
            _out=$(eval "${args[0]:2}" 2>/dev/null) && __bs_ret="s:$_out" || __bs_ret="b:#f" ;;
        'f:shell-exec')
            printf '%s' "${args[1]:2}" | eval "${args[0]:2}" 2>/dev/null
            [[ $? -eq 0 ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;

        # ── Vector ────────────────────────────────────────────────────
        'f:make-vector')
            local _id="v:${__bs_heap_next}"
            (( __bs_heap_next++ )) || true
            local _n="${args[0]:2}" _fill="${args[1]:-i:0}"
            __bs_env["${_id}:__len"]="$_n"
            for (( _k=0; _k<_n; _k++ )); do __bs_env["${_id}:${_k}"]="$_fill"; done
            __bs_ret="$_id" ;;
        'f:vector')
            local _id="v:${__bs_heap_next}"
            (( __bs_heap_next++ )) || true
            local _n=${#args[@]}
            __bs_env["${_id}:__len"]="$_n"
            for (( _k=0; _k<_n; _k++ )); do __bs_env["${_id}:${_k}"]="${args[$_k]}"; done
            __bs_ret="$_id" ;;
        'f:vector-ref')
            __bs_ret="${__bs_env[${args[0]}:${args[1]:2}]}" ;;
        'f:vector-set!')
            __bs_env["${args[0]}:${args[1]:2}"]="${args[2]}"
            __bs_ret="n:()" ;;
        'f:vector-length')
            __bs_ret="i:${__bs_env[${args[0]}:__len]}" ;;
        'f:vector->list')
            local _vid="${args[0]}" _n="${__bs_env[${args[0]}:__len]}"
            __bs_ret="n:()"
            for (( _k=_n-1; _k>=0; _k-- )); do __bs_cons "${__bs_env[${_vid}:${_k}]}" "$__bs_ret"; done ;;
        'f:list->vector')
            local _id="v:${__bs_heap_next}"
            (( __bs_heap_next++ )) || true
            local -a _es=()
            local _lst="${args[0]}"
            while [[ "$_lst" == p:* ]]; do _es+=("${__bs_car[$_lst]}"); _lst="${__bs_cdr[$_lst]}"; done
            __bs_env["${_id}:__len"]="${#_es[@]}"
            for (( _k=0; _k<${#_es[@]}; _k++ )); do __bs_env["${_id}:${_k}"]="${_es[$_k]}"; done
            __bs_ret="$_id" ;;

        # ── Exact/inexact (identity for integers) ─────────────────────
        'f:exact->inexact'|'f:inexact->exact'|'f:exact'|'f:inexact'| \
        'f:floor'|'f:ceiling'|'f:round'|'f:truncate')
            __bs_ret="${args[0]}" ;;

        # ── apply (as first-class function) ───────────────────────────
        'f:apply')
            local _inner="${args[0]}"
            local -a _aargs=()
            for (( _k=1; _k<${#args[@]}-1; _k++ )); do _aargs+=("${args[$_k]}"); done
            local _last_arg="${args[-1]}"
            while [[ "$_last_arg" == p:* ]]; do
                _aargs+=("${__bs_car[$_last_arg]}")
                _last_arg="${__bs_cdr[$_last_arg]}"
            done
            __bs_apply "$_inner" "${_aargs[@]}"
            return $? ;;

        # ── error ─────────────────────────────────────────────────────
        'f:error')
            local _msg="${args[0]:2}"
            local _irr=""
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                __bs_display "${args[$_k]}"
                _irr+=" ${__bs_ret}"
            done
            __bs_error "$_msg$_irr"
            return 1 ;;

        # ── call/cc (stub) ────────────────────────────────────────────
        'f:call-with-current-continuation'|'f:call/cc')
            __bs_make_closure "y:_k" "n:()" "0"
            local _dummy="$__bs_ret"
            __bs_apply "${args[0]}" "$_dummy"
            return $? ;;

        # ── values / call-with-values (simplified) ────────────────────
        'f:values')
            [[ ${#args[@]} -gt 0 ]] && __bs_ret="${args[0]}" || __bs_ret="n:()" ;;
        'f:call-with-values')
            __bs_apply "${args[0]}"
            __bs_apply "${args[1]}" "$__bs_ret"
            return $? ;;

        # ── with-exception-handler / raise (stub) ─────────────────────
        'f:with-exception-handler')
            __bs_apply "${args[1]}" || true
            __bs_ret="n:()"  ;;
        'f:raise'|'f:raise-continuable')
            __bs_display "${args[0]}"
            __bs_error "uncaught raise: $__bs_ret"
            return 1 ;;

        # ── Closure application ───────────────────────────────────────
        f:*)
            local _params="${__bs_closure_params[$proc]:-}"
            local _body="${__bs_closure_body[$proc]:-}"
            local _cenv="${__bs_closure_env[$proc]:-}"

            if [[ -z "$_body" ]]; then
                __bs_error "apply: not a procedure: $proc"
                return 1
            fi

            __bs_new_env "$_cenv"
            local _call_env="$__bs_ret"

            # Bind parameters
            local _k=0
            local _params_cur="$_params"

            if [[ "$_params_cur" == y:* ]]; then
                # Variadic: (lambda args body)
                __bs_ret="n:()"
                for (( _j=${#args[@]}-1; _j>=0; _j-- )); do
                    __bs_cons "${args[$_j]}" "$__bs_ret"
                done
                __bs_env_bind "$_call_env" "${_params_cur:2}" "$__bs_ret"
            else
                while [[ "$_params_cur" != 'n:()' && -n "$_params_cur" ]]; do
                    local _p="${__bs_car[$_params_cur]}"
                    local _nxt="${__bs_cdr[$_params_cur]}"
                    if [[ "$_nxt" == y:* ]]; then
                        # Dotted rest
                        __bs_env_bind "$_call_env" "${_p:2}" "${args[$_k]:-n:()}"
                        (( _k++ )) || true
                        local _rest_list="n:()"
                        for (( _j=${#args[@]}-1; _j>=_k; _j-- )); do
                            __bs_cons "${args[$_j]}" "$_rest_list"
                            _rest_list="$__bs_ret"
                        done
                        __bs_env_bind "$_call_env" "${_nxt:2}" "$_rest_list"
                        _params_cur="n:()"
                        break
                    fi
                    __bs_env_bind "$_call_env" "${_p:2}" "${args[$_k]:-n:()}"
                    (( _k++ )) || true
                    _params_cur="$_nxt"
                done
            fi

            __bs_eval_seq "$_body" "$_call_env"
            return $? ;;

        *)
            __bs_error "apply: not a procedure: $proc"
            return 1 ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────────────
# Global interpreter state
# ──────────────────────────────────────────────────────────────────────────────
declare -gA __bs_car=() __bs_cdr=()
declare -gA __bs_closure_params=() __bs_closure_body=() __bs_closure_env=()
declare -gA __bs_env=() __bs_env_parent=()
declare -g __bs_heap_next=0 __bs_env_next=1
declare -g __bs_last="" __bs_last_display="" __bs_ret=""
declare -g __bs_last_error=""
declare -g __bs_stty_saved=""
declare -ga __bs_tokens=()
declare -g __bs_tpos=0

# ──────────────────────────────────────────────────────────────────────────────
# bs - evaluate Scheme source inline (no subshell overhead)
#
# All state lives in global variables.  Top-level define/set! export values
# directly via declare -g.  After calling bs(), the result is available in
# $__bs_last (tagged) and $__bs_last_display (human-readable).
# ──────────────────────────────────────────────────────────────────────────────
bs() {
    local _src="$1" _bs_old_opts=""
    # Save and disable errexit — arithmetic (( )) returning 0 is exit code 1
    [[ $- == *e* ]] && _bs_old_opts="e" && set +e
    __bs_tokenize "$_src"
    __bs_tpos=0
    __bs_ret="n:()"
    while (( __bs_tpos < ${#__bs_tokens[@]} )); do
        __bs_parse_expr || break
        __bs_eval "$__bs_ret" "0" || true
    done
    __bs_last="$__bs_ret"
    __bs_display "$__bs_last"
    __bs_last_display="$__bs_ret"
    [[ -n "$_bs_old_opts" ]] && set -e
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# bs-reset: wipe interpreter state (call between independent sessions)
# ──────────────────────────────────────────────────────────────────────────────
bs-reset() {
    __bs_car=() __bs_cdr=()
    __bs_closure_params=() __bs_closure_body=() __bs_closure_env=()
    __bs_env=() __bs_env_parent=()
    __bs_heap_next=0 __bs_env_next=1
    __bs_last="" __bs_last_display="" __bs_ret=""
    __bs_last_error=""
    # Note: __bs_stty_saved is NOT reset (must survive for safety-net traps)
    __bs_tokens=() __bs_tpos=0
}

# ──────────────────────────────────────────────────────────────────────────────
# bs-eval: convenience wrapper - evaluate and print human-readable result
# ──────────────────────────────────────────────────────────────────────────────
bs-eval() {
    bs "$1"
    printf '%s\n' "$__bs_last_display"
}

# ══════════════════════════════════════════════════════════════════════════════
# AOT Compiler: Scheme → Bash
# ══════════════════════════════════════════════════════════════════════════════
#
# bs-compile <source> — transpile Scheme source to native bash code.
# Output is a self-contained bash script (functions + global variable decls).
#
# Design:
#   - Unboxed values: ints are bash ints, strings are bash strings, bools 0/1
#   - Return convention: __r global for function results, $(( )) for arith
#   - Name mangling: hyphen→_, ?→_p, !→_x, >→_to_, *→_star_
#   - Vectors: bash indexed arrays
#   - Lists: bash arrays (cons=prepend, car=[0], null?=length check)

# ── Name mangling ────────────────────────────────────────────────────────────
__bsc_mangle() {
    local name="$1" r=""
    local i c
    for (( i=0; i<${#name}; i++ )); do
        c="${name:$i:1}"
        case "$c" in
            '-') r+='_' ;;
            '?') r+='_p' ;;
            '!') r+='_x' ;;
            '>') r+='_to_' ;;
            '<') r+='_lt_' ;;
            '*') r+='_star_' ;;
            '/') r+='_sl_' ;;
            '=') r+='_eq_' ;;
            '+') r+='_plus_' ;;
            '%') r+='_pct_' ;;
            '@') r+='_at_' ;;
            '#') r+='_hash_' ;;
            '.') r+='_dot_' ;;
            [a-zA-Z0-9_]) r+="$c" ;;
            *) r+='_' ;;
        esac
    done
    # Rename variables that clash with zsh special read-only names
    if [[ "$__bsc_target" == "zsh" ]]; then
        case "$r" in
            status|pipestatus|funcstack|funcfiletrace|funcsourcetrace|\
            LINENO|FUNCNAME|BASH_SOURCE) r="__sc_${r}" ;;
        esac
    fi
    __bsc_ret="$r"
}

# ── Compiler globals ─────────────────────────────────────────────────────────
declare -g __bsc_ret=""
declare -g __bsc_out=""          # accumulated output
declare -g __bsc_indent=""       # current indentation
declare -gA __bsc_globals=()     # set of global variable names (mangled)
declare -gA __bsc_funcs=()       # set of function names (mangled)
declare -gA __bsc_int_vars=()    # variables known to be integer-typed
declare -gA __bsc_pair_vars=()   # variables known to be 2-element pairs
declare -gA __bsc_arr_vars=()    # variables known to be arrays (vectors/lists)
declare -g  __bsc_in_func=0      # 1 when inside a function definition
declare -g __bsc_list_n=0        # counter for temp list variables
declare -g __bsc_target="bash"   # output target: "bash" or "zsh"

# ── Output helpers ───────────────────────────────────────────────────────────
__bsc_line() { __bsc_out+="${__bsc_indent}$1"$'\n'; }
# Emit "local ..." or "declare ..." depending on scope
__bsc_local() {
    local kw="local"
    if ! (( __bsc_in_func )); then
        [[ "$__bsc_target" == "zsh" ]] && kw="typeset" || kw="declare"
    fi
    __bsc_line "$kw $1"
}
__bsc_push_indent() { __bsc_indent+="    "; }
__bsc_pop_indent() { __bsc_indent="${__bsc_indent%    }"; }

# ── AST walking helpers ──────────────────────────────────────────────────────
# List a cons-list into a bash array __bsc_list_result
__bsc_list_to_array() {
    local cur="$1"
    __bsc_list_result=()
    while [[ "$cur" == p:* ]]; do
        __bsc_list_result+=("${__bs_car[$cur]}")
        cur="${__bs_cdr[$cur]}"
    done
}

# Get length of a cons-list
__bsc_list_length() {
    local cur="$1" n=0
    while [[ "$cur" == p:* ]]; do (( n++ )); cur="${__bs_cdr[$cur]}"; done
    __bsc_ret="$n"
}

# ── Emit expression as bash string (returns result in __bsc_ret) ─────────────
# mode: "stmt" = statement context, "expr" = need value, "test" = boolean test
__bsc_emit_expr() {
    local expr="$1" mode="${2:-expr}"
    __bsc_is_pair=0

    case "${expr:0:2}" in
        'i:')  # integer literal
            __bsc_ret="${expr:2}"
            return 0 ;;
        'b:')  # boolean literal
            if [[ "$expr" == 'b:#t' ]]; then __bsc_ret="1"
            else __bsc_ret="0"; fi
            return 0 ;;
        's:')  # string literal — needs quoting
            local s="${expr:2}"
            if [[ "$s" == *$'\n'* || "$s" == *$'\t'* ]]; then
                # Use $'...' quoting for strings with newlines/tabs
                s="${s//\\/\\\\}"
                local _sq="'" _bsq="\\'"
                s="${s//$_sq/$_bsq}"
                s="${s//$'\n'/\\n}"
                s="${s//$'\t'/\\t}"
                __bsc_ret="\$'${s}'"
            else
                # Regular double-quoted string
                s="${s//\\/\\\\}"
                s="${s//\"/\\\"}"
                s="${s//\$/\\\$}"
                s="${s//\`/\\\`}"
                __bsc_ret="\"${s}\""
            fi
            return 0 ;;
        'c:')  # character literal
            local ch="${expr:2}"
            case "$ch" in
                $'\n') __bsc_ret="\$'\\n'" ;;
                $'\t') __bsc_ret="\$'\\t'" ;;
                ' ')   __bsc_ret="\" \"" ;;
                \\)    __bsc_ret="\"\\\\\""  ;;
                '"')   __bsc_ret="'\"'" ;;
                \$)    __bsc_ret="'\$'" ;;
                \`)    __bsc_ret="'\`'" ;;
                *)     __bsc_ret="\"${ch}\"" ;;
            esac
            return 0 ;;
        'n:')  # null / empty list
            __bsc_ret='()'
            return 0 ;;
        'y:')  # variable reference
            local vname="${expr:2}"
            __bsc_mangle "$vname"
            local mangled="$__bsc_ret"
            if [[ "$mode" == "test" ]]; then
                # In test context, check truthiness
                if [[ -n "${__bsc_int_vars[$mangled]:-}" ]]; then
                    __bsc_ret="(( $mangled ))"
                else
                    __bsc_ret="[[ -n \"\$$mangled\" && \"\$$mangled\" != \"0\" ]]"
                fi
            else
                __bsc_ret="\$$mangled"
            fi
            return 0 ;;
        'p:')  # list — function call or special form
            ;;
        *)
            __bsc_ret="\"\"  # unknown: $expr"
            return 0 ;;
    esac

    # ── List: special form or function call ──
    local head="${__bs_car[$expr]}"
    local rest="${__bs_cdr[$expr]}"

    case "$head" in

        # ── quote ─────────────────────────────────────────────────────────
        'y:quote')
            __bsc_emit_quote "${__bs_car[$rest]}"
            return 0 ;;

        # ── if ────────────────────────────────────────────────────────────
        'y:if')
            __bsc_emit_if "$rest" "$mode"
            return 0 ;;

        # ── when ──────────────────────────────────────────────────────────
        'y:when')
            __bsc_emit_when "$rest" "$mode"
            return 0 ;;

        # ── unless ────────────────────────────────────────────────────────
        'y:unless')
            __bsc_emit_unless "$rest" "$mode"
            return 0 ;;

        # ── begin ─────────────────────────────────────────────────────────
        'y:begin')
            __bsc_emit_begin "$rest" "$mode"
            return 0 ;;

        # ── define ────────────────────────────────────────────────────────
        'y:define')
            __bsc_emit_define "$rest"
            return 0 ;;

        # ── set! ──────────────────────────────────────────────────────────
        'y:set!')
            __bsc_emit_set "$rest"
            return 0 ;;

        # ── let / let* ────────────────────────────────────────────────────
        'y:let')
            __bsc_emit_let "$rest" "$mode"
            return 0 ;;
        'y:let*')
            __bsc_emit_letstar "$rest" "$mode"
            return 0 ;;
        'y:letrec'|'y:letrec*')
            __bsc_emit_letstar "$rest" "$mode"
            return 0 ;;

        # ── cond ──────────────────────────────────────────────────────────
        'y:cond')
            __bsc_emit_cond "$rest" "$mode"
            return 0 ;;

        # ── case ──────────────────────────────────────────────────────────
        'y:case')
            __bsc_emit_case "$rest" "$mode"
            return 0 ;;

        # ── and / or / not ────────────────────────────────────────────────
        'y:and')
            __bsc_emit_and "$rest" "$mode"
            return 0 ;;
        'y:or')
            __bsc_emit_or "$rest" "$mode"
            return 0 ;;
        'y:not')
            __bsc_emit_not "$rest" "$mode"
            return 0 ;;

        # ── do ────────────────────────────────────────────────────────────
        'y:do')
            __bsc_emit_do "$rest" "$mode"
            return 0 ;;

        # ── lambda ────────────────────────────────────────────────────────
        'y:lambda')
            __bsc_emit_lambda "$rest"
            return 0 ;;

        # ── apply ─────────────────────────────────────────────────────────
        'y:apply')
            __bsc_emit_apply "$rest" "$mode"
            return 0 ;;

        # ── Builtin operations — dispatch to specialized emitters ─────────
        'y:+'|'y:-'|'y:*'|'y:/'|'y:quotient'|'y:remainder'|'y:modulo'| \
        'y:expt'|'y:abs'|'y:max'|'y:min')
            __bsc_emit_arith "$head" "$rest" "$mode"
            return 0 ;;

        'y:='|'y:<'|'y:>'|'y:<='|'y:>='|'y:zero?'|'y:positive?'|'y:negative?'| \
        'y:even?'|'y:odd?')
            __bsc_emit_num_cmp "$head" "$rest" "$mode"
            return 0 ;;

        'y:equal?'|'y:eq?'|'y:eqv?'|'y:string=?'|'y:string<?'|'y:string>?'| \
        'y:string<=?'|'y:string>=?'|'y:char=?'|'y:char<?'|'y:char>=?')
            __bsc_emit_str_cmp "$head" "$rest" "$mode"
            return 0 ;;

        'y:string-append'|'y:string-length'|'y:substring'|'y:string-ref'| \
        'y:string'|'y:make-string'|'y:string-copy'|'y:string-upcase'| \
        'y:string-downcase'|'y:number->string'|'y:string->number'| \
        'y:string->symbol'|'y:symbol->string'|'y:string-repeat')
            __bsc_emit_string_op "$head" "$rest" "$mode"
            return 0 ;;

        'y:char->integer'|'y:integer->char'|'y:char-alphabetic?'| \
        'y:char-numeric?'|'y:char-word?')
            __bsc_emit_char_op "$head" "$rest" "$mode"
            return 0 ;;

        'y:not'|'y:boolean?'|'y:number?'|'y:string?'|'y:symbol?'| \
        'y:pair?'|'y:null?'|'y:list?'|'y:procedure?'|'y:vector?'|'y:char?')
            __bsc_emit_type_pred "$head" "$rest" "$mode"
            return 0 ;;

        'y:vector-ref'|'y:vector-set!'|'y:vector-length'|'y:make-vector'| \
        'y:vector'|'y:vector-ref-safe'|'y:vector->list'|'y:list->vector'| \
        'y:vector-insert'|'y:vector-remove')
            __bsc_emit_vector_op "$head" "$rest" "$mode"
            return 0 ;;

        'y:cons'|'y:car'|'y:cdr'|'y:list'|'y:length'|'y:append'|'y:reverse'| \
        'y:list-ref'|'y:list-tail'|'y:null?')
            __bsc_emit_list_op "$head" "$rest" "$mode"
            return 0 ;;

        'y:map'|'y:for-each'|'y:filter')
            __bsc_emit_higher_order "$head" "$rest" "$mode"
            return 0 ;;

        'y:display'|'y:write'|'y:newline'|'y:write-stdout'|'y:read-byte'| \
        'y:read-byte-timeout'|'y:read-line')
            __bsc_emit_io "$head" "$rest" "$mode"
            return 0 ;;

        'y:terminal-size'|'y:terminal-raw!'|'y:terminal-restore!'| \
        'y:terminal-suspend!')
            __bsc_emit_terminal "$head" "$rest" "$mode"
            return 0 ;;

        'y:file-read'|'y:file-write'|'y:file-write-atomic'|'y:file-glob'| \
        'y:file-directory?')
            __bsc_emit_file_op "$head" "$rest" "$mode"
            return 0 ;;

        'y:shell-capture'|'y:shell-exec')
            __bsc_emit_shell_op "$head" "$rest" "$mode"
            return 0 ;;

        'y:eval-string')
            __bsc_emit_eval_string "$rest" "$mode"
            return 0 ;;

        'y:error')
            __bsc_emit_error "$rest"
            return 0 ;;

        # ── User-defined function call ────────────────────────────────────
        'y:'*)
            __bsc_emit_call "$head" "$rest" "$mode"
            return 0 ;;
    esac

    # Fallback: emit as comment
    __bsc_ret="# unhandled: $head"
    __bsc_line "$__bsc_ret"
}

# ── Quote ─────────────────────────────────────────────────────────────────────
__bsc_emit_quote() {
    local val="$1"
    case "${val:0:2}" in
        'i:') __bsc_ret="${val:2}" ;;
        's:')
            local s="${val:2}"
            s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//\$/\\\$}"; s="${s//\`/\\\`}"
            __bsc_ret="\"${s}\"" ;;
        'b:') [[ "$val" == 'b:#t' ]] && __bsc_ret="1" || __bsc_ret="0" ;;
        'n:') __bsc_ret="()" ;;  # '() → empty array
        'c:') __bsc_ret="\"${val:2}\"" ;;
        'p:')
            # quoted list → bash array literal
            local items="" cur="$val"
            while [[ "$cur" == p:* ]]; do
                __bsc_emit_quote "${__bs_car[$cur]}"
                [[ -n "$items" ]] && items+=" "
                items+="$__bsc_ret"
                cur="${__bs_cdr[$cur]}"
            done
            __bsc_ret="($items)" ;;
        *) __bsc_ret="\"\"" ;;
    esac
}

# ── If ────────────────────────────────────────────────────────────────────────
__bsc_emit_if() {
    local rest="$1" mode="$2"
    local test_e="${__bs_car[$rest]}"
    local branches="${__bs_cdr[$rest]}"
    local then_e="${__bs_car[$branches]}"
    local else_rest="${__bs_cdr[$branches]}"

    local test_str
    __bsc_emit_test "$test_e"
    test_str="$__bsc_ret"

    # Enable return context if this if is used as expression (mode=expr) or already in rc
    local _save_rc="${__bsc_return_ctx:-}"
    [[ "$mode" == "expr" ]] && __bsc_return_ctx=1

    __bsc_line "if $test_str; then"
    __bsc_push_indent
    __bsc_emit_expr "$then_e" "stmt"
    if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
        if [[ "${__bsc_return_ctx:-}" == 1 ]]; then
            [[ "$__bsc_ret" != "\$__r" ]] && __bsc_line "__r=$__bsc_ret"
        else
            __bsc_line "$__bsc_ret"
        fi
    fi
    __bsc_pop_indent

    if [[ "$else_rest" != 'n:()' ]]; then
        local else_e="${__bs_car[$else_rest]}"
        # Check for elif pattern: else branch is another if
        if [[ "${else_e:0:2}" == "p:" && "${__bs_car[$else_e]}" == "y:if" ]]; then
            __bsc_indent="${__bsc_indent}" __bsc_emit_elif "${__bs_cdr[$else_e]}" "$mode"
        else
            __bsc_line "else"
            __bsc_push_indent
            __bsc_emit_expr "$else_e" "stmt"
            if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
                if [[ "${__bsc_return_ctx:-}" == 1 && "$__bsc_ret" != "\$__r" ]]; then
                    __bsc_line "__r=$__bsc_ret"
                else
                    __bsc_line "$__bsc_ret"
                fi
            fi
            __bsc_pop_indent
        fi
    fi
    __bsc_line "fi"
    __bsc_return_ctx="$_save_rc"
    # When in expr mode, the result is in __r
    if [[ "$mode" == "expr" ]]; then
        __bsc_ret="\$__r"
    else
        __bsc_ret=""
    fi
}

__bsc_emit_elif() {
    local rest="$1" mode="$2"
    local test_e="${__bs_car[$rest]}"
    local branches="${__bs_cdr[$rest]}"
    local then_e="${__bs_car[$branches]}"
    local else_rest="${__bs_cdr[$branches]}"

    local _pre_len=${#__bsc_out}
    __bsc_emit_test "$test_e"
    local _test_expr="$__bsc_ret"
    local _has_preamble=0
    local _preamble=""
    if (( ${#__bsc_out} > _pre_len )); then
        _preamble="${__bsc_out:$_pre_len}"
        __bsc_out="${__bsc_out:0:$_pre_len}"
        _has_preamble=1
    fi
    if (( _has_preamble )); then
        # Preamble between elif and previous body is invalid bash;
        # use else + nested if to place preamble correctly
        __bsc_line "else"
        __bsc_push_indent
        __bsc_out+="$_preamble"
        __bsc_line "if $_test_expr; then"
    else
        __bsc_line "elif $_test_expr; then"
    fi
    __bsc_push_indent
    __bsc_emit_expr "$then_e" "stmt"
    if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
        if [[ "${__bsc_return_ctx:-}" == 1 ]]; then
            [[ "$__bsc_ret" != "\$__r" ]] && __bsc_line "__r=$__bsc_ret"
        else
            __bsc_line "$__bsc_ret"
        fi
    fi
    __bsc_pop_indent

    if [[ "$else_rest" != 'n:()' ]]; then
        local else_e="${__bs_car[$else_rest]}"
        if [[ "${else_e:0:2}" == "p:" && "${__bs_car[$else_e]}" == "y:if" ]]; then
            __bsc_emit_elif "${__bs_cdr[$else_e]}" "$mode"
        else
            __bsc_line "else"
            __bsc_push_indent
            __bsc_emit_expr "$else_e" "stmt"
            if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
                if [[ "${__bsc_return_ctx:-}" == 1 && "$__bsc_ret" != "\$__r" ]]; then
                    __bsc_line "__r=$__bsc_ret"
                else
                    __bsc_line "$__bsc_ret"
                fi
            fi
            __bsc_pop_indent
        fi
    fi
    # Close extra nesting if preamble was present
    if (( _has_preamble )); then
        __bsc_line "fi"
        __bsc_pop_indent
    fi
}

# ── Test expression: emit as bash conditional ─────────────────────────────────
__bsc_emit_test() {
    local expr="$1"

    # Simple literals
    case "${expr:0:2}" in
        'b:')
            if [[ "$expr" == 'b:#t' ]]; then __bsc_ret="true"
            else __bsc_ret="false"; fi
            return 0 ;;
        'y:')
            __bsc_mangle "${expr:2}"
            local m="$__bsc_ret"
            if [[ -n "${__bsc_int_vars[$m]:-}" ]]; then
                __bsc_ret="(( $m ))"
            else
                __bsc_ret="[[ -n \"\$$m\" && \"\$$m\" != \"0\" ]]"
            fi
            return 0 ;;
    esac

    # Not a list? Just evaluate
    [[ "${expr:0:2}" != "p:" ]] && {
        __bsc_emit_expr "$expr" "expr"
        local _uq="$(__bsc_unquote "$__bsc_ret")"
        __bsc_ret="[[ -n \"$_uq\" && \"$_uq\" != \"0\" ]]"
        return 0
    }

    local head="${__bs_car[$expr]}"
    local rest="${__bs_cdr[$expr]}"

    case "$head" in
        # Numeric comparisons
        'y:<'|'y:>'|'y:<='|'y:>='|'y:=')
            local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
            __bsc_emit_arith_val "$a_e"; local a="$__bsc_ret"
            __bsc_emit_arith_val "$b_e"; local b="$__bsc_ret"
            local op="${head:2}"
            [[ "$op" == "=" ]] && op="=="
            __bsc_ret="(( $a $op $b ))"
            return 0 ;;

        'y:zero?')
            __bsc_emit_arith_val "${__bs_car[$rest]}"; __bsc_ret="(( $__bsc_ret == 0 ))"; return 0 ;;
        'y:positive?')
            __bsc_emit_arith_val "${__bs_car[$rest]}"; __bsc_ret="(( $__bsc_ret > 0 ))"; return 0 ;;
        'y:negative?')
            __bsc_emit_arith_val "${__bs_car[$rest]}"; __bsc_ret="(( $__bsc_ret < 0 ))"; return 0 ;;
        'y:even?')
            __bsc_emit_arith_val "${__bs_car[$rest]}"; __bsc_ret="(( $__bsc_ret % 2 == 0 ))"; return 0 ;;
        'y:odd?')
            __bsc_emit_arith_val "${__bs_car[$rest]}"; __bsc_ret="(( $__bsc_ret % 2 != 0 ))"; return 0 ;;

        # String/equal comparisons
        'y:equal?'|'y:eq?'|'y:eqv?'|'y:string=?')
            local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
            __bsc_emit_expr "$a_e" "expr"; local a="$(__bsc_unquote "$__bsc_ret")"
            __bsc_emit_expr "$b_e" "expr"; local b="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$a\" == \"$b\" ]]"
            return 0 ;;

        'y:string<?')
            local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
            __bsc_emit_expr "$a_e" "expr"; local a="$(__bsc_unquote "$__bsc_ret")"
            __bsc_emit_expr "$b_e" "expr"; local b="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$a\" < \"$b\" ]]"
            return 0 ;;
        'y:string>?')
            local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
            __bsc_emit_expr "$a_e" "expr"; local a="$(__bsc_unquote "$__bsc_ret")"
            __bsc_emit_expr "$b_e" "expr"; local b="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$a\" > \"$b\" ]]"
            return 0 ;;

        # char comparisons
        'y:char=?')
            local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
            __bsc_emit_expr "$a_e" "expr"; local a="$(__bsc_unquote "$__bsc_ret")"
            __bsc_emit_expr "$b_e" "expr"; local b="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$a\" == \"$b\" ]]"
            return 0 ;;
        'y:char<?')
            local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
            __bsc_emit_expr "$a_e" "expr"; local a="$(__bsc_unquote "$__bsc_ret")"
            __bsc_emit_expr "$b_e" "expr"; local b="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$a\" < \"$b\" ]]"
            return 0 ;;
        'y:char>=?')
            local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
            __bsc_emit_expr "$a_e" "expr"; local a="$(__bsc_unquote "$__bsc_ret")"
            __bsc_emit_expr "$b_e" "expr"; local b="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ ! \"$a\" < \"$b\" ]]"
            return 0 ;;

        # Boolean ops
        'y:and')
            __bsc_list_to_array "$rest"
            local parts=()
            for elem in "${__bsc_list_result[@]}"; do
                __bsc_emit_test "$elem"
                parts+=("$__bsc_ret")
            done
            local joined=""
            for (( _k=0; _k<${#parts[@]}; _k++ )); do
                [[ -n "$joined" ]] && joined+=" && "
                joined+="${parts[$_k]}"
            done
            __bsc_ret="$joined"
            return 0 ;;

        'y:or')
            __bsc_list_to_array "$rest"
            local parts=()
            for elem in "${__bsc_list_result[@]}"; do
                __bsc_emit_test "$elem"
                parts+=("$__bsc_ret")
            done
            local joined=""
            for (( _k=0; _k<${#parts[@]}; _k++ )); do
                [[ -n "$joined" ]] && joined+=" || "
                joined+="${parts[$_k]}"
            done
            __bsc_ret="$joined"
            return 0 ;;

        'y:not')
            __bsc_emit_test "${__bs_car[$rest]}"
            __bsc_ret="! $__bsc_ret"
            return 0 ;;

        # Type predicates in test context
        'y:null?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ret="[[ \${#$(__bsc_strip_dollar "$__bsc_ret")[@]} -eq 0 ]]"
            return 0 ;;
        'y:pair?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ret="[[ \${#$(__bsc_strip_dollar "$__bsc_ret")[@]} -gt 0 ]]"
            return 0 ;;

        # char predicates
        'y:char-alphabetic?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local v="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$v\" =~ [a-zA-Z] ]]"
            return 0 ;;
        'y:char-numeric?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local v="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$v\" =~ [0-9] ]]"
            return 0 ;;
        'y:char-word?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local v="$(__bsc_unquote "$__bsc_ret")"
            __bsc_ret="[[ \"$v\" =~ [a-zA-Z0-9_] ]]"
            return 0 ;;

        # Negated version: (not (equal? ...))
        # Fall through to general case
    esac

    # General: evaluate expression and test truthiness
    __bsc_emit_expr "$expr" "expr"
    local val="$__bsc_ret"
    # If it's already a (( )) or [[ ]] expression, use it directly
    if [[ "$val" == "(("* || "$val" == "[["* ]]; then
        __bsc_ret="$val"
    else
        local _uq="$(__bsc_unquote "$val")"
        __bsc_ret="[[ -n \"$_uq\" && \"$_uq\" != \"0\" ]]"
    fi
}

# Strip leading $ from variable reference
__bsc_strip_dollar() {
    local v="$1"
    [[ "$v" == \$* ]] && v="${v:1}"
    printf '%s' "$v"
}

# Strip outer quotes for embedding in [[ ]] contexts
# "foo" → foo, "$var" → $var, but $(( )) stays as-is
__bsc_unquote() {
    local v="$1"
    if [[ "$v" == '"'*'"' ]]; then
        printf '%s' "${v:1:${#v}-2}"
    else
        printf '%s' "$v"
    fi
}

# Get a bare variable name for an array expression.
# If __bsc_ret is an array literal like (...), materialize to a temp var.
# Otherwise strip $ and return the variable name.
# Sets __bsc_arr_name to the usable variable name.
__bsc_ensure_arr_var() {
    local v="$__bsc_ret"
    if [[ "$v" == "("* ]]; then
        (( __bsc_list_n = ${__bsc_list_n:-0} + 1 )) || true
        __bsc_arr_name="__tmp_arr${__bsc_list_n}"
        __bsc_line "local -a ${__bsc_arr_name}=${v}"
    else
        __bsc_arr_name="$(__bsc_strip_dollar "$v")"
    fi
}

# Emit arithmetic value (for use inside $(( )) or (( )) )
__bsc_emit_arith_val() {
    local expr="$1"
    case "${expr:0:2}" in
        'i:') __bsc_ret="${expr:2}"; return 0 ;;
        'y:')
            __bsc_mangle "${expr:2}"; return 0 ;;  # bare name in arith context
        'p:')
            local head="${__bs_car[$expr]}"
            case "$head" in
                'y:+'|'y:-'|'y:*'|'y:/'|'y:quotient'|'y:remainder'|'y:modulo')
                    __bsc_emit_arith_inline "$expr"
                    return 0 ;;
                'y:string-length')
                    local arg="${__bs_car[${__bs_cdr[$expr]}]}"
                    __bsc_emit_expr "$arg" "expr"
                    local v="$__bsc_ret"
                    if [[ "$v" == '$'[a-zA-Z_]* && "$v" != *'['* && "$v" != *'{'* && "$v" != *':'* ]]; then
                        __bsc_ret="\${#${v:1}}"
                    else
                        __bsc_local "__sl=$v"
                        __bsc_ret="\${#__sl}"
                    fi
                    return 0 ;;
                'y:vector-length')
                    local arg="${__bs_car[${__bs_cdr[$expr]}]}"
                    __bsc_emit_expr "$arg" "expr"
                    local v="$(__bsc_strip_dollar "$__bsc_ret")"
                    __bsc_ret="\${#${v}[@]}"
                    return 0 ;;
                *)
                    __bsc_emit_expr "$expr" "expr"
                    return 0 ;;
            esac ;;
        *) __bsc_emit_expr "$expr" "expr"; return 0 ;;
    esac
}

# Emit inline arithmetic (no side effects, nestable)
__bsc_emit_arith_inline() {
    local expr="$1"
    local head="${__bs_car[$expr]}"
    local rest="${__bs_cdr[$expr]}"
    local op="${head:2}"

    __bsc_list_to_array "$rest"
    local -a vals=()
    for elem in "${__bsc_list_result[@]}"; do
        __bsc_emit_arith_val "$elem"
        vals+=("$__bsc_ret")
    done

    case "$op" in
        '+')
            if (( ${#vals[@]} == 0 )); then __bsc_ret="0"
            elif (( ${#vals[@]} == 1 )); then __bsc_ret="${vals[0]}"
            else
                local r="${vals[0]}"
                for (( _k=1; _k<${#vals[@]}; _k++ )); do r+=" + ${vals[$_k]}"; done
                __bsc_ret="$r"
            fi ;;
        '-')
            if (( ${#vals[@]} == 1 )); then __bsc_ret="-(${vals[0]})"
            else
                local r="${vals[0]}"
                for (( _k=1; _k<${#vals[@]}; _k++ )); do r+=" - ${vals[$_k]}"; done
                __bsc_ret="$r"
            fi ;;
        '*')
            if (( ${#vals[@]} == 0 )); then __bsc_ret="1"
            elif (( ${#vals[@]} == 1 )); then __bsc_ret="${vals[0]}"
            else
                local r="${vals[0]}"
                for (( _k=1; _k<${#vals[@]}; _k++ )); do r+=" * ${vals[$_k]}"; done
                __bsc_ret="$r"
            fi ;;
        '/')
            local r="${vals[0]}"
            for (( _k=1; _k<${#vals[@]}; _k++ )); do r+=" / ${vals[$_k]}"; done
            __bsc_ret="$r" ;;
        'quotient')
            __bsc_ret="${vals[0]} / ${vals[1]}" ;;
        'remainder'|'modulo')
            __bsc_ret="${vals[0]} % ${vals[1]}" ;;
        *) __bsc_ret="${vals[0]}" ;;
    esac
}

# ── When / Unless ─────────────────────────────────────────────────────────────
__bsc_emit_when() {
    local rest="$1" mode="$2"
    local test_e="${__bs_car[$rest]}"
    local body="${__bs_cdr[$rest]}"

    __bsc_emit_test "$test_e"
    __bsc_line "if $__bsc_ret; then"
    __bsc_push_indent
    __bsc_emit_body "$body"
    __bsc_pop_indent
    __bsc_line "fi"
    __bsc_ret=""
}

__bsc_emit_unless() {
    local rest="$1" mode="$2"
    local test_e="${__bs_car[$rest]}"
    local body="${__bs_cdr[$rest]}"

    __bsc_emit_test "$test_e"
    __bsc_line "if ! $__bsc_ret; then"
    __bsc_push_indent
    __bsc_emit_body "$body"
    __bsc_pop_indent
    __bsc_line "fi"
    __bsc_ret=""
}

# ── Begin ─────────────────────────────────────────────────────────────────────
__bsc_emit_begin() {
    local rest="$1" mode="$2"
    if [[ "${__bsc_return_ctx:-}" == 1 ]]; then
        __bsc_emit_body_rc "$rest"
    else
        __bsc_emit_body "$rest"
    fi
    __bsc_ret=""
}

# ── Emit a local variable binding ─────────────────────────────────────────────
# Handles test expressions ((..)) and [[..]] by converting to 0/1 values
__bsc_emit_local_binding() {
    local mvar="$1" ival="$2"
    local _kw="local"
    (( __bsc_in_func )) || _kw="declare"
    if [[ "$ival" =~ ^-?[0-9]+$ ]] || [[ "$ival" == '$(('* ]]; then
        __bsc_int_vars[$mvar]=1
        __bsc_line "$_kw -i $mvar=$ival"
    elif [[ "$ival" == "(("* || "$ival" == "[["* || "$ival" == "! "* ]]; then
        # Test expression — convert to 0/1 value
        __bsc_int_vars[$mvar]=1
        __bsc_line "$_kw -i $mvar=0"
        __bsc_line "$ival && $mvar=1"
    elif [[ "$ival" == '("'* || "$ival" == '($'* || "$ival" == "()" ]]; then
        # Array value
        __bsc_arr_vars[$mvar]=1
        if [[ "${__bsc_is_pair:-}" == 1 ]]; then
            __bsc_pair_vars[$mvar]=1
            __bsc_is_pair=0
        fi
        __bsc_line "$_kw -a $mvar=$ival"
    else
        __bsc_line "$_kw $mvar=$ival"
    fi
}

# ── Body: emit a sequence of expressions ──────────────────────────────────────
__bsc_emit_body() {
    local exprs="$1"
    while [[ "$exprs" != 'n:()' && -n "$exprs" ]]; do
        local e="${__bs_car[$exprs]}"
        __bsc_emit_expr "$e" "stmt"
        [[ -n "$__bsc_ret" && "$__bsc_ret" != "" ]] && __bsc_line "$__bsc_ret"
        exprs="${__bs_cdr[$exprs]}"
    done
}

# Body emitter that respects return context for last expression
__bsc_emit_body_rc() {
    local exprs="$1"
    while [[ "$exprs" != 'n:()' && -n "$exprs" ]]; do
        local e="${__bs_car[$exprs]}"
        local next="${__bs_cdr[$exprs]}"
        if [[ "$next" == 'n:()' && "${__bsc_return_ctx:-}" == 1 ]]; then
            # Last expression in return context
            __bsc_emit_expr "$e" "stmt"
            if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
                if [[ "$__bsc_ret" == "\$__r" ]]; then
                    :
                else
                    __bsc_line "__r=$__bsc_ret"
                fi
            fi
        else
            __bsc_emit_expr "$e" "stmt"
            [[ -n "$__bsc_ret" && "$__bsc_ret" != "" ]] && __bsc_line "$__bsc_ret"
        fi
        exprs="$next"
    done
}

# ── Define ────────────────────────────────────────────────────────────────────
__bsc_emit_define() {
    local rest="$1"
    local name_part="${__bs_car[$rest]}"
    local body_rest="${__bs_cdr[$rest]}"

    if [[ "$name_part" == y:* ]]; then
        # Variable define: (define var expr)
        local vname="${name_part:2}"
        __bsc_mangle "$vname"
        local mangled="$__bsc_ret"
        __bsc_globals[$mangled]=1

        local init_e="${__bs_car[$body_rest]}"
        __bsc_emit_expr "$init_e" "expr"
        local val="$__bsc_ret"

        # Detect integer and array variables
        if [[ "$val" =~ ^-?[0-9]+$ ]] || [[ "$val" == '$(('* ]]; then
            __bsc_int_vars[$mangled]=1
            __bsc_line "$mangled=$val"
        elif [[ "$val" == '("'* || "$val" == '($'* || "$val" == "()" ]]; then
            __bsc_arr_vars[$mangled]=1
            __bsc_line "$mangled=$val"
        else
            __bsc_line "$mangled=$val"
        fi
        __bsc_ret=""
    else
        # Function define: (define (fname params...) body...)
        local fname="${__bs_car[$name_part]}"
        local params="${__bs_cdr[$name_part]}"
        __bsc_mangle "${fname:2}"
        local mangled="$__bsc_ret"

        # Skip if already emitted as a runtime helper
        if [[ -n "${__bsc_funcs[$mangled]:-}" ]]; then
            __bsc_ret=""
            return 0
        fi
        __bsc_funcs[$mangled]=1

        __bsc_line "${mangled}() {"
        __bsc_push_indent
        __bsc_in_func=1

        # Emit parameter bindings
        local pi=1
        local p="$params"
        while [[ "$p" != 'n:()' && -n "$p" && "$p" == p:* ]]; do
            local pname="${__bs_car[$p]}"
            __bsc_mangle "${pname:2}"
            __bsc_line "local ${__bsc_ret}=\"\${$pi}\""
            (( pi++ ))
            p="${__bs_cdr[$p]}"
        done
        # Handle rest param (dotted pair)
        if [[ "$p" == y:* ]]; then
            __bsc_mangle "${p:2}"
            __bsc_line "shift $(( pi - 1 ))"
            __bsc_line "local -a ${__bsc_ret}=(\"\$@\")"
        fi

        # Emit body — last expression may need __r= for return value
        __bsc_emit_func_body "$body_rest"

        __bsc_in_func=0
        __bsc_pop_indent
        __bsc_line "}"
        __bsc_line ""
        __bsc_ret=""
    fi
}

# Emit function body: statements for all but last, return value for last
__bsc_emit_func_body() {
    local exprs="$1"
    while [[ "$exprs" != 'n:()' && -n "$exprs" ]]; do
        local e="${__bs_car[$exprs]}"
        local next="${__bs_cdr[$exprs]}"
        if [[ "$next" == 'n:()' ]]; then
            # Last expression in return context
            local _save_rc="${__bsc_return_ctx:-}"
            __bsc_return_ctx=1
            __bsc_emit_expr "$e" "stmt"
            __bsc_return_ctx="$_save_rc"
            if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
                if [[ "$__bsc_ret" == "\$__r" ]]; then
                    : # already in __r
                else
                    __bsc_line "__r=$__bsc_ret"
                fi
            fi
        else
            __bsc_emit_expr "$e" "stmt"
            [[ -n "$__bsc_ret" && "$__bsc_ret" != "" ]] && __bsc_line "$__bsc_ret"
        fi
        exprs="$next"
    done
}

# ── Set! ──────────────────────────────────────────────────────────────────────
__bsc_emit_set() {
    local rest="$1"
    local var_e="${__bs_car[$rest]}"
    local val_e="${__bs_car[${__bs_cdr[$rest]}]}"
    local vname="${var_e:2}"
    __bsc_mangle "$vname"
    local mangled="$__bsc_ret"

    # Check if value is a simple arithmetic expression
    __bsc_emit_expr "$val_e" "expr"
    local val="$__bsc_ret"

    # Special case: (set! var (+ var 1)) → ((var++))
    if [[ "${val_e:0:2}" == "p:" ]]; then
        local vh="${__bs_car[$val_e]}"
        local vr="${__bs_cdr[$val_e]}"
        if [[ "$vh" == "y:+" ]]; then
            local a1="${__bs_car[$vr]}"
            local a2r="${__bs_cdr[$vr]}"
            if [[ "$a2r" != 'n:()' ]]; then
                local a2="${__bs_car[$a2r]}"
                if [[ "$a1" == "$var_e" && "$a2" == "i:1" ]]; then
                    __bsc_line "(( ${mangled}++ )) || true"
                    __bsc_ret=""
                    return 0
                elif [[ "$a2" == "$var_e" && "$a1" == "i:1" ]]; then
                    __bsc_line "(( ${mangled}++ )) || true"
                    __bsc_ret=""
                    return 0
                fi
            fi
        elif [[ "$vh" == "y:-" ]]; then
            local a1="${__bs_car[$vr]}"
            local a2r="${__bs_cdr[$vr]}"
            if [[ "$a2r" != 'n:()' ]]; then
                local a2="${__bs_car[$a2r]}"
                if [[ "$a1" == "$var_e" && "$a2" == "i:1" ]]; then
                    __bsc_line "(( ${mangled}-- )) || true"
                    __bsc_ret=""
                    return 0
                fi
            fi
        fi
    fi

    # Check if value is arithmetic
    if [[ -n "${__bsc_int_vars[$mangled]:-}" ]]; then
        # Known integer variable — use arithmetic assignment
        if [[ "${val_e:0:2}" == "p:" ]]; then
            local vh2="${__bs_car[$val_e]}"
            case "$vh2" in
                'y:+'|'y:-'|'y:*'|'y:/'|'y:quotient'|'y:remainder'|'y:modulo'|'y:max'|'y:min'|'y:abs')
                    __bsc_emit_arith_val "$val_e"
                    __bsc_line "(( ${mangled} = $__bsc_ret )) || true"
                    __bsc_ret=""
                    return 0 ;;
                'y:string-length'|'y:vector-length')
                    __bsc_emit_arith_val "$val_e"
                    __bsc_line "${mangled}=$__bsc_ret"
                    __bsc_ret=""
                    return 0 ;;
            esac
        fi
        if [[ "$val" =~ ^-?[0-9]+$ ]] || [[ "$val" =~ ^\$[a-zA-Z_] ]]; then
            __bsc_line "${mangled}=$val"
        else
            __bsc_line "${mangled}=$val"
        fi
    elif [[ -n "${__bsc_arr_vars[$mangled]:-}" ]]; then
        # Known array variable — assign as array
        if [[ "$val" == '("'* || "$val" == '($'* || "$val" == "()" ]]; then
            __bsc_line "${mangled}=$val"
        elif [[ "$val" == "\$__r" ]]; then
            # Result from a function that returns an array
            __bsc_line "${mangled}=(\"\${__r[@]}\")"
        elif [[ "$val" == *'[@]'* ]]; then
            __bsc_line "${mangled}=($val)"
        else
            __bsc_line "${mangled}=$val"
        fi
    else
        __bsc_line "${mangled}=$val"
    fi
    __bsc_ret=""
}

# ── Let ───────────────────────────────────────────────────────────────────────
__bsc_emit_let() {
    local rest="$1" mode="$2"
    local first="${__bs_car[$rest]}"

    # Named let: (let name ((v i) ...) body...)
    if [[ "$first" == y:* ]]; then
        __bsc_emit_named_let "$rest" "$mode"
        return 0
    fi

    # Regular let: (let ((v i) ...) body...)
    local bindings="$first"
    local body="${__bs_cdr[$rest]}"

    local b="$bindings"
    while [[ "$b" != 'n:()' ]]; do
        local bnd="${__bs_car[$b]}"
        local var="${__bs_car[$bnd]}"
        local init="${__bs_car[${__bs_cdr[$bnd]}]}"
        __bsc_mangle "${var:2}"
        local mvar="$__bsc_ret"

        __bsc_emit_expr "$init" "expr"
        local ival="$__bsc_ret"

        __bsc_emit_local_binding "$mvar" "$ival"
        b="${__bs_cdr[$b]}"
    done

    if [[ "${__bsc_return_ctx:-}" == 1 ]]; then
        __bsc_emit_body_rc "$body"
    else
        __bsc_emit_body "$body"
    fi
    __bsc_ret=""
}

# ── Named Let (loops) ────────────────────────────────────────────────────────
__bsc_emit_named_let() {
    local rest="$1" mode="$2"
    local loop_name_e="${__bs_car[$rest]}"
    local loop_name="${loop_name_e:2}"
    __bsc_mangle "$loop_name"
    local m_loop="$__bsc_ret"

    local bindings="${__bs_car[${__bs_cdr[$rest]}]}"
    local body="${__bs_cdr[${__bs_cdr[$rest]}]}"

    # Emit initial bindings
    local b="$bindings"
    local -a bind_vars=() bind_mangles=()
    while [[ "$b" != 'n:()' ]]; do
        local bnd="${__bs_car[$b]}"
        local var="${__bs_car[$bnd]}"
        local init="${__bs_car[${__bs_cdr[$bnd]}]}"
        __bsc_mangle "${var:2}"
        local mvar="$__bsc_ret"
        bind_vars+=("${var:2}")
        bind_mangles+=("$mvar")

        __bsc_emit_expr "$init" "expr"
        local ival="$__bsc_ret"

        __bsc_emit_local_binding "$mvar" "$ival"
        b="${__bs_cdr[$b]}"
    done

    # Emit as while-true loop
    __bsc_line "while true; do"
    __bsc_push_indent

    # Replace recursive calls to loop_name with continue
    __bsc_emit_named_let_body "$body" "$loop_name" "${bind_vars[*]}" "${bind_mangles[*]}"

    __bsc_line "break"
    __bsc_pop_indent
    __bsc_line "done"
    __bsc_ret=""
}

# Emit body of named-let, replacing tail calls with variable updates + continue
__bsc_emit_named_let_body() {
    local body="$1" loop_name="$2" bind_vars_str="$3" bind_mangles_str="$4"
    local -a bind_vars=($bind_vars_str) bind_mangles=($bind_mangles_str)

    local exprs="$body"
    while [[ "$exprs" != 'n:()' && -n "$exprs" ]]; do
        local e="${__bs_car[$exprs]}"
        local next="${__bs_cdr[$exprs]}"

        if [[ "$next" == 'n:()' ]]; then
            # Last expression — check for tail call to loop
            __bsc_emit_named_let_expr "$e" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
        else
            __bsc_emit_named_let_expr "$e" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
        fi
        exprs="$next"
    done
}

__bsc_emit_named_let_expr() {
    local expr="$1" loop_name="$2" bind_vars_str="$3" bind_mangles_str="$4"
    local -a bind_vars=($bind_vars_str) bind_mangles=($bind_mangles_str)

    [[ "${expr:0:2}" != "p:" ]] && {
        __bsc_emit_expr "$expr" "stmt"
        if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
            if [[ "${__bsc_return_ctx:-}" == 1 && "$__bsc_ret" != "\$__r" ]]; then
                __bsc_line "__r=$__bsc_ret"
            else
                __bsc_line "$__bsc_ret"
            fi
        fi
        return 0
    }

    local head="${__bs_car[$expr]}"
    local rest="${__bs_cdr[$expr]}"

    # Direct tail call: (loop-name arg1 arg2 ...)
    if [[ "$head" == "y:$loop_name" ]]; then
        __bsc_emit_loop_continue "$rest" "$bind_vars_str" "$bind_mangles_str"
        return 0
    fi

    # if/when/unless with tail calls
    case "$head" in
        'y:if')
            local test_e="${__bs_car[$rest]}"
            local branches="${__bs_cdr[$rest]}"
            local then_e="${__bs_car[$branches]}"
            local else_rest="${__bs_cdr[$branches]}"

            __bsc_emit_test "$test_e"
            __bsc_line "if $__bsc_ret; then"
            __bsc_push_indent
            __bsc_emit_named_let_expr "$then_e" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
            __bsc_pop_indent
            if [[ "$else_rest" != 'n:()' ]]; then
                local else_e="${__bs_car[$else_rest]}"
                __bsc_line "else"
                __bsc_push_indent
                __bsc_emit_named_let_expr "$else_e" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
                __bsc_pop_indent
            fi
            __bsc_line "fi"
            return 0 ;;

        'y:when')
            local test_e="${__bs_car[$rest]}"
            local body="${__bs_cdr[$rest]}"
            __bsc_emit_test "$test_e"
            __bsc_line "if $__bsc_ret; then"
            __bsc_push_indent
            __bsc_emit_named_let_body "$body" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
            __bsc_pop_indent
            __bsc_line "fi"
            return 0 ;;

        'y:unless')
            local test_e="${__bs_car[$rest]}"
            local body="${__bs_cdr[$rest]}"
            __bsc_emit_test "$test_e"
            __bsc_line "if ! $__bsc_ret; then"
            __bsc_push_indent
            __bsc_emit_named_let_body "$body" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
            __bsc_pop_indent
            __bsc_line "fi"
            return 0 ;;

        'y:begin')
            __bsc_emit_named_let_body "$rest" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
            return 0 ;;

        'y:cond')
            __bsc_emit_cond_with_loop "$rest" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
            return 0 ;;

        'y:let'|'y:let*')
            # Emit bindings, then body in loop context
            local _nl_first="${__bs_car[$rest]}"
            local _nl_bindings _nl_body
            if [[ "$_nl_first" == y:* ]]; then
                # Named let inside named let - just emit normally
                __bsc_emit_expr "$expr" "stmt"
                [[ -n "$__bsc_ret" ]] && __bsc_line "$__bsc_ret"
                return 0
            fi
            _nl_bindings="$_nl_first"
            _nl_body="${__bs_cdr[$rest]}"
            local _nl_b="$_nl_bindings"
            while [[ "$_nl_b" != 'n:()' ]]; do
                local _nl_bnd="${__bs_car[$_nl_b]}"
                local _nl_var="${__bs_car[$_nl_bnd]}"
                local _nl_init="${__bs_car[${__bs_cdr[$_nl_bnd]}]}"
                __bsc_mangle "${_nl_var:2}"
                local _nl_mvar="$__bsc_ret"
                __bsc_emit_expr "$_nl_init" "expr"
                __bsc_emit_local_binding "$_nl_mvar" "$__bsc_ret"
                _nl_b="${__bs_cdr[$_nl_b]}"
            done
            __bsc_emit_named_let_body "$_nl_body" "$loop_name" "$bind_vars_str" "$bind_mangles_str"
            return 0 ;;
    esac

    # Not a tail call — emit normally
    __bsc_emit_expr "$expr" "stmt"
    if [[ -n "$__bsc_ret" && "$__bsc_ret" != "# "* ]]; then
        if [[ "${__bsc_return_ctx:-}" == 1 ]]; then
            [[ "$__bsc_ret" != "\$__r" ]] && __bsc_line "__r=$__bsc_ret"
        else
            __bsc_line "$__bsc_ret"
        fi
    fi
}

# Emit loop continue: update variables and continue
__bsc_emit_loop_continue() {
    local args="$1" bind_vars_str="$2" bind_mangles_str="$3"
    local -a bind_vars=($bind_vars_str) bind_mangles=($bind_mangles_str)

    # Compute new values
    local -a new_vals=()
    local _lc_a="$args"
    local -i _lc_n=${#bind_vars[@]} _lc_i
    for (( _lc_i=0; _lc_i<_lc_n; _lc_i++ )); do
        if [[ "$_lc_a" != 'n:()' ]]; then
            __bsc_emit_expr "${__bs_car[$_lc_a]}" "expr"
            new_vals+=("$__bsc_ret")
            _lc_a="${__bs_cdr[$_lc_a]}"
        fi
    done

    # Helper: check if a value or its target variable is an array
    _lc_is_arr() {
        [[ "$1" == "("* ]] && return 0
        [[ -n "${__bsc_arr_vars[$2]:-}" ]] && return 0
        return 1
    }

    # Assign new values (use temp vars to handle simultaneous update)
    if (( _lc_n == 1 )); then
        local _v="${new_vals[0]}" _m="${bind_mangles[0]}"
        if _lc_is_arr "$_v" "$_m"; then
            if [[ "$_v" == "("* ]]; then
                __bsc_line "${_m}=${_v}"
            else
                __bsc_line "${_m}=(\"\${${_v#\$}[@]}\")"
            fi
        else
            __bsc_line "${_m}=${_v}"
        fi
    else
        # Use temp vars for simultaneous update
        for (( _lc_i=0; _lc_i<_lc_n; _lc_i++ )); do
            local _v="${new_vals[$_lc_i]}" _m="${bind_mangles[$_lc_i]}"
            if _lc_is_arr "$_v" "$_m"; then
                if [[ "$_v" == "("* ]]; then
                    __bsc_line "local -a __t${_lc_i}=${_v}"
                else
                    __bsc_line "local -a __t${_lc_i}=(\"\${${_v#\$}[@]}\")"
                fi
            else
                __bsc_line "local __t${_lc_i}=${_v}"
            fi
        done
        for (( _lc_i=0; _lc_i<_lc_n; _lc_i++ )); do
            local _v="${new_vals[$_lc_i]}" _m="${bind_mangles[$_lc_i]}"
            if _lc_is_arr "$_v" "$_m"; then
                __bsc_line "${_m}=(\"\${__t${_lc_i}[@]}\")"
            else
                __bsc_line "${_m}=\$__t${_lc_i}"
            fi
        done
    fi
    __bsc_line "continue"
}

# Emit cond in named-let context (with tail call optimization)
__bsc_emit_cond_with_loop() {
    local clauses="$1" loop_name="$2" bv="$3" bm="$4"
    local first=1
    local _extra_fi=0

    while [[ "$clauses" != 'n:()' ]]; do
        local clause="${__bs_car[$clauses]}"
        local test_e="${__bs_car[$clause]}"
        local cl_body="${__bs_cdr[$clause]}"

        if [[ "$test_e" == 'y:else' || "$test_e" == 'b:#t' ]]; then
            if (( first )); then
                __bsc_emit_named_let_body "$cl_body" "$loop_name" "$bv" "$bm"
            else
                __bsc_line "else"
                __bsc_push_indent
                __bsc_emit_named_let_body "$cl_body" "$loop_name" "$bv" "$bm"
                __bsc_pop_indent
                __bsc_line "fi"
            fi
            local _ef; for (( _ef=0; _ef<_extra_fi; _ef++ )); do
                __bsc_pop_indent
                __bsc_line "fi"
            done
            return 0
        fi

        local _pre_len=${#__bsc_out}
        __bsc_emit_test "$test_e"
        local _test_expr="$__bsc_ret"
        local _has_preamble=0
        local _preamble=""
        if (( ${#__bsc_out} > _pre_len )); then
            _preamble="${__bsc_out:$_pre_len}"
            __bsc_out="${__bsc_out:0:$_pre_len}"
            _has_preamble=1
        fi
        if (( first )); then
            [[ -n "$_preamble" ]] && __bsc_out+="$_preamble"
            __bsc_line "if $_test_expr; then"
            first=0
        elif (( _has_preamble )); then
            __bsc_line "else"
            __bsc_push_indent
            __bsc_out+="$_preamble"
            __bsc_line "if $_test_expr; then"
            (( _extra_fi++ ))
        else
            __bsc_line "elif $_test_expr; then"
        fi
        __bsc_push_indent
        __bsc_emit_named_let_body "$cl_body" "$loop_name" "$bv" "$bm"
        __bsc_pop_indent

        clauses="${__bs_cdr[$clauses]}"
    done
    (( first )) || __bsc_line "fi"
    local _ef; for (( _ef=0; _ef<_extra_fi; _ef++ )); do
        __bsc_pop_indent
        __bsc_line "fi"
    done
}

# ── Let* ──────────────────────────────────────────────────────────────────────
__bsc_emit_letstar() {
    local rest="$1" mode="$2"
    local bindings="${__bs_car[$rest]}"
    local body="${__bs_cdr[$rest]}"

    local b="$bindings"
    while [[ "$b" != 'n:()' ]]; do
        local bnd="${__bs_car[$b]}"
        local var="${__bs_car[$bnd]}"
        local init="${__bs_car[${__bs_cdr[$bnd]}]}"
        __bsc_mangle "${var:2}"
        local mvar="$__bsc_ret"

        __bsc_emit_expr "$init" "expr"
        local ival="$__bsc_ret"

        __bsc_emit_local_binding "$mvar" "$ival"
        b="${__bs_cdr[$b]}"
    done

    if [[ "${__bsc_return_ctx:-}" == 1 ]]; then
        __bsc_emit_body_rc "$body"
    else
        __bsc_emit_body "$body"
    fi
    __bsc_ret=""
}

# ── Cond ──────────────────────────────────────────────────────────────────────
__bsc_emit_cond() {
    local clauses="$1" mode="$2"
    local first=1
    local _save_rc="${__bsc_return_ctx:-}"
    [[ "$mode" == "expr" ]] && __bsc_return_ctx=1
    local _extra_fi=0

    while [[ "$clauses" != 'n:()' ]]; do
        local clause="${__bs_car[$clauses]}"
        local test_e="${__bs_car[$clause]}"
        local cl_body="${__bs_cdr[$clause]}"

        if [[ "$test_e" == 'y:else' || "$test_e" == 'b:#t' ]]; then
            if (( first )); then
                __bsc_emit_body_rc "$cl_body"
            else
                __bsc_line "else"
                __bsc_push_indent
                __bsc_emit_body_rc "$cl_body"
                __bsc_pop_indent
                __bsc_line "fi"
            fi
            local _ef; for (( _ef=0; _ef<_extra_fi; _ef++ )); do
                __bsc_pop_indent
                __bsc_line "fi"
            done
            __bsc_return_ctx="$_save_rc"
            if [[ "$mode" == "expr" ]]; then
                __bsc_ret="\$__r"
            else
                __bsc_ret=""
            fi
            return 0
        fi

        # Check if test expression produces preamble (side-effect lines)
        local _pre_len=${#__bsc_out}
        __bsc_emit_test "$test_e"
        local _test_expr="$__bsc_ret"
        local _has_preamble=0
        local _preamble=""
        if (( ${#__bsc_out} > _pre_len )); then
            _preamble="${__bsc_out:$_pre_len}"
            __bsc_out="${__bsc_out:0:$_pre_len}"
            _has_preamble=1
        fi
        if (( first )); then
            # For the first clause, preamble before 'if' is fine
            [[ -n "$_preamble" ]] && __bsc_out+="$_preamble"
            __bsc_line "if $_test_expr; then"
            first=0
        elif (( _has_preamble )); then
            # Preamble between elif and previous body is invalid bash;
            # use else + nested if to place preamble correctly
            __bsc_line "else"
            __bsc_push_indent
            __bsc_out+="$_preamble"
            __bsc_line "if $_test_expr; then"
            (( _extra_fi++ ))
        else
            __bsc_line "elif $_test_expr; then"
        fi
        __bsc_push_indent
        __bsc_emit_body_rc "$cl_body"
        __bsc_pop_indent

        clauses="${__bs_cdr[$clauses]}"
    done
    (( first )) || __bsc_line "fi"
    local _ef; for (( _ef=0; _ef<_extra_fi; _ef++ )); do
        __bsc_pop_indent
        __bsc_line "fi"
    done
    __bsc_return_ctx="$_save_rc"
    if [[ "$mode" == "expr" ]]; then
        __bsc_ret="\$__r"
    else
        __bsc_ret=""
    fi
}

# ── Case ──────────────────────────────────────────────────────────────────────
__bsc_emit_case() {
    local rest="$1" mode="$2"
    local key_e="${__bs_car[$rest]}"
    local clauses="${__bs_cdr[$rest]}"

    __bsc_emit_expr "$key_e" "expr"
    __bsc_line "case \"$__bsc_ret\" in"
    __bsc_push_indent

    while [[ "$clauses" != 'n:()' ]]; do
        local clause="${__bs_car[$clauses]}"
        local datums="${__bs_car[$clause]}"
        local cl_body="${__bs_cdr[$clause]}"

        if [[ "$datums" == 'y:else' ]]; then
            __bsc_line "*)"
        else
            local pats="" d="$datums"
            while [[ "$d" != 'n:()' && "$d" == p:* ]]; do
                local datum="${__bs_car[$d]}"
                __bsc_emit_quote "$datum"
                [[ -n "$pats" ]] && pats+="|"
                pats+="$__bsc_ret"
                d="${__bs_cdr[$d]}"
            done
            __bsc_line "$pats)"
        fi
        __bsc_push_indent
        __bsc_emit_body "$cl_body"
        __bsc_line ";;"
        __bsc_pop_indent

        clauses="${__bs_cdr[$clauses]}"
    done

    __bsc_pop_indent
    __bsc_line "esac"
    __bsc_ret=""
}

# ── And / Or ──────────────────────────────────────────────────────────────────
__bsc_emit_and() {
    local rest="$1" mode="$2"
    # In statement context, just test each
    __bsc_list_to_array "$rest"
    if (( ${#__bsc_list_result[@]} == 0 )); then
        __bsc_ret="1"; return 0
    fi
    # Emit as if chains
    local exprs="$rest"
    local first_e="${__bs_car[$exprs]}"
    local rest_e="${__bs_cdr[$exprs]}"
    if [[ "$rest_e" == 'n:()' ]]; then
        __bsc_emit_expr "$first_e" "$mode"
        return 0
    fi
    # Multi-element and in test: already handled by __bsc_emit_test
    # In statement/expr: emit last value if all true
    __bsc_emit_expr "$first_e" "stmt"
    [[ -n "$__bsc_ret" ]] && __bsc_line "$__bsc_ret"
    __bsc_ret=""
}

__bsc_emit_or() {
    local rest="$1" mode="$2"
    __bsc_list_to_array "$rest"
    if (( ${#__bsc_list_result[@]} == 0 )); then
        __bsc_ret="0"; return 0
    fi
    local first_e="${__bs_car[$rest]}"
    local rest_e="${__bs_cdr[$rest]}"
    if [[ "$rest_e" == 'n:()' ]]; then
        __bsc_emit_expr "$first_e" "$mode"
        return 0
    fi
    __bsc_emit_expr "$first_e" "stmt"
    [[ -n "$__bsc_ret" ]] && __bsc_line "$__bsc_ret"
    __bsc_ret=""
}

__bsc_emit_not() {
    local rest="$1" mode="$2"
    __bsc_emit_test "${__bs_car[$rest]}"
    if [[ "$mode" == "test" ]]; then
        __bsc_ret="! $__bsc_ret"
    else
        __bsc_ret=""
    fi
}

# ── Do ────────────────────────────────────────────────────────────────────────
__bsc_emit_do() {
    local rest="$1" mode="$2"
    local var_specs="${__bs_car[$rest]}"
    local test_clause="${__bs_car[${__bs_cdr[$rest]}]}"
    local commands="${__bs_cdr[${__bs_cdr[$rest]}]}"
    local test_e="${__bs_car[$test_clause]}"
    local result_exprs="${__bs_cdr[$test_clause]}"

    # Init vars
    local vs="$var_specs"
    local -a dv_names=() dv_mangles=() dv_steps=()
    while [[ "$vs" != 'n:()' ]]; do
        local spec="${__bs_car[$vs]}"
        local dvar="${__bs_car[$spec]}"
        local dinit="${__bs_car[${__bs_cdr[$spec]}]}"
        local ds_rest="${__bs_cdr[${__bs_cdr[$spec]}]}"
        __bsc_mangle "${dvar:2}"
        local dm="$__bsc_ret"
        dv_names+=("${dvar:2}")
        dv_mangles+=("$dm")

        __bsc_emit_expr "$dinit" "expr"
        local iv="$__bsc_ret"
        __bsc_emit_local_binding "$dm" "$iv"

        if [[ "$ds_rest" != 'n:()' ]]; then
            dv_steps+=("${__bs_car[$ds_rest]}")
        else
            dv_steps+=("")
        fi
        vs="${__bs_cdr[$vs]}"
    done

    # Emit loop
    __bsc_emit_test "$test_e"
    __bsc_line "while ! $__bsc_ret; do"
    __bsc_push_indent

    # Commands
    __bsc_emit_body "$commands"

    # Steps
    if (( ${#dv_names[@]} == 1 )); then
        if [[ -n "${dv_steps[0]}" ]]; then
            __bsc_emit_expr "${dv_steps[0]}" "expr"
            __bsc_line "${dv_mangles[0]}=$__bsc_ret"
        fi
    else
        for (( _k=0; _k<${#dv_names[@]}; _k++ )); do
            if [[ -n "${dv_steps[$_k]}" ]]; then
                __bsc_emit_expr "${dv_steps[$_k]}" "expr"
                __bsc_line "local __dt${_k}=$__bsc_ret"
            fi
        done
        for (( _k=0; _k<${#dv_names[@]}; _k++ )); do
            if [[ -n "${dv_steps[$_k]}" ]]; then
                __bsc_line "${dv_mangles[$_k]}=\$__dt${_k}"
            fi
        done
    fi

    __bsc_pop_indent
    __bsc_line "done"

    # Result
    if [[ "$result_exprs" != 'n:()' ]]; then
        __bsc_emit_body "$result_exprs"
    fi
    __bsc_ret=""
}

# ── Lambda ────────────────────────────────────────────────────────────────────
__bsc_emit_lambda() {
    local rest="$1"
    # Emit as inline function name (will be handled at call site)
    __bsc_ret="# lambda (not yet inlined)"
}

# ── Apply ─────────────────────────────────────────────────────────────────────
__bsc_emit_apply() {
    local rest="$1" mode="$2"
    local proc_e="${__bs_car[$rest]}"
    local args_rest="${__bs_cdr[$rest]}"

    # Special case: (apply string-append ...)
    if [[ "$proc_e" == "y:string-append" ]]; then
        local _apply_args=()
        local _ar="$args_rest"
        while [[ "$_ar" != 'n:()' ]]; do
            _apply_args+=("${__bs_car[$_ar]}")
            _ar="${__bs_cdr[$_ar]}"
        done
        local _last_arg="${_apply_args[${#_apply_args[@]}-1]}"
        local _prefix_parts=()
        for (( _ai=0; _ai<${#_apply_args[@]}-1; _ai++ )); do
            __bsc_emit_expr "${_apply_args[$_ai]}" "expr"
            _prefix_parts+=("$__bsc_ret")
        done
        # Last arg is the list to spread
        local _list_expr="$_last_arg"
        local _reverse=0
        if [[ "${_list_expr:0:2}" == "p:" && "${__bs_car[$_list_expr]}" == "y:reverse" ]]; then
            local rev_arg="${__bs_car[${__bs_cdr[$_list_expr]}]}"
            __bsc_emit_expr "$rev_arg" "expr"
            local arr="$(__bsc_strip_dollar "$__bsc_ret")"
            _reverse=1
        else
            __bsc_emit_expr "$_list_expr" "expr"
            local arr="$(__bsc_strip_dollar "$__bsc_ret")"
        fi
        # Use a local string accumulation variable instead of a subshell,
        # avoiding a fork() per call (critical for render-loop performance).
        local _sa_tmp="__sa_r${__bsc_list_n}"
        (( __bsc_list_n++ )) || true
        if (( _reverse )); then
            local _pfx=""
            if (( ${#_prefix_parts[@]} > 0 )); then
                for _pp in "${_prefix_parts[@]}"; do _pfx+="\${$(__bsc_strip_dollar "$_pp")}"; done
            fi
            __bsc_line "local ${_sa_tmp}=\"${_pfx}\""
            __bsc_line "for (( __i=\${#${arr}[@]}-1; __i>=0; __i-- )); do ${_sa_tmp}+=\"\${${arr}[\$__i]}\"; done"
        elif (( ${#_prefix_parts[@]} > 0 )); then
            local _pfx=""
            for _pp in "${_prefix_parts[@]}"; do _pfx+="\${$(__bsc_strip_dollar "$_pp")}"; done
            __bsc_line "local ${_sa_tmp}=\"${_pfx}\""
            __bsc_line "for __sa_e in \"\${${arr}[@]}\"; do ${_sa_tmp}+=\"\$__sa_e\"; done"
        else
            __bsc_line "local ${_sa_tmp}=\"\""
            __bsc_line "for __sa_e in \"\${${arr}[@]}\"; do ${_sa_tmp}+=\"\$__sa_e\"; done"
        fi
        __bsc_ret="\"\$${_sa_tmp}\""
        return 0
    fi

    # General apply: function + args
    __bsc_mangle "${proc_e:2}"
    local mfunc="$__bsc_ret"
    __bsc_emit_expr "${__bs_car[$args_rest]}" "expr"
    __bsc_line "$mfunc \"\${$(__bsc_strip_dollar "$__bsc_ret")[@]}\""
    __bsc_ret=""
}

# ── Error ─────────────────────────────────────────────────────────────────────
__bsc_emit_error() {
    local rest="$1"
    __bsc_emit_expr "${__bs_car[$rest]}" "expr"
    __bsc_line "printf 'error: %s\\n' $__bsc_ret >&2"
    __bsc_line "return 1"
    __bsc_ret=""
}

# ── Function call ─────────────────────────────────────────────────────────────
__bsc_emit_call() {
    local head="$1" rest="$2" mode="$3"
    local fname="${head:2}"
    __bsc_mangle "$fname"
    local mfunc="$__bsc_ret"

    # Collect arguments, handling function call results and array expansions
    local args_str=""
    local arg_tmpn=0
    local a="$rest"
    while [[ "$a" != 'n:()' && -n "$a" ]]; do
        __bsc_emit_expr "${__bs_car[$a]}" "expr"
        local v="$__bsc_ret"
        # If variable is a known array, expand it
        if [[ "$v" == '$'* && "$v" != '$('* ]]; then
            local _vn="${v:1}"
            if [[ -n "${__bsc_arr_vars[$_vn]:-}" ]]; then
                v="\"\${${_vn}[@]}\""
            fi
        fi
        # If result is $__r, save to temp to avoid clobbering
        if [[ "$v" == "\$__r" ]]; then
            __bsc_line "local __ca${arg_tmpn}=\"\$__r\""
            v="\$__ca${arg_tmpn}"
            (( arg_tmpn++ ))
        fi
        [[ -n "$args_str" ]] && args_str+=" "
        # Array literal → expand elements inline as individual args
        if [[ "$v" == "("*")" ]]; then
            local inner="${v:1:${#v}-2}"
            # Store in temp array and expand
            __bsc_line "local -a __la${arg_tmpn}=($inner)"
            args_str+="\"\${__la${arg_tmpn}[@]}\""
            (( arg_tmpn++ ))
        elif [[ "$v" == '"'* || "$v" == '$(('* || "$v" =~ ^-?[0-9]+$ || "$v" == "\$'"* ]]; then
            args_str+="$v"
        elif [[ "$v" == '$'* ]]; then
            # Quote bare $var references to prevent word-splitting
            args_str+="\"$v\""
        else
            args_str+="\"$v\""
        fi
        a="${__bs_cdr[$a]}"
    done

    if [[ "$mode" == "expr" ]]; then
        # Need result — emit call then reference __r
        __bsc_line "$mfunc $args_str"
        __bsc_ret="\$__r"
    else
        __bsc_line "$mfunc $args_str"
        __bsc_ret=""
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Phase 2: Expression compilation — arithmetic, strings, comparisons
# ══════════════════════════════════════════════════════════════════════════════

# ── Arithmetic ────────────────────────────────────────────────────────────────
__bsc_emit_arith() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    __bsc_list_to_array "$rest"
    local -a args=("${__bsc_list_result[@]}")

    case "$op" in
        'abs')
            __bsc_emit_arith_val "${args[0]}"
            local v="$__bsc_ret"
            __bsc_ret="\$(( $v < 0 ? -($v) : $v ))"
            return 0 ;;
        'max')
            __bsc_emit_arith_val "${args[0]}"; local a="$__bsc_ret"
            __bsc_emit_arith_val "${args[1]}"; local b="$__bsc_ret"
            __bsc_ret="\$(( $a > $b ? $a : $b ))"
            return 0 ;;
        'min')
            __bsc_emit_arith_val "${args[0]}"; local a="$__bsc_ret"
            __bsc_emit_arith_val "${args[1]}"; local b="$__bsc_ret"
            __bsc_ret="\$(( $a < $b ? $a : $b ))"
            return 0 ;;
        'expt')
            __bsc_emit_arith_val "${args[0]}"; local base="$__bsc_ret"
            __bsc_emit_arith_val "${args[1]}"; local exp="$__bsc_ret"
            __bsc_ret="\$(( $base ** $exp ))"
            return 0 ;;
    esac

    # Standard binary/n-ary ops
    local -a vals=()
    for elem in "${args[@]}"; do
        __bsc_emit_arith_val "$elem"
        vals+=("$__bsc_ret")
    done

    local result
    __bsc_emit_arith_inline_from_vals "$op" vals
    result="$__bsc_ret"
    __bsc_ret="\$(( $result ))"
}

__bsc_emit_arith_inline_from_vals() {
    local op="$1"
    local -n _vals="$2"

    case "$op" in
        '+')
            if (( ${#_vals[@]} == 0 )); then __bsc_ret="0"
            elif (( ${#_vals[@]} == 1 )); then __bsc_ret="${_vals[0]}"
            else
                local r="${_vals[0]}"
                for (( _k=1; _k<${#_vals[@]}; _k++ )); do r+=" + ${_vals[$_k]}"; done
                __bsc_ret="$r"
            fi ;;
        '-')
            if (( ${#_vals[@]} == 1 )); then __bsc_ret="-(${_vals[0]})"
            else
                local r="${_vals[0]}"
                for (( _k=1; _k<${#_vals[@]}; _k++ )); do r+=" - ${_vals[$_k]}"; done
                __bsc_ret="$r"
            fi ;;
        '*')
            if (( ${#_vals[@]} == 0 )); then __bsc_ret="1"
            elif (( ${#_vals[@]} == 1 )); then __bsc_ret="${_vals[0]}"
            else
                local r="${_vals[0]}"
                for (( _k=1; _k<${#_vals[@]}; _k++ )); do r+=" * ${_vals[$_k]}"; done
                __bsc_ret="$r"
            fi ;;
        '/'|'quotient')
            local r="${_vals[0]}"
            for (( _k=1; _k<${#_vals[@]}; _k++ )); do r+=" / ${_vals[$_k]}"; done
            __bsc_ret="$r" ;;
        'remainder'|'modulo')
            __bsc_ret="${_vals[0]} % ${_vals[1]}" ;;
        *) __bsc_ret="${_vals[0]}" ;;
    esac
}

# ── Numeric comparisons ──────────────────────────────────────────────────────
__bsc_emit_num_cmp() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'zero?'|'positive?'|'negative?'|'even?'|'odd?')
            __bsc_emit_arith_val "${__bs_car[$rest]}"
            local v="$__bsc_ret"
            case "$op" in
                'zero?')     __bsc_ret="(( $v == 0 ))" ;;
                'positive?') __bsc_ret="(( $v > 0 ))" ;;
                'negative?') __bsc_ret="(( $v < 0 ))" ;;
                'even?')     __bsc_ret="(( $v % 2 == 0 ))" ;;
                'odd?')      __bsc_ret="(( $v % 2 != 0 ))" ;;
            esac
            return 0 ;;
    esac

    local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
    __bsc_emit_arith_val "$a_e"; local a="$__bsc_ret"
    __bsc_emit_arith_val "$b_e"; local b="$__bsc_ret"

    local bash_op="$op"
    [[ "$op" == "=" ]] && bash_op="=="

    if [[ "$mode" == "test" ]]; then
        __bsc_ret="(( $a $bash_op $b ))"
    else
        __bsc_ret="(( $a $bash_op $b ))"
    fi
}

# ── String/equality comparisons ──────────────────────────────────────────────
__bsc_emit_str_cmp() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"
    local a_e="${__bs_car[$rest]}" b_e="${__bs_car[${__bs_cdr[$rest]}]}"
    __bsc_emit_expr "$a_e" "expr"; local a="$(__bsc_unquote "$__bsc_ret")"
    __bsc_emit_expr "$b_e" "expr"; local b="$(__bsc_unquote "$__bsc_ret")"

    case "$op" in
        'equal?'|'eq?'|'eqv?'|'string=?'|'char=?')
            __bsc_ret="[[ \"$a\" == \"$b\" ]]" ;;
        'string<?'|'char<?')
            __bsc_ret="[[ \"$a\" < \"$b\" ]]" ;;
        'string>?')
            __bsc_ret="[[ \"$a\" > \"$b\" ]]" ;;
        'string<=?')
            __bsc_ret="[[ ! \"$a\" > \"$b\" ]]" ;;
        'string>=?'|'char>=?')
            __bsc_ret="[[ ! \"$a\" < \"$b\" ]]" ;;
    esac
}

# ── String operations ─────────────────────────────────────────────────────────
__bsc_emit_string_op() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'string-append')
            __bsc_list_to_array "$rest"
            # First pass: evaluate all args, saving function results to temps
            local -a sa_vals=()
            local sa_tmpn=0
            for elem in "${__bsc_list_result[@]}"; do
                __bsc_emit_expr "$elem" "expr"
                local v="$__bsc_ret"
                if [[ "$v" == "\$__r" ]]; then
                    # Function call result — save to temp
                    __bsc_line "local __sa${sa_tmpn}=\"\$__r\""
                    sa_vals+=("\$__sa${sa_tmpn}")
                    (( sa_tmpn++ ))
                else
                    sa_vals+=("$v")
                fi
            done
            # Build concatenation
            local parts=""
            for v in "${sa_vals[@]}"; do
                if [[ "$v" == '"'*'"' ]]; then
                    v="${v:1:${#v}-2}"
                    parts+="$v"
                elif [[ "$v" == '$((  '* || "$v" == '$(('* ]]; then
                    # Arithmetic expansion — embed as-is
                    parts+="$v"
                elif [[ "$v" == "\$'"*"'" ]]; then
                    # ANSI-C quoted string: $'\n' → embed literal char
                    local _inner="${v:2:${#v}-3}"
                    _inner="${_inner//\\n/$'\n'}"
                    _inner="${_inner//\\t/$'\t'}"
                    _inner="${_inner//\\\\/\\}"
                    parts+="$_inner"
                elif [[ "$v" == \$* ]]; then
                    parts+="\${${v:1}}"
                else
                    parts+="$v"
                fi
            done
            __bsc_ret="\"${parts}\""
            return 0 ;;

        'string-length')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local v="$__bsc_ret"
            # If it's a simple $variable, use ${#var}
            if [[ "$v" == '$'[a-zA-Z_]* && "$v" != *'['* && "$v" != *'{'* && "$v" != *':'* ]]; then
                __bsc_ret="\${#${v:1}}"
            elif [[ "$v" == '"${'*'}"' ]]; then
                # Complex expansion like "${em_lines[em_cy]:-}" — use temp var
                __bsc_local "__sl=$v"
                __bsc_ret="\${#__sl}"
            else
                __bsc_local "__sl=$v"
                __bsc_ret="\${#__sl}"
            fi
            return 0 ;;

        'substring')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local s="$__bsc_ret"
            s="$(__bsc_strip_dollar "$s")"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local start="$__bsc_ret"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[${__bs_cdr[$rest]}]}]}"
            local end="$__bsc_ret"
            __bsc_ret="\"\${${s}:${start}:\$(( ${end} - ${start} ))}\""
            return 0 ;;

        'string-ref')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local s="$__bsc_ret"
            s="$(__bsc_strip_dollar "$s")"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local idx="$__bsc_ret"
            __bsc_ret="\"\${${s}:${idx}:1}\""
            return 0 ;;

        'string')
            # (string ch) → string from char; single char is identity
            __bsc_list_to_array "$rest"
            if (( ${#__bsc_list_result[@]} == 1 )); then
                __bsc_emit_expr "${__bsc_list_result[0]}" "expr"
                return 0
            fi
            local parts=""
            for elem in "${__bsc_list_result[@]}"; do
                __bsc_emit_expr "$elem" "expr"
                local v="$__bsc_ret"
                if [[ "$v" == '"'*'"' ]]; then
                    v="${v:1:${#v}-2}"
                    parts+="$v"
                elif [[ "$v" == \$* ]]; then
                    parts+="\${${v:1}}"
                else
                    parts+="$v"
                fi
            done
            __bsc_ret="\"${parts}\""
            return 0 ;;

        'make-string')
            __bsc_emit_arith_val "${__bs_car[$rest]}"
            local n="$__bsc_ret"
            local fill_e="${__bs_car[${__bs_cdr[$rest]}]:-}"
            local fill=" "
            if [[ -n "$fill_e" && "$fill_e" != 'n:()' ]]; then
                __bsc_emit_expr "$fill_e" "expr"
                fill="$__bsc_ret"
            fi
            __bsc_ret="\$(printf '%*s' $n '' | tr ' ' \"$fill\")"
            return 0 ;;

        'string-copy')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            return 0 ;;

        'string-upcase')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local v="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_ret="\"\${${v}^^}\""
            return 0 ;;

        'string-downcase')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local v="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_ret="\"\${${v},,}\""
            return 0 ;;

        'number->string')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            # In bash, numbers are already strings — just use the value
            return 0 ;;

        'string->number')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ret="$__bsc_ret"
            return 0 ;;

        'string->symbol'|'symbol->string')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            return 0 ;;

        'string-repeat')
            # Custom helper used in em.scm
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local s="$__bsc_ret"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local n="$__bsc_ret"
            __bsc_line "string_repeat $s $n"
            __bsc_ret="\$__r"
            return 0 ;;
    esac

    __bsc_ret="\"\"  # unhandled string op: $op"
}

# ── Char operations ───────────────────────────────────────────────────────────
__bsc_emit_char_op() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'char->integer')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local ch="$__bsc_ret"
            if [[ "$__bsc_target" == "zsh" ]]; then
                __bsc_line "__r=\$(printf '%d' \"'$ch\" 2>/dev/null) || __r=0"
            else
                __bsc_line "printf -v __r '%d' \"'$ch\""
            fi
            __bsc_ret="\$__r"
            return 0 ;;

        'integer->char')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            # Use pre-built lookup table to avoid fork-per-call overhead.
            # Falls back to subshell for values > 127 (rare in practice).
            local _n="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_line "if (( ${_n} <= 127 )); then"
            __bsc_line "    __r=\"\${__bsc_b2c[${_n}]}\""
            __bsc_line "else"
            __bsc_line "    __r=\$(printf \"\\\\x\$(printf '%x' \"${_n}\")\")"
            __bsc_line "fi"
            __bsc_ret="\$__r"
            return 0 ;;

        'char-alphabetic?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ret="[[ \"$__bsc_ret\" =~ [a-zA-Z] ]]"
            return 0 ;;

        'char-numeric?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ret="[[ \"$__bsc_ret\" =~ [0-9] ]]"
            return 0 ;;

        'char-word?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ret="[[ \"$__bsc_ret\" =~ [a-zA-Z0-9_] ]]"
            return 0 ;;
    esac

    __bsc_ret="\"\"  # unhandled char op: $op"
}

# ── Type predicates ───────────────────────────────────────────────────────────
__bsc_emit_type_pred() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"
    __bsc_emit_expr "${__bs_car[$rest]}" "expr"
    local v="$__bsc_ret"

    case "$op" in
        'not')
            __bsc_emit_test "${__bs_car[$rest]}"
            if [[ "$mode" == "test" ]]; then
                __bsc_ret="! $__bsc_ret"
            else
                # Statement context
                __bsc_ret=""
            fi
            return 0 ;;
        'null?')
            local sv="$(__bsc_strip_dollar "$v")"
            __bsc_ret="[[ \${#${sv}[@]} -eq 0 ]]"
            return 0 ;;
        'pair?'|'list?')
            local sv="$(__bsc_strip_dollar "$v")"
            __bsc_ret="[[ \${#${sv}[@]} -gt 0 ]]"
            return 0 ;;
        'number?')
            __bsc_ret="[[ \"$v\" =~ ^-?[0-9]+\$ ]]"
            return 0 ;;
        'string?')
            __bsc_ret="[[ -n \"$v\" ]]"
            return 0 ;;
        'boolean?')
            __bsc_ret="[[ \"$v\" == \"0\" || \"$v\" == \"1\" ]]"
            return 0 ;;
        'vector?')
            __bsc_ret="[[ -n \"$v\" ]]"
            return 0 ;;
        *)
            __bsc_ret="true  # type pred: $op"
            return 0 ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# Phase 3-4: Data structures — vectors, lists
# ══════════════════════════════════════════════════════════════════════════════

# ── Vector operations ─────────────────────────────────────────────────────────
__bsc_emit_vector_op() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'vector-ref')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local vec="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local idx="$__bsc_ret"
            __bsc_ret="\"\${${vec}[${idx}]}\""
            return 0 ;;

        'vector-ref-safe')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local vec="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local idx="$__bsc_ret"
            __bsc_ret="\"\${${vec}[${idx}]:-}\""
            return 0 ;;

        'vector-set!')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local vec="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local idx="$__bsc_ret"
            __bsc_emit_expr "${__bs_car[${__bs_cdr[${__bs_cdr[$rest]}]}]}" "expr"
            local val="$__bsc_ret"
            __bsc_line "${vec}[${idx}]=$val"
            __bsc_ret=""
            return 0 ;;

        'vector-length')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local vec="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_ret="\${#${vec}[@]}"
            return 0 ;;

        'make-vector')
            __bsc_emit_arith_val "${__bs_car[$rest]}"
            local n="$__bsc_ret"
            local fill_e="${__bs_car[${__bs_cdr[$rest]}]:-}"
            local fill='""'
            if [[ -n "$fill_e" && "$fill_e" != 'n:()' ]]; then
                __bsc_emit_expr "$fill_e" "expr"
                fill="$__bsc_ret"
            fi
            # Emit as loop to fill array
            __bsc_line "local -a __mv=()"
            __bsc_line "for (( __i=0; __i<$n; __i++ )); do __mv+=($fill); done"
            __bsc_ret='("${__mv[@]}")'
            return 0 ;;

        'vector')
            __bsc_list_to_array "$rest"
            local items=""
            for elem in "${__bsc_list_result[@]}"; do
                __bsc_emit_expr "$elem" "expr"
                [[ -n "$items" ]] && items+=" "
                items+="$__bsc_ret"
            done
            __bsc_ret="($items)"
            return 0 ;;

        'vector->list'|'list->vector')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            return 0 ;;  # arrays are arrays

        'vector-insert')
            # (vector-insert vec idx val) → splice val into array at idx
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local vec="$(__bsc_strip_dollar "$__bsc_ret")"
            local rest2="${__bs_cdr[$rest]}"
            __bsc_emit_arith_val "${__bs_car[$rest2]}"
            local idx="$__bsc_ret"
            __bsc_emit_expr "${__bs_car[${__bs_cdr[$rest2]}]}" "expr"
            local val="$__bsc_ret"
            # Quote bare $var refs for safe array embedding
            if [[ "$val" == '$'* && "$val" != '"'* ]]; then
                val="\"$val\""
            fi
            (( __bsc_vi_n = ${__bsc_vi_n:-0} + 1 )) || true
            local tmp="__vi${__bsc_vi_n}"
            local _lkw="local"
            (( __bsc_in_func )) || _lkw="declare"
            __bsc_line "$_lkw -i __vi_idx=\$(( $idx ))"
            __bsc_line "$_lkw -a ${tmp}=(\"\${${vec}[@]:0:__vi_idx}\" $val \"\${${vec}[@]:__vi_idx}\")"
            __bsc_ret="(\"\${${tmp}[@]}\")"
            return 0 ;;

        'vector-remove')
            # (vector-remove vec idx) → remove element at idx
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local vec="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local idx="$__bsc_ret"
            (( __bsc_vr_n = ${__bsc_vr_n:-0} + 1 )) || true
            local tmp="__vr${__bsc_vr_n}"
            local _lkw="local"
            (( __bsc_in_func )) || _lkw="declare"
            __bsc_line "$_lkw -i __vr_idx=\$(( $idx ))"
            __bsc_line "$_lkw -a ${tmp}=(\"\${${vec}[@]:0:__vr_idx}\" \"\${${vec}[@]:__vr_idx+1}\")"
            __bsc_ret="(\"\${${tmp}[@]}\")"
            return 0 ;;
    esac

    __bsc_ret="# unhandled vector op: $op"
}

# ── List operations ───────────────────────────────────────────────────────────
__bsc_emit_list_op() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'cons')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local car_v="$__bsc_ret"
            __bsc_emit_expr "${__bs_car[${__bs_cdr[$rest]}]}" "expr"
            local cdr_v="$__bsc_ret"
            # Prepend to array — extract inner content from cdr
            local _cdr_inner
            if [[ "$cdr_v" == "("*")" ]]; then
                # Strip outer parens: (...) → ...
                _cdr_inner="${cdr_v:1:${#cdr_v}-2}"
            elif [[ "$cdr_v" == "()" ]]; then
                _cdr_inner=""
            else
                local cdr_s="$(__bsc_strip_dollar "$cdr_v")"
                _cdr_inner="\"\${${cdr_s}[@]}\""
            fi
            # Quote bare $var references in car position
            local _qcar="$car_v"
            if [[ "$car_v" == '$'* && "$car_v" != '"'* && "$car_v" != '$('* ]]; then
                _qcar="\"$car_v\""
            fi
            if [[ -n "$_cdr_inner" ]]; then
                __bsc_ret="(${_qcar} ${_cdr_inner})"
            else
                __bsc_ret="(${_qcar})"
            fi
            return 0 ;;

        'car')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local lst="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_ret="\"\${${lst}[0]}\""
            return 0 ;;

        'cdr')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local lst="$(__bsc_strip_dollar "$__bsc_ret")"
            if [[ -n "${__bsc_pair_vars[$lst]:-}" ]]; then
                # Pair: cdr returns second element as scalar
                __bsc_ret="\"\${${lst}[1]}\""
            else
                __bsc_ret="(\"\${${lst}[@]:1}\")"
            fi
            return 0 ;;

        'list')
            __bsc_list_to_array "$rest"
            (( __bsc_list_n = ${__bsc_list_n:-0} + 1 )) || true
            local list_var="__lst${__bsc_list_n}"
            # Evaluate all args into temp array
            local _lkw="local"
            (( __bsc_in_func )) || _lkw="declare"
            __bsc_line "$_lkw -a ${list_var}=()"
            for elem in "${__bsc_list_result[@]}"; do
                __bsc_emit_expr "$elem" "expr"
                local v="$__bsc_ret"
                if [[ "$v" == "\$__r" ]]; then
                    __bsc_line "${list_var}+=(\"\$__r\")"
                elif [[ "$v" == '("'* || "$v" == '($'* ]]; then
                    # Array ref — expand
                    local sv="$(__bsc_strip_dollar "${v:1:${#v}-2}")"
                    __bsc_line "${list_var}+=(\"\${${sv}[@]}\")"
                elif [[ "$v" == "\$"* && "$v" == *"[@]"* ]]; then
                    __bsc_line "${list_var}+=($v)"
                else
                    __bsc_line "${list_var}+=($v)"
                fi
            done
            __bsc_ret="\"\${${list_var}[@]}\""
            return 0 ;;

        'length')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ensure_arr_var; local lst="$__bsc_arr_name"
            __bsc_ret="\${#${lst}[@]}"
            return 0 ;;

        'null?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local lst="$(__bsc_strip_dollar "$__bsc_ret")"
            __bsc_ret="[[ \${#${lst}[@]} -eq 0 ]]"
            return 0 ;;

        'append')
            __bsc_list_to_array "$rest"
            if (( ${#__bsc_list_result[@]} == 2 )); then
                __bsc_emit_expr "${__bsc_list_result[0]}" "expr"
                local _app_a="$__bsc_ret"
                __bsc_emit_expr "${__bsc_list_result[1]}" "expr"
                local _app_b="$__bsc_ret"
                # Extract inner content (strip outer parens if present)
                local _a_inner _b_inner
                if [[ "$_app_a" == "("*")" ]]; then
                    _a_inner="${_app_a:1:${#_app_a}-2}"
                elif [[ "$_app_a" == *'[@]'* ]]; then
                    _a_inner="$_app_a"
                else
                    local _a_s="$(__bsc_strip_dollar "$_app_a")"
                    _a_inner="\"\${${_a_s}[@]}\""
                fi
                if [[ "$_app_b" == "("*")" ]]; then
                    _b_inner="${_app_b:1:${#_app_b}-2}"
                elif [[ "$_app_b" == *'[@]'* ]]; then
                    _b_inner="$_app_b"
                else
                    local _b_s="$(__bsc_strip_dollar "$_app_b")"
                    _b_inner="\"\${${_b_s}[@]}\""
                fi
                __bsc_ret="(${_a_inner} ${_b_inner})"
            else
                __bsc_emit_expr "${__bsc_list_result[0]}" "expr"
                __bsc_ret="$__bsc_ret"
            fi
            return 0 ;;

        'reverse')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ensure_arr_var; local lst="$__bsc_arr_name"
            __bsc_line "local -a __rv=()"
            __bsc_line "for __ri in \"\${${lst}[@]}\"; do __rv=(\"\$__ri\" \"\${__rv[@]}\"); done"
            __bsc_ret='("${__rv[@]}")'
            return 0 ;;

        'list-ref')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ensure_arr_var; local lst="$__bsc_arr_name"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local idx="$__bsc_ret"
            __bsc_ret="\"\${${lst}[${idx}]}\""
            return 0 ;;

        'list-tail')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ensure_arr_var; local lst="$__bsc_arr_name"
            __bsc_emit_arith_val "${__bs_car[${__bs_cdr[$rest]}]}"
            local idx="$__bsc_ret"
            __bsc_ret="(\"\${${lst}[@]:${idx}}\")"
            return 0 ;;
    esac

    __bsc_ret="# unhandled list op: $op"
}

# ── Higher-order: map, for-each, filter ───────────────────────────────────────
__bsc_emit_higher_order() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    local proc_e="${__bs_car[$rest]}"
    local list_e="${__bs_car[${__bs_cdr[$rest]}]}"

    __bsc_emit_expr "$list_e" "expr"
    local lst="$(__bsc_strip_dollar "$__bsc_ret")"

    # Check if proc is a lambda — inline it
    if [[ "${proc_e:0:2}" == "p:" && "${__bs_car[$proc_e]}" == "y:lambda" ]]; then
        local lam_rest="${__bs_cdr[$proc_e]}"
        local lam_params="${__bs_car[$lam_rest]}"
        local lam_body="${__bs_cdr[$lam_rest]}"
        local param_name="${__bs_car[$lam_params]}"
        __bsc_mangle "${param_name:2}"
        local mparam="$__bsc_ret"

        case "$op" in
            'for-each')
                __bsc_line "for $mparam in \"\${${lst}[@]}\"; do"
                __bsc_push_indent
                __bsc_emit_body "$lam_body"
                __bsc_pop_indent
                __bsc_line "done"
                __bsc_ret=""
                return 0 ;;
            'map')
                __bsc_line "local -a __map_r=()"
                __bsc_line "for $mparam in \"\${${lst}[@]}\"; do"
                __bsc_push_indent
                __bsc_emit_body "$lam_body"
                __bsc_line "__map_r+=(\"\$__r\")"
                __bsc_pop_indent
                __bsc_line "done"
                __bsc_ret='("${__map_r[@]}")'
                return 0 ;;
            'filter')
                __bsc_line "local -a __filt_r=()"
                __bsc_line "for $mparam in \"\${${lst}[@]}\"; do"
                __bsc_push_indent
                __bsc_emit_body "$lam_body"
                __bsc_line "[[ -n \"\$__r\" && \"\$__r\" != \"0\" ]] && __filt_r+=(\"\$$mparam\")"
                __bsc_pop_indent
                __bsc_line "done"
                __bsc_ret='("${__filt_r[@]}")'
                return 0 ;;
        esac
    fi

    # Non-lambda proc: call it by name
    if [[ "$proc_e" == y:* ]]; then
        __bsc_mangle "${proc_e:2}"
        local mproc="$__bsc_ret"
        case "$op" in
            'for-each')
                __bsc_line "for __fe_item in \"\${${lst}[@]}\"; do"
                __bsc_push_indent
                __bsc_line "$mproc \"\$__fe_item\""
                __bsc_pop_indent
                __bsc_line "done"
                __bsc_ret=""
                return 0 ;;
            'map')
                __bsc_line "local -a __map_r=()"
                __bsc_line "for __mp_item in \"\${${lst}[@]}\"; do"
                __bsc_push_indent
                __bsc_line "$mproc \"\$__mp_item\""
                __bsc_line "__map_r+=(\"\$__r\")"
                __bsc_pop_indent
                __bsc_line "done"
                __bsc_ret='("${__map_r[@]}")'
                return 0 ;;
            'filter')
                __bsc_line "local -a __filt_r=()"
                __bsc_line "for __fp_item in \"\${${lst}[@]}\"; do"
                __bsc_push_indent
                __bsc_line "$mproc \"\$__fp_item\""
                __bsc_line "[[ -n \"\$__r\" && \"\$__r\" != \"0\" ]] && __filt_r+=(\"\$__fp_item\")"
                __bsc_pop_indent
                __bsc_line "done"
                __bsc_ret='("${__filt_r[@]}")'
                return 0 ;;
        esac
    fi

    __bsc_ret="# unhandled higher-order: $op"
}

# ══════════════════════════════════════════════════════════════════════════════
# Phase 5: I/O operations
# ══════════════════════════════════════════════════════════════════════════════

# ── I/O ───────────────────────────────────────────────────────────────────────
__bsc_emit_io() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'display')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_line "printf '%s' $__bsc_ret >&2"
            __bsc_ret=""
            return 0 ;;
        'write')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_line "printf '%s' $__bsc_ret >&2"
            __bsc_ret=""
            return 0 ;;
        'newline')
            __bsc_line "printf '\\n' >&2"
            __bsc_ret=""
            return 0 ;;
        'write-stdout')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            if [[ "$__bsc_target" == "zsh" ]]; then
                __bsc_line "printf '%s' $__bsc_ret >&\${_BS_OUT_FD:-1}"
            else
                __bsc_line "printf '%s' $__bsc_ret"
            fi
            __bsc_ret=""
            return 0 ;;
        'read-byte')
            __bsc_line "local __rb_ch __rb_rc"
            if [[ "$__bsc_target" == "zsh" ]]; then
                __bsc_line "IFS= read -u\${_BS_IN_FD:-0} -k1 __rb_ch 2>/dev/null; __rb_rc=\$?"
                __bsc_line "if (( __rb_rc != 0 )); then"
                __bsc_line "    __r=\"\""
                __bsc_line "else"
                __bsc_line "    __r=\$(printf '%d' \"'\$__rb_ch\" 2>/dev/null) || __r=0"
                __bsc_line "fi"
            else
                __bsc_line "IFS= read -ru\${_BS_IN_FD:-0} -n1 -d '' __rb_ch; __rb_rc=\$?"
                __bsc_line "if [[ \$__rb_rc -ne 0 && -z \"\$__rb_ch\" ]]; then"
                __bsc_line "    __r=\"\""
                __bsc_line "elif [[ -z \"\$__rb_ch\" ]]; then"
                __bsc_line "    __r=0"
                __bsc_line "else"
                __bsc_line "    printf -v __r '%d' \"'\$__rb_ch\" 2>/dev/null || __r=0"
                __bsc_line "fi"
            fi
            __bsc_ret="\$__r"
            return 0 ;;
        'read-byte-timeout')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local timeout="$__bsc_ret"
            __bsc_line "local __rb_ch __rb_rc"
            if [[ "$__bsc_target" == "zsh" ]]; then
                __bsc_line "IFS= read -u\${_BS_IN_FD:-0} -t $timeout -k1 __rb_ch 2>/dev/null; __rb_rc=\$?"
                __bsc_line "if (( __rb_rc != 0 )); then"
                __bsc_line "    __r=\"\""
                __bsc_line "else"
                __bsc_line "    __r=\$(printf '%d' \"'\$__rb_ch\" 2>/dev/null) || __r=0"
                __bsc_line "fi"
            else
                __bsc_line "IFS= read -ru\${_BS_IN_FD:-0} -n1 -d '' -t $timeout __rb_ch; __rb_rc=\$?"
                __bsc_line "if [[ \$__rb_rc -ne 0 && -z \"\$__rb_ch\" ]]; then"
                __bsc_line "    __r=\"\""
                __bsc_line "elif [[ -z \"\$__rb_ch\" ]]; then"
                __bsc_line "    __r=0"
                __bsc_line "else"
                __bsc_line "    printf -v __r '%d' \"'\$__rb_ch\" 2>/dev/null || __r=0"
                __bsc_line "fi"
            fi
            __bsc_ret="\$__r"
            return 0 ;;
        'read-line')
            __bsc_line "IFS= read -r __r"
            __bsc_ret="\$__r"
            return 0 ;;
    esac

    __bsc_ret="# unhandled io: $op"
}

# ── Terminal ──────────────────────────────────────────────────────────────────
__bsc_emit_terminal() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'terminal-size')
            __bsc_line "local __ts_rows __ts_cols"
            __bsc_line "if [[ -n \"\${LINES:-}\" && -n \"\${COLUMNS:-}\" ]]; then"
            __bsc_line "    __ts_rows=\$LINES; __ts_cols=\$COLUMNS"
            __bsc_line "else"
            __bsc_line "    __ts_rows=\$(tput lines 2>/dev/null) || __ts_rows=0"
            __bsc_line "    __ts_cols=\$(tput cols 2>/dev/null) || __ts_cols=0"
            __bsc_line "fi"
            __bsc_line "if (( __ts_rows <= 0 || __ts_cols <= 0 )); then"
            __bsc_line "    local __ts_sz; __ts_sz=\$(stty size 2>/dev/null) || __ts_sz=\"0 0\""
            __bsc_line "    (( __ts_rows <= 0 )) && __ts_rows=\"\${__ts_sz%% *}\""
            __bsc_line "    (( __ts_cols <= 0 )) && __ts_cols=\"\${__ts_sz##* }\""
            __bsc_line "fi"
            __bsc_line "(( __ts_rows <= 0 )) && __ts_rows=24"
            __bsc_line "(( __ts_cols <= 0 )) && __ts_cols=80"
            # Return as a 2-element array pair
            __bsc_line "__r=(\$__ts_rows \$__ts_cols)"
            __bsc_ret='("${__r[@]}")'
            __bsc_is_pair=1
            return 0 ;;
        'terminal-raw!')
            __bsc_line "__bsc_stty_saved=\$(stty -g 2>/dev/null)"
            __bsc_line "stty raw -echo -isig -ixon -ixoff -icrnl intr undef quit undef susp undef lnext undef 2>/dev/null"
            __bsc_line "stty dsusp undef 2>/dev/null || true"
            if [[ "$__bsc_target" != "zsh" ]]; then
                # Start dd coprocess as sole TTY reader — avoids tcsetattr(TCSADRAIN) on every read-byte
                __bsc_line "if [[ -t 0 ]]; then"
                __bsc_line "    coproc __bsc_tty (dd bs=1 status=none < /dev/tty 2>/dev/null)"
                __bsc_line "    _BS_IN_FD=\${__bsc_tty[0]}"
                __bsc_line "    exec 0</dev/null"
                __bsc_line "fi"
            fi
            __bsc_ret=""
            return 0 ;;
        'terminal-restore!')
            if [[ "$__bsc_target" != "zsh" ]]; then
                __bsc_line "if [[ -n \"\${__bsc_tty_PID:-}\" ]]; then"
                __bsc_line "    kill \"\$__bsc_tty_PID\" 2>/dev/null; wait \"\$__bsc_tty_PID\" 2>/dev/null || true"
                __bsc_line "    exec 0</dev/tty"
                __bsc_line "    _BS_IN_FD=0"
                __bsc_line "fi"
            fi
            __bsc_line "if [[ -n \"\${__bsc_stty_saved:-}\" ]]; then"
            __bsc_line "    stty \"\$__bsc_stty_saved\" 2>/dev/null || stty sane 2>/dev/null"
            __bsc_line "    __bsc_stty_saved=\"\""
            __bsc_line "fi"
            __bsc_ret=""
            return 0 ;;
        'terminal-suspend!')
            __bsc_line "kill -TSTP \$\$ 2>/dev/null"
            __bsc_ret=""
            return 0 ;;
    esac

    __bsc_ret="# unhandled terminal: $op"
}

# ── File I/O ──────────────────────────────────────────────────────────────────
__bsc_emit_file_op() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'file-read')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local path="$__bsc_ret"
            __bsc_line "if [[ -f $path ]]; then"
            __bsc_line "    __r=\$(cat $path 2>/dev/null) || __r=\"\""
            __bsc_line "else"
            __bsc_line "    __r=\"\""
            __bsc_line "fi"
            __bsc_ret="\$__r"
            return 0 ;;
        'file-write')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local path="$__bsc_ret"
            __bsc_emit_expr "${__bs_car[${__bs_cdr[$rest]}]}" "expr"
            local content="$__bsc_ret"
            __bsc_line "{ printf '%s\\n' \"$content\" > \"$path\"; } 2>/dev/null && __r=1 || __r=0"
            __bsc_ret="\$__r"
            return 0 ;;
        'file-write-atomic')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local path="$__bsc_ret"
            __bsc_emit_expr "${__bs_car[${__bs_cdr[$rest]}]}" "expr"
            local content="$__bsc_ret"
            __bsc_line "local __fwa_tmp=\"${path}.em\$\$\""
            __bsc_line "if { printf '%s\\n' \"$content\" > \"\$__fwa_tmp\"; } 2>/dev/null && mv -f \"\$__fwa_tmp\" \"$path\" 2>/dev/null; then"
            __bsc_line "    __r=1"
            __bsc_line "else"
            __bsc_line "    rm -f \"\$__fwa_tmp\" 2>/dev/null; __r=0"
            __bsc_line "fi"
            __bsc_ret="\$__r"
            return 0 ;;
        'file-glob')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local pat="$__bsc_ret"
            __bsc_line "local -a __fg=()"
            if [[ "$__bsc_target" == "zsh" ]]; then
                __bsc_line "for __fgf in \${~${pat}}*(N); do __fg+=(\"\$__fgf\"); done"
            else
                __bsc_line "for __fgf in \${${pat}}*; do [[ -e \"\$__fgf\" ]] && __fg+=(\"\$__fgf\"); done"
            fi
            __bsc_ret='("${__fg[@]}")'
            return 0 ;;
        'file-directory?')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_ret="[[ -d $__bsc_ret ]]"
            return 0 ;;
    esac

    __bsc_ret="# unhandled file op: $op"
}

# ── Shell operations ──────────────────────────────────────────────────────────
__bsc_emit_shell_op() {
    local head="$1" rest="$2" mode="$3"
    local op="${head:2}"

    case "$op" in
        'shell-capture')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            __bsc_line "__r=\$(eval $__bsc_ret 2>/dev/null) || __r=\"0\""
            __bsc_ret="\$__r"
            return 0 ;;
        'shell-exec')
            __bsc_emit_expr "${__bs_car[$rest]}" "expr"
            local cmd="$__bsc_ret"
            __bsc_emit_expr "${__bs_car[${__bs_cdr[$rest]}]}" "expr"
            local input="$__bsc_ret"
            __bsc_line "printf '%s' $input | eval $cmd 2>/dev/null"
            __bsc_line "[[ \$? -eq 0 ]] && __r=1 || __r=0"
            __bsc_ret="\$__r"
            return 0 ;;
    esac

    __bsc_ret="# unhandled shell op: $op"
}

# ── Eval-string ───────────────────────────────────────────────────────────────
__bsc_emit_eval_string() {
    local rest="$1" mode="$2"
    __bsc_emit_expr "${__bs_car[$rest]}" "expr"
    # eval-string needs the interpreter; emit a call to bs() and return (ok? . display)
    __bsc_line "if bs $__bsc_ret 2>/dev/null; then"
    __bsc_line "    __r=(1 \"\$__bs_last_display\")"
    __bsc_line "else"
    __bsc_line "    __r=(0 \"\${__bs_last_error:-error}\")"
    __bsc_line "fi"
    __bsc_ret='("${__r[@]}")'
    __bsc_is_pair=1
}

# ══════════════════════════════════════════════════════════════════════════════
# bs-compile: Public entry point
# ══════════════════════════════════════════════════════════════════════════════
bs-compile() {
    local _src="$1"
    local _bs_old_opts=""
    [[ $- == *e* ]] && _bs_old_opts="e" && set +e

    # Reset compiler state
    __bsc_out=""
    __bsc_indent=""
    __bsc_globals=()
    __bsc_funcs=()
    __bsc_int_vars=()
    __bsc_pair_vars=()
    __bsc_arr_vars=()

    # Emit header
    if [[ "$__bsc_target" == "zsh" ]]; then
        __bsc_line "#!/usr/bin/env zsh"
        __bsc_line "# Generated by bs-compile-zsh (sheme AOT compiler)"
        __bsc_line "# Source: Scheme → Zsh transpilation"
        __bsc_line "setopt KSH_ARRAYS 2>/dev/null || true"
        __bsc_line ""
        __bsc_line "# Return value convention: \$__r for function results"
        __bsc_line "typeset -g __r=\"\" __bsc_stty_saved=\"\""
        __bsc_line ""
    else
        __bsc_line "#!/usr/bin/env bash"
        __bsc_line "# Generated by bs-compile (sheme AOT compiler)"
        __bsc_line "# Source: Scheme → Bash transpilation"
        __bsc_line ""
        __bsc_line "# Return value convention: \$__r for function results"
        __bsc_line "declare -g __r=\"\" __bsc_stty_saved=\"\""
        __bsc_line ""
    fi
    # Emit byte-to-char lookup table — built once at startup, eliminates
    # fork-per-call overhead from integer->char in interactive hot paths.
    if [[ "$__bsc_target" == "zsh" ]]; then
        __bsc_line "# Runtime: byte-to-char lookup table (avoids fork per integer->char call)"
        __bsc_line "typeset -ga __bsc_b2c=()"
        __bsc_line 'for (( __bsc_i=0; __bsc_i<=127; __bsc_i++ )); do'
        __bsc_line '    __bsc_b2c[$__bsc_i]=$(printf "\\$(printf '"'"'%03o'"'"' "$__bsc_i")")'
        __bsc_line 'done'
        __bsc_line ""
    else
        __bsc_line "# Runtime: byte-to-char lookup table (avoids fork per integer->char call)"
        __bsc_line "declare -ga __bsc_b2c=()"
        __bsc_line 'for (( __bsc_i=0; __bsc_i<=127; __bsc_i++ )); do'
        __bsc_line '    __bsc_b2c[$__bsc_i]=$(printf "\\$(printf '"'"'%03o'"'"' "$__bsc_i")")'
        __bsc_line 'done'
        __bsc_line ""
    fi
    # Mark builtins that have Scheme user-defined versions — skip those defines
    __bsc_funcs["string_repeat"]=1
    __bsc_funcs["vector_insert"]=1
    __bsc_funcs["vector_remove"]=1
    __bsc_funcs["em_undo_push"]=1
    __bsc_funcs["em_undo"]=1
    __bsc_funcs["em_lines_list"]=1
    __bsc_funcs["em_make_buffer"]=1
    __bsc_funcs["em_find_buffer_by_id"]=1
    __bsc_funcs["em_find_buffer_by_name"]=1
    __bsc_funcs["em_find_buffer_by_filename"]=1
    __bsc_funcs["em_save_buffer_state"]=1
    __bsc_funcs["em_restore_buffer_state"]=1
    __bsc_funcs["em_new_buffer"]=1
    __bsc_funcs["em_buf_update_name"]=1
    __bsc_funcs["em_do_switch_buffer"]=1
    __bsc_funcs["em_do_kill_buffer"]=1
    __bsc_funcs["em_list_buffers"]=1
    __bsc_funcs["em_complete_buffer"]=1
    __bsc_funcs["em_do_quit"]=1

    __bsc_line "# Runtime helper: string-repeat"
    __bsc_line "string_repeat() {"
    __bsc_line "    local s=\"\$1\" n=\"\$2\" r=\"\""
    __bsc_line "    for (( __i=0; __i<n; __i++ )); do r+=\"\$s\"; done"
    __bsc_line "    __r=\"\$r\""
    __bsc_line "}"
    __bsc_line ""

    # Runtime helper: em_undo_push — packs record fields with US delimiter
    # For replace_region, the last args (saved lines) are packed with RS sub-delimiter
    __bsc_line "# Runtime helper: em_undo_push"
    __bsc_line 'em_undo_push() {'
    __bsc_line '    local US=$'"'"'\x1f'"'"' RS=$'"'"'\x1e'"'"''
    __bsc_line '    local type="$1"'
    __bsc_line '    if [[ "$type" == "replace_region" ]]; then'
    __bsc_line '        local record="${1}${US}${2}${US}${3}${US}${4}${US}${5}"'
    __bsc_line '        shift 5'
    __bsc_line '        local packed=""'
    __bsc_line '        for __ul in "$@"; do'
    __bsc_line '            [[ -n "$packed" ]] && packed+="$RS"'
    __bsc_line '            packed+="$__ul"'
    __bsc_line '        done'
    __bsc_line '        record+="${US}${packed}"'
    __bsc_line '    else'
    __bsc_line '        local record="$1"; shift'
    __bsc_line '        for __ul in "$@"; do record+="${US}${__ul}"; done'
    __bsc_line '    fi'
    __bsc_line '    em_undo_stack=("$record" "${em_undo_stack[@]}")'
    __bsc_line '    (( ${#em_undo_stack[@]} > 200 )) && em_undo_stack=("${em_undo_stack[@]:0:200}")'
    __bsc_line '}'
    __bsc_line ''

    # Runtime helper: em_undo — unpacks record and applies undo operation
    __bsc_line '# Runtime helper: em_undo'
    __bsc_line 'em_undo() {'
    __bsc_line '    local US=$'"'"'\x1f'"'"' RS=$'"'"'\x1e'"'"''
    __bsc_line '    if (( ${#em_undo_stack[@]} == 0 )); then'
    __bsc_line '        em_message="No further undo information"; return'
    __bsc_line '    fi'
    __bsc_line '    local __rec="${em_undo_stack[0]}"'
    __bsc_line '    em_undo_stack=("${em_undo_stack[@]:1}")'
    __bsc_line '    local -a __f=()'
    __bsc_line '    while [[ "$__rec" == *"$US"* ]]; do'
    __bsc_line '        __f+=("${__rec%%"$US"*}"); __rec="${__rec#*"$US"}"'
    __bsc_line '    done'
    __bsc_line '    __f+=("$__rec")'
    __bsc_line '    local __type="${__f[0]}"'
    __bsc_line '    case "$__type" in'
    __bsc_line '        insert_char)'
    __bsc_line '            local -i __y=${__f[1]} __x=${__f[2]}'
    __bsc_line '            local __ch="${__f[3]}" __ln="${em_lines[__y]:-}"'
    __bsc_line '            em_lines[__y]="${__ln:0:__x}${__ch}${__ln:__x}"'
    __bsc_line '            em_cy=$__y; em_cx=$__x ;;'
    __bsc_line '        delete_char)'
    __bsc_line '            local -i __y=${__f[1]} __x=${__f[2]}'
    __bsc_line '            local __ln="${em_lines[__y]:-}"'
    __bsc_line '            em_lines[__y]="${__ln:0:__x}${__ln:__x+1}"'
    __bsc_line '            em_cy=$__y; em_cx=$__x ;;'
    __bsc_line '        join_lines)'
    __bsc_line '            local -i __y=${__f[1]} __x=${__f[2]}'
    __bsc_line '            local __ln="${em_lines[__y]:-}"'
    __bsc_line '            em_lines[__y]="${__ln:0:__x}"'
    __bsc_line '            local -i __idx=__y+1'
    __bsc_line '            em_lines=("${em_lines[@]:0:__idx}" "${__ln:__x}" "${em_lines[@]:__idx}")'
    __bsc_line '            (( em_nlines++ )) || true'
    __bsc_line '            em_cy=$__y; em_cx=$__x ;;'
    __bsc_line '        split_line)'
    __bsc_line '            local -i __y=${__f[1]} __x=${__f[2]}'
    __bsc_line '            local __ln="${em_lines[__y]:-}" __nx="${em_lines[__y+1]:-}"'
    __bsc_line '            em_lines[__y]="${__ln}${__nx}"'
    __bsc_line '            local -i __idx=__y+1'
    __bsc_line '            em_lines=("${em_lines[@]:0:__idx}" "${em_lines[@]:__idx+1}")'
    __bsc_line '            (( em_nlines-- )) || true'
    __bsc_line '            em_cy=$__y; em_cx=$__x ;;'
    __bsc_line '        replace_line)'
    __bsc_line '            local -i __y=${__f[1]} __x=${__f[2]}'
    __bsc_line '            em_lines[__y]="${__f[3]}"'
    __bsc_line '            em_cy=$__y; em_cx=$__x ;;'
    __bsc_line '        replace_region)'
    __bsc_line '            local -i __sy=${__f[1]} __nc=${__f[2]} __scy=${__f[3]} __scx=${__f[4]}'
    __bsc_line '            local __pk="${__f[5]}"'
    __bsc_line '            local -a __sv=()'
    __bsc_line '            while [[ "$__pk" == *"$RS"* ]]; do'
    __bsc_line '                __sv+=("${__pk%%"$RS"*}"); __pk="${__pk#*"$RS"}"'
    __bsc_line '            done'
    __bsc_line '            __sv+=("$__pk")'
    __bsc_line '            local -i __i'
    __bsc_line '            for (( __i=0; __i<__nc && em_nlines>0; __i++ )); do'
    __bsc_line '                em_lines=("${em_lines[@]:0:__sy}" "${em_lines[@]:__sy+1}")'
    __bsc_line '                (( em_nlines-- )) || true'
    __bsc_line '            done'
    __bsc_line '            for (( __i=0; __i<${#__sv[@]}; __i++ )); do'
    __bsc_line '                local -i __idx=__sy+__i'
    __bsc_line '                em_lines=("${em_lines[@]:0:__idx}" "${__sv[__i]}" "${em_lines[@]:__idx}")'
    __bsc_line '                (( em_nlines++ )) || true'
    __bsc_line '            done'
    __bsc_line '            (( em_nlines == 0 )) && { em_lines=(""); em_nlines=1; }'
    __bsc_line '            em_cy=$__scy; em_cx=$__scx ;;'
    __bsc_line '    esac'
    __bsc_line '    em_modified=1'
    __bsc_line '    em_ensure_visible'
    __bsc_line '    em_message="Undo!"'
    __bsc_line '}'
    __bsc_line ''

    # Runtime helper: em_lines_list — collect lines sy..ey into array
    __bsc_line '# Runtime helper: em_lines_list'
    __bsc_line 'em_lines_list() {'
    __bsc_line '    local -i __sy=$1 __ey=$2'
    __bsc_line '    __r=("${em_lines[@]:__sy:__ey-__sy+1}")'
    __bsc_line '}'
    __bsc_line ''

    # ── Buffer system runtime helpers ────────────────────────────────────
    # Uses an associative array em_bufs with keys like "${id}_field"
    # em_buf_ids tracks known buffer IDs as a regular array
    __bsc_line '# Buffer system: uses em_bufs associative array for nested state'
    __bsc_line 'declare -gA em_bufs=()'
    __bsc_line 'declare -ga em_buf_ids=()'
    __bsc_line ''

    __bsc_line 'em_make_buffer() {'
    __bsc_line '    local -i id=$1; local name="$2" filename="$3"'
    __bsc_line '    em_bufs["${id}_name"]="$name"'
    __bsc_line '    em_bufs["${id}_filename"]="$filename"'
    __bsc_line '    em_bufs["${id}_nlines"]=1'
    __bsc_line '    em_bufs["${id}_line_0"]=""'
    __bsc_line '    em_bufs["${id}_cy"]=0; em_bufs["${id}_cx"]=0'
    __bsc_line '    em_bufs["${id}_top"]=0; em_bufs["${id}_left"]=0'
    __bsc_line '    em_bufs["${id}_modified"]=0'
    __bsc_line '    em_bufs["${id}_goal_col"]=-1'
    __bsc_line '    em_bufs["${id}_mark_y"]=-1; em_bufs["${id}_mark_x"]=-1'
    __bsc_line '    em_bufs["${id}_undo"]=""'
    __bsc_line '    em_bufs["${id}_kill"]=""'
    __bsc_line '    __r=$id'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_find_buffer_by_id() {'
    __bsc_line '    local -i id=$1 bid'
    __bsc_line '    for bid in "${em_buf_ids[@]}"; do'
    __bsc_line '        if (( bid == id )); then __r=$bid; return 0; fi'
    __bsc_line '    done'
    __bsc_line '    __r=0; return 1'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_find_buffer_by_name() {'
    __bsc_line '    local target="$1" bid'
    __bsc_line '    for bid in "${em_buf_ids[@]}"; do'
    __bsc_line '        if [[ "${em_bufs["${bid}_name"]}" == "$target" ]]; then __r=$bid; return 0; fi'
    __bsc_line '    done'
    __bsc_line '    __r=0; return 1'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_find_buffer_by_filename() {'
    __bsc_line '    local target="$1" bid'
    __bsc_line '    for bid in "${em_buf_ids[@]}"; do'
    __bsc_line '        if [[ "${em_bufs["${bid}_filename"]}" == "$target" ]]; then __r=$bid; return 0; fi'
    __bsc_line '    done'
    __bsc_line '    __r=0; return 1'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_save_buffer_state() {'
    __bsc_line '    local -i bid=$em_cur_buf_id'
    __bsc_line '    em_bufs["${bid}_name"]="$em_bufname"'
    __bsc_line '    em_bufs["${bid}_filename"]="$em_filename"'
    __bsc_line '    em_bufs["${bid}_nlines"]=$em_nlines'
    __bsc_line '    em_bufs["${bid}_cy"]=$em_cy; em_bufs["${bid}_cx"]=$em_cx'
    __bsc_line '    em_bufs["${bid}_top"]=$em_scroll_top; em_bufs["${bid}_left"]=$em_left'
    __bsc_line '    em_bufs["${bid}_modified"]=$em_modified'
    __bsc_line '    em_bufs["${bid}_goal_col"]=$em_goal_col'
    __bsc_line '    em_bufs["${bid}_mark_y"]=$em_mark_y; em_bufs["${bid}_mark_x"]=$em_mark_x'
    __bsc_line '    local -i __i old_n=${em_bufs["${bid}_old_nlines"]:-0}'
    __bsc_line '    for (( __i=em_nlines; __i<old_n; __i++ )); do'
    __bsc_line '        unset "em_bufs[${bid}_line_${__i}]" 2>/dev/null'
    __bsc_line '    done'
    __bsc_line '    em_bufs["${bid}_old_nlines"]=$em_nlines'
    __bsc_line '    for (( __i=0; __i<em_nlines; __i++ )); do'
    __bsc_line '        em_bufs["${bid}_line_${__i}"]="${em_lines[__i]}"'
    __bsc_line '    done'
    __bsc_line '    local GS=$'"'"'\x1d'"'"''
    __bsc_line '    local __us="" __rec; for __rec in "${em_undo_stack[@]}"; do'
    __bsc_line '        [[ -n "$__us" ]] && __us+="$GS"; __us+="$__rec"'
    __bsc_line '    done'
    __bsc_line '    em_bufs["${bid}_undo"]="$__us"'
    __bsc_line '    local __ks="" __kr; for __kr in "${em_kill_ring[@]}"; do'
    __bsc_line '        [[ -n "$__ks" ]] && __ks+="$GS"; __ks+="$__kr"'
    __bsc_line '    done'
    __bsc_line '    em_bufs["${bid}_kill"]="$__ks"'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_restore_buffer_state() {'
    __bsc_line '    local -i bid=$1'
    __bsc_line '    em_cur_buf_id=$bid'
    __bsc_line '    em_bufname="${em_bufs["${bid}_name"]}"'
    __bsc_line '    em_filename="${em_bufs["${bid}_filename"]}"'
    __bsc_line '    em_nlines=${em_bufs["${bid}_nlines"]:-1}'
    __bsc_line '    em_cy=${em_bufs["${bid}_cy"]:-0}; em_cx=${em_bufs["${bid}_cx"]:-0}'
    __bsc_line '    em_scroll_top=${em_bufs["${bid}_top"]:-0}; em_left=${em_bufs["${bid}_left"]:-0}'
    __bsc_line '    em_modified=${em_bufs["${bid}_modified"]:-0}'
    __bsc_line '    em_goal_col=${em_bufs["${bid}_goal_col"]:-"-1"}'
    __bsc_line '    em_mark_y=${em_bufs["${bid}_mark_y"]:-"-1"}; em_mark_x=${em_bufs["${bid}_mark_x"]:-"-1"}'
    __bsc_line '    em_lines=()'
    __bsc_line '    local -i __i __nl=$em_nlines'
    __bsc_line '    for (( __i=0; __i<__nl; __i++ )); do'
    __bsc_line '        em_lines+=("${em_bufs["${bid}_line_${__i}"]}")'
    __bsc_line '    done'
    __bsc_line '    [[ ${#em_lines[@]} -eq 0 ]] && em_lines=("")'
    __bsc_line '    local GS=$'"'"'\x1d'"'"''
    __bsc_line '    em_undo_stack=()'
    __bsc_line '    local __us="${em_bufs["${bid}_undo"]}"'
    __bsc_line '    if [[ -n "$__us" ]]; then'
    __bsc_line '        while [[ "$__us" == *"$GS"* ]]; do'
    __bsc_line '            em_undo_stack+=("${__us%%"$GS"*}"); __us="${__us#*"$GS"}"'
    __bsc_line '        done'
    __bsc_line '        em_undo_stack+=("$__us")'
    __bsc_line '    fi'
    __bsc_line '    em_kill_ring=()'
    __bsc_line '    local __ks="${em_bufs["${bid}_kill"]}"'
    __bsc_line '    if [[ -n "$__ks" ]]; then'
    __bsc_line '        while [[ "$__ks" == *"$GS"* ]]; do'
    __bsc_line '            em_kill_ring+=("${__ks%%"$GS"*}"); __ks="${__ks#*"$GS"}"'
    __bsc_line '        done'
    __bsc_line '        em_kill_ring+=("$__ks")'
    __bsc_line '    fi'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_new_buffer() {'
    __bsc_line '    local name="$1" filename="$2"'
    __bsc_line '    (( em_buf_id_counter++ )) || true'
    __bsc_line '    em_make_buffer $em_buf_id_counter "$name" "$filename"'
    __bsc_line '    em_buf_ids+=($em_buf_id_counter)'
    __bsc_line '    em_cur_buf_id=$em_buf_id_counter'
    __bsc_line '    em_bufname="$name"; em_filename="$filename"'
    __bsc_line '    em_lines=(""); em_nlines=1'
    __bsc_line '    em_cy=0; em_cx=0; em_scroll_top=0; em_left=0'
    __bsc_line '    em_modified=0; em_goal_col=-1'
    __bsc_line '    em_mark_y=-1; em_mark_x=-1'
    __bsc_line '    em_undo_stack=(); em_kill_ring=()'
    __bsc_line '    __r=$em_buf_id_counter'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_buf_update_name() {'
    __bsc_line '    local name="$1" filename="$2"'
    __bsc_line '    em_bufs["${em_cur_buf_id}_name"]="$name"'
    __bsc_line '    em_bufs["${em_cur_buf_id}_filename"]="$filename"'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_do_switch_buffer() {'
    __bsc_line '    local target="$1"'
    __bsc_line '    [[ -z "$target" ]] && target="$em_bufname"'
    __bsc_line '    if em_find_buffer_by_name "$target"; then'
    __bsc_line '        local -i __bid=$__r'
    __bsc_line '        em_save_buffer_state'
    __bsc_line '        em_restore_buffer_state $__bid'
    __bsc_line '        em_message="$em_bufname"'
    __bsc_line '    else'
    __bsc_line '        em_message="No buffer named '"'"'${target}'"'"'"'
    __bsc_line '    fi'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_do_kill_buffer() {'
    __bsc_line '    local target="$1"'
    __bsc_line '    [[ -z "$target" ]] && target="$em_bufname"'
    __bsc_line '    if (( ${#em_buf_ids[@]} <= 1 )); then'
    __bsc_line '        em_message="Cannot kill the only buffer"; return'
    __bsc_line '    fi'
    __bsc_line '    if ! em_find_buffer_by_name "$target"; then'
    __bsc_line '        em_message="No buffer named '"'"'${target}'"'"'"; return'
    __bsc_line '    fi'
    __bsc_line '    local -i __bid=$__r __is_cur=0'
    __bsc_line '    (( __bid == em_cur_buf_id )) && __is_cur=1'
    __bsc_line '    local -a __new_ids=()'
    __bsc_line '    local __b; for __b in "${em_buf_ids[@]}"; do'
    __bsc_line '        (( __b != __bid )) && __new_ids+=($__b)'
    __bsc_line '    done'
    __bsc_line '    em_buf_ids=("${__new_ids[@]}")'
    __bsc_line '    if (( __is_cur )); then'
    __bsc_line '        em_restore_buffer_state ${em_buf_ids[0]}'
    __bsc_line '    fi'
    __bsc_line '    em_message="Killed buffer '"'"'${target}'"'"'"'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_list_buffers() {'
    __bsc_line '    em_save_buffer_state'
    __bsc_line '    local -a __bl=(" MR  Buffer               Size    File"'
    __bsc_line '                   " --  --------------------  ----    ----")'
    __bsc_line '    local __b; for __b in "${em_buf_ids[@]}"; do'
    __bsc_line '        local __bn="${em_bufs["${__b}_name"]}" __bf="${em_bufs["${__b}_filename"]}"'
    __bsc_line '        local __bm=${em_bufs["${__b}_modified"]:-0} __bnl=${em_bufs["${__b}_nlines"]:-1}'
    __bsc_line '        local __cur=" " __mod=" "'
    __bsc_line '        (( __b == em_cur_buf_id )) && __cur="."'
    __bsc_line '        (( __bm == 1 )) && __mod="*"'
    __bsc_line '        string_repeat " " $(( 20 - ${#__bn} ))'
    __bsc_line '        local __pad="$__r"'
    __bsc_line '        __bl+=(" ${__cur}${__mod}  ${__bn}${__pad}  ${__bnl}    ${__bf}")'
    __bsc_line '    done'
    __bsc_line '    __bl+=("" "[Press C-g or q to return]")'
    __bsc_line '    local -a __save_lines=("${em_lines[@]}")'
    __bsc_line '    local -i __save_nlines=$em_nlines __save_cy=$em_cy __save_cx=$em_cx __save_top=$em_scroll_top'
    __bsc_line '    local __save_mod=$em_modified __save_name="$em_bufname" __save_file="$em_filename"'
    __bsc_line '    em_lines=("${__bl[@]}"); em_nlines=${#__bl[@]}'
    __bsc_line '    em_cy=0; em_cx=0; em_scroll_top=0'
    __bsc_line '    em_bufname="*Buffer List*"; em_filename=""; em_modified=0; em_message=""'
    __bsc_line '    while true; do'
    __bsc_line '        em_render'
    __bsc_line '        em_read_key'
    __bsc_line '        local __k="$__r"'
    __bsc_line '        case "$__k" in'
    __bsc_line '            C-g|SELF:q) break ;;'
    __bsc_line '            C-n|DOWN) em_next_line ;;'
    __bsc_line '            C-p|UP) em_previous_line ;;'
    __bsc_line '            C-v|PGDN) em_scroll_down ;;'
    __bsc_line '            M-v|PGUP) em_scroll_up ;;'
    __bsc_line '        esac'
    __bsc_line '    done'
    __bsc_line '    em_restore_buffer_state $em_cur_buf_id'
    __bsc_line '    em_message=""'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_complete_buffer() {'
    __bsc_line '    local input="$1" __b'
    __bsc_line '    __r=()'
    __bsc_line '    for __b in "${em_buf_ids[@]}"; do'
    __bsc_line '        local __bn="${em_bufs["${__b}_name"]}"'
    __bsc_line '        if [[ -z "$input" || "$__bn" == "$input"* ]]; then'
    __bsc_line '            __r+=("$__bn")'
    __bsc_line '        fi'
    __bsc_line '    done'
    __bsc_line '}'
    __bsc_line ''

    __bsc_line 'em_do_quit() {'
    __bsc_line '    em_save_buffer_state'
    __bsc_line '    local -i __unsaved=0 __b'
    __bsc_line '    for __b in "${em_buf_ids[@]}"; do'
    __bsc_line '        if (( ${em_bufs["${__b}_modified"]:-0} == 1 )) && [[ "${em_bufs["${__b}_name"]}" != "*scratch*" ]]; then'
    __bsc_line '            (( __unsaved++ )) || true'
    __bsc_line '        fi'
    __bsc_line '    done'
    __bsc_line '    if (( __unsaved > 0 )); then'
    __bsc_line '        em_minibuffer_start "${__unsaved} modified buffer(s) not saved; exit anyway? (yes or no) " "quit-confirm"'
    __bsc_line '    else'
    __bsc_line '        em_running=0'
    __bsc_line '    fi'
    __bsc_line '}'
    __bsc_line ''

    # Parse and compile all top-level forms
    __bs_tokenize "$_src"
    __bs_tpos=0
    while (( __bs_tpos < ${#__bs_tokens[@]} )); do
        __bs_parse_expr || break
        local parsed="$__bs_ret"
        __bsc_emit_expr "$parsed" "stmt"
        # If there's a leftover expression result, emit it
        [[ -n "$__bsc_ret" && "$__bsc_ret" != "" ]] && __bsc_line "$__bsc_ret"
    done

    # Output the result
    printf '%s' "$__bsc_out"

    __bsc_target="bash"   # reset to default
    [[ -n "$_bs_old_opts" ]] && set -e
    return 0
}

# ── bs-compile-zsh ────────────────────────────────────────────────────────────
# Compile Scheme source to native zsh code.
# Usage: bs-compile-zsh <scheme-source>
# Output: zsh script on stdout (cache as *.zsh.cache; source to get functions)
# ──────────────────────────────────────────────────────────────────────────────
bs-compile-zsh() {
    __bsc_target="zsh"
    bs-compile "$@"
}
