use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use clap::{Parser, Subcommand};
use ignore::WalkBuilder;
use regex::Regex;

static GITHUB_PERMALINK_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"https://github\.com/[^/\s]+/[^/\s]+/blob/[0-9a-f]{40}/[^\s]*")
        .expect("invalid regex")
});

#[derive(Parser)]
#[command(name = "permanager", about = "Manage permanent links to specifications in source code")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Scan and list specification permanent links
    List,
}

struct Link {
    file: String,
    line: usize,
    url: String,
}

fn collect_links(root: &Path) -> Vec<Link> {
    // 40文字の完全 SHA のみ対象
    let mut links = Vec::new();

    let walker = WalkBuilder::new(root)
        .hidden(false) // hidden ファイルも対象（.github/ など）
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .build();

    for entry in walker.flatten() {
        if !entry.file_type().map(|ft| ft.is_file()).unwrap_or(false) {
            continue;
        }

        let path = entry.path();

        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue, // バイナリや読み取り不可はスキップ
        };

        for (line_idx, line_str) in content.lines().enumerate() {
            for m in GITHUB_PERMALINK_RE.find_iter(line_str) {
                let relative = path
                    .strip_prefix(root)
                    .unwrap_or(path)
                    .display()
                    .to_string();
                links.push(Link {
                    file: relative,
                    line: line_idx + 1,
                    url: m.as_str().to_string(),
                });
            }
        }
    }

    links
}

#[cfg(test)]
mod tests {
    use super::{find_git_root, run_list, GITHUB_PERMALINK_RE};
    use std::fs;
    use tempfile::tempdir;

    fn is_match(s: &str) -> bool {
        GITHUB_PERMALINK_RE.is_match(s)
    }

    const SHA40: &str = "abc123def456abc123def456abc123def456abc1";

    // --- 検出されるべきケース ---

    // ファイルパスのみの基本的なパーマリンクを検出できる
    #[test]
    fn detects_basic_permalink() {
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/docs/spec.md");
        assert!(is_match(&url));
    }

    // `#L10` 形式の行番号付きパーマリンクを検出できる
    #[test]
    fn detects_permalink_with_line() {
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/docs/spec.md#L10");
        assert!(is_match(&url));
    }

    // `#L10-L20` 形式の行範囲付きパーマリンクを検出できる
    #[test]
    fn detects_permalink_with_line_range() {
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/docs/spec.md#L10-L20");
        assert!(is_match(&url));
    }

    // コメント行に埋め込まれた URL も検出できる
    #[test]
    fn detects_url_embedded_in_comment() {
        let line = format!("// See: https://github.com/owner/repo/blob/{SHA40}/docs/spec.md#L1");
        assert!(is_match(&line));
    }

    // --- 検出されないべきケース ---

    // ブランチ名 `main` を含む URL はパーマリンクではないため無視する
    #[test]
    fn ignores_branch_name_main() {
        assert!(!is_match(
            "https://github.com/owner/repo/blob/main/docs/spec.md"
        ));
    }

    // ブランチ名 `master` を含む URL はパーマリンクではないため無視する
    #[test]
    fn ignores_branch_name_master() {
        assert!(!is_match(
            "https://github.com/owner/repo/blob/master/docs/spec.md"
        ));
    }

    // SHA が 39 文字（1文字不足）の URL は無視する
    #[test]
    fn ignores_39_char_sha() {
        let sha39 = "a".repeat(39);
        assert!(!is_match(&format!(
            "https://github.com/owner/repo/blob/{sha39}/docs/spec.md"
        )));
    }

    // SHA が 41 文字（1文字超過）の URL は無視する
    #[test]
    fn ignores_41_char_sha() {
        // {40} は「ちょうど40文字」。41文字目が `/` でなくなるためマッチしない。
        let sha41 = "a".repeat(41);
        assert!(!is_match(&format!(
            "https://github.com/owner/repo/blob/{sha41}/docs/spec.md"
        )));
    }

    // SHA に大文字を含む URL は無視する（正規表現は小文字 [0-9a-f] のみ許可）
    #[test]
    fn ignores_uppercase_sha() {
        // [0-9a-f] は小文字のみ。大文字 SHA はマッチしない。
        let sha_upper = "A".repeat(40);
        assert!(!is_match(&format!(
            "https://github.com/owner/repo/blob/{sha_upper}/docs/spec.md"
        )));
    }

    // --- find_git_root のテスト ---

    // .git ディレクトリが存在するルートを返す
    #[test]
    fn find_git_root_from_root() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join(".git")).unwrap();
        assert_eq!(find_git_root(dir.path()), Some(dir.path().to_path_buf()));
    }

    // サブディレクトリから実行しても親の .git を見つけられる
    #[test]
    fn find_git_root_from_subdirectory() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join(".git")).unwrap();
        let sub = dir.path().join("src");
        fs::create_dir(&sub).unwrap();
        assert_eq!(find_git_root(&sub), Some(dir.path().to_path_buf()));
    }

    // .git が存在しない場合は None を返す
    #[test]
    fn find_git_root_not_found() {
        let dir = tempdir().unwrap();
        assert_eq!(find_git_root(dir.path()), None);
    }

    // サブディレクトリから実行した場合、ファイルパスは git ルートからの相対パスで表示される
    #[test]
    fn list_path_is_relative_to_git_root_when_run_from_subdirectory() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join(".git")).unwrap();
        let sub = dir.path().join("src");
        fs::create_dir(&sub).unwrap();
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/spec.md#L1");
        fs::write(sub.join("code.rs"), format!("// {url}\n")).unwrap();

        let root = find_git_root(&sub).unwrap();
        let mut out = Vec::new();
        run_list(&root, &mut out);

        // git ルートから見た src/code.rs と表示される
        assert_eq!(
            String::from_utf8(out).unwrap(),
            format!("src/code.rs:1 {url}\n")
        );
    }

    // --- run_list の出力テスト ---

    // ファイルパスはルートからの相対パスで表示される（絶対パスや `.` プレフィックスは含まない）
    #[test]
    fn list_file_path_is_relative_to_root() {
        let dir = tempdir().unwrap();
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/spec.md#L1");
        let src_dir = dir.path().join("src");
        fs::create_dir(&src_dir).unwrap();
        fs::write(src_dir.join("main.rs"), format!("// {url}\n")).unwrap();

        let mut out = Vec::new();
        run_list(dir.path(), &mut out);

        assert_eq!(
            String::from_utf8(out).unwrap(),
            format!("src/main.rs:1 {url}\n")
        );
    }

    // パーマリンクが存在しない場合、何も出力しない
    #[test]
    fn list_no_links_found() {
        let dir = tempdir().unwrap();
        let mut out = Vec::new();
        run_list(dir.path(), &mut out);
        assert_eq!(String::from_utf8(out).unwrap(), "");
    }

    // パーマリンクが1件の場合、`ファイル名:行番号 URL` の形式で出力する
    #[test]
    fn list_single_link_output() {
        let dir = tempdir().unwrap();
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/spec.md#L1");
        fs::write(dir.path().join("code.rs"), format!("// {url}\n")).unwrap();

        let mut out = Vec::new();
        run_list(dir.path(), &mut out);

        assert_eq!(
            String::from_utf8(out).unwrap(),
            format!("code.rs:1 {url}\n")
        );
    }

    // パーマリンクが複数件の場合、1行ずつ出力する
    #[test]
    fn list_multiple_links_output() {
        let dir = tempdir().unwrap();
        let url1 = format!("https://github.com/owner/repo/blob/{SHA40}/spec.md#L1");
        let url2 = format!("https://github.com/owner/repo/blob/{SHA40}/spec.md#L2");
        fs::write(
            dir.path().join("code.rs"),
            format!("// {url1}\n// {url2}\n"),
        )
        .unwrap();

        let mut out = Vec::new();
        run_list(dir.path(), &mut out);

        assert_eq!(
            String::from_utf8(out).unwrap(),
            format!("code.rs:1 {url1}\ncode.rs:2 {url2}\n")
        );
    }
}

fn find_git_root(start: &Path) -> Option<PathBuf> {
    let mut current = start.to_path_buf();
    loop {
        if current.join(".git").exists() {
            return Some(current);
        }
        if !current.pop() {
            return None;
        }
    }
}

fn run_list(root: &Path, out: &mut impl std::io::Write) {
    let links = collect_links(root);

    for link in &links {
        writeln!(out, "{}:{} {}", link.file, link.line, link.url).unwrap();
    }
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::List => {
            let cwd = std::env::current_dir().expect("failed to get current directory");
            let root = find_git_root(&cwd).unwrap_or(cwd);
            run_list(&root, &mut std::io::stdout());
        }
    }
}
