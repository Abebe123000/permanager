#!/bin/bash
# Test 5: 元の行番号から変更を検出（permanagerの実際のユースケース）
#
# シナリオ：
# - パーマネントリンク: blob/COMMIT1/spec.md#L3-L4
# - 現在のHEAD: 行番号がずれている可能性
# - 質問: 元の3-4行目は変更されたか？
#
# 検証内容：
# - git log -L <元の行番号> <old_commit>..<new_commit>
# - 変更がなければ出力なし
# - 変更があればコミット情報が表示される

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 5: 元の行番号から変更を検出（permanagerの実際のユースケース）"

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

echo_subheader "COMMIT1: パーマネントリンクの基準"
echo "コミット: ${COMMIT1:0:7}"
echo "パーマネントリンク: blob/${COMMIT1:0:7}/spec.md#L3-L4"
cat -n spec.md | sed -n '3,4p'

# シナリオ1: 冒頭に新セクション追加（行番号がシフト、内容変更なし）
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

echo
echo_subheader "COMMIT2: 行番号がシフト（内容変更なし）"
echo "コミット: ${COMMIT2:0:7}"
echo "元の3-4行目は現在6-7行目に移動"
cat -n spec.md

# 検証1: 元の3-4行目に変更があったか？
echo
echo_subheader "検証1: 元の3-4行目（Rate Limiting）に変更があったか？"
echo "コマンド: git log -L 3,4:spec.md ${COMMIT1}..${COMMIT2}"
echo

# 変更がなければ、行の移動だけが表示される
OUTPUT=$(git log -L 3,4:spec.md ${COMMIT1}..${COMMIT2} 2>&1)

if echo "$OUTPUT" | grep -q "Add new section"; then
    echo "$OUTPUT"
    echo
    echo_success "結果: コミットが表示されるが、Rate Limitingの内容自体は変更なし"
    echo_info "→ 新しいセクションの追加により行番号が移動しただけ"
else
    echo "$OUTPUT"
    echo_error "予期しない結果"
fi

# シナリオ2: 実際に内容を変更
cat > spec.md << 'EOF'
# API Specification

## New Section
This is new content.

## Rate Limiting
Rate limit: 50 requests per minute

## Endpoints
POST /api/data
EOF

git add spec.md
git commit -q -m "Change rate limit to 50"
COMMIT3=$(git rev-parse HEAD)

echo
echo_subheader "COMMIT3: 実際に内容を変更（100 → 50）"
echo "コミット: ${COMMIT3:0:7}"
cat -n spec.md | sed -n '6,7p'

# 検証2: 元の3-4行目に変更があったか？
echo
echo_subheader "検証2: 元の3-4行目に変更があったか？"
echo "コマンド: git log -L 3,4:spec.md ${COMMIT1}..${COMMIT3}"
echo

git log -L 3,4:spec.md ${COMMIT1}..${COMMIT3} --oneline

echo
echo_success "結果: 実際に内容が変更されたコミットが表示される"
echo_info "→ ${COMMIT3:0:7}: Rate limitを50に変更"

# 検証3: git log -L の限界を確認
echo
echo_subheader "検証3: git log -L の限界"
echo "元の3-4行目が移動した後に内容が変更されたCOMMIT3は検出されるか？"
echo

# 元の内容を取得
ORIGINAL_CONTENT=$(git show ${COMMIT1}:spec.md | sed -n '4p')
echo "元の内容: $ORIGINAL_CONTENT"

# 新しいコミットでの内容を確認
NEW_CONTENT=$(git show ${COMMIT3}:spec.md | sed -n '7p')
echo "新しい内容: $NEW_CONTENT"
echo

if [ "$ORIGINAL_CONTENT" != "$NEW_CONTENT" ]; then
    echo_error "内容が変更されているが、git log -L では検出されなかった"
    echo_info "→ git log -L は行番号ベースのため、移動後の変更は追跡できない"
fi

# まとめ
echo
echo_subheader "permanagerへの応用"
cat << EOF

${RED}git log -L の限界:${NC}
- 指定した行番号範囲の履歴のみを追跡
- 行が移動した後の変更は検出できない
- COMMIT3での内容変更（100→50）が見逃される

${GREEN}正しいアプローチ:${NC}

${CYAN}方法1: 内容ベースの比較${NC}
1. 元のコミットから対象行の内容を取得
   content_old = git show OLD_COMMIT:file | sed -n 'START,ENDp'

2. 新しいコミットでその内容を検索（git grep）
   git grep -F "\$content_old" NEW_COMMIT -- file

3. 見つかった行番号で内容を比較
   - 完全一致 → 変更なし（移動のみ）
   - 不一致 → 変更あり
   - 見つからない → 削除された

${CYAN}方法2: コミット範囲全体で検索${NC}
1. 対象文字列が変更されたコミットを全て取得
   git log -S "Rate limit: 100" OLD..NEW --oneline

2. 各コミットでの変更内容を確認
3. 対象行範囲に関連する変更かを判定

${CYAN}推奨実装（疑似コード）:${NC}
# 1. 元の内容を取得
old_content = git_show(old_commit, file, line_range)

# 2. 新しいコミットで検索
new_location = git_grep(new_commit, old_content, file)

if new_location.found():
    new_content = git_show(new_commit, file, new_location.range)

    if old_content == new_content:
        return Status::MovedOnly(new_location)
    else:
        return Status::Changed(old_location, new_location)
else:
    return Status::Deleted

EOF

echo
if [ "$KEEP_TEMP" = "1" ]; then
    echo_info "デバッグ用：作業ディレクトリを保持 → $WORK_DIR"
fi
