#!/bin/bash
# 全テストを実行

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "======================================"
echo "Git Content Tracking Tests"
echo "======================================"
echo

# テストファイルを順番に実行
for test_file in "$SCRIPT_DIR"/test-*.sh; do
    if [ -f "$test_file" ]; then
        bash "$test_file"
        echo
        echo "--------------------------------------"
        echo
    fi
done

echo "======================================"
echo "All tests completed!"
echo "======================================"
