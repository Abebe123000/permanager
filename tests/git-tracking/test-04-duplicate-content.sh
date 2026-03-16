#!/bin/bash
# Test 4: 同じ内容が複数箇所にある場合
#
# 検証内容：
# - 同じ内容「Rate limit: 50」が2箇所に存在
# - git log -S では区別できない
# - git log -L なら特定の行範囲を追跡可能
#
# 期待結果：
# - git log -S: ファイル全体で検索するため区別不可
# - git log -L: 特定の行範囲を正確に追跡可能

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 4: 同じ内容が複数箇所にある場合"

# セットアップ
WORK_DIR=$(setup_git_repo)
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

# 初期ファイル作成
cat > spec.md << 'EOF'
# API Specification

## Rate Limiting (Public API)
Rate limit: 50 requests per minute

## Rate Limiting (Internal API)
Rate limit: 50 requests per minute
EOF

git add spec.md
git commit -q -m "Initial spec with duplicate content"
COMMIT1=$(git rev-parse HEAD)

echo_subheader "初期状態"
echo "コミット: ${COMMIT1:0:7}"
cat -n spec.md
echo
echo_warning "注意：「Rate limit: 50」が 4行目と 7行目 の2箇所に存在"

# Public APIのrate limitを変更
cat > spec.md << 'EOF'
# API Specification

## Rate Limiting (Public API)
Rate limit: 100 requests per minute

## Rate Limiting (Internal API)
Rate limit: 50 requests per minute
EOF

git add spec.md
git commit -q -m "Change public API rate limit to 100"
COMMIT2=$(git rev-parse HEAD)

echo_subheader "Public APIのみ変更後"
echo "コミット: ${COMMIT2:0:7}"
cat -n spec.md

# 問題の実証：git log -S
echo_subheader "問題：git log -S では区別できない"
echo "\"Rate limit\" が変更されたコミット："
git log -S "Rate limit" --oneline --all
echo
echo_error "どちらのRate Limitingが変更されたか特定できない"
echo_info "→ git log -S はファイル全体で検索する"
echo_info "→ 複数箇所にある場合は区別不可"

# 解決策：git log -L
echo_subheader "解決策：git log -L で特定の行を追跡"
echo
echo "【4行目（Public API）の履歴】"
git log -L 4,4:spec.md --oneline
echo
echo_success "4行目の変更履歴を正確に取得できる"
echo_info "→ git log -L は特定の行範囲に限定して追跡"
echo_info "→ 他の箇所と明確に区別できる"

echo
echo_subheader "結論"
echo_info "git log -S: ファイル全体で検索 → 複数箇所の区別不可"
echo_success "git log -L: 特定の行範囲を追跡 → 正確に追跡可能 ✓"

echo
if [ "$KEEP_TEMP" = "1" ]; then
    echo_info "デバッグ用：作業ディレクトリを保持 → $WORK_DIR"
fi
