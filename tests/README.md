# Tests

docref プロジェクトのテストスイート

## テストグループ

### [git-tracking/](git-tracking/)

Gitの内容追跡機能の検証テスト。docrefの`check`コマンド実装のための基礎研究。

- `git log -S` vs `git log -L` の比較
- 行番号の移動と内容変更の区別
- 複数箇所にある同じ内容の追跡方法

**詳細:** [git-tracking/README.md](git-tracking/README.md)

## 実行方法

```bash
# 特定のテストグループを実行
bash tests/git-tracking/run-all.sh

# 個別テストを実行
bash tests/git-tracking/test-01-line-movement.sh
```

## 今後追加予定のテストグループ

- `link-parsing/` - パーマネントリンクのパース処理
- `integration/` - エンドツーエンドの統合テスト
- `performance/` - パフォーマンステスト
