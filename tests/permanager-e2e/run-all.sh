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

for test_file in "$SCRIPT_DIR"/test-*.sh; do
    if [ -f "$test_file" ]; then
        if bash "$test_file"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
        echo
        echo "--------------------------------------"
        echo
    fi
done

echo "======================================"
echo "結果: ${PASS} passed, ${FAIL} failed"
echo "======================================"

[ "$FAIL" -eq 0 ]
