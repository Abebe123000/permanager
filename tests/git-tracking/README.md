# Git Content Tracking Tests

docref の `check` コマンド実装のための検証テスト集

## 概要

Gitがどのように「行番号の移動」と「内容の変更」を区別するかを実証します。

## テスト一覧

| テスト | 検証内容 | 主な発見 |
|--------|----------|----------|
| [test-01-line-movement.sh](test-01-line-movement.sh) | 行番号の移動のみ | `git log -S` は移動を無視 |
| [test-02-content-change.sh](test-02-content-change.sh) | 実際の内容変更 | `git log -S` は変更を検出 |
| [test-03-git-log-l.sh](test-03-git-log-l.sh) | `git log -L` の追跡機能 | 行番号が変わっても追跡可能 |
| [test-04-duplicate-content.sh](test-04-duplicate-content.sh) | 同じ内容が複数箇所 | `git log -L` なら区別可能 |
| [test-05-check-original-range.sh](test-05-check-original-range.sh) | **元の行番号からの変更検出** | ⚠️ `git log -L`の限界を実証 |
| [test-06-track-line-numbers.sh](test-06-track-line-numbers.sh) | **行番号の対応関係を追跡** | ✅ `git diff`で正確に追跡可能 |
| [test-07-diff-line-mapping.sh](test-07-diff-line-mapping.sh) | **`git diff --unified=0` による行番号マッピング実装** | ✅ 複数hunk・削除・挿入を正しく処理 |

## 実行方法

### 個別テスト実行

```bash
# ローカルで実行（推奨）
bash tests/git-tracking/test-01-line-movement.sh
```

### 全テスト実行

```bash
# ローカルで実行（推奨）
bash tests/git-tracking/run-all.sh
```

### Docker での実行

Git と bash が必要です。以下のいずれかの方法で実行できます：

```bash
# 方法1: Alpine + bash + git
docker run --rm -v "$(pwd)/tests:/tests" -w /tests/git-tracking alpine sh -c \
  "apk add --no-cache bash git >/dev/null 2>&1 && bash run-all.sh"

# 方法2: Ubuntu（bash と git がプリインストール済み）
docker run --rm -v "$(pwd)/tests:/tests" -w /tests/git-tracking ubuntu bash run-all.sh
```

**注意：** Docker環境では一部のgitコマンドで警告が出る場合がありますが、テスト自体は正常に動作します。

### デバッグモード

一時ディレクトリを削除せずに保持したい場合：

```bash
# 一時ディレクトリを保持（デバッグ用）
KEEP_TEMP=1 bash tests/git-tracking/test-01-line-movement.sh

# 表示されたパスで手動確認
cd /tmp/tmp.xxxxx
git log --oneline
```

## 主要な発見

### 1. `git log -S` の特徴

**できること：**
- 特定の文字列が追加/削除されたコミットを検出
- 行番号の移動は無視（Test 1で実証）

**限界：**
- ファイル全体で検索するため、複数箇所の区別不可（Test 4で実証）
- 特定の行範囲に限定できない

### 2. `git log -L` の特徴

**できること：**
- 特定の行範囲の履歴を内容ベースで追跡（Test 3で実証）
- 行番号が変わっても同じ内容を追跡
- 複数箇所にある同じ内容を区別可能（Test 4で実証）

**⚠️ 重要な限界（Test 5で実証）：**
- **行番号ベース**のため、移動後の変更は検出できない
- 例：3-4行目が6-7行目に移動した後に内容が変更されても見逃される
- `git log -L 3,4:file OLD..NEW` は移動先の変更を追跡しない

## docref への応用

### 実装フロー（Test 7 の実証に基づく）

```
1. git diff --unified=0 で hunk を取得
   diff = git diff --unified=0 <old_commit> <new_commit> -- <file>

2. map_line(old_line, diff) でマッピング
   → 数値: 新しい行番号
   → DELETED: 行が変更/削除された

3. DELETED でなければ内容を比較
   old_content = git show <old_commit>:<file> | sed -n '<old_line>p'
   new_content = git show <new_commit>:<file> | sed -n '<new_line>p'

   old == new → MovedOnly(new_line)
   old != new → Changed

4. DELETED なら git grep でフォールバック検索
   git grep -Fn "$old_content" <new_commit> -- <file>
   見つかれば MovedOnly、なければ Deleted
```

### 実装例（疑似コード）

```rust
fn check_spec_link(link: &PermaLink) -> LinkStatus {
    let diff = git_diff_unified0(link.commit, "HEAD", link.file);
    let old_content = git_show_range(link.commit, link.file, link.range);

    match map_line_range(&diff, link.range) {
        Some(new_range) => {
            let new_content = git_show_range("HEAD", link.file, new_range);
            if old_content == new_content {
                LinkStatus::MovedOnly { new_range }
            } else {
                LinkStatus::Changed { new_range, diff: compute_diff(...) }
            }
        }
        None => {
            // DELETED: フォールバック
            match git_grep("HEAD", &old_content, link.file) {
                Some(loc) => LinkStatus::MovedOnly { new_range: loc },
                None      => LinkStatus::Deleted,
            }
        }
    }
}

fn map_line_range(diff: &str, range: Range) -> Option<Range> {
    // range.start が DELETED なら None
    let new_start = map_line(diff, range.start)?;
    let new_end   = map_line(diff, range.end)?;
    Some(Range { start: new_start, end: new_end })
}

// Test 7 で実証したアルゴリズム
fn map_line(diff: &str, old_line: usize) -> Option<usize> {
    let mut offset: isize = 0;
    for hunk in parse_hunks(diff) {  // @@ -os,oc +ns,nc @@
        if old_line < hunk.os {
            break;
        } else if hunk.oc == 0 {
            // 純粋挿入: old_line > os なら offset += nc
            if old_line > hunk.os { offset += hunk.nc as isize; }
        } else if old_line < hunk.os + hunk.oc {
            return None;  // 範囲内 = 削除または変更
        } else {
            offset += hunk.nc as isize - hunk.oc as isize;
        }
    }
    Some((old_line as isize + offset) as usize)
}
```

## 結論

### ✅ 確定した実装方法（Test 7で実証）

**`git diff --unified=0` で行番号をマッピングする**

```bash
git diff --unified=0 <old_commit> <new_commit> -- <file>
```

`--unified=0` はコンテキスト行を含まないため、`@@` ヘッダーの数字が変更行だけを指す。これによりアルゴリズムがシンプルになる。

**アルゴリズム：**

```
offset = 0
for each hunk (@@ -os,oc +ns,nc @@):
    if old_line < os:          → break（以降のhunkも影響なし）
    elif oc == 0:              → 純粋挿入。old_line > os なら offset += nc
    elif old_line < os + oc:   → DELETED（範囲内 = 変更/削除された行）
    else:                      → offset += nc - oc（hunk 通過、累積）

return old_line + offset
```

**Test 7 で検証したケース：**

| ケース | 内容 |
|--------|------|
| hunk より後ろ | offset を累積して正方向シフト |
| 削除 hunk | DELETED / 負方向シフト |
| 複数 hunk | 各 hunk のオフセットを順番に累積 |
| 純粋挿入（`oc=0`） | 挿入点より後ろの行のみシフト |
| 行範囲の一括マッピング | 各行に同じ関数を適用 |

**フォールバック（行が DELETED の場合）: `git grep` で内容ベース検索**

```bash
old_content=$(git show <old_commit>:<file> | sed -n '<line>p')
git grep -Fn "$old_content" <new_commit> -- <file>
```

### ✗ 単独では不十分な方法

**`git log -L <range>:<file> <old>..<new>`**（Test 5で実証）
- 移動後の変更を見逃す

**`git log -S <string>`**（Test 4で実証）
- ファイル全体を対象にするため複数箇所の区別不可

## 参考資料

- `man git-log` - `-L` オプションの詳細
- [Git のドキュメント](https://git-scm.com/docs/git-log#Documentation/git-log.txt--Lltstart-gtltend-gtltfilegt)

## ファイル構成

```
tests/git-tracking/
├── README.md                        # このファイル
├── helpers.sh                       # 共通ヘルパー関数
├── test-01-line-movement.sh         # Test 1: 行番号の移動
├── test-02-content-change.sh        # Test 2: 内容変更
├── test-03-git-log-l.sh             # Test 3: git log -L
├── test-04-duplicate-content.sh     # Test 4: 重複内容
├── test-05-check-original-range.sh  # Test 5: git log -L の限界
├── test-06-track-line-numbers.sh    # Test 6: 行番号追跡（デモ）
├── test-07-diff-line-mapping.sh     # Test 7: git diff --unified=0 による実装 ⭐
└── run-all.sh                       # 全テスト実行
```
