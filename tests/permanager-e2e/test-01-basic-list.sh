#!/bin/bash
# Test 1: 基本的な list コマンド
#
# 検証内容：
# - パーマリンクが含まれるファイルをコミット済みのリポジトリで list を実行
# - 正しいファイルパス・行番号・URLが出力される

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 1: 基本的な list コマンド"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

SHA="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
URL="https://github.com/owner/repo/blob/${SHA}/docs/spec.md"

# パーマリンクを含むファイルを作成
cat > main.rs << EOF
// Implementation based on the specification
// See: ${URL}
fn main() {
    println!("hello");
}
EOF

git add main.rs
git commit -q -m "Add main.rs with permalink"

echo_subheader "list を実行"
OUTPUT=$("$PERMANAGER" list)
echo "$OUTPUT"

echo_subheader "アサーション"
assert_contains "URLが出力に含まれる" "$URL" "$OUTPUT"
assert_contains "ファイルパスが出力に含まれる" "main.rs:" "$OUTPUT"
assert_contains "行番号 2 が含まれる" "main.rs:2" "$OUTPUT"
assert_line_count "出力が1行" 1 "$OUTPUT"
