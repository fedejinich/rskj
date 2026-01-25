use anyhow::{bail, Context, Result};
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

pub fn ensure_cmd(cmd: &str, probe_arg: Option<&str>) -> Result<()> {
    let mut command = Command::new(cmd);
    if let Some(arg) = probe_arg {
        command.arg(arg);
    }
    match command.output() {
        Ok(_) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            bail!("missing command: {}", cmd)
        }
        Err(err) => bail!("failed to run {}: {}", cmd, err),
    }
}

pub fn run_cmd<I, S>(cmd: &str, args: I, dir: Option<&Path>) -> Result<Output>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let mut command = Command::new(cmd);
    command.args(args);
    if let Some(dir) = dir {
        command.current_dir(dir);
    }
    let output = command.output().with_context(|| format!("run {}", cmd))?;
    if !output.status.success() {
        bail!("command failed: {}\n{}", cmd, format_output(&output));
    }
    Ok(output)
}

pub fn run_cmd_allow_failure<I, S>(cmd: &str, args: I, dir: Option<&Path>) -> Result<Output>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let mut command = Command::new(cmd);
    command.args(args);
    if let Some(dir) = dir {
        command.current_dir(dir);
    }
    let output = command.output().with_context(|| format!("run {}", cmd))?;
    Ok(output)
}

pub fn format_output(output: &Output) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let mut combined = String::new();
    if !stdout.trim().is_empty() {
        combined.push_str(stdout.trim());
    }
    if !stderr.trim().is_empty() {
        if !combined.is_empty() {
            combined.push('\n');
        }
        combined.push_str(stderr.trim());
    }
    combined
}

pub fn root_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

pub fn log_step(msg: &str) {
    println!("== {}", msg);
}
