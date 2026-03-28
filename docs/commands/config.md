# config

`.permanager.toml` の設定値を操作します。設定ファイルは git リポジトリのトップに配置されます。

```bash
permanager config <subcommand> [args...]
```

## サブコマンド

| サブコマンド | 説明 |
|-------------|------|
| [`set`](#set) | 設定値を追加・更新 |
| [`unset`](#unset) | 設定値を削除 |
| [`list`](#list) | 全設定を一覧表示 |

---

## set

設定値を追加・更新します。すでに同じエントリが存在する場合は上書きします。

```bash
permanager config set <section> <name> [options]
```

### `linked-repo`

リンク先リポジトリの設定を追加・更新します。

```bash
permanager config set linked-repo <owner/repo> [options]
```

**オプション:**

| オプション | 説明 |
|------------|------|
| `--branch <branch>` | 最新とみなすブランチ |

**例:**

```bash
permanager config set linked-repo octocat/Hello-World --branch main
permanager config set linked-repo octocat/Spoon-Knife --branch develop
```

---

## unset

設定値を削除します。オプションを指定しない場合はそのエントリの設定をすべて削除します。

```bash
permanager config unset <section> <name> [options]
```

### `linked-repo`

```bash
permanager config unset linked-repo <owner/repo> [options]
```

**オプション:**

| オプション | 説明 |
|------------|------|
| `--branch` | ブランチ設定を削除 |

**例:**

```bash
# branch 設定のみ削除
permanager config unset linked-repo octocat/Hello-World --branch

# octocat/Hello-World のすべての設定を削除
permanager config unset linked-repo octocat/Hello-World
```

---

## list

全ての設定を一覧表示します。

```bash
permanager config list
```

**出力例:**

```
linked-repo octocat/Hello-World  branch=main
linked-repo octocat/Spoon-Knife  branch=develop
```

設定が存在しない場合:

```
No configuration found.
```

---

## .permanager.toml の形式

```toml
[[linked_repo]]
repo = "octocat/Hello-World"
branch = "main"

[[linked_repo]]
repo = "octocat/Spoon-Knife"
branch = "develop"
```

`.permanager.toml` はチームで共有する場合はコミットし、ローカル専用にする場合は `.gitignore` に追加します。

## 終了コード

| コード | 意味 |
|--------|------|
| 0 | 正常終了 |
| 1 | 指定したエントリが存在しない（`unset` 時） |
| 2 | エラー（引数不足、無効なセクション名など） |
