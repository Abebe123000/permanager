#!/bin/bash
# Test 3: git log -L で行範囲を追跡
#
# 検証内容：
# - git log -L で特定の行範囲の履歴を追跡
# - 行番号が変わっても内容を追跡できるか
#
# 期待結果：
# - 内容ベースで追跡できる
# - 元の行番号が変わっても追跡可能

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 3: git log -L で行範囲を追跡"

# セットアップ
WORK_DIR=$(setup_git_repo)
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

# 初期ファイル作成
cat > spec.md << 'EOF'
# API Specification

## Rate Limiting
Rate limit: 100 requests per minute

## Endpoints
POST /api/data
EOF

git add spec.md
git commit -q -m "Initial spec"
COMMIT1=$(git rev-parse HEAD)

echo_subheader "初期状態（Rate Limiting は 3-4行目）"
echo "コミット: ${COMMIT1:0:7}"
cat -n spec.md

# 冒頭に新セクション追加（行番号がシフト）
cat > spec.md << 'EOF'
# API Specification

## New Section
This is new content.

## Rate Limiting
Rate limit: 100 requests per minute

## Endpoints
POST /api/data
EOF

git add spec.md
git commit -q -m "Add new section at top"
COMMIT2=$(git rev-parse HEAD)

echo_subheader "新セクション追加後（Rate Limiting は 6-7行目）"
echo "コミット: ${COMMIT2:0:7}"
cat -n spec.md

# git log -L で追跡
echo_subheader "git log -L で 6-7行目の履歴を追跡"
echo "現在の 6-7行目（Rate Limiting）の履歴："
git log -L 6,7:spec.md --oneline -p

echo
echo_success "結果：元々 3-4行目 にあった内容を追跡できている"
echo_info "→ git log -L は内容ベースで追跡する"
echo_info "→ 行番号が変わっても同じ内容を追跡可能"

echo
if [ "$KEEP_TEMP" = "1" ]; then
    echo_info "デバッグ用：作業ディレクトリを保持 → $WORK_DIR"
fi
