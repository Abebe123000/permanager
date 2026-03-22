# permanager アーキテクチャ・実装仕様

## 実装言語

Rust

## 依存関係（予定）

| クレート | 用途 |
|----------|------|
| `clap` | CLI パーサー |
| `tokio` | 非同期ランタイム |
| `regex` | URL パターンマッチング |
| `serde` / `toml` | 設定ファイル処理 |
| `git2` | Git 操作（libgit2 バインディング） |

## コア機能

### パーマネントリンクの検出

正規表現で URL パターンをマッチします。

```rust
// 検出パターン（概念）
let pattern = r"https://(github\.com|gitlab\.com|bitbucket\.org)/[\w-]+/[\w-]+/blob/([a-f0-9]{7,40})/[^\s#]+(?:#L\d+(?:-L\d+)?)?";
```

**検出フロー:**
1. 設定ファイルの `include` / `exclude` パターンでファイルをフィルタ
2. 各ファイルをテキストとして読み込み
3. 正規表現でパーマネントリンクを抽出
4. URL をパースして構造化データに変換

### リンクの構造

```rust
struct SpecLink {
    // 検出されたファイルの情報
    source_file: PathBuf,
    source_line: usize,

    // リンク先の情報
    host: String,           // "github.com"
    owner: String,          // "owner"
    repo: String,           // "repo"
    commit_sha: String,     // "abc123..."
    path: String,           // "docs/spec.md"
    line_start: Option<u32>,
    line_end: Option<u32>,
}
```

---

## Git 操作

外部 API に依存せず、全て Git コマンド / libgit2 で実現します。

### ローカルリポジトリ（カレントプロジェクト）

| 操作 | コマンド |
|------|----------|
| ファイル内容取得 | `git show {sha}:{path}` |
| 差分取得 | `git diff {sha1}..{sha2} -- {path}` |
| デフォルトブランチ | `git symbolic-ref refs/remotes/origin/HEAD` |
| 最新コミット SHA | `git rev-parse {branch}` |

### 外部リポジトリ

外部リポジトリはキャッシュディレクトリに sparse clone して管理します。

**キャッシュ構造:**
```
~/.cache/permanager/repos/
├── github.com/
│   ├── owner1/repo1/
│   └── owner2/repo2/
├── gitlab.com/
│   └── org/project/
└── bitbucket.org/
    └── team/repo/
```

**操作:**
| 操作 | コマンド |
|------|----------|
| 初回 clone | `git clone --filter=blob:none --sparse <url>` |
| ファイル追加 | `git sparse-checkout add {path}` |
| デフォルトブランチ取得 | `git ls-remote --symref <url> HEAD` |
| 更新 | `git fetch origin` |
| ファイル内容取得 | `git show {sha}:{path}` |

### 認証

Git の標準認証機構を利用します。追加の設定は不要です。

- SSH キー（`~/.ssh/id_rsa`, `~/.ssh/id_ed25519`）
- credential helper（`git credential-osxkeychain`, `git credential-manager`）
- `.netrc` ファイル
- 環境変数（`GIT_ASKPASS`）

---

## check コマンドの処理フロー

```
1. スキャン
   ├── include/exclude パターンでファイルをフィルタ
   └── 各ファイルからパーマネントリンクを抽出

2. リンクごとの処理
   ├── ローカルリポジトリか外部リポジトリか判定
   ├── 外部の場合: キャッシュを確認、なければ clone
   ├── デフォルトブランチの最新 SHA を取得
   └── リンクの SHA と最新 SHA でファイル内容を比較

3. 結果出力
   ├── 変更なし: current
   ├── 変更あり: outdated（diff を表示可能）
   └── ファイル削除: stale
```

---

## update コマンドの処理フロー

```
1. check と同様にリンクをスキャン・比較

2. 古いリンクごとの処理
   ├── 最新の commit SHA を取得
   ├── 行番号の追跡（オプション）
   │   ├── git blame で該当行の移動を検出
   │   └── 新しい行番号を計算
   └── ソースファイル内のリンクを置換

3. ファイル書き込み
   └── 変更があったファイルを上書き保存
```

---

## sync コマンドの処理フロー

```
1. check と同様にリンクをスキャン・比較

2. 変更があったリンクごとの処理
   ├── 仕様書の diff を取得
   ├── リンク周辺のコード（コンテキスト）を抽出
   └── AI API に送信
       ├── プロンプト: 仕様変更 + 現在の実装
       └── レスポンス: 修正案

3. ユーザー確認（--interactive）
   ├── 修正案を表示
   └── 適用するか確認

4. ファイル更新
   └── 承認された修正を適用
```

---

## エラーハンドリング

| エラー種別 | 対応 |
|------------|------|
| ファイルが見つからない | 警告を出して続行 |
| Git 認証エラー | エラーメッセージを表示して終了 |
| ネットワークエラー | リトライ後、エラーで終了 |
| 不正な URL 形式 | 警告を出して続行 |
| AI API エラー | エラーメッセージを表示して続行 |

---

## パフォーマンス考慮

### 並列処理

- ファイルスキャンは並列で実行
- 外部リポジトリの fetch は並列で実行
- AI API 呼び出しは rate limit を考慮して直列

### キャッシュ

- 外部リポジトリは sparse clone でディスク使用量を最小化
- `ttl` 設定で fetch 頻度を制御
- `auto_fetch = false` でオフライン動作可能

---

## メタデータ（ロックファイル）

### 目的

コードと仕様書が合致しているかどうかの状態を管理する。人間や AI が一度確認・修正した箇所を `matched` として記録し、仕様が更新されるまでは再レビュー不要という共通認識を作る。

### ライフサイクル

```
リンクが新規追加される → unverified
         ↓
人間 / AI が実装を確認・修正 → matched
         ↓
仕様が更新され permanager update でURLのコミットハッシュが変わる → matched が外れる → unverified
```

### ファイル形式

`.permanager/metadata.json` にロックファイルとして保存する（VCS に含める）。

```json
{
  "entries": [
    {
      "id": "a1b2c3",
      "file": "src/api.rs",
      "url": "https://github.com/owner/repo/blob/abc123/docs/spec.md#L15-L30",
      "line_hint": 12,
      "status": "matched"
    },
    {
      "id": "d4e5f6",
      "file": "src/handler.rs",
      "url": "https://github.com/owner/repo/blob/abc123/docs/spec.md#L15-L30",
      "line_hint": 45,
      "status": "unverified"
    }
  ]
}
```

### エントリの識別

コードには URL 以外を書かない運用を維持するため、識別子はロックファイル側で管理する。

- **主キー**: `(file, url)` の組み合わせ
- **`line_hint`**: 同一ファイルに同一 URL が複数存在する場合の曖昧さ解消にのみ使用する補助情報
- **再マッチング**: `permanager check` 実行時にソースをスキャンして `(file, url)` で既存エントリと照合し、`line_hint` を最新行番号に更新する

### status の種類

| status | 意味 |
|--------|------|
| `unverified` | 未確認（新規追加時のデフォルト） |
| `matched` | 実装と仕様が合致していることを確認済み |

---

## ディレクトリ構成（予定）

```
src/
├── main.rs           # エントリーポイント
├── cli.rs            # CLI 定義（clap）
├── config.rs         # 設定ファイル処理
├── scanner.rs        # パーマネントリンク検出
├── checker.rs        # リンク比較ロジック
├── updater.rs        # リンク更新ロジック
├── syncer.rs         # AI 同期ロジック
├── git/
│   ├── mod.rs
│   ├── local.rs      # ローカルリポジトリ操作
│   └── remote.rs     # 外部リポジトリ操作・キャッシュ
└── models/
    ├── mod.rs
    └── spec_link.rs  # リンク構造体
```
