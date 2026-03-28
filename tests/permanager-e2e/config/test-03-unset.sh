#!/bin/bash
# Test 3: config unset で設定を削除する
#
# 検証内容：
# - --branch を指定するとブランチ設定のみ削除される（エントリは残る）
# - フラグなしで unset するとエントリごと削除される
# - 存在しないリポジトリを unset すると非ゼロで終了する

set -e
source "$(dirname "$0")/../helpers.sh"

echo_header "Test 3: config unset で設定を削除する"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

"$PERMANAGER" config set linked-repo octocat/Hello-World --branch main
"$PERMANAGER" config set linked-repo octocat/Spoon-Knife --branch develop

echo_subheader "--branch でブランチ設定のみ削除"
"$PERMANAGER" config unset linked-repo octocat/Hello-World --branch

OUTPUT=$("$PERMANAGER" config list)
echo "$OUTPUT"

assert_contains "エントリ自体は残っている" "octocat/Hello-World" "$OUTPUT"
assert_not_contains "ブランチ設定は削除されている" "branch=main" "$OUTPUT"
assert_contains "他のエントリは影響を受けない" "octocat/Spoon-Knife" "$OUTPUT"

echo_subheader "フラグなしでエントリごと削除"
"$PERMANAGER" config unset linked-repo octocat/Spoon-Knife

OUTPUT=$("$PERMANAGER" config list)
echo "$OUTPUT"

assert_not_contains "エントリが削除されている" "octocat/Spoon-Knife" "$OUTPUT"

echo_subheader "存在しないリポジトリを unset すると非ゼロで終了"
set +e
"$PERMANAGER" config unset linked-repo nonexistent/repo
EXIT_CODE=$?
set -e
assert_equals "終了コードが非ゼロ" "1" "$EXIT_CODE"
