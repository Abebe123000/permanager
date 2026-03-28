use std::path::Path;

use clap::Subcommand;
use serde::{Deserialize, Serialize};

#[derive(Subcommand)]
pub enum ConfigSubcommand {
    /// Add or update a configuration value
    Set {
        #[command(subcommand)]
        section: ConfigSetSection,
    },
    /// Remove a configuration value
    Unset {
        #[command(subcommand)]
        section: ConfigUnsetSection,
    },
    /// List all configuration values
    List,
}

#[derive(Subcommand)]
pub enum ConfigSetSection {
    /// Configure a linked repository
    #[command(name = "linked-repo")]
    LinkedRepo {
        /// Repository in owner/repo format
        repo: String,
        /// Branch to treat as latest
        #[arg(long)]
        branch: Option<String>,
    },
}

#[derive(Subcommand)]
pub enum ConfigUnsetSection {
    /// Remove configuration for a linked repository
    #[command(name = "linked-repo")]
    LinkedRepo {
        /// Repository in owner/repo format
        repo: String,
        /// Remove the branch setting
        #[arg(long)]
        branch: bool,
    },
}

#[derive(Serialize, Deserialize, Default)]
pub struct PermanagerConfig {
    #[serde(default)]
    pub linked_repo: Vec<LinkedRepoEntry>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct LinkedRepoEntry {
    pub repo: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
}

pub fn read_config(root: &Path) -> PermanagerConfig {
    let path = root.join(".permanager.toml");
    if !path.exists() {
        return PermanagerConfig::default();
    }
    let content = std::fs::read_to_string(&path).expect("failed to read .permanager.toml");
    toml::from_str(&content).expect("failed to parse .permanager.toml")
}

pub fn write_config(root: &Path, config: &PermanagerConfig) {
    let path = root.join(".permanager.toml");
    let content = toml::to_string(config).expect("failed to serialize config");
    std::fs::write(path, content).expect("failed to write .permanager.toml");
}

pub fn run_config_set_linked_repo(root: &Path, repo: &str, branch: Option<&str>) {
    let mut config = read_config(root);
    if let Some(entry) = config.linked_repo.iter_mut().find(|e| e.repo == repo) {
        if let Some(b) = branch {
            entry.branch = Some(b.to_string());
        }
    } else {
        config.linked_repo.push(LinkedRepoEntry {
            repo: repo.to_string(),
            branch: branch.map(|b| b.to_string()),
        });
    }
    write_config(root, &config);
}

// Returns exit code: 0 = success, 1 = not found
pub fn run_config_unset_linked_repo(root: &Path, repo: &str, branch: bool) -> i32 {
    let mut config = read_config(root);
    match config.linked_repo.iter().position(|e| e.repo == repo) {
        None => {
            eprintln!("error: linked-repo '{}' not found", repo);
            1
        }
        Some(pos) => {
            if branch {
                if config.linked_repo[pos].branch.is_none() {
                    eprintln!("error: branch is not set for '{}'", repo);
                    return 1;
                }
                config.linked_repo[pos].branch = None;
            } else {
                config.linked_repo.remove(pos);
            }
            write_config(root, &config);
            0
        }
    }
}

pub fn run_config_list(root: &Path, out: &mut impl std::io::Write) {
    let config = read_config(root);
    if config.linked_repo.is_empty() {
        writeln!(out, "No configuration found.").unwrap();
        return;
    }
    for entry in &config.linked_repo {
        let settings: Vec<String> = entry.branch.iter().map(|b| format!("branch={}", b)).collect();
        if settings.is_empty() {
            writeln!(out, "linked-repo {}", entry.repo).unwrap();
        } else {
            writeln!(out, "linked-repo {}  {}", entry.repo, settings.join("  ")).unwrap();
        }
    }
}
