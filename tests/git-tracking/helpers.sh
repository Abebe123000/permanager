#!/bin/bash
# 共通ヘルパー関数

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

echo_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# テスト用のGitリポジトリをセットアップ
setup_git_repo() {
    local work_dir=$(mktemp -d)
    cd "$work_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "$work_dir"
}

# クリーンアップ（環境変数 KEEP_TEMP=1 で削除をスキップ）
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

# trapでエラー時もクリーンアップ
setup_cleanup_trap() {
    local work_dir="$1"
    trap "cleanup_repo '$work_dir'" EXIT
}
