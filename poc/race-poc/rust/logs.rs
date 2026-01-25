use anyhow::{bail, Context, Result};
use std::fs;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

pub fn resolve_log_files(root_dir: &Path, explicit: Option<&PathBuf>) -> Result<Vec<PathBuf>> {
    if let Some(path) = explicit {
        if path.exists() {
            return Ok(vec![path.clone()]);
        }
        bail!("log file not found: {}", path.display());
    }

    let mut files = Vec::new();
    let local_rsk = root_dir.join("logs/rsk.log");
    if local_rsk.exists() {
        files.push(local_rsk);
    }
    let local_rskj = root_dir.join("logs/rskj.log");
    if local_rskj.exists() {
        files.push(local_rskj);
    }
    let root = root_dir.join("../../logs/rsk.log");
    if root.exists() {
        files.push(root);
    }
    if files.is_empty() {
        bail!("log file not found. set LOG_FILE to an existing log path");
    }
    Ok(files)
}

pub fn fmt_log_files(files: &[PathBuf]) -> String {
    files
        .iter()
        .map(|p| p.display().to_string())
        .collect::<Vec<_>>()
        .join(", ")
}

pub fn capture_log_offsets(log_files: &[PathBuf]) -> Result<Vec<(PathBuf, u64)>> {
    let mut offsets = Vec::new();
    for path in log_files {
        let len = fs::metadata(path)
            .map(|m| m.len())
            .with_context(|| format!("read log file metadata: {}", path.display()))?;
        offsets.push((path.clone(), len));
    }
    Ok(offsets)
}

pub fn read_log_tails(offsets: &[(PathBuf, u64)]) -> Result<String> {
    let mut combined = String::new();
    for (path, offset) in offsets {
        let mut file = File::open(path)
            .with_context(|| format!("open log file: {}", path.display()))?;
        file.seek(SeekFrom::Start(*offset))?;
        let mut buf = String::new();
        file.read_to_string(&mut buf)?;
        if !buf.is_empty() {
            if !combined.is_empty() {
                combined.push('\n');
            }
            combined.push_str(&buf);
        }
    }
    Ok(combined)
}
