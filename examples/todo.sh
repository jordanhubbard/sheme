#!/usr/bin/env bash
# examples/todo.sh — Task manager with human reminders and shell automation
#
# Each task has two "arms":
#   human arm   — a plain-language reminder printed (and OS-notified) when due
#   shell arm   — a shell command run automatically when due
#
# Synchronization model
# ─────────────────────
# The daemon is a separate process (run with `daemon &`).  It does NOT poll on
# a fixed timer.  Instead it uses an event-driven wait:
#
#   1. A background subshell runs inotifywait (Linux) or fswatch (macOS),
#      watching $TODO_FILE.  When the file changes it sends SIGUSR1 to the
#      daemon PID and exits.
#
#   2. The daemon main loop blocks on `read -r -t $timeout < /dev/null`.
#      bash's `read` is interrupted by any signal that has a non-ignored
#      handler.  USR1's handler is `trap ':' USR1` — the null command —
#      which satisfies that requirement while doing nothing else.
#
#   3. Every command that modifies the task list (add/done/del/edit) calls
#      notify_daemon(), which sends SIGUSR1 directly to the daemon PID.
#      This wakes the daemon immediately without waiting for inotifywait.
#
#   4. The timeout is not fixed at 60 s; Scheme computes the number of
#      seconds until the earliest pending task and uses that, capped at
#      300 s.  The daemon wakes up right when a task becomes due even if
#      nothing else prodded it.
#
#   5. The daemon writes $TODO_FILE only when it actually fires tasks.
#      A no-op loop iteration leaves the file untouched, preventing the
#      daemon's own write from triggering an immediate USR1 wakeup loop.
#
# Showcases sheme features:
#   file-read / file-write-atomic / eval-string  — Scheme data as persistence
#   shell-capture                                — tool detection, system time
#   shell-exec                                   — fire automation commands
#   filter / map / for-each / foldl / apply      — functional list operations
#   closures                                     — task field accessors
#
# Usage:
#   bash examples/todo.sh add              add a task interactively
#   bash examples/todo.sh list             show all tasks
#   bash examples/todo.sh done  <id>       mark task complete
#   bash examples/todo.sh del   <id>       remove a task
#   bash examples/todo.sh edit  <id>       edit a task interactively
#   bash examples/todo.sh fire             fire all currently due tasks now
#   bash examples/todo.sh daemon           start event-driven daemon (foreground)
#   bash examples/todo.sh daemon &         start daemon in background
#   bash examples/todo.sh stop             gracefully stop a running daemon
#   bash examples/todo.sh status           show daemon and task-store status
#
# Storage: ~/.local/share/sheme/todo.scm  (or $SHEME_TODO_FILE)
#
# Input restriction: task strings must not contain " \ $ or backtick — these
# are stripped at input time so strings survive Scheme source serialization.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/bs.sh"
bs-reset

# ── Storage paths ─────────────────────────────────────────────────────────────
TODO_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sheme"
TODO_FILE="${SHEME_TODO_FILE:-$TODO_DIR/todo.scm}"
PID_FILE="$TODO_DIR/daemon.pid"
mkdir -p "$TODO_DIR"

# ── Terminal colours ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    BOLD='\033[1m' CYAN='\033[1;36m' GREEN='\033[0;32m'
    YELLOW='\033[1;33m' RED='\033[0;31m' DIM='\033[2m' RESET='\033[0m'
else
    BOLD='' CYAN='' GREEN='' YELLOW='' RED='' DIM='' RESET=''
fi

banner() { printf "\n${CYAN}── %s ──${RESET}\n" "$1"; }
ok()     { printf "  ${GREEN}✓${RESET}  %s\n" "$1"; }
warn()   { printf "  ${YELLOW}⚠${RESET}  %s\n" "$1"; }
die()    { printf "  ${RED}✗${RESET}  %s\n" "$1" >&2; exit 1; }

# ── Scheme definitions ────────────────────────────────────────────────────────
# Evaluated once at startup; definitions persist in __bs_env for this process.

bs '
;; ── Task structure ─────────────────────────────────────────────────────────
;; A task is a plain list: (id  title  human-msg  shell-cmd  due-epoch  done?)
;;   id         integer, unique and stable
;;   title      short label shown in listings
;;   human-msg  reminder text printed/notified when due
;;   shell-cmd  shell command fired when due ("" = none)
;;   due-epoch  Unix timestamp (seconds since 1970-01-01)
;;   done?      #t once fired+auto-marked, or manually completed

(define (task-id    t) (car   t))
(define (task-title t) (cadr  t))
(define (task-human t) (caddr t))
(define (task-shell t) (car   (cdddr t)))
(define (task-due   t) (cadr  (cdddr t)))
(define (task-done? t) (caddr (cdddr t)))

(define (make-task id title human shell-cmd due done)
  (list id title human shell-cmd due done))

;; ── Serialization ───────────────────────────────────────────────────────────
;; Each task serializes to a Scheme list literal so the file can be reloaded
;; with (eval-string (file-read path)).  Strings must not contain " (stripped
;; at input time by sanitize()).

(define (task->sexp t)
  (string-append
    "(list "
    (number->string (task-id t))  " "
    "\"" (task-title t) "\" "
    "\"" (task-human t) "\" "
    "\"" (task-shell t) "\" "
    (number->string (task-due t)) " "
    (if (task-done? t) "#t" "#f")
    ")"))

(define (tasks->file-str tasks)
  (string-append
    ";; sheme todo — edit with `todo.sh edit`, not by hand\n"
    "(list\n"
    (apply string-append
           (map (lambda (t) (string-append "  " (task->sexp t) "\n")) tasks))
    ")"))

;; ── Utilities ───────────────────────────────────────────────────────────────

(define (next-id tasks)
  (+ 1 (foldl (lambda (t acc) (if (> (task-id t) acc) (task-id t) acc))
              0 tasks)))

(define (replace-task tasks id new-t)
  (map (lambda (t) (if (= (task-id t) id) new-t t)) tasks))

;; Cross-platform epoch → "YYYY-MM-DD HH:MM"
(define (epoch->human e)
  (let ((r (shell-capture
              (string-append
                "date -d @" (number->string e) " \"+%Y-%m-%d %H:%M\" 2>/dev/null"
                " || date -r " (number->string e) " \"+%Y-%m-%d %H:%M\""))))
    (if (equal? r #f) (number->string e) r)))

;; Seconds until the earliest pending task, capped at max-secs.
;; Returns max-secs when nothing is pending (safe fallback sleep).
(define (secs-to-next-due tasks now max-secs)
  (let ((pending (filter (lambda (t) (not (task-done? t))) tasks)))
    (if (null? pending)
        max-secs
        (let ((earliest
               (foldl (lambda (t best)
                        (if (< (task-due t) best) (task-due t) best))
                      999999999
                      pending)))
          (max 5 (- earliest now))))))  ; at least 5 s so we never busy-loop

;; ── Firing a task ────────────────────────────────────────────────────────────
;; Side effects only: terminal output, shell command, OS notification.

(define (fire-task t)
  (write-stdout
    (string-append
      "\n\033[1;33m╔══════════════════════════════════════════════╗\033[0m\n"
      "\033[1;33m  REMINDER\033[0m  " (task-title t) "\n"
      "  " (task-human t) "\n"
      "\033[1;33m╚══════════════════════════════════════════════╝\033[0m\n"))

  (when (not (equal? "" (task-shell t)))
    (write-stdout (string-append "  \033[2mRunning: " (task-shell t) "\033[0m\n"))
    (shell-exec (task-shell t) ""))

  ;; OS notification: notify-send (Linux/freedesktop) or osascript (macOS)
  (let ((ns (shell-capture "command -v notify-send 2>/dev/null"))
        (oa (shell-capture "command -v osascript   2>/dev/null")))
    (cond
      ((not (equal? ns #f))
       (shell-exec (string-append "notify-send "
                                  "'" (task-title t) "' "
                                  "'" (task-human t) "'") ""))
      ((not (equal? oa #f))
       (shell-exec (string-append "osascript -e 'display notification \""
                                  (task-human t) "\" with title \""
                                  (task-title t) "\"'") "")))))
'

# ── Persistence helpers ───────────────────────────────────────────────────────

load_tasks() {
    if [[ -f "$TODO_FILE" ]]; then
        bs "(define *tasks* (eval-string (file-read \"$TODO_FILE\")))"
    else
        bs '(define *tasks* (list))'
    fi
}

# Plain save — used internally by the daemon (no notification back to itself).
save_tasks() {
    bs "(file-write-atomic \"$TODO_FILE\" (tasks->file-str *tasks*))"
}

# Save and wake the daemon — used by all interactive commands.
save_and_notify() {
    save_tasks
    notify_daemon
}

# Send SIGUSR1 to a running daemon so it checks immediately.
# Silently ignores a missing or stale PID file.
notify_daemon() {
    [[ -f "$PID_FILE" ]] || return 0
    local dpid
    dpid=$(cat "$PID_FILE" 2>/dev/null) || return 0
    if kill -0 "$dpid" 2>/dev/null; then
        kill -USR1 "$dpid" 2>/dev/null || true
    else
        rm -f "$PID_FILE" 2>/dev/null || true  # stale
    fi
}

sanitize() { printf '%s' "$1" | tr -d '"\\$`'; }

parse_due() {
    local spec="$1"
    case "$spec" in
        *m) date -d "+${spec%m} minutes" +%s 2>/dev/null || date -v "+${spec%m}M" +%s ;;
        *h) date -d "+${spec%h} hours"   +%s 2>/dev/null || date -v "+${spec%h}H" +%s ;;
        *d) date -d "+${spec%d} days"    +%s 2>/dev/null || date -v "+${spec%d}d" +%s ;;
        *)  date -d  "$spec"  +%s 2>/dev/null || date -jf "%Y-%m-%d %H:%M" "$spec" +%s ;;
    esac
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_add() {
    banner "New task"
    printf "  Title            : "; IFS= read -r title
    printf "  Human reminder   : "; IFS= read -r human
    printf "  Shell command    : "; IFS= read -r shell_cmd
    printf "  Due (30m/2h/1d or YYYY-MM-DD HH:MM): "; IFS= read -r due_spec

    title=$(sanitize "$title"); human=$(sanitize "$human")
    shell_cmd=$(sanitize "$shell_cmd")
    [[ -z "$title" ]] && die "Title is required."

    local due_epoch
    due_epoch=$(parse_due "$due_spec") || die "Cannot parse due time: $due_spec"

    load_tasks
    bs "(define *tasks*
          (append *tasks*
            (list (make-task (next-id *tasks*)
                             \"$title\" \"$human\" \"$shell_cmd\"
                             $due_epoch #f))))"
    save_and_notify
    ok "Task added (due $(date -d "@$due_epoch" "+%Y-%m-%d %H:%M" 2>/dev/null \
        || date -r "$due_epoch" "+%Y-%m-%d %H:%M"))."
}

cmd_list() {
    load_tasks
    bs '(length *tasks*)'
    local count="${__bs_last_display}"
    if [[ "$count" == "0" ]]; then
        warn "No tasks yet.  Use 'add' to create one."
        return
    fi
    banner "Tasks ($count)"

    # Build a tab-separated table in Scheme, pipe through column(1) for alignment.
    # shell-exec pipes its second arg as stdin to the column command.
    bs '
(define (status-glyph t)
  (if (task-done? t) "\033[2m✓\033[0m" " "))

(define (row t)
  (string-append
    (number->string (task-id t)) "\t"
    (status-glyph t)             "\t"
    (task-title t)               "\t"
    (epoch->human (task-due t))  "\t"
    (task-human t)
    (if (equal? "" (task-shell t)) ""
        (string-append " \033[2m[" (task-shell t) "]\033[0m"))
    "\n"))

(define table-str
  (string-append
    "ID\t \tTITLE\tDUE\tREMINDER\n"
    "──\t─\t─────\t───\t────────\n"
    (apply string-append (map row *tasks*))))

(shell-exec "column -ts $'"'"'\\t'"'"' 2>/dev/null || cat" table-str)'
}

cmd_done() {
    local id="${1:-}"; [[ -n "$id" ]] || die "Usage: todo done <id>"
    load_tasks
    bs "(define *tasks*
          (map (lambda (t)
                 (if (= (task-id t) $id)
                     (make-task (task-id t) (task-title t) (task-human t)
                                (task-shell t) (task-due t) #t)
                     t))
               *tasks*))"
    save_and_notify
    ok "Task $id marked done."
}

cmd_delete() {
    local id="${1:-}"; [[ -n "$id" ]] || die "Usage: todo del <id>"
    load_tasks
    bs "(define *tasks* (filter (lambda (t) (not (= (task-id t) $id))) *tasks*))"
    save_and_notify
    ok "Task $id deleted."
}

cmd_edit() {
    local id="${1:-}"; [[ -n "$id" ]] || die "Usage: todo edit <id>"
    load_tasks

    # define outside let so _edit_t is visible to subsequent bs calls
    bs "(define _edit_t
          (let ((matches (filter (lambda (t) (= (task-id t) $id)) *tasks*)))
            (if (null? matches)
                (error \"No task with id\" $id)
                (car matches))))"

    local cur_title cur_human cur_shell cur_due
    bs '(task-title _edit_t)';            cur_title="${__bs_last_display}"
    bs '(task-human _edit_t)';            cur_human="${__bs_last_display}"
    bs '(task-shell _edit_t)';            cur_shell="${__bs_last_display}"
    bs '(epoch->human (task-due _edit_t))'; cur_due="${__bs_last_display}"

    banner "Edit task $id"
    printf "  Title            [%s]: " "$cur_title"; IFS= read -r title
    printf "  Human reminder   [%s]: " "$cur_human"; IFS= read -r human
    printf "  Shell command    [%s]: " "$cur_shell"; IFS= read -r shell_cmd
    printf "  Due              [%s]: " "$cur_due";   IFS= read -r due_spec

    title=$(sanitize    "${title:-$cur_title}")
    human=$(sanitize    "${human:-$cur_human}")
    shell_cmd=$(sanitize "${shell_cmd:-$cur_shell}")

    local due_epoch
    if [[ -z "$due_spec" ]]; then
        bs '(task-due _edit_t)'; due_epoch="${__bs_last_display}"
    else
        due_epoch=$(parse_due "$due_spec") || die "Cannot parse due time: $due_spec"
    fi

    bs "(define *tasks*
          (replace-task *tasks* $id
            (make-task $id \"$title\" \"$human\" \"$shell_cmd\" $due_epoch #f)))"
    save_and_notify
    ok "Task $id updated."
}

cmd_fire() {
    load_tasks
    local now; now=$(date +%s)
    banner "Firing due tasks"
    bs "
(define _now $now)
(define _due (filter (lambda (t) (and (not (task-done? t)) (<= (task-due t) _now)))
                     *tasks*))
(if (null? _due)
    (write-stdout \"  No pending tasks are currently due.\\n\")
    (for-each fire-task _due))
(length _due)"
    local fired="${__bs_last_display}"
    [[ "$fired" != "0" ]] && ok "$fired task(s) fired."
}

# ── Event-driven wait ─────────────────────────────────────────────────────────
# Blocks until one of: file changes, SIGUSR1 arrives, or timeout expires.
# USR1 is handled by `trap ':' USR1` (set in cmd_daemon), which makes it a
# real signal delivery that interrupts `read -t` without doing anything else.
#
# inotifywait / fswatch runs in a background subshell.  When the watched file
# changes, the subshell sends SIGUSR1 to $daemon_pid and exits.  We then kill
# the subshell (in case it is still running) and clean up.
#
# Note: killing the bash subshell may briefly orphan the inotifywait/fswatch
# child.  It exits naturally when the file next changes or is replaced, which
# for a TODO manager is entirely harmless.
_wait_for_event() {
    local timeout="$1" daemon_pid="$2" watch_tool="$3"
    local watcher_pid=0

    case "$watch_tool" in
        inotifywait)
            # $daemon_pid captured before the subshell so there is no ambiguity
            (inotifywait -q -e close_write "$TODO_FILE" 2>/dev/null
             kill -USR1 "$daemon_pid" 2>/dev/null) &
            watcher_pid=$!
            ;;
        fswatch)
            (fswatch -1 "$TODO_FILE" &>/dev/null
             kill -USR1 "$daemon_pid" 2>/dev/null) &
            watcher_pid=$!
            ;;
        # poll: no watcher; read -t below acts as the timed sleep
    esac

    # Block here.  Woken by: USR1 (watcher or notify_daemon), timeout, SIGTERM.
    read -r -t "$timeout" < /dev/null 2>/dev/null || true

    if (( watcher_pid > 0 )); then
        kill "$watcher_pid" 2>/dev/null || true
        wait "$watcher_pid" 2>/dev/null || true
    fi
}

cmd_daemon() {
    # Refuse to start a second instance.
    if [[ -f "$PID_FILE" ]]; then
        local existing; existing=$(cat "$PID_FILE" 2>/dev/null) || existing=""
        if [[ -n "$existing" ]] && kill -0 "$existing" 2>/dev/null; then
            die "Daemon already running (PID $existing). Use 'stop' first."
        fi
        rm -f "$PID_FILE"
    fi

    # Detect best available watch tool.
    local watch_tool
    if   command -v inotifywait &>/dev/null; then watch_tool="inotifywait"
    elif command -v fswatch     &>/dev/null; then watch_tool="fswatch"
    else
        watch_tool="poll"
        warn "inotifywait and fswatch not found — falling back to 300 s polling."
        warn "Install inotify-tools (Linux) or fswatch (macOS) for event-driven mode."
    fi

    # Write PID file so other commands can find us.
    printf '%d\n' $$ > "$PID_FILE"

    # USR1: null handler so the signal is received (not ignored) and interrupts read.
    # TERM/INT: remove PID file and exit cleanly.
    trap ':' USR1
    trap 'rm -f "$PID_FILE"; printf "\n"; ok "Daemon stopped."; exit 0' TERM INT

    local daemon_pid=$$
    banner "Daemon started (PID $daemon_pid, watcher: $watch_tool)"
    ok "Send SIGUSR1 to wake immediately:  kill -USR1 $daemon_pid"
    ok "Stop cleanly:                      bash examples/todo.sh stop"

    local now fired_count timeout

    while true; do
        now=$(date +%s)
        load_tasks

        # Fire any tasks that are now due; mark them done in *tasks*.
        bs "
(define _now $now)
(define _due (filter (lambda (t) (and (not (task-done? t)) (<= (task-due t) _now)))
                     *tasks*))
(for-each
  (lambda (t)
    (fire-task t)
    (set! *tasks*
          (replace-task *tasks* (task-id t)
            (make-task (task-id t) (task-title t) (task-human t)
                       (task-shell t) (task-due t) #t))))
  _due)
(length _due)"
        fired_count="${__bs_last_display}"

        # Only write the file when something changed.  A no-op iteration must
        # not write, or the watcher would trigger an immediate re-wakeup loop.
        if [[ "$fired_count" != "0" ]]; then
            save_tasks  # plain save — no notify_daemon (that's ourselves)
        fi

        # Compute seconds until the earliest pending task (Scheme does the math).
        bs "(secs-to-next-due *tasks* $now 300)"
        timeout="${__bs_last_display}"
        (( timeout > 300 )) && timeout=300

        bs '(length *tasks*)'
        printf "  ${DIM}[%s] %s task(s) loaded, next check in %ss" \
            "$(date '+%H:%M:%S')" "${__bs_last_display}" "$timeout"
        [[ "$fired_count" != "0" ]] \
            && printf " — ${YELLOW}%s fired${RESET}" "$fired_count" \
            || printf " — none due"
        printf "${RESET}\n"

        _wait_for_event "$timeout" "$daemon_pid" "$watch_tool"
    done
}

cmd_stop() {
    if [[ ! -f "$PID_FILE" ]]; then
        warn "No PID file found — daemon may not be running."
        return
    fi
    local dpid; dpid=$(cat "$PID_FILE")
    if kill -0 "$dpid" 2>/dev/null; then
        kill -TERM "$dpid"
        ok "Sent SIGTERM to daemon (PID $dpid)."
    else
        warn "Daemon not running (stale PID $dpid)."
        rm -f "$PID_FILE"
    fi
}

cmd_status() {
    banner "Status"
    if [[ -f "$PID_FILE" ]]; then
        local dpid; dpid=$(cat "$PID_FILE")
        if kill -0 "$dpid" 2>/dev/null; then
            ok "Daemon running (PID $dpid)"
        else
            warn "Daemon not running (stale PID file for $dpid)"
            rm -f "$PID_FILE"
        fi
    else
        warn "Daemon not running"
    fi
    load_tasks
    bs '(length *tasks*)'; local total="${__bs_last_display}"
    bs "(length (filter (lambda (t) (not (task-done? t))) *tasks*))"; local pending="${__bs_last_display}"
    bs "(length (filter task-done? *tasks*))"; local done="${__bs_last_display}"
    ok "$total task(s): $pending pending, $done done"
    ok "Store: $TODO_FILE"
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    printf "${BOLD}sheme todo${RESET} — task manager with reminders and shell automation\n\n"
    printf "${BOLD}Usage:${RESET}  bash examples/todo.sh <command> [args]\n\n"
    printf "${BOLD}Commands:${RESET}\n"
    printf "  add              add a task (interactive)\n"
    printf "  list             show all tasks\n"
    printf "  done  <id>       mark a task complete\n"
    printf "  del   <id>       delete a task\n"
    printf "  edit  <id>       edit a task (interactive)\n"
    printf "  fire             fire all currently due tasks immediately\n"
    printf "  daemon           start event-driven daemon (foreground)\n"
    printf "  stop             gracefully stop the daemon\n"
    printf "  status           show daemon and task-store status\n"
    printf "\n${BOLD}Due time formats:${RESET}  30m  2h  1d  \"2026-12-25 09:00\"\n"
    printf "\n${BOLD}Daemon wakeup sources:${RESET}\n"
    printf "  • inotifywait/fswatch  file-change event (immediate)\n"
    printf "  • SIGUSR1              sent by add/done/del/edit (immediate)\n"
    printf "  • Timeout              calculated as secs-to-next-due (exact)\n"
    printf "  • SIGTERM/SIGINT       clean shutdown\n"
    printf "\n${BOLD}Example session:${RESET}\n"
    printf '  bash examples/todo.sh daemon &\n'
    printf '  bash examples/todo.sh add\n'
    printf '    Title           : Pick up laundry\n'
    printf '    Human reminder  : Laundry has been sitting since this morning!\n'
    printf '    Shell command   : xdg-open https://maps.google.com\n'
    printf '    Due             : 2h\n'
    printf '  bash examples/todo.sh list\n'
    printf '  bash examples/todo.sh status\n'
    printf '  bash examples/todo.sh stop\n'
    printf "\n${BOLD}Storage:${RESET}  %s\n" "$TODO_FILE"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${1:-}" in
    add)            cmd_add ;;
    list)           cmd_list ;;
    done)           cmd_done   "${2:-}" ;;
    del|delete)     cmd_delete "${2:-}" ;;
    edit)           cmd_edit   "${2:-}" ;;
    fire)           cmd_fire ;;
    daemon)         cmd_daemon ;;
    stop)           cmd_stop ;;
    status)         cmd_status ;;
    *)              usage ;;
esac
