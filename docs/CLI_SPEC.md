# permanager コマンド仕様

## コマンド一覧

| コマンド | 説明 |
|----------|------|
| `list` | パーマネントリンクを一覧表示 |

---

## list - リンクの一覧表示

カレントディレクトリの git リポジトリをスキャンし、仕様書へのパーマネントリンクを一覧表示します。

```bash
permanager list
```

**オプション:**
| オプション | 説明 |
|------------|------|
| `--status` | 外部リポジトリを参照し、各リンクが最新かどうかを確認 |
| `--fail-on-outdated` | `--status` と併用。古いリンクがある場合に非ゼロで終了（CI用） |

**デフォルトの動作（`--status` なし）:**

外部リポジトリへのアクセスは行わず、ローカルで検出したリンクの一覧を表示します。

```
Found 3 specification links:

src/api.rs:12
  https://github.com/owner/repo/blob/abc123/docs/api-spec.md#L15-L30

src/handler.rs:45
  https://github.com/owner/repo/blob/abc123/docs/api-spec.md#L50-L65

src/model.rs:8
  https://github.com/owner/repo/blob/def456/docs/data-model.md#L1-L20
```

**`--status` を指定した場合:**

外部リポジトリの最新状態と比較し、各リンクのステータスを表示します。

```
Found 3 specification links:

src/api.rs:12
  https://github.com/owner/repo/blob/abc123/docs/api-spec.md#L15-L30
  Status: current (matches latest on main)

src/handler.rs:45
  https://github.com/owner/repo/blob/abc123/docs/api-spec.md#L50-L65
  Status: outdated (spec modified in 3 commits)

src/model.rs:8
  https://github.com/owner/repo/blob/def456/docs/data-model.md#L1-L20
  Status: stale (file deleted)
```

---

## リンクの検出方式

ファイル内の Git パーマネントリンク URL を正規表現でマッチします。コメント形式や言語を問わず、全てのテキストファイルから検出します。

**検出例:**

```rust
// ソースコードのコメント
// See: https://github.com/owner/repo/blob/abc123/docs/spec.md#L10-L20
fn validate_request() { ... }
```

```markdown
<!-- Markdown ドキュメント -->
この機能は [仕様](https://github.com/owner/repo/blob/abc123/docs/spec.md#L10-L20) に基づいています。
```

```yaml
# テスト仕様書
test_case:
  description: "認証フローのテスト"
  spec_ref: https://github.com/owner/repo/blob/abc123/docs/auth-spec.md#L5-L20
```

**対応ファイル:**
- ソースコード（`.rs`, `.ts`, `.py`, `.go` など）
- ドキュメント（`.md`, `.txt`, `.adoc` など）
- 設定ファイル（`.yaml`, `.toml`, `.json` など）
- その他全てのテキストファイル

`.gitignore` に記載されたファイル・ディレクトリはスキャン対象外とします。

---

## パーマネントリンクの検出パターン

以下の URL パターンを検出します：

```
# 基本形式
https://github.com/{owner}/{repo}/blob/{commit_sha}/{path}

# 行指定あり
https://github.com/{owner}/{repo}/blob/{commit_sha}/{path}#L{line}

# 範囲指定あり
https://github.com/{owner}/{repo}/blob/{commit_sha}/{path}#L{start}-L{end}
```

**commit SHA の識別:**
- 40文字の完全な SHA: `abc123def456...`
- 7文字以上の短縮 SHA: `abc123d`
- ブランチ名・タグ名は対象外（これらはパーマネントリンクではないため警告を出す）

---

## 終了コード

| コード | 意味 |
|--------|------|
| 0 | 正常終了（古いリンクが検出された場合も含む） |
| 1 | 古いリンクが検出された（`--fail-on-outdated` 使用時） |
| 2 | エラー（ファイルが見つからない、Git エラーなど） |

---

## 対応プラットフォーム

現在は GitHub のみ対応しています：

- GitHub (`https://github.com/...`)

> GitLab・Bitbucket などその他のプラットフォームへの対応は将来的に検討予定です。
