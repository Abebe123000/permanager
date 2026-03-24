#!/bin/bash
# Test 5: 様々なファイル形式でリンクを検出する
#
# 検証内容：
# - .py / .ts / .md / .yaml など拡張子を問わず検出できる

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 5: 様々なファイル形式でリンクを検出する"

require_binary

WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

SHA="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
URL_PY="https://github.com/owner/repo/blob/${SHA}/docs/spec.md#L1"
URL_TS="https://github.com/owner/repo/blob/${SHA}/docs/spec.md#L2"
URL_MD="https://github.com/owner/repo/blob/${SHA}/docs/spec.md#L3"
URL_YML="https://github.com/owner/repo/blob/${SHA}/docs/spec.md#L4"

cat > script.py << EOF
# See: ${URL_PY}
def run(): pass
EOF

cat > index.ts << EOF
// See: ${URL_TS}
export function run() {}
EOF

cat > notes.md << EOF
Reference: ${URL_MD}
EOF

cat > config.yml << EOF
# See: ${URL_YML}
name: example
EOF

git add script.py index.ts notes.md config.yml
git commit -q -m "Add various file types with permalinks"

echo_subheader "list を実行"
OUTPUT=$("$PERMANAGER" list)
echo "$OUTPUT"

echo_subheader "アサーション"
assert_contains ".py ファイルのリンクが検出される" "script.py:1" "$OUTPUT"
assert_contains ".ts ファイルのリンクが検出される" "index.ts:1" "$OUTPUT"
assert_contains ".md ファイルのリンクが検出される" "notes.md:1" "$OUTPUT"
assert_contains ".yml ファイルのリンクが検出される" "config.yml:1" "$OUTPUT"
assert_line_count "4ファイル分が出力される" 4 "$OUTPUT"
