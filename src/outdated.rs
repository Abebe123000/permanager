use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::config::PermanagerConfig;

pub struct ParsedPermalink {
    pub owner: String,
    pub repo: String,
    pub sha: String,
    pub path: String,
    pub line_range: Option<(usize, usize)>, // (start, end), 1-indexed, inclusive
}

pub enum LinkStatus {
    Current,
    Outdated,
    Stale,
}

pub fn parse_permalink(url: &str) -> Option<ParsedPermalink> {
    // https://github.com/{owner}/{repo}/blob/{sha40}/{path}[#L{start}[-L{end}]]
    let rest = url.strip_prefix("https://github.com/")?;
    let mut parts = rest.splitn(5, '/');
    let owner = parts.next()?.to_string();
    let repo = parts.next()?.to_string();
    if parts.next()? != "blob" {
        return None;
    }
    let sha = parts.next()?.to_string();
    let path_with_fragment = parts.next()?.to_string();

    let (path, fragment) = match path_with_fragment.split_once('#') {
        Some((p, f)) => (p.to_string(), Some(f)),
        None => (path_with_fragment, None),
    };

    let line_range = fragment.and_then(parse_line_range);

    Some(ParsedPermalink { owner, repo, sha, path, line_range })
}

// Parse "#L10" → Some((10, 10)), "#L10-L20" → Some((10, 20))
fn parse_line_range(fragment: &str) -> Option<(usize, usize)> {
    let s = fragment.strip_prefix('L')?;
    if let Some((start_s, end_s)) = s.split_once("-L") {
        let start = start_s.parse().ok()?;
        let end = end_s.parse().ok()?;
        Some((start, end))
    } else {
        let line = s.parse().ok()?;
        Some((line, line))
    }
}

// map_line: test-07 のアルゴリズムを Rust に移植
// None = DELETED（その行が変更または削除された）
// Some(n) = 新しい行番号
fn map_line(old_line: usize, diff: &str) -> Option<usize> {
    let mut offset: isize = 0;

    for line in diff.lines() {
        if let Some((os, oc, _ns, nc)) = parse_hunk_header(line) {
            if old_line < os {
                break;
            } else if oc == 0 {
                // 純粋な挿入: 挿入点より後ろの行のみシフト
                if old_line > os {
                    offset += nc as isize;
                }
            } else if old_line < os + oc {
                // hunk の範囲内 = 変更または削除された行
                return None;
            } else {
                // hunk より後ろ: オフセットを累積
                offset += nc as isize - oc as isize;
            }
        }
    }

    Some((old_line as isize + offset) as usize)
}

// "@@ -os[,oc] +ns[,nc] @@" をパース → (os, oc, ns, nc)
// カウント省略時は 1（git の省略記法）
fn parse_hunk_header(line: &str) -> Option<(usize, usize, usize, usize)> {
    let line = line.strip_prefix("@@ ")?;
    let line = line.strip_prefix('-')?;
    let (old_part, rest) = line.split_once(" +")?;
    let new_part = rest.split_once(" @@").map(|(p, _)| p).unwrap_or(rest);

    let (os, oc) = parse_range(old_part);
    let (ns, nc) = parse_range(new_part);
    Some((os, oc, ns, nc))
}

fn parse_range(s: &str) -> (usize, usize) {
    if let Some((start, count)) = s.split_once(',') {
        let start = start.parse().unwrap_or(0);
        let count = count.parse().unwrap_or(0);
        (start, count)
    } else {
        let start = s.parse().unwrap_or(0);
        (start, 1) // カウント省略 = 1
    }
}

fn cache_dir(owner: &str, repo: &str) -> PathBuf {
    let cache_base = std::env::var("XDG_CACHE_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        format!("{}/.cache", home)
    });
    PathBuf::from(cache_base)
        .join("permanager/repos")
        .join(owner)
        .join(repo)
}

fn run_git(dir: &Path, args: &[&str]) -> bool {
    Command::new("git")
        .args(["-C", dir.to_str().unwrap_or(".")])
        .args(args)
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_git_output(dir: &Path, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .args(["-C", dir.to_str().unwrap_or(".")])
        .args(args)
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        None
    }
}

fn ensure_cache(owner: &str, repo: &str, dir: &Path) -> bool {
    if dir.exists() {
        run_git(dir, &["fetch", "--filter=blob:none", "origin"])
    } else {
        let _ = std::fs::create_dir_all(dir.parent().unwrap_or(dir));
        let url = format!("https://github.com/{}/{}", owner, repo);
        Command::new("git")
            .args([
                "clone",
                "--filter=blob:none",
                "--no-checkout",
                &url,
                dir.to_str().unwrap_or("."),
            ])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }
}

fn resolve_branch(owner: &str, repo: &str, dir: &Path, config: &PermanagerConfig) -> String {
    let repo_key = format!("{}/{}", owner, repo);
    if let Some(entry) = config.linked_repo.iter().find(|e| e.repo == repo_key) {
        if let Some(branch) = &entry.branch {
            return branch.clone();
        }
    }
    if let Some(out) = run_git_output(dir, &["symbolic-ref", "refs/remotes/origin/HEAD"]) {
        let trimmed = out.trim();
        if let Some(branch) = trimmed.strip_prefix("refs/remotes/origin/") {
            return branch.to_string();
        }
    }
    "main".to_string()
}

// git show {commit}:{file} の指定行範囲を取得（1-indexed, inclusive）
fn get_file_lines(dir: &Path, commit: &str, file: &str, start: usize, end: usize) -> Option<Vec<String>> {
    let spec = format!("{}:{}", commit, file);
    let content = run_git_output(dir, &["show", &spec])?;
    let lines: Vec<String> = content
        .lines()
        .skip(start - 1)
        .take(end - start + 1)
        .map(|l| l.to_string())
        .collect();
    Some(lines)
}

// 行範囲がリンクの SHA から最新状態で内容が変わっていないか確認
// true = 変わっていない（current）, false = 変わっている（outdated）
fn is_content_current(
    dir: &Path,
    linked_sha: &str,
    branch: &str,
    file: &str,
    line_start: usize,
    line_end: usize,
) -> bool {
    let head_ref = format!("origin/{}", branch);
    let diff = match run_git_output(dir, &["diff", "--unified=0", linked_sha, &head_ref, "--", file]) {
        Some(d) => d,
        None => return false,
    };

    // 各行を map_line でマッピング
    let new_start = match map_line(line_start, &diff) {
        Some(n) => n,
        None => return false, // 先頭行が変更された
    };
    let new_end = match map_line(line_end, &diff) {
        Some(n) => n,
        None => return false, // 末尾行が変更された
    };

    // 旧内容と新内容を比較
    let old_lines = match get_file_lines(dir, linked_sha, file, line_start, line_end) {
        Some(l) => l,
        None => return false,
    };
    let new_lines = match get_file_lines(dir, &head_ref, file, new_start, new_end) {
        Some(l) => l,
        None => return false,
    };

    old_lines == new_lines
}

pub fn check_link_status(url: &str, config: &PermanagerConfig) -> Result<LinkStatus, String> {
    let parsed =
        parse_permalink(url).ok_or_else(|| format!("failed to parse URL: {}", url))?;

    let dir = cache_dir(&parsed.owner, &parsed.repo);

    if !ensure_cache(&parsed.owner, &parsed.repo, &dir) {
        return Err(format!(
            "failed to access {}/{}",
            parsed.owner, parsed.repo
        ));
    }

    let branch = resolve_branch(&parsed.owner, &parsed.repo, &dir, config);

    // ファイル自体が削除されていないか確認
    let head_ref = format!("origin/{}:{}", branch, parsed.path);
    if !run_git(dir.as_path(), &["cat-file", "-e", &head_ref]) {
        return Ok(LinkStatus::Stale);
    }

    // 行番号がある場合: 内容ベースの比較
    if let Some((line_start, line_end)) = parsed.line_range {
        if is_content_current(&dir, &parsed.sha, &branch, &parsed.path, line_start, line_end) {
            return Ok(LinkStatus::Current);
        }
        return Ok(LinkStatus::Outdated);
    }

    // 行番号なし: ファイルへのコミットが存在するか確認（従来の判定）
    let range = format!("{}..origin/{}", parsed.sha, branch);
    match run_git_output(&dir, &["log", "--oneline", &range, "--", &parsed.path]) {
        None => Ok(LinkStatus::Outdated),
        Some(out) => {
            let count = out.lines().filter(|l| !l.is_empty()).count();
            if count > 0 {
                Ok(LinkStatus::Outdated)
            } else {
                Ok(LinkStatus::Current)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{map_line, parse_hunk_header, parse_line_range, parse_permalink};

    const SHA40: &str = "abc123def456abc123def456abc123def456abc1";

    // --- parse_permalink ---

    #[test]
    fn parse_basic_url() {
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/docs/spec.md");
        let p = parse_permalink(&url).unwrap();
        assert_eq!(p.owner, "owner");
        assert_eq!(p.repo, "repo");
        assert_eq!(p.sha, SHA40);
        assert_eq!(p.path, "docs/spec.md");
        assert_eq!(p.line_range, None);
    }

    #[test]
    fn parse_url_with_single_line() {
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/docs/spec.md#L10");
        let p = parse_permalink(&url).unwrap();
        assert_eq!(p.line_range, Some((10, 10)));
    }

    #[test]
    fn parse_url_with_line_range() {
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/docs/spec.md#L10-L20");
        let p = parse_permalink(&url).unwrap();
        assert_eq!(p.line_range, Some((10, 20)));
    }

    #[test]
    fn parse_url_with_nested_path() {
        let url = format!("https://github.com/owner/repo/blob/{SHA40}/a/b/c.md");
        let p = parse_permalink(&url).unwrap();
        assert_eq!(p.path, "a/b/c.md");
    }

    #[test]
    fn parse_invalid_url_returns_none() {
        assert!(parse_permalink("https://github.com/owner/repo").is_none());
        assert!(parse_permalink("https://example.com/owner/repo/blob/abc/file.md").is_none());
    }

    // --- parse_line_range ---

    #[test]
    fn parse_single_line_anchor() {
        assert_eq!(parse_line_range("L5"), Some((5, 5)));
    }

    #[test]
    fn parse_range_anchor() {
        assert_eq!(parse_line_range("L3-L7"), Some((3, 7)));
    }

    #[test]
    fn parse_invalid_anchor_returns_none() {
        assert!(parse_line_range("invalid").is_none());
    }

    // --- parse_hunk_header ---

    #[test]
    fn parse_hunk_count_omitted() {
        // カウント省略 = 1
        assert_eq!(parse_hunk_header("@@ -2 +4 @@"), Some((2, 1, 4, 1)));
    }

    #[test]
    fn parse_hunk_with_counts() {
        assert_eq!(parse_hunk_header("@@ -2,3 +4,5 @@"), Some((2, 3, 4, 5)));
    }

    #[test]
    fn parse_hunk_pure_insertion() {
        // 純粋な挿入: old_count = 0
        assert_eq!(parse_hunk_header("@@ -2,0 +3,2 @@"), Some((2, 0, 3, 2)));
    }

    // --- map_line ---

    #[test]
    fn map_line_no_diff() {
        // diff がなければ行番号そのまま
        assert_eq!(map_line(5, ""), Some(5));
    }

    #[test]
    fn map_line_before_hunk() {
        // hunk より前の行はシフトしない
        let diff = "@@ -5,2 +5,3 @@";
        assert_eq!(map_line(3, diff), Some(3));
    }

    #[test]
    fn map_line_after_hunk_shift_forward() {
        // hunk より後ろ: +1行追加されたので +1 シフト
        let diff = "@@ -2,2 +2,3 @@";
        assert_eq!(map_line(5, diff), Some(6));
    }

    #[test]
    fn map_line_within_hunk_returns_none() {
        // hunk の範囲内 = DELETED
        let diff = "@@ -3,4 +3,2 @@";
        assert_eq!(map_line(4, diff), None);
        assert_eq!(map_line(6, diff), None);
    }

    #[test]
    fn map_line_pure_insertion_before_target() {
        // 挿入点 os=2 に2行挿入、対象行は 4 → +2 シフト
        let diff = "@@ -2,0 +3,2 @@";
        assert_eq!(map_line(4, diff), Some(6));
    }

    #[test]
    fn map_line_pure_insertion_at_boundary() {
        // 挿入点 os と同じ行はシフトしない（os 自体は境界）
        let diff = "@@ -2,0 +3,2 @@";
        assert_eq!(map_line(2, diff), Some(2));
    }

    #[test]
    fn map_line_multiple_hunks() {
        // 複数 hunk の累積オフセット
        // hunk1: -2,1 +2,2 (1行→2行, offset+1)
        // hunk2: -6,2 +7,1 (2行→1行, offset-1)
        let diff = "@@ -2,1 +2,2 @@\n@@ -6,2 +7,1 @@";
        assert_eq!(map_line(1, diff), Some(1)); // hunk1 より前
        assert_eq!(map_line(4, diff), Some(5)); // hunk1 の後 (+1)
        assert_eq!(map_line(9, diff), Some(9)); // hunk2 の後 (+1-1=0)
    }
}
