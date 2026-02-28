#!/usr/bin/env bash
# run_em_tests.sh - Run Scheme editor expect tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pass=0 fail=0 total=0

for test_file in "$SCRIPT_DIR"/test_em_*.exp; do
    name=$(basename "$test_file" .exp)
    ((total++)) || true
    printf '  %-40s ' "$name"
    if output=$(expect "$test_file" 2>&1); then
        printf 'PASS\n'
        ((pass++)) || true
    else
        printf 'FAIL\n'
        echo "$output" | tail -5 | sed 's/^/    /'
        ((fail++)) || true
    fi
done

echo ""
echo "Scheme editor tests: $pass/$total passed"
[[ $fail -eq 0 ]]
