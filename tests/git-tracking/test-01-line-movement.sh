#!/bin/bash
# Test 1: 行番号の移動（内容変更なし）
#
# 検証内容：
# - 仕様書の冒頭に新しいセクションを追加
# - 既存の内容が下にシフト（行番号が変わる）
# - しかし内容自体は変更されない
#
# 期待結果：
# - git log -S では変更として検出されない

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 1: 行番号の移動（内容変更なし）"

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
GET /api/status
EOF

git add spec.md
git commit -q -m "Initial spec"
COMMIT1=$(git rev-parse HEAD)

echo_subheader "初期状態"
echo "コミット: ${COMMIT1:0:7}"
cat -n spec.md

# 冒頭に新セクション追加
cat > spec.md << 'EOF'
# API Specification

## New Section
This is new content at the top.

## Rate Limiting
Rate limit: 100 requests per minute

## Endpoints
POST /api/data
GET /api/status
EOF

git add spec.md
git commit -q -m "Add new section at top"
COMMIT2=$(git rev-parse HEAD)

echo_subheader "新セクション追加後"
echo "コミット: ${COMMIT2:0:7}"
cat -n spec.md

# 検証：Rate Limitingセクションの行番号が変化
echo_subheader "検証：行番号の変化"
echo "【COMMIT1】 Rate Limiting は 3-4行目"
git show ${COMMIT1}:spec.md | sed -n '3,4p' | nl -v 3
echo
echo "【COMMIT2】 Rate Limiting は 6-7行目"
git show ${COMMIT2}:spec.md | sed -n '6,7p' | nl -v 6

# git log -S で検索
echo_subheader "git log -S で検索"
echo "\"Rate limit: 100\" が変更されたコミット："
git log -S "Rate limit: 100" --oneline --all

echo
echo_success "結果：${COMMIT1:0:7} のみが表示される"
echo_info "→ ${COMMIT2:0:7} は表示されない（内容変更なし）"
echo_info "→ git log -S は行番号の移動を無視する"

echo
if [ "$KEEP_TEMP" = "1" ]; then
    echo_info "デバッグ用：作業ディレクトリを保持 → $WORK_DIR"
fi
