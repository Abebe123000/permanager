# list

カレントディレクトリの git リポジトリをスキャンし、仕様書へのパーマネントリンクを一覧表示します。

```bash
permanager list
```

## オプション

| オプション | 説明 |
|------------|------|
| `--status` | 外部リポジトリを参照し、各リンクが最新かどうかを確認 |
| `--fail-on-outdated` | `--status` と併用。古いリンクがある場合に非ゼロで終了（CI用） |

## 出力例

**デフォルト（`--status` なし）:**

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

**`--status` あり:**

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
