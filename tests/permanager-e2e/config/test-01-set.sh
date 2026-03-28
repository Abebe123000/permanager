#!/bin/bash
# Test 1: config set でリポジトリを登録する
#
# 検証内容：
# - config set linked-repo で .permanager.toml が作成される
# - config list に登録内容が表示される

set -e
source "$(dirname "$0")/../helpers.sh"

echo_header "Test 1: config set でリポジトリを登録する"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

echo_subheader "config set を実行"
"$PERMANAGER" config set linked-repo octocat/Hello-World --branch main

echo_subheader ".permanager.toml が作成されている"
assert_equals ".permanager.toml が存在する" "0" "$([ -f .permanager.toml ] && echo 0 || echo 1)"

echo_subheader "config list を実行"
OUTPUT=$("$PERMANAGER" config list)
echo "$OUTPUT"

echo_subheader "アサーション"
assert_contains "リポジトリ名が含まれる" "octocat/Hello-World" "$OUTPUT"
assert_contains "ブランチ名が含まれる" "branch=main" "$OUTPUT"
