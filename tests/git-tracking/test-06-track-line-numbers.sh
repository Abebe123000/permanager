#!/bin/bash
# Test 6: 行番号の対応関係を追跡
#
# 質問：
# - COMMIT1の3-4行目は、COMMIT3ではどの行番号に対応するか？
# - Gitでこれを判定する方法はあるか？
#
# 検証内容：
# - git log -L の出力を解析
# - diff ヘッダーから行番号の対応を計算
# - git diff を使った代替手段

set -e
source "$(dirname "$0")/helpers.sh"

echo_header "Test 6: 行番号の対応関係を追跡"

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

echo_subheader "COMMIT1: 元の状態"
echo "コミット: ${COMMIT1:0:7}"
echo "Rate Limiting は 3-4行目"
cat -n spec.md

# 冒頭に新セクション追加
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
echo_subheader "COMMIT2: 新セクション追加後"
echo "コミット: ${COMMIT2:0:7}"
echo "Rate Limiting は 6-7行目に移動"
cat -n spec.md

# 方法1: git log -L の出力を解析
echo
echo_subheader "方法1: git log -L の出力を解析"
echo "コマンド: git log -L 3,4:spec.md ${COMMIT1}..${COMMIT2} -p"
echo

OUTPUT=$(git log -L 3,4:spec.md ${COMMIT1}..${COMMIT2} -p)
echo "$OUTPUT"

echo
echo_info "diff ヘッダーに注目："
echo "$OUTPUT" | grep "^@@"

echo
echo_success "結果: @@ -3,0 +3,2 @@ は「元の3行目の前に、新しく3行目から2行追加」"
echo_info "→ 元の3-4行目は、3行分下にシフト → 6-7行目"

# 方法2: git diff で直接確認
echo
echo_subheader "方法2: git diff で行番号の対応を確認"
echo "コマンド: git diff ${COMMIT1} ${COMMIT2} -- spec.md"
echo

git diff ${COMMIT1} ${COMMIT2} -- spec.md | head -20

echo
echo_info "diff ヘッダー @@ -1,7 +1,9 @@ の意味："
echo_info "  -1,7  : 元のファイルの1行目から7行"
echo_info "  +1,9  : 新しいファイルの1行目から9行"
echo_info "  → 2行追加されたため、元の3行目以降は2行下にシフト"

# 方法3: 実装例 - diff出力から行番号を計算
echo
echo_subheader "方法3: diff出力から行番号を計算（実装例）"

# diffの最初のhunkを解析
DIFF_OUTPUT=$(git diff ${COMMIT1} ${COMMIT2} -- spec.md)
FIRST_HUNK=$(echo "$DIFF_OUTPUT" | grep -m1 "^@@")

echo "Diff hunk: $FIRST_HUNK"

# @@ -1,7 +1,9 @@ から情報を抽出
# 正規表現で解析
if [[ "$FIRST_HUNK" =~ @@\ -([0-9]+),([0-9]+)\ \+([0-9]+),([0-9]+)\ @@ ]]; then
    OLD_START="${BASH_REMATCH[1]}"
    OLD_COUNT="${BASH_REMATCH[2]}"
    NEW_START="${BASH_REMATCH[3]}"
    NEW_COUNT="${BASH_REMATCH[4]}"

    echo
    echo "解析結果："
    echo "  元のファイル: ${OLD_START}行目から${OLD_COUNT}行"
    echo "  新ファイル: ${NEW_START}行目から${NEW_COUNT}行"

    LINES_ADDED=$((NEW_COUNT - OLD_COUNT))
    echo "  差分: ${LINES_ADDED}行追加"

    # 元の3行目の新しい位置を計算
    ORIGINAL_LINE=3
    if [ $ORIGINAL_LINE -ge $OLD_START ]; then
        NEW_LINE=$((ORIGINAL_LINE + LINES_ADDED))
        echo
        echo_success "計算結果: 元の${ORIGINAL_LINE}行目 → 新しい${NEW_LINE}行目"

        # 検証
        ORIGINAL_CONTENT=$(git show ${COMMIT1}:spec.md | sed -n "${ORIGINAL_LINE}p")
        NEW_CONTENT=$(git show ${COMMIT2}:spec.md | sed -n "${NEW_LINE}p")

        echo
        echo "検証:"
        echo "  元の${ORIGINAL_LINE}行目: $ORIGINAL_CONTENT"
        echo "  新しい${NEW_LINE}行目: $NEW_CONTENT"

        if [ "$ORIGINAL_CONTENT" = "$NEW_CONTENT" ]; then
            echo_success "✓ 内容が一致！正しく追跡できた"
        fi
    fi
fi

# まとめ
echo
echo_subheader "docrefへの応用"
cat << 'EOF'

行番号の対応を追跡する方法:

【方法1: git log -L の出力を解析】
1. git log -L <old_range>:<file> <old_commit>..<new_commit> -p
2. diff ヘッダー（@@ -X,Y +A,B @@）を解析
3. 各hunkでの行数変化を累積計算
4. 最終的な行番号を算出

実装例（疑似コード）:
```
offset = 0
for each hunk in diff:
    if target_line >= hunk.old_start:
        offset += (hunk.new_count - hunk.old_count)

new_line = target_line + offset
```

【方法2: git diff を解析】
1. git diff <old> <new> -- file
2. diffを順番に解析
3. 累積オフセットを計算

【方法3: git blame (逆方向)】
- 新しいコミットから古いコミットへの追跡
- git blame -L <new_range> <new_commit> -- file

推奨アプローチ:
┌──────────────────────────────────────────────────┐
│ 1. 元の内容を取得                                │
│    old_content = git show old_commit:file        │
│                                                  │
│ 2. git diff で行番号の対応を計算                │
│    offset = parse_diff_hunks(old_commit, new)   │
│    new_line = old_line + offset                 │
│                                                  │
│ 3. 新しい行番号で内容を比較                      │
│    new_content = git show new_commit:file        │
│    if old_content == new_content:               │
│        return MovedOnly(new_line)               │
│    else:                                         │
│        return Changed                           │
└──────────────────────────────────────────────────┘
```

これにより、内容の検索（git grep）よりも正確に行番号を追跡できます！
EOF

echo
if [ "$KEEP_TEMP" = "1" ]; then
    echo_info "デバッグ用：作業ディレクトリを保持 → $WORK_DIR"
fi
