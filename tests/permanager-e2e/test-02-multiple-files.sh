#!/bin/bash
# Test 2: 複数ファイルにリンクがある場合
#
# 検証内容：
# - 複数のファイルにパーマリンクが散在している
# - すべてのファイルのリンクが出力される

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 2: 複数ファイルにリンクがある場合"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

SHA="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
URL_A="https://github.com/owner/repo/blob/${SHA}/docs/api.md#L10"
URL_B="https://github.com/owner/repo/blob/${SHA}/docs/model.md#L5-L20"

mkdir -p src

cat > src/handler.rs << EOF
// Handler based on ${URL_A}
fn handle() {}
EOF

cat > src/model.rs << EOF
// Model defined in ${URL_B}
struct Model {}
EOF

git add src/
git commit -q -m "Add handler and model"

echo_subheader "list を実行"
OUTPUT=$("$PERMANAGER" list)
echo "$OUTPUT"

echo_subheader "アサーション"
assert_contains "handler.rs のリンクが含まれる" "src/handler.rs:1" "$OUTPUT"
assert_contains "handler.rs の URL が含まれる" "$URL_A" "$OUTPUT"
assert_contains "model.rs のリンクが含まれる" "src/model.rs:1" "$OUTPUT"
assert_contains "model.rs の URL が含まれる" "$URL_B" "$OUTPUT"
assert_line_count "出力が2行" 2 "$OUTPUT"
