#!/bin/bash
# Test 4: config list の表示
#
# 検証内容：
# - 設定がない場合は "No configuration found." が表示される
# - 設定がある場合は一覧が表示される

set -e
source "$(dirname "$0")/../helpers.sh"

echo_header "Test 4: config list の表示"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

echo_subheader "設定なしで config list を実行"
OUTPUT=$("$PERMANAGER" config list)
echo "$OUTPUT"

assert_contains "設定なしのメッセージが表示される" "No configuration found." "$OUTPUT"

echo_subheader "設定追加後に config list を実行"
"$PERMANAGER" config set linked-repo octocat/Hello-World --branch main

OUTPUT=$("$PERMANAGER" config list)
echo "$OUTPUT"

assert_contains "linked-repo のプレフィックスが含まれる" "linked-repo" "$OUTPUT"
assert_contains "リポジトリ名が含まれる" "octocat/Hello-World" "$OUTPUT"
assert_contains "ブランチが含まれる" "branch=main" "$OUTPUT"
