#!/bin/bash
# Test 2: 複数リポジトリの登録と更新
#
# 検証内容：
# - 複数のリポジトリを登録できる
# - 同じリポジトリを再度 set すると上書きされる

set -e
source "$(dirname "$0")/../helpers.sh"

echo_header "Test 2: 複数リポジトリの登録と更新"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

echo_subheader "複数リポジトリを登録"
"$PERMANAGER" config set linked-repo octocat/Hello-World --branch main
"$PERMANAGER" config set linked-repo octocat/Spoon-Knife --branch develop

OUTPUT=$("$PERMANAGER" config list)
echo "$OUTPUT"

assert_contains "1つ目のリポジトリが含まれる" "octocat/Hello-World" "$OUTPUT"
assert_contains "1つ目のブランチが含まれる" "branch=main" "$OUTPUT"
assert_contains "2つ目のリポジトリが含まれる" "octocat/Spoon-Knife" "$OUTPUT"
assert_contains "2つ目のブランチが含まれる" "branch=develop" "$OUTPUT"
assert_line_count "2件表示される" 2 "$OUTPUT"

echo_subheader "既存リポジトリのブランチを更新"
"$PERMANAGER" config set linked-repo octocat/Hello-World --branch feature

OUTPUT=$("$PERMANAGER" config list)
echo "$OUTPUT"

assert_contains "ブランチが更新されている" "branch=feature" "$OUTPUT"
assert_not_contains "古いブランチ名が残っていない" "branch=main" "$OUTPUT"
assert_line_count "件数は変わらない" 2 "$OUTPUT"
