#!/bin/bash
# Test 2: 実際の内容変更
#
# 検証内容：
# - Rate limitの値を 100 → 50 に変更
# - 実際に内容が変わる
#
# 期待結果：
# - git log -S で変更として検出される

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 2: 実際の内容変更"

# セットアップ
WORK_DIR=$(setup_git_repo)
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

# 初期ファイル作成
cat > spec.md << 'EOF'
# API Specification

## Rate Limiting
Rate limit: 100 requests per minute
EOF

git add spec.md
git commit -q -m "Initial spec"
COMMIT1=$(git rev-parse HEAD)

echo_subheader "初期状態"
echo "コミット: ${COMMIT1:0:7}"
cat -n spec.md

# 内容を変更
cat > spec.md << 'EOF'
# API Specification

## Rate Limiting
Rate limit: 50 requests per minute
EOF

git add spec.md
git commit -q -m "Change rate limit from 100 to 50"
COMMIT2=$(git rev-parse HEAD)

echo_subheader "内容変更後"
echo "コミット: ${COMMIT2:0:7}"
cat -n spec.md

# 検証：内容が変化
echo_subheader "検証：内容の変化"
git diff ${COMMIT1} ${COMMIT2}

# git log -S で検索
echo_subheader "git log -S で検索"
echo "\"Rate limit: 100\" が変更されたコミット："
git log -S "Rate limit: 100" --oneline --all

echo
echo_success "結果：両方のコミットが表示される"
echo_info "→ ${COMMIT1:0:7}: \"100\" が追加された"
echo_info "→ ${COMMIT2:0:7}: \"100\" が削除された"
echo_info "→ git log -S は実際の内容変更を検出する"

echo
if [ "$KEEP_TEMP" = "1" ]; then
    echo_info "デバッグ用：作業ディレクトリを保持 → $WORK_DIR"
fi
