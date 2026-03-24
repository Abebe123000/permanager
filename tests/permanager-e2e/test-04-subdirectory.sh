#!/bin/bash
# Test 4: サブディレクトリから実行した場合
#
# 検証内容：
# - リポジトリのサブディレクトリから list を実行
# - ファイルパスはgitルートからの相対パスで出力される

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 4: サブディレクトリから実行した場合"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

SHA="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
URL="https://github.com/owner/repo/blob/${SHA}/docs/spec.md#L1"

mkdir -p src/api

cat > src/api/handler.rs << EOF
// Handler - See: ${URL}
fn handle() {}
EOF

git add src/
git commit -q -m "Add handler in subdirectory"

echo_subheader "サブディレクトリ src/api から list を実行"
cd src/api
OUTPUT=$("$PERMANAGER" list)
echo "$OUTPUT"

echo_subheader "アサーション"
assert_contains "gitルートからの相対パスで出力される" "src/api/handler.rs:1" "$OUTPUT"
assert_contains "URLが含まれる" "$URL" "$OUTPUT"
