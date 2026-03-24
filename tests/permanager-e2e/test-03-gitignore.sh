#!/bin/bash
# Test 3: .gitignore に含まれるファイルを無視する
#
# 検証内容：
# - パーマリンクが含まれるファイルを .gitignore に追加
# - そのファイルのリンクは出力されない

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 3: .gitignore に含まれるファイルを無視する"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

SHA="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
URL_TRACKED="https://github.com/owner/repo/blob/${SHA}/docs/spec.md"
URL_IGNORED="https://github.com/owner/repo/blob/${SHA}/docs/internal.md"

# トラッキングされるファイル
cat > main.rs << EOF
// See: ${URL_TRACKED}
fn main() {}
EOF

# .gitignore に追加するファイル
cat > generated.rs << EOF
// Auto-generated - See: ${URL_IGNORED}
fn generated() {}
EOF

cat > .gitignore << 'EOF'
generated.rs
EOF

git add main.rs .gitignore
git commit -q -m "Add files with gitignore"

echo_subheader "list を実行"
OUTPUT=$("$PERMANAGER" list)
echo "$OUTPUT"

echo_subheader "アサーション"
assert_contains "トラッキング対象ファイルのリンクが出力される" "$URL_TRACKED" "$OUTPUT"
assert_not_contains "無視ファイルのリンクが出力されない" "$URL_IGNORED" "$OUTPUT"
assert_line_count "出力が1行" 1 "$OUTPUT"
