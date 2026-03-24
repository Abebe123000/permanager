#!/bin/bash
# E2Eテスト共通ヘルパー関数

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

echo_subheader() {
    echo -e "\n${YELLOW}▸ $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

echo_error() {
    echo -e "${RED}✗ $1${NC}"
}

echo_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# permanagerバイナリを探す
find_binary() {
    # PATHにあるか確認
    if command -v permanager &>/dev/null; then
        echo "permanager"
        return
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root
    project_root="$(cd "$script_dir/../.." && pwd)"

    # releaseビルドを確認
    if [ -f "$project_root/target/release/permanager" ]; then
        echo "$project_root/target/release/permanager"
        return
    fi

    # debugビルドを確認
    if [ -f "$project_root/target/debug/permanager" ]; then
        echo "$project_root/target/debug/permanager"
        return
    fi

    echo ""
}

# バイナリが存在することを確認（なければ終了）
require_binary() {
    PERMANAGER=$(find_binary)
    if [ -z "$PERMANAGER" ]; then
        echo_error "permanagerバイナリが見つかりません。先に 'cargo build' を実行してください。"
        exit 1
    fi
    echo_info "使用バイナリ: $PERMANAGER"
}

# テスト用のGitリポジトリをセットアップ
setup_git_repo() {
    local work_dir
    work_dir=$(mktemp -d)
    cd "$work_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "$work_dir"
}

# クリーンアップ（KEEP_TEMP=1 で削除をスキップ）
cleanup_repo() {
    local work_dir="$1"
    if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
        if [ "$KEEP_TEMP" = "1" ]; then
            echo_info "一時ディレクトリを保持: $work_dir"
        else
            rm -rf "$work_dir"
        fi
    fi
}

setup_cleanup_trap() {
    local work_dir="$1"
    trap "cleanup_repo '$work_dir'" EXIT
}

# アサーション：完全一致
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        echo_success "$description"
    else
        echo_error "$description"
        echo "  期待値:"
        echo "$expected" | sed 's/^/    /'
        echo "  実際の値:"
        echo "$actual" | sed 's/^/    /'
        exit 1
    fi
}

# アサーション：出力に指定文字列が含まれる
assert_contains() {
    local description="$1"
    local expected_substr="$2"
    local actual="$3"

    if echo "$actual" | grep -qF "$expected_substr"; then
        echo_success "$description"
    else
        echo_error "$description"
        echo "  含まれるべき文字列: $expected_substr"
        echo "  実際の出力:"
        echo "$actual" | sed 's/^/    /'
        exit 1
    fi
}

# アサーション：出力に指定文字列が含まれない
assert_not_contains() {
    local description="$1"
    local not_expected="$2"
    local actual="$3"

    if echo "$actual" | grep -qF "$not_expected"; then
        echo_error "$description"
        echo "  含まれるべきでない文字列: $not_expected"
        echo "  実際の出力:"
        echo "$actual" | sed 's/^/    /'
        exit 1
    else
        echo_success "$description"
    fi
}

# アサーション：出力が空
assert_empty() {
    local description="$1"
    local actual="$2"

    if [ -z "$actual" ]; then
        echo_success "$description"
    else
        echo_error "$description"
        echo "  空であるべき出力:"
        echo "$actual" | sed 's/^/    /'
        exit 1
    fi
}

# アサーション：出力の行数が一致
assert_line_count() {
    local description="$1"
    local expected_count="$2"
    local actual="$3"

    local actual_count
    if [ -z "$actual" ]; then
        actual_count=0
    else
        actual_count=$(echo "$actual" | wc -l | tr -d ' ')
    fi

    if [ "$actual_count" -eq "$expected_count" ]; then
        echo_success "$description"
    else
        echo_error "$description"
        echo "  期待行数: $expected_count"
        echo "  実際行数: $actual_count"
        echo "  実際の出力:"
        echo "$actual" | sed 's/^/    /'
        exit 1
    fi
}
