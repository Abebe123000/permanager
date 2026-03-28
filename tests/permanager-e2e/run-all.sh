#!/bin/bash
# 全E2Eテストを実行

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "======================================"
echo "permanager E2E Tests"
echo "======================================"
echo

PASS=0
FAIL=0

run_tests_in_dir() {
    local dir="$1"
    local label="$2"

    local found=0
    for test_file in "$dir"/test-*.sh; do
        [ -f "$test_file" ] || continue
        found=1
        if bash "$test_file"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
        echo
        echo "--------------------------------------"
        echo
    done

    if [ "$found" -eq 0 ]; then
        echo "  (テストなし: $label)"
        echo
    fi
}

for subdir in "$SCRIPT_DIR"/list "$SCRIPT_DIR"/config; do
    if [ -d "$subdir" ]; then
        label=$(basename "$subdir")
        echo "======================================"
        echo "[$label]"
        echo "======================================"
        echo
        run_tests_in_dir "$subdir" "$label"
    fi
done

echo "======================================"
echo "結果: ${PASS} passed, ${FAIL} failed"
echo "======================================"

[ "$FAIL" -eq 0 ]
