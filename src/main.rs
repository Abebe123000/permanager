use std::path::{Path, PathBuf};

use clap::{Parser, Subcommand};

mod config;
mod list;
mod outdated;

use config::{
    run_config_list, run_config_set_linked_repo, run_config_unset_linked_repo, ConfigSetSection,
    ConfigSubcommand, ConfigUnsetSection,
};
use list::run_list;

#[derive(Parser)]
#[command(name = "permanager", about = "Manage permanent links to specifications in source code")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Scan and list specification permanent links
    List {
        /// Show only outdated links (requires network access to linked repositories)
        #[arg(long)]
        outdated: bool,
    },
    /// Manage configuration in .permanager.toml
    Config {
        #[command(subcommand)]
        subcommand: ConfigSubcommand,
    },
}

pub fn find_git_root(start: &Path) -> Option<PathBuf> {
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

fn main() {
    let cli = Cli::parse();

    let cwd = std::env::current_dir().expect("failed to get current directory");
    let root = find_git_root(&cwd).unwrap_or(cwd);

    match cli.command {
        Commands::List { outdated } => {
            let config = config::read_config(&root);
            run_list(&root, &mut std::io::stdout(), outdated, &config);
        }
        Commands::Config { subcommand } => match subcommand {
            ConfigSubcommand::Set { section } => match section {
                ConfigSetSection::LinkedRepo { repo, branch } => {
                    run_config_set_linked_repo(&root, &repo, branch.as_deref());
                }
            },
            ConfigSubcommand::Unset { section } => match section {
                ConfigUnsetSection::LinkedRepo { repo, branch } => {
                    let code = run_config_unset_linked_repo(&root, &repo, branch);
                    if code != 0 {
                        std::process::exit(code);
                    }
                }
            },
            ConfigSubcommand::List => {
                run_config_list(&root, &mut std::io::stdout());
            }
        },
    }
}

#[cfg(test)]
mod tests {
    use super::find_git_root;
    use std::fs;
    use tempfile::tempdir;

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
}
