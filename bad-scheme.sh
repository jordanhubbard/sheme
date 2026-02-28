#!/usr/bin/env bash
# bad-scheme.sh - Scheme interpreter in Bash
# Source this file; then call:  eval "$(bs '<scheme source>')"

# ──────────────────────────────────────────────────────────────────────────────
# State-file path (unique per top-level shell session)
# ──────────────────────────────────────────────────────────────────────────────
__BS_STATE_FILE="${TMPDIR:-/tmp}/__bs_state_$$"

# ──────────────────────────────────────────────────────────────────────────────
# Heap - pairs
# ──────────────────────────────────────────────────────────────────────────────
declare -gA __bs_car=()
declare -gA __bs_cdr=()

# ──────────────────────────────────────────────────────────────────────────────
# Heap - closures
# ──────────────────────────────────────────────────────────────────────────────
declare -gA __bs_closure_params=()   # f:<id>  -> Scheme param list (p:... or n:() or y:rest)
declare -gA __bs_closure_body=()     # f:<id>  -> Scheme body list  (p:...)
declare -gA __bs_closure_env=()      # f:<id>  -> env-id of definition site

# ──────────────────────────────────────────────────────────────────────────────
# Heap - vectors (stored inline in __bs_env as vid:idx)
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Environments  __bs_env["envid:varname"] = tagged-value
#               __bs_env_parent["envid"]  = parent envid for lexical scope chain
#               __bs_env_parent["envid"]  = parent-envid  (empty string = no parent)
# env-id 0 is the global environment
# ──────────────────────────────────────────────────────────────────────────────
declare -gA __bs_env=()
declare -gA __bs_env_parent=()

declare -g __bs_heap_next=0
declare -g __bs_env_next=1     # 0 is global; user frames start at 1
declare -g __bs_last=""
declare -g __bs_output_file="" # set by bs() for each invocation

# ──────────────────────────────────────────────────────────────────────────────
# Heap allocation helpers
# ──────────────────────────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# Environment helpers
# ──────────────────────────────────────────────────────────────────────────────
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
    # Check builtins
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

# ──────────────────────────────────────────────────────────────────────────────
# Builtin name table (no heap entries needed)
# ──────────────────────────────────────────────────────────────────────────────
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
        'string-upcase'|'string-downcase') return 0 ;;
        'char->integer'|'integer->char'|'char=?'|'char<?'|'char-alphabetic?'|'char-numeric?') return 0 ;;
        display|write|newline|apply|error|'read-line') return 0 ;;
        'make-vector'|vector|'vector-ref'|'vector-set!'|'vector-length'|'vector->list'|'list->vector'|'vector?') return 0 ;;
        'exact->inexact'|'inexact->exact'|exact|inexact|floor|ceiling|round|truncate) return 0 ;;
        'call-with-current-continuation'|'call/cc') return 0 ;;
        'with-exception-handler'|raise|'raise-continuable') return 0 ;;
        values|'call-with-values') return 0 ;;
        'foldl'|'foldr'|'fold-left'|'fold-right') return 0 ;;
        *) return 1 ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────────────
# Error helper
# ──────────────────────────────────────────────────────────────────────────────
__bs_error() {
    printf 'bad-scheme: %s\n' "$*" >&2
    __bs_ret="n:()"
}

# Return 0 if $1 is a valid Bash variable name (no hyphens etc.)
__bs_valid_bash_id() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# Tokenizer
# ──────────────────────────────────────────────────────────────────────────────
declare -ga __bs_tokens=()
declare -g  __bs_tpos=0

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

        # Parentheses & dot
        case "$c" in
            '('|')') __bs_tokens+=("$c"); (( i++ )); continue ;;
        esac

        # Quote abbreviation
        if [[ "$c" == "'" ]]; then
            __bs_tokens+=("QUOTE"); (( i++ )); continue
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

# ──────────────────────────────────────────────────────────────────────────────
# Parser
# ──────────────────────────────────────────────────────────────────────────────
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
        # Character literals  #\a  #\space  #\newline
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
            # Strip surrounding quotes and process escape sequences
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

# ──────────────────────────────────────────────────────────────────────────────
# Display / Write helpers
# ──────────────────────────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# Evaluator
# ──────────────────────────────────────────────────────────────────────────────
# Forward declaration of __bs_apply (defined after evaluator helpers)

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

        # ── quote ──────────────────────────────────────────────────────────
        'y:quote')
            __bs_ret="${__bs_car[$rest]}"
            return 0 ;;

        # ── if ─────────────────────────────────────────────────────────────
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

        # ── define ─────────────────────────────────────────────────────────
        'y:define')
            local name_part="${__bs_car[$rest]}"
            local body_rest="${__bs_cdr[$rest]}"

            if [[ "$name_part" == y:* ]]; then
                # (define var expr)
                __bs_eval "${__bs_car[$body_rest]}" "$env" || return 1
                local def_val="$__bs_ret"
                __bs_env_bind "$env" "${name_part:2}" "$def_val"
                if [[ "$env" == '0' ]] && __bs_valid_bash_id "${name_part:2}"; then
                    printf 'declare -g %s=%q\n' "${name_part:2}" "$def_val" >> "$__bs_output_file"
                fi
            else
                # (define (fname params...) body...)
                local fname="${__bs_car[$name_part]}"
                local params="${__bs_cdr[$name_part]}"
                __bs_make_closure "$params" "$body_rest" "$env"
                local clos="$__bs_ret"
                __bs_env_bind "$env" "${fname:2}" "$clos"
                if [[ "$env" == '0' ]] && __bs_valid_bash_id "${fname:2}"; then
                    printf 'declare -g %s=%q\n' "${fname:2}" "$clos" >> "$__bs_output_file"
                fi
            fi
            __bs_ret="n:()"
            return 0 ;;

        # ── set! ───────────────────────────────────────────────────────────
        'y:set!')
            local sv="${__bs_car[$rest]}"
            __bs_eval "${__bs_car[${__bs_cdr[$rest]}]}" "$env" || return 1
            local set_val="$__bs_ret"
            __bs_env_set_existing "$env" "${sv:2}" "$set_val" || return 1
            if [[ "$env" == '0' ]] && __bs_valid_bash_id "${sv:2}"; then
                printf 'declare -g %s=%q\n' "${sv:2}" "$set_val" >> "$__bs_output_file"
            else
                # Also propagate if the binding lives in the global frame
                local _cur="$env"
                while [[ -n "$_cur" ]]; do
                    if [[ -v __bs_env["${_cur}:${sv:2}"] && "$_cur" == '0' ]]; then
                        __bs_valid_bash_id "${sv:2}" && \
                            printf 'declare -g %s=%q\n' "${sv:2}" "$set_val" >> "$__bs_output_file"
                        break
                    fi
                    _cur="${__bs_env_parent[$_cur]:-}"
                done
            fi
            __bs_ret="n:()"
            return 0 ;;

        # ── lambda ─────────────────────────────────────────────────────────
        'y:lambda')
            local lam_params="${__bs_car[$rest]}"
            local lam_body="${__bs_cdr[$rest]}"
            __bs_make_closure "$lam_params" "$lam_body" "$env"
            return 0 ;;

        # ── begin ──────────────────────────────────────────────────────────
        'y:begin')
            __bs_eval_seq "$rest" "$env"
            return 0 ;;

        # ── let ────────────────────────────────────────────────────────────
        'y:let')
            __bs_eval_let "$rest" "$env"
            return 0 ;;

        # ── let* ───────────────────────────────────────────────────────────
        'y:let*')
            __bs_eval_letstar "$rest" "$env"
            return 0 ;;

        # ── letrec / letrec* ───────────────────────────────────────────────
        'y:letrec'|'y:letrec*')
            __bs_eval_letrec "$rest" "$env"
            return 0 ;;

        # ── cond ───────────────────────────────────────────────────────────
        'y:cond')
            __bs_eval_cond "$rest" "$env"
            return 0 ;;

        # ── and ────────────────────────────────────────────────────────────
        'y:and')
            __bs_ret="b:#t"
            local and_exprs="$rest"
            while [[ "$and_exprs" != 'n:()' ]]; do
                __bs_eval "${__bs_car[$and_exprs]}" "$env" || return 1
                [[ "$__bs_ret" == 'b:#f' ]] && return 0
                and_exprs="${__bs_cdr[$and_exprs]}"
            done
            return 0 ;;

        # ── or ─────────────────────────────────────────────────────────────
        'y:or')
            __bs_ret="b:#f"
            local or_exprs="$rest"
            while [[ "$or_exprs" != 'n:()' ]]; do
                __bs_eval "${__bs_car[$or_exprs]}" "$env" || return 1
                [[ "$__bs_ret" != 'b:#f' ]] && return 0
                or_exprs="${__bs_cdr[$or_exprs]}"
            done
            return 0 ;;

        # ── when ───────────────────────────────────────────────────────────
        'y:when')
            __bs_eval "${__bs_car[$rest]}" "$env" || return 1
            if [[ "$__bs_ret" != 'b:#f' ]]; then
                __bs_eval_seq "${__bs_cdr[$rest]}" "$env"
            else
                __bs_ret="n:()"
            fi
            return 0 ;;

        # ── unless ─────────────────────────────────────────────────────────
        'y:unless')
            __bs_eval "${__bs_car[$rest]}" "$env" || return 1
            if [[ "$__bs_ret" == 'b:#f' ]]; then
                __bs_eval_seq "${__bs_cdr[$rest]}" "$env"
            else
                __bs_ret="n:()"
            fi
            return 0 ;;

        # ── case ───────────────────────────────────────────────────────────
        'y:case')
            __bs_eval_case "$rest" "$env"
            return 0 ;;

        # ── do ─────────────────────────────────────────────────────────────
        'y:do')
            __bs_eval_do "$rest" "$env"
            return 0 ;;

        # ── quasiquote ─────────────────────────────────────────────────────
        'y:quasiquote')
            __bs_eval_quasiquote "${__bs_car[$rest]}" "$env"
            return 0 ;;

        # ── define-record-type / define-syntax (stubs) ─────────────────────
        'y:define-record-type'|'y:define-syntax'|'y:syntax-rules'|'y:let-syntax'|'y:letrec-syntax')
            __bs_ret="n:()"
            return 0 ;;

        # ── values (pass-through first value) ──────────────────────────────
        'y:values')
            if [[ "$rest" != 'n:()' ]]; then
                __bs_eval "${__bs_car[$rest]}" "$env"
            else
                __bs_ret="n:()"
            fi
            return 0 ;;

        # ── apply ──────────────────────────────────────────────────────────
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

    # ── Function application ────────────────────────────────────────────────
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

# ── Evaluate a sequence, return last ──────────────────────────────────────────
__bs_eval_seq() {                     # exprs env
    local exprs="$1" env="$2"
    __bs_ret="n:()"
    while [[ "$exprs" != 'n:()' && -n "$exprs" ]]; do
        __bs_eval "${__bs_car[$exprs]}" "$env" || return 1
        exprs="${__bs_cdr[$exprs]}"
    done
}

# ── let ───────────────────────────────────────────────────────────────────────
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

# ── let* ──────────────────────────────────────────────────────────────────────
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

# ── letrec ────────────────────────────────────────────────────────────────────
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

# ── cond ──────────────────────────────────────────────────────────────────────
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
    # No clause matched
    __bs_ret="n:()"
}

# ── case ──────────────────────────────────────────────────────────────────────
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

# ── do ────────────────────────────────────────────────────────────────────────
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

# ── quasiquote ────────────────────────────────────────────────────────────────
__bs_eval_quasiquote() {              # tmpl env
    local tmpl="$1" env="$2"
    if [[ "$tmpl" == p:* ]]; then
        local h="${__bs_car[$tmpl]}"
        # (unquote expr)
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

# ──────────────────────────────────────────────────────────────────────────────
# Apply
# ──────────────────────────────────────────────────────────────────────────────
__bs_apply() {                        # proc [args...]
    local proc="$1"; shift
    local -a args=("$@")

    case "$proc" in

        # ── Arithmetic ──────────────────────────────────────────────────────
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

        # ── Comparisons ─────────────────────────────────────────────────────
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

        # ── Boolean ─────────────────────────────────────────────────────────
        'f:not')
            [[ "${args[0]}" == 'b:#f' ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;

        # ── Type predicates ─────────────────────────────────────────────────
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

        # ── Pair / List ─────────────────────────────────────────────────────
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

        # ── String ──────────────────────────────────────────────────────────
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

        # ── Char ────────────────────────────────────────────────────────────
        'f:char->integer')
            local _c="${args[0]:2}"
            printf -v __bs_ret 'i:%d' "'$_c" ;;
        'f:integer->char')
            local _n="${args[0]:2}"
            printf -v __bs_ret 'c:\\x%x' "$_n"
            __bs_ret="c:$(printf "\\x$(printf '%x' "$_n")")" ;;
        'f:char=?') [[ "${args[0]:2}" == "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:char<?') [[ "${args[0]:2}" < "${args[1]:2}" ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:char-alphabetic?') [[ "${args[0]:2}" =~ [a-zA-Z] ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;
        'f:char-numeric?') [[ "${args[0]:2}" =~ [0-9] ]] && __bs_ret="b:#t" || __bs_ret="b:#f" ;;

        # ── I/O ─────────────────────────────────────────────────────────────
        'f:display')
            __bs_display "${args[0]}"
            printf 'printf %%s %q >&2\n' "$__bs_ret" >> "$__bs_output_file"
            __bs_ret="n:()" ;;
        'f:write')
            __bs_write "${args[0]}"
            printf 'printf %%s %q >&2\n' "$__bs_ret" >> "$__bs_output_file"
            __bs_ret="n:()" ;;
        'f:newline')
            printf 'printf "\\n" >&2\n' >> "$__bs_output_file"
            __bs_ret="n:()" ;;
        'f:read-line')
            IFS= read -r __bs_tmp_readline
            __bs_ret="s:${__bs_tmp_readline}" ;;

        # ── Vector ──────────────────────────────────────────────────────────
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

        # ── Exact/inexact (identity for integers) ───────────────────────────
        'f:exact->inexact'|'f:inexact->exact'|'f:exact'|'f:inexact'| \
        'f:floor'|'f:ceiling'|'f:round'|'f:truncate')
            __bs_ret="${args[0]}" ;;

        # ── apply (as first-class function) ─────────────────────────────────
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

        # ── error ────────────────────────────────────────────────────────────
        'f:error')
            local _msg="${args[0]:2}"
            local _irr=""
            for (( _k=1; _k<${#args[@]}; _k++ )); do
                __bs_display "${args[$_k]}"
                _irr+=" ${__bs_ret}"
            done
            __bs_error "$_msg$_irr"
            return 1 ;;

        # ── call/cc (stub - just calls thunk with dummy) ─────────────────────
        'f:call-with-current-continuation'|'f:call/cc')
            # Pass a dummy escape procedure
            __bs_make_closure "y:_k" "n:()" "0"
            local _dummy="$__bs_ret"
            __bs_apply "${args[0]}" "$_dummy"
            return $? ;;

        # ── values / call-with-values (simplified) ───────────────────────────
        'f:values')
            [[ ${#args[@]} -gt 0 ]] && __bs_ret="${args[0]}" || __bs_ret="n:()" ;;
        'f:call-with-values')
            __bs_apply "${args[0]}"
            __bs_apply "${args[1]}" "$__bs_ret"
            return $? ;;

        # ── with-exception-handler / raise (stub) ────────────────────────────
        'f:with-exception-handler')
            __bs_apply "${args[1]}" || true
            __bs_ret="n:()"  ;;
        'f:raise'|'f:raise-continuable')
            __bs_display "${args[0]}"
            __bs_error "uncaught raise: $__bs_ret"
            return 1 ;;

        # ── Closure application ──────────────────────────────────────────────
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
# State persistence (load / save)
# ──────────────────────────────────────────────────────────────────────────────
__bs_load_state() {
    if [[ -f "${__BS_STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${__BS_STATE_FILE}"
    fi
}

__bs_save_state() {
    {
        printf 'declare -g __bs_heap_next=%q\n' "$__bs_heap_next"
        printf 'declare -g __bs_env_next=%q\n'  "$__bs_env_next"

        for _k in "${!__bs_car[@]}"; do
            printf '__bs_car[%s]=%q\n' "$_k" "${__bs_car[$_k]}"
        done
        for _k in "${!__bs_cdr[@]}"; do
            printf '__bs_cdr[%s]=%q\n' "$_k" "${__bs_cdr[$_k]}"
        done
        for _k in "${!__bs_closure_params[@]}"; do
            printf '__bs_closure_params[%s]=%q\n' "$_k" "${__bs_closure_params[$_k]}"
        done
        for _k in "${!__bs_closure_body[@]}"; do
            printf '__bs_closure_body[%s]=%q\n' "$_k" "${__bs_closure_body[$_k]}"
        done
        for _k in "${!__bs_closure_env[@]}"; do
            printf '__bs_closure_env[%s]=%q\n' "$_k" "${__bs_closure_env[$_k]}"
        done
        for _k in "${!__bs_env[@]}"; do
            printf '__bs_env[%s]=%q\n' "$_k" "${__bs_env[$_k]}"
        done
        for _k in "${!__bs_env_parent[@]}"; do
            printf '__bs_env_parent[%s]=%q\n' "$_k" "${__bs_env_parent[$_k]}"
        done
    } > "${__BS_STATE_FILE}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Public API: bs
# ──────────────────────────────────────────────────────────────────────────────
bs() {
    local _src="$1"

    # Load heap state saved by previous calls (survives subshell boundary)
    __bs_load_state

    # Single output file: accumulates top-level assignments AND I/O printf stmts
    __bs_output_file="$(mktemp)"

    # Tokenize -> parse -> eval all top-level expressions
    __bs_tokenize "$_src"
    __bs_tpos=0
    __bs_ret="n:()"

    while (( __bs_tpos < ${#__bs_tokens[@]} )); do
        __bs_parse_expr || break
        __bs_eval "$__bs_ret" "0" || true
    done

    __bs_last="$__bs_ret"

    # Save updated heap for next call
    __bs_save_state

    # ── Emit output for eval ──
    # One-time array declarations
    printf '%s\n' \
        '[[ ${__BS_RUNTIME_LOADED-} ]] || {' \
        '  declare -gA __bs_car=() __bs_cdr=()' \
        '  declare -gA __bs_closure_params=() __bs_closure_body=() __bs_closure_env=()' \
        '  declare -gA __bs_env=() __bs_env_parent=()' \
        "  declare -g  __bs_heap_next=0 __bs_env_next=1 __bs_last=\"\"" \
        '  __BS_RUNTIME_LOADED=1' \
        '}'

    # Always emit full heap state so caller scope stays in sync
    printf 'declare -g __bs_heap_next=%q\n' "$__bs_heap_next"
    printf 'declare -g __bs_env_next=%q\n'  "$__bs_env_next"
    for _k in "${!__bs_car[@]}"; do
        printf '__bs_car[%s]=%q\n' "$_k" "${__bs_car[$_k]}"
    done
    for _k in "${!__bs_cdr[@]}"; do
        printf '__bs_cdr[%s]=%q\n' "$_k" "${__bs_cdr[$_k]}"
    done
    for _k in "${!__bs_closure_params[@]}"; do
        printf '__bs_closure_params[%s]=%q\n' "$_k" "${__bs_closure_params[$_k]}"
    done
    for _k in "${!__bs_closure_body[@]}"; do
        printf '__bs_closure_body[%s]=%q\n' "$_k" "${__bs_closure_body[$_k]}"
    done
    for _k in "${!__bs_closure_env[@]}"; do
        printf '__bs_closure_env[%s]=%q\n' "$_k" "${__bs_closure_env[$_k]}"
    done
    for _k in "${!__bs_env[@]}"; do
        printf '__bs_env[%s]=%q\n' "$_k" "${__bs_env[$_k]}"
    done
    for _k in "${!__bs_env_parent[@]}"; do
        printf '__bs_env_parent[%s]=%q\n' "$_k" "${__bs_env_parent[$_k]}"
    done

    # Top-level bindings and I/O produced this call (in evaluation order)
    cat "$__bs_output_file"
    rm -f "$__bs_output_file"

    # Last value
    printf 'declare -g __bs_last=%q\n' "$__bs_last"
}

# ──────────────────────────────────────────────────────────────────────────────
# bs-reset: wipe persistent state (call between independent test sessions)
# ──────────────────────────────────────────────────────────────────────────────
bs-reset() {
    rm -f "${__BS_STATE_FILE}"
    __bs_car=(); __bs_cdr=()
    __bs_closure_params=(); __bs_closure_body=(); __bs_closure_env=()
    __bs_env=(); __bs_env_parent=()
    __bs_heap_next=0; __bs_env_next=1; __bs_last=""
}

# ──────────────────────────────────────────────────────────────────────────────
# bs-eval: convenience wrapper - evaluate and capture display value
# ──────────────────────────────────────────────────────────────────────────────
bs-eval() {
    eval "$(bs "$1")"
    __bs_display "$__bs_last"
    printf '%s\n' "$__bs_ret"
}
