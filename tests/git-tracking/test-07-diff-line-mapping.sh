#!/bin/bash
# Test 7: git diff による行番号マッピングの実装と検証
#
# 検証内容：
# - 複数 hunk がある diff での行番号マッピング
# - 行が削除された場合（DELETED を返す）
# - hunk の前・中・後の行それぞれの扱い
# - 純粋な挿入（old_count=0）のケース

set -e
source "$(dirname "$0")/helpers.sh"

# ============================================================
# map_line: git diff --unified=0 の出力から行番号をマッピング
#
# 引数:
#   $1 = 元の行番号 (1-indexed)
#   $2 = git diff --unified=0 の出力テキスト
#
# 出力:
#   新しい行番号、または "DELETED"（行が削除された場合）
# ============================================================
map_line() {
    local old_line=$1
    local diff_output=$2

    local offset=0
    local result=""

    while IFS= read -r line; do
        # @@ -os[,oc] +ns[,nc] @@ 形式のhunkヘッダーを解析
        if [[ "$line" =~ ^\@\@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ \@\@ ]]; then
            local os="${BASH_REMATCH[1]}"
            local oc="${BASH_REMATCH[3]}"
            local ns="${BASH_REMATCH[4]}"
            local nc="${BASH_REMATCH[6]}"

            # カウントが省略されている場合は 1（git の省略記法）
            [ -z "$oc" ] && oc=1
            [ -z "$nc" ] && nc=1

            if [ "$old_line" -lt "$os" ]; then
                # このhunkより前に対象行がある → 以降のhunkも影響しない
                break
            elif [ "$oc" -eq 0 ]; then
                # 純粋な挿入（行の削除なし）: os の直後に nc 行追加
                # os より後ろの行はシフト（os 自体はシフトしない）
                if [ "$old_line" -gt "$os" ]; then
                    offset=$((offset + nc))
                fi
            elif [ "$old_line" -lt $((os + oc)) ]; then
                # このhunkの範囲内 → 行が変更または削除された
                result="DELETED"
                break
            else
                # このhunkより後 → オフセットを累積
                offset=$((offset + nc - oc))
            fi
        fi
    done <<< "$diff_output"

    if [ -z "$result" ]; then
        echo $((old_line + offset))
    else
        echo "$result"
    fi
}

# ============================================================
# アサーション用ヘルパー
# ============================================================
PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
    local label=$1
    local expected=$2
    local actual=$3

    if [ "$expected" = "$actual" ]; then
        echo_success "PASS: $label (→ $actual)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo_error "FAIL: $label"
        echo "  期待値: $expected"
        echo "  実際値: $actual"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_content_match() {
    local label=$1
    local commit_a=$2
    local commit_b=$3
    local file=$4
    local old_line=$5

    local diff_output
    diff_output=$(git diff --unified=0 "$commit_a" "$commit_b" -- "$file")
    local new_line
    new_line=$(map_line "$old_line" "$diff_output")

    if [ "$new_line" = "DELETED" ]; then
        echo_error "FAIL: $label — 行が削除された（行番号: $old_line）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    local old_content new_content
    old_content=$(git show "${commit_a}:${file}" | sed -n "${old_line}p")
    new_content=$(git show "${commit_b}:${file}" | sed -n "${new_line}p")

    if [ "$old_content" = "$new_content" ]; then
        echo_success "PASS: $label — 内容一致 (${old_line}行目 → ${new_line}行目: \"$old_content\")"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo_error "FAIL: $label — 内容不一致"
        echo "  ${commit_a}:${old_line} = \"$old_content\""
        echo "  ${commit_b}:${new_line} = \"$new_content\""
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ============================================================
echo_header "Test 7: git diff による行番号マッピング"

WORK_DIR=$(setup_git_repo)
setup_cleanup_trap "$WORK_DIR"
echo_info "作業ディレクトリ: $WORK_DIR"

# ============================================================
echo_subheader "シナリオ A: 前方への行シフト（hunk より後ろの行）"
# ============================================================
# 構造:
#   Commit A:            Commit B:
#   1: # Title          1: # Title
#   2: ## Rate          2: ## New Section    ← 挿入
#   3: Target           3: New content       ← 挿入
#   4: Footer           4: ## Rate
#                       5: Target            ← A の 3行目
#                       6: Footer

cat > file.md << 'EOF'
# Title
## Rate
Target line
Footer
EOF
git add file.md
git commit -q -m "Commit A"
COMMIT_A=$(git rev-parse HEAD)

cat > file.md << 'EOF'
# Title
## New Section
New content
## Rate
Target line
Footer
EOF
git add file.md
git commit -q -m "Commit B: insert before target"
COMMIT_B=$(git rev-parse HEAD)

DIFF_AB=$(git diff --unified=0 "$COMMIT_A" "$COMMIT_B" -- file.md)
echo "Diff hunks:"
echo "$DIFF_AB" | grep "^@@"
echo

# hunk 1つ: @@ -2,0 +2,2 @@ → 2行目の前に2行挿入
# A の 1行目 → B の 1行目（offset=0）
assert_eq "A:1行目 → B:1行目" 1 "$(map_line 1 "$DIFF_AB")"
# A の 2行目 → B の 4行目（offset=+2）
assert_eq "A:2行目 → B:4行目" 4 "$(map_line 2 "$DIFF_AB")"
# A の 3行目 → B の 5行目（offset=+2）
assert_eq "A:3行目 → B:5行目" 5 "$(map_line 3 "$DIFF_AB")"
# A の 4行目 → B の 6行目
assert_eq "A:4行目 → B:6行目" 6 "$(map_line 4 "$DIFF_AB")"

echo
assert_content_match "A:3行目の内容がB:5行目に一致" "$COMMIT_A" "$COMMIT_B" file.md 3

# ============================================================
echo_subheader "シナリオ B: 後方への行シフト（行削除）"
# ============================================================
# 構造:
#   Commit B:            Commit C:
#   1: # Title          1: # Title
#   2: ## New Section   (削除)
#   3: New content      (削除)
#   4: ## Rate          2: ## Rate
#   5: Target           3: Target            ← B の 5行目
#   6: Footer           4: Footer

cat > file.md << 'EOF'
# Title
## Rate
Target line
Footer
EOF
git add file.md
git commit -q -m "Commit C: remove inserted section"
COMMIT_C=$(git rev-parse HEAD)

DIFF_BC=$(git diff --unified=0 "$COMMIT_B" "$COMMIT_C" -- file.md)
echo "Diff hunks:"
echo "$DIFF_BC" | grep "^@@"
echo

# B の 1行目 → C の 1行目
assert_eq "B:1行目 → C:1行目" 1 "$(map_line 1 "$DIFF_BC")"
# B の 2行目 → DELETED（削除された行）
assert_eq "B:2行目 → DELETED" "DELETED" "$(map_line 2 "$DIFF_BC")"
# B の 4行目 → C の 2行目（offset=-2）
assert_eq "B:4行目 → C:2行目" 2 "$(map_line 4 "$DIFF_BC")"
# B の 5行目 → C の 3行目（offset=-2）
assert_eq "B:5行目 → C:3行目" 3 "$(map_line 5 "$DIFF_BC")"

echo
assert_content_match "B:5行目の内容がC:3行目に一致" "$COMMIT_B" "$COMMIT_C" file.md 5

# ============================================================
echo_subheader "シナリオ C: 複数 hunk（前後に変更）"
# ============================================================
# 構造:
#   Commit C:            Commit D:
#   1: # Title          1: # Title v2       ← 変更
#   2: ## Rate          2: ## Rate
#   3: Target           3: Target           ← C の 3行目（変化なし）
#   4: Footer           4: Appendix         ← 追加
#                       5: Footer

cat > file.md << 'EOF'
# Title v2
## Rate
Target line
Appendix
Footer
EOF
git add file.md
git commit -q -m "Commit D: change title, add appendix"
COMMIT_D=$(git rev-parse HEAD)

DIFF_CD=$(git diff --unified=0 "$COMMIT_C" "$COMMIT_D" -- file.md)
echo "Diff hunks:"
echo "$DIFF_CD" | grep "^@@"
echo

# C の 1行目 → DELETED（内容が変更された）
assert_eq "C:1行目 → DELETED（内容変更）" "DELETED" "$(map_line 1 "$DIFF_CD")"
# C の 2行目 → D の 2行目（hunk1 は 1行置換なので offset=0）
assert_eq "C:2行目 → D:2行目" 2 "$(map_line 2 "$DIFF_CD")"
# C の 3行目 → D の 3行目（hunk1 は 1→1 の置換でオフセット0）
assert_eq "C:3行目 → D:3行目" 3 "$(map_line 3 "$DIFF_CD")"
# C の 4行目 → D の 5行目（hunk2 で1行追加）
assert_eq "C:4行目 → D:5行目" 5 "$(map_line 4 "$DIFF_CD")"

echo
assert_content_match "C:3行目の内容がD:3行目に一致" "$COMMIT_C" "$COMMIT_D" file.md 3

# ============================================================
echo_subheader "シナリオ D: 純粋な挿入（行削除なし）の境界"
# ============================================================
# @@ -N,0 +N,M @@ の形式（old_count=0 の特殊ケース）
# 挿入点の直前・直後の行が正しく扱われるか検証

cat > file.md << 'EOF'
Line 1
Line 2
Line 3
EOF
git add file.md
git commit -q -m "Commit E"
COMMIT_E=$(git rev-parse HEAD)

cat > file.md << 'EOF'
Line 1
Line 2
Inserted A
Inserted B
Line 3
EOF
git add file.md
git commit -q -m "Commit F: insert after line 2"
COMMIT_F=$(git rev-parse HEAD)

DIFF_EF=$(git diff --unified=0 "$COMMIT_E" "$COMMIT_F" -- file.md)
echo "Diff hunks:"
echo "$DIFF_EF" | grep "^@@"
echo

# 挿入点より前（E:2行目）はシフトしない
assert_eq "E:2行目 → F:2行目（挿入前）" 2 "$(map_line 2 "$DIFF_EF")"
# 挿入点より後（E:3行目）は+2シフト
assert_eq "E:3行目 → F:5行目（挿入後）" 5 "$(map_line 3 "$DIFF_EF")"

echo
assert_content_match "E:2行目の内容がF:2行目に一致" "$COMMIT_E" "$COMMIT_F" file.md 2
assert_content_match "E:3行目の内容がF:5行目に一致" "$COMMIT_E" "$COMMIT_F" file.md 3

# ============================================================
echo_subheader "シナリオ E: hunk をまたぐ複数行の追跡（範囲指定）"
# ============================================================
# 行範囲（start..end）を一括でマッピングする例

cat > file.md << 'EOF'
Header
Section A start
Section A content
Section A end
Footer
EOF
git add file.md
git commit -q -m "Commit G"
COMMIT_G=$(git rev-parse HEAD)

cat > file.md << 'EOF'
Header
Prefix line
Section A start
Section A content
Section A end
Footer
EOF
git add file.md
git commit -q -m "Commit H: insert prefix"
COMMIT_H=$(git rev-parse HEAD)

DIFF_GH=$(git diff --unified=0 "$COMMIT_G" "$COMMIT_H" -- file.md)
echo "Diff hunks:"
echo "$DIFF_GH" | grep "^@@"
echo

# G の 2-4行目（Section A の範囲）が H でどこになるか
for old_l in 2 3 4; do
    new_l=$(map_line "$old_l" "$DIFF_GH")
    expected=$((old_l + 1))
    assert_eq "G:${old_l}行目 → H:${expected}行目" "$expected" "$new_l"
done

echo
for old_l in 2 3 4; do
    assert_content_match "G:${old_l}行目の内容が一致" "$COMMIT_G" "$COMMIT_H" file.md "$old_l"
done

# ============================================================
echo_subheader "結果サマリー"
# ============================================================
echo
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "合計: $TOTAL テスト"
echo_success "PASS: $PASS_COUNT"
if [ $FAIL_COUNT -gt 0 ]; then
    echo_error "FAIL: $FAIL_COUNT"
    exit 1
fi
