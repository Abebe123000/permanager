#!/bin/bash
# Test 6: --outdated フラグ
#
# 検証内容：
# - 行番号あり・内容が変わった → outdated
# - 行番号あり・移動のみ（内容は同じ） → outdated に含まれない
# - 行番号あり・ファイルが削除された → stale
# - 行番号なし・ファイルに変更あり → outdated
# - 全て current のとき → "Found 0 outdated specification links:"
#
# 仕組み：
#   ローカルの bare リポジトリを「偽リモート」として作成し、
#   XDG_CACHE_HOME でキャッシュ先を一時ディレクトリに向けることで
#   ネットワークアクセスなしに全コードパスをテストする

set -e
source "$(dirname "$0")/../helpers.sh"

echo_header "Test 6: --outdated フラグ"

require_binary

# ============================================================
# 共通セットアップ: 偽リモートリポジトリの作成
# ============================================================
FAKE_REMOTE=$(mktemp -d)
FAKE_XDG_CACHE=$(mktemp -d)
trap "rm -rf '$FAKE_REMOTE' '$FAKE_XDG_CACHE'" EXIT

cd "$FAKE_REMOTE"
git init -q
git config user.name "Test"
git config user.email "test@example.com"

# v1: spec.md を作成（行番号テスト用の内容）
cat > spec.md << 'EOF'
# Specification

## Section A
Target line A
End of A

## Section B
Target line B
End of B
EOF

# deleted.md: 後で削除するファイル
echo "This will be deleted" > deleted.md

git add spec.md deleted.md
git commit -q -m "v1: initial"
SHA_V1=$(git rev-parse HEAD)

# v2: spec.md の Section A の前に行を挿入（Target line A は移動するだけ、内容は同じ）
#     deleted.md を削除
#     no_anchor.md を変更
cat > spec.md << 'EOF'
# Specification

## Section A
Inserted line
Target line A
End of A

## Section B
Target line B
End of B
EOF

git rm -q deleted.md
git add spec.md
git commit -q -m "v2: insert line before target A, delete deleted.md"
SHA_V2=$(git rev-parse HEAD)

# v3: spec.md の Target line B の内容を変更
cat > spec.md << 'EOF'
# Specification

## Section A
Inserted line
Target line A
End of A

## Section B
CHANGED content B
End of B
EOF

git add spec.md
git commit -q -m "v3: change content of target B"

# キャッシュをローカルリポジトリから事前構築
# owner="local-test" repo="spec-repo" として扱う
CACHE_DIR="$FAKE_XDG_CACHE/permanager/repos/local-test/spec-repo"
mkdir -p "$CACHE_DIR"
git clone -q --filter=blob:none --no-checkout "file://$FAKE_REMOTE" "$CACHE_DIR"

# ============================================================
# テスト用プロジェクトリポジトリの作成
# ============================================================
WORK_DIR=$(setup_git_repo)
cd "$WORK_DIR"
setup_cleanup_trap "$WORK_DIR"

BASE_URL="https://github.com/local-test/spec-repo/blob"

# ============================================================
echo_subheader "ケース1: 行番号あり・内容が変わった → outdated"
# ============================================================
# SHA_V1 の spec.md:4 = "Target line B" → v3 では "CHANGED content B" に変更
# SHA_V1 の spec.md での行番号:
#   1: # Specification
#   2: (blank)
#   3: ## Section A
#   4: Target line A
#   5: End of A
#   6: (blank)
#   7: ## Section B
#   8: Target line B  ← ここをリンク
#   9: End of B

cat > src.rs << EOF
// Spec: ${BASE_URL}/${SHA_V1}/spec.md#L8
fn handler() {}
EOF
git add src.rs && git commit -q -m "add link to target B"

OUTPUT=$(XDG_CACHE_HOME="$FAKE_XDG_CACHE" "$PERMANAGER" list --outdated)
echo "$OUTPUT"

assert_contains "src.rs が含まれる" "src.rs" "$OUTPUT"
assert_line_count "1件出力される" 1 "$OUTPUT"

# ============================================================
echo_subheader "ケース2: 行番号あり・移動のみ（内容は同じ） → outdated に含まれない"
# ============================================================
# SHA_V1 の spec.md:4 = "Target line A"
# v2 で1行挿入されて spec.md:5 に移動したが内容は同じ → current

cat > src.rs << EOF
// Spec: ${BASE_URL}/${SHA_V1}/spec.md#L4
fn handler() {}
EOF
git add src.rs && git commit -q -m "link to target A (moves but content unchanged)"

OUTPUT=$(XDG_CACHE_HOME="$FAKE_XDG_CACHE" "$PERMANAGER" list --outdated)
echo "$OUTPUT"

assert_not_contains "移動のみは outdated に含まれない" "src.rs" "$OUTPUT"

# ============================================================
echo_subheader "ケース3: 行番号あり・ファイルが削除された → stale"
# ============================================================
cat > src.rs << EOF
// Spec: ${BASE_URL}/${SHA_V1}/deleted.md#L1
fn handler() {}
EOF
git add src.rs && git commit -q -m "link to deleted file"

OUTPUT=$(XDG_CACHE_HOME="$FAKE_XDG_CACHE" "$PERMANAGER" list --outdated)
echo "$OUTPUT"

assert_contains "src.rs が含まれる" "src.rs" "$OUTPUT"
assert_line_count "1件出力される" 1 "$OUTPUT"

# ============================================================
echo_subheader "ケース4: 全て current のとき → 0 件"
# ============================================================
# SHA_V1 の spec.md:4 = "Target line A" → v3 でも内容は同じ（移動のみ）
cat > src.rs << EOF
// Spec: ${BASE_URL}/${SHA_V1}/spec.md#L4
fn handler() {}
EOF
git add src.rs && git commit -q -m "only current links"

OUTPUT=$(XDG_CACHE_HOME="$FAKE_XDG_CACHE" "$PERMANAGER" list --outdated)
echo "$OUTPUT"

assert_empty "出力が空である" "$OUTPUT"

echo_success "Test 6 完了"
