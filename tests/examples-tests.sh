#!/usr/bin/env bash
# Non-interactive regressions for the maintained larger examples.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/sheme-example-tests.XXXXXXXX")
daemon_job=""
cleanup() {
    if [[ -f "$TMP/data/sheme/daemon.pid" ]]; then
        kill -TERM "$(cat "$TMP/data/sheme/daemon.pid")" 2>/dev/null || true
    fi
    [[ -z "$daemon_job" ]] || wait "$daemon_job" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

pass=0
fail=0
check_contains() {
    local description="$1" output="$2" expected="$3"
    if [[ "$output" == *"$expected"* ]]; then
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$((pass + fail))" "$description"
    else
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$((pass + fail))" "$description"
        printf '  missing: %s\n' "$expected"
    fi
}

algorithms=$(bash examples/algorithms.sh)
check_contains "merge-sort example" "$algorithms" "(1 2 3 4 5 6 7 8 9)"
check_contains "sieve example" "$algorithms" "(2 3 5 7 11 13 17 19 23 29 31 37 41 43 47)"
check_contains "Hanoi example" "$algorithms" "((A C) (A B) (C B) (A C) (B A) (B C) (A C))"

channels=$(bash examples/channels.sh)
check_contains "channel work queue" "$channels" "10 squared = 100"
check_contains "channel stack machine" "$channels" "Program: 3 4 + 2 * dup *  =>  196"
check_contains "channel word frequency" "$channels" "(the . 3)"

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/data"
export SHEME_TODO_FILE="$TMP/data/sheme/tasks-quote\"-back\\slash.scm"
mkdir -p "$HOME"

todo() { bash examples/todo.sh "$@"; }

printf '%s\n' 'Dollar $ and `tick`' "Reminder's \"quoted\" text" '' '1d' | \
    todo add >/dev/null
todo_list=$(todo list)
check_contains "todo persists shell metacharacters safely" "$todo_list" 'Dollar $ and `tick`'
check_contains "todo sanitizes serialized/notification quotes" "$todo_list" "Reminders quoted text"

todo_status=$(todo status)
check_contains "todo reports a pending task" "$todo_status" "1 task(s): 1 pending, 0 done"
todo done 1 >/dev/null
todo_status=$(todo status)
check_contains "todo marks a task done" "$todo_status" "1 task(s): 0 pending, 1 done"

if todo done nope >/dev/null 2>&1 || todo del 99 >/dev/null 2>&1; then
    fail=$((fail + 1))
    printf 'not ok %d - todo rejects invalid or missing ids\n' "$((pass + fail))"
else
    pass=$((pass + 1))
    printf 'ok %d - todo rejects invalid or missing ids\n' "$((pass + fail))"
fi

todo del 1 >/dev/null
todo_list=$(todo list)
check_contains "todo deletes persisted tasks" "$todo_list" "No tasks yet"

# The daemon should block after one check rather than spin on /dev/null.
todo daemon >"$TMP/daemon.log" 2>&1 &
daemon_job=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -f "$TMP/data/sheme/daemon.pid" ]] && break
    sleep 0.2
done
sleep 1
daemon_checks=$(grep -c 'task(s) loaded' "$TMP/daemon.log" || true)
todo stop >/dev/null
wait "$daemon_job"
daemon_job=""
if [[ "$daemon_checks" == 1 ]]; then
    pass=$((pass + 1))
    printf 'ok %d - todo daemon blocks between checks\n' "$((pass + fail))"
else
    fail=$((fail + 1))
    printf 'not ok %d - todo daemon blocks between checks\n' "$((pass + fail))"
fi

printf '1..%d\n' "$((pass + fail))"
printf '# %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
